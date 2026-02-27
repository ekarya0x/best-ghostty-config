#!/usr/bin/env zsh

# tmux shortcuts for fast session navigation and safe cleanup.
# Load from ~/.zshrc:
#   [[ -f ~/.config/ghostty/tmux-aliases.zsh ]] && source ~/.config/ghostty/tmux-aliases.zsh

alias tls='tmux ls -F "#{session_name} attached=#{session_attached} windows=#{session_windows}"'
alias twin='tmux list-windows -a -F "#{session_name}:#{window_index} active=#{window_active} panes=#{window_panes} name=#{window_name}"'
alias tpanes='tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} active=#{pane_active} cmd=#{pane_current_command} cwd=#{pane_current_path}"'
alias ttree='tmux choose-tree -sZw'
alias tmain='tgo main'

__tmux_list() {
    tmux ls -F "#{session_name} attached=#{session_attached} windows=#{session_windows}" 2>/dev/null
}

__tmux_normalize_target() {
    local raw="$1"
    raw="${raw//[[:space:]]/}"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        echo "main-${raw}"
        return 0
    fi
    echo "$raw"
}

tgo() {
    local target
    target="$(__tmux_normalize_target "${1:-}")"
    if [[ -z "$target" ]]; then
        echo "usage: tgo <session>"
        __tmux_list
        return 1
    fi

    if ! tmux has-session -t "$target" 2>/dev/null; then
        echo "session not found: $target"
        __tmux_list
        return 1
    fi

    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$target"
    else
        tmux attach-session -t "$target"
    fi
}

tnew() {
    local name="${1:-}"
    local cwd="${2:-$PWD}"

    if [[ -z "$name" ]]; then
        if ! tmux has-session -t "main" 2>/dev/null; then
            name="main"
        else
            local i=2
            while tmux has-session -t "main-${i}" 2>/dev/null; do
                i=$((i + 1))
            done
            name="main-${i}"
        fi
    fi

    tmux new-session -Ad -s "$name" -c "$cwd" || return 1
    tgo "$name"
}

tprev() {
    if [[ -z "${TMUX:-}" ]]; then
        echo "tprev works inside tmux only"
        return 1
    fi

    local current target
    current="$(tmux display-message -p '#S' 2>/dev/null)"
    target="$(tmux list-sessions -F '#{session_name} #{session_last_attached}' \
        | awk -v current="$current" '$1 != current { print }' \
        | sort -k2,2nr \
        | head -n1 \
        | awk '{print $1}')"

    if [[ -z "$target" ]]; then
        echo "no other sessions available"
        return 1
    fi

    tmux switch-client -t "$target"
}

tkill() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        if [[ -n "${TMUX:-}" ]]; then
            target="$(tmux display-message -p '#S' 2>/dev/null)"
        else
            echo "usage: tkill <session>"
            return 1
        fi
    fi

    target="$(__tmux_normalize_target "$target")"

    if ! tmux has-session -t "$target" 2>/dev/null; then
        echo "session not found: $target"
        __tmux_list
        return 1
    fi

    if [[ -n "${TMUX:-}" ]]; then
        local current fallback
        current="$(tmux display-message -p '#S' 2>/dev/null)"
        if [[ "$target" == "$current" ]]; then
            fallback="$(tmux list-sessions -F '#{session_name}' | grep -vxF "$current" | head -n1)"
            if [[ -z "$fallback" ]]; then
                echo "refusing to kill last session: $current"
                return 1
            fi
            tmux switch-client -t "$fallback" || return 1
        fi
    fi

    tmux kill-session -t "$target"
}

tkillc() {
    if [[ -z "${TMUX:-}" ]]; then
        echo "tkillc works inside tmux only"
        return 1
    fi
    tkill "$(tmux display-message -p '#S' 2>/dev/null)"
}

tprune() {
    local keep=""
    local killed=0

    if [[ -n "${TMUX:-}" ]]; then
        keep="$(tmux display-message -p '#S' 2>/dev/null)"
    fi

    while IFS=' ' read -r session attached; do
        if [[ "$attached" == "0" && "$session" == main-* && "$session" != "$keep" ]]; then
            tmux kill-session -t "$session" && echo "killed: $session"
            killed=$((killed + 1))
        fi
    done < <(tmux ls -F '#{session_name} #{session_attached}' 2>/dev/null)

    echo "pruned $killed session(s)"
}

trunaway() {
    local apply=0
    local min_index="${TRUNAWAY_MIN_INDEX:-10}"
    local max_age_seconds="${TRUNAWAY_MAX_AGE_SECONDS:-7200}"
    local all_ages=0

    while (( $# > 0 )); do
        case "$1" in
            --apply)
                apply=1
                ;;
            --min-index)
                shift
                min_index="${1:-}"
                ;;
            --max-age)
                shift
                max_age_seconds="${1:-}"
                ;;
            --all-ages)
                all_ages=1
                ;;
            -h|--help)
                cat <<'EOF'
usage: trunaway [--apply] [--min-index N] [--max-age SECONDS] [--all-ages]

Finds "runaway-style" tmux sessions and optionally kills them.
Candidate rules:
  - session name is main-N (N >= min-index, default 10)
  - exactly 1 window and 1 pane
  - pane command is a shell (zsh/bash/sh/fish)
  - age <= max-age (default 7200 seconds), unless --all-ages

Default is dry-run. Add --apply to actually kill candidates.
EOF
                return 0
                ;;
            *)
                echo "unknown option: $1"
                return 1
                ;;
        esac
        shift
    done

    [[ "$min_index" == <-> ]] || { echo "invalid --min-index: $min_index"; return 1; }
    [[ "$max_age_seconds" == <-> ]] || { echo "invalid --max-age: $max_age_seconds"; return 1; }

    local now
    now="$(date +%s)"
    local -a candidates
    local session windows created attached idx pane_count cmd age key

    while IFS='|' read -r session windows created attached; do
        [[ "$session" == main-* ]] || continue
        idx="${session#main-}"
        [[ "$idx" == <-> ]] || continue
        (( idx >= min_index )) || continue
        [[ "$windows" == "1" ]] || continue

        pane_count="$(tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d '[:space:]')"
        [[ "$pane_count" == "1" ]] || continue

        cmd="$(tmux list-panes -t "$session" -F '#{pane_current_command}' 2>/dev/null | head -n1 | tr -d '\r')"
        case "$cmd" in
            zsh|bash|sh|fish) ;;
            *) continue ;;
        esac

        age=0
        if [[ "$created" == <-> ]]; then
            age=$(( now - created ))
            (( age < 0 )) && age=0
        fi
        if (( all_ages == 0 && age > max_age_seconds )); then
            continue
        fi

        key="$(printf '%06d' "$idx")"
        candidates+=("${key}|${session}|${attached}|${cmd}|${age}")
    done < <(tmux ls -F '#{session_name}|#{session_windows}|#{session_created}|#{session_attached}' 2>/dev/null)

    if (( ${#candidates[@]} == 0 )); then
        echo "no runaway-style session candidates found"
        return 0
    fi

    echo "runaway candidates:"
    local row out_session out_attached out_cmd out_age
    local -a sorted
    sorted=("${(@On)candidates}")
    for row in "${sorted[@]}"; do
        IFS='|' read -r _ out_session out_attached out_cmd out_age <<< "$row"
        printf '  %s attached=%s cmd=%s age=%ss\n' "$out_session" "$out_attached" "$out_cmd" "$out_age"
    done

    if (( apply == 0 )); then
        echo "dry-run only. run with --apply to kill these sessions."
        return 0
    fi

    local killed=0 failed=0
    for row in "${sorted[@]}"; do
        IFS='|' read -r _ out_session out_attached out_cmd out_age <<< "$row"
        if tkill "$out_session" >/dev/null 2>&1; then
            printf 'killed: %s\n' "$out_session"
            killed=$((killed + 1))
        else
            printf 'failed: %s\n' "$out_session"
            failed=$((failed + 1))
        fi
    done

    printf 'runaway prune complete: killed=%d failed=%d\n' "$killed" "$failed"
    (( failed == 0 ))
}

thoston() {
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/best-ghostty-config"
    local pid_file="${state_dir}/caffeinate.pid"
    mkdir -p "$state_dir"

    if [[ -f "$pid_file" ]]; then
        local existing
        existing="$(cat "$pid_file" 2>/dev/null || true)"
        if [[ -n "$existing" ]] && kill -0 "$existing" 2>/dev/null; then
            echo "host-awake already active (pid=$existing)"
            return 0
        fi
        rm -f "$pid_file"
    fi

    command -v caffeinate >/dev/null 2>&1 || { echo "caffeinate not found (macOS only)"; return 1; }
    nohup caffeinate -dimsu >/dev/null 2>&1 &
    echo "$!" > "$pid_file"
    echo "host-awake enabled (pid=$!)"
}

thostoff() {
    local pid_file="${XDG_STATE_HOME:-$HOME/.local/state}/best-ghostty-config/caffeinate.pid"
    if [[ ! -f "$pid_file" ]]; then
        echo "host-awake not active"
        return 0
    fi
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        echo "host-awake disabled"
    else
        echo "host-awake pid file stale; cleaned"
    fi
    rm -f "$pid_file"
}

thoststatus() {
    local pid_file="${XDG_STATE_HOME:-$HOME/.local/state}/best-ghostty-config/caffeinate.pid"
    if [[ ! -f "$pid_file" ]]; then
        echo "host-awake inactive"
        return 1
    fi
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "host-awake active (pid=$pid)"
        return 0
    fi
    echo "host-awake stale pid file"
    return 1
}

gdrift() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "not inside a git repository"
        return 1
    fi

    local hidden
    hidden="$(git ls-files -v | awk '$1 ~ /^[a-z]/ { print $2 }')"
    if [[ -z "$hidden" ]]; then
        echo "no hidden assume-unchanged entries"
        return 0
    fi

    echo "hidden assume-unchanged entries:"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        printf '  %s\n' "$path"
    done <<< "$hidden"
}

gdriftfix() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "not inside a git repository"
        return 1
    fi

    local hidden
    hidden="$(git ls-files -v | awk '$1 ~ /^[a-z]/ { print $2 }')"
    if [[ -z "$hidden" ]]; then
        echo "no hidden assume-unchanged entries"
        return 0
    fi

    local path
    local count=0
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        git update-index --no-assume-unchanged -- "$path"
        count=$((count + 1))
    done <<< "$hidden"

    echo "cleared assume-unchanged on ${count} file(s)"
}

tvpncheck() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        cat <<'EOF'
usage: tvpncheck <tailscale-host-or-ip>

Checks:
  1) local Tailscale daemon/session
  2) TSMP reachability to target
  3) peer path/latency to target
EOF
        return 1
    fi

    command -v tailscale >/dev/null 2>&1 || { echo "tailscale CLI not found"; return 1; }

    echo "[1/3] local tailscale status"
    if ! tailscale status --self; then
        echo "tailscale status failed (is tailscaled running and logged in?)"
        return 1
    fi

    echo "[2/3] TSMP reachability: $target"
    if ! tailscale ping --tsmp -c 2 "$target"; then
        echo "TSMP reachability failed for $target"
        return 1
    fi

    echo "[3/3] peer path and latency: $target"
    if ! tailscale ping -c 2 "$target"; then
        echo "peer ping failed for $target"
        return 1
    fi

    echo "vpn reachability OK: $target"
}

tmoshdoctor() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        echo "usage: tmoshdoctor <tailscale-host-or-ip>"
        return 1
    fi

    command -v ssh >/dev/null 2>&1 || { echo "ssh not found"; return 1; }
    command -v mosh >/dev/null 2>&1 || { echo "mosh not found"; return 1; }

    tvpncheck "$target" || return 1

    echo "[4/4] remote mosh-server check"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" 'command -v mosh-server >/dev/null'; then
        echo "remote mosh-server found"
        return 0
    fi
    echo "remote mosh-server missing/unreachable via non-interactive ssh"
    return 1
}

tmosh() {
    local do_check=1
    local ssh_cmd="${TMOSH_SSH_CMD:-ssh}"
    local udp_port=""

    while (( $# > 0 )); do
        case "$1" in
            --no-check)
                do_check=0
                shift
                ;;
            --ssh)
                shift
                ssh_cmd="${1:-}"
                [[ -n "$ssh_cmd" ]] || { echo "missing value for --ssh"; return 1; }
                shift
                ;;
            --port)
                shift
                udp_port="${1:-}"
                [[ "$udp_port" == <-> ]] || { echo "invalid --port: $udp_port"; return 1; }
                shift
                ;;
            -h|--help)
                cat <<'EOF'
usage: tmosh [--no-check] [--ssh "ssh ..."] [--port UDP_PORT] <tailscale-host-or-ip> [-- remote-command...]

Examples:
  tmosh mac-mini.tailnet.ts.net
  tmosh --port 60001 devbox
  tmosh devbox -- ssh-agent zsh -lc 'tmux attach -t main'
EOF
                return 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "unknown option: $1"
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    local target="${1:-}"
    if [[ -z "$target" ]]; then
        echo "usage: tmosh <tailscale-host-or-ip> [-- remote-command...]"
        return 1
    fi
    shift

    command -v mosh >/dev/null 2>&1 || { echo "mosh not found"; return 1; }

    if (( do_check == 1 )); then
        tvpncheck "$target" || return 1
    fi

    local -a cmd
    cmd=(mosh --ssh="$ssh_cmd")
    if [[ -n "$udp_port" ]]; then
        cmd+=(-p "$udp_port")
    fi
    cmd+=("$target")
    if (( $# > 0 )); then
        cmd+=(-- "$@")
    fi

    "${cmd[@]}"
}
