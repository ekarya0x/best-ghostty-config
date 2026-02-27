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
    local min_index="${TRUNAWAY_MIN_INDEX:-2}"
    local max_age_seconds="${TRUNAWAY_MAX_AGE_SECONDS:-7200}"
    local all_ages=1
    local include_main="${TRUNAWAY_INCLUDE_MAIN:-0}"

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
                all_ages=0
                ;;
            --all-ages)
                all_ages=1
                ;;
            --include-main)
                include_main=1
                ;;
            -h|--help)
                cat <<'EOF'
usage: trunaway [--apply] [--min-index N] [--max-age SECONDS] [--all-ages] [--include-main]

Finds "runaway-style" tmux sessions and optionally kills them.
Candidate rules:
  - session name is main-N (N >= min-index, default 2)
  - optional: include base session "main" with --include-main
  - exactly 1 window and 1 pane
  - pane command is a shell (zsh/bash/sh/fish)
  - by default: any age
  - with --max-age: age <= max-age seconds (unless --all-ages)

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
    [[ "$include_main" == "0" || "$include_main" == "1" ]] || { echo "invalid include_main: $include_main"; return 1; }

    local now
    now="$(date +%s)"
    local -a candidates
    local session windows created attached idx pane_count cmd age key match_main

    while IFS='|' read -r session windows created attached; do
        match_main=0
        idx=0
        if [[ "$session" == "main" ]]; then
            (( include_main == 1 )) || continue
            match_main=1
        elif [[ "$session" == main-* ]]; then
            idx="${session#main-}"
            [[ "$idx" == <-> ]] || continue
            (( idx >= min_index )) || continue
        else
            continue
        fi
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

        if (( match_main == 1 )); then
            key="000000"
        else
            key="$(printf '%06d' "$idx")"
        fi
        candidates+=("${key}|${session}|${attached}|${cmd}|${age}")
    done < <(tmux ls -F '#{session_name}|#{session_windows}|#{session_created}|#{session_attached}' 2>/dev/null)

    if (( ${#candidates[@]} == 0 )); then
        echo "no runaway-style session candidates found"
        echo "hint: include older/base sessions with:"
        echo "  trunaway --apply --all-ages --min-index 2 --include-main"
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

talways() {
    local sub="${1:-status}"
    case "$sub" in
        on)
            thoston
            echo "note: local persistence requires host power. for true power-off persistence, run tmux on an always-on remote host."
            ;;
        off)
            thostoff
            ;;
        status)
            thoststatus
            ;;
        -h|--help|help)
            cat <<'EOF'
usage: talways [on|off|status]

Wrapper around host-awake controls.
Important: if this Mac is physically powered off, local tmux cannot keep running.
Use an always-on remote machine for true power-off persistence.
EOF
            ;;
        *)
            echo "unknown subcommand: $sub"
            echo "usage: talways [on|off|status]"
            return 1
            ;;
    esac
}

__resurrect_dir() {
    local from_tmux=""
    from_tmux="$(tmux show -gv @resurrect-dir 2>/dev/null || true)"
    if [[ -n "$from_tmux" && -d "$from_tmux" ]]; then
        echo "$from_tmux"
        return 0
    fi

    local xdg_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    if [[ -d "$xdg_dir" ]]; then
        echo "$xdg_dir"
        return 0
    fi

    local legacy_dir="$HOME/.tmux/resurrect"
    if [[ -d "$legacy_dir" ]]; then
        echo "$legacy_dir"
        return 0
    fi
    return 1
}

__snapshot_non_shell_count() {
    local file="$1"
    awk -F '\t' '
        /^pane/ {
            cmd=$10
            if (cmd != "zsh" && cmd != "bash" && cmd != "sh" && cmd != "fish" && cmd != "login" && cmd != "") {
                count++
            }
        }
        END { print count + 0 }
    ' "$file" 2>/dev/null || echo "0"
}

tsaves() {
    local dir
    dir="$(__resurrect_dir)" || { echo "resurrect directory not found"; return 1; }

    local -a files
    files=("${(@f)$(ls -1t "$dir"/tmux_resurrect_*.txt 2>/dev/null)}")
    if (( ${#files[@]} == 0 )); then
        echo "no resurrect snapshots found in $dir"
        return 0
    fi

    echo "resurrect snapshots ($dir):"
    local f panes non_shell sessions ts
    for f in "${files[@]}"; do
        panes="$(awk -F '\t' '/^pane/ {c++} END {print c+0}' "$f" 2>/dev/null)"
        non_shell="$(__snapshot_non_shell_count "$f")"
        sessions="$(awk -F '\t' '/^pane/ {s[$2]=1} END {print length(s)+0}' "$f" 2>/dev/null)"
        ts="$(basename "$f")"
        printf '  %s panes=%s non_shell=%s sessions=%s\n' "$ts" "$panes" "$non_shell" "$sessions"
    done
}

trestorebest() {
    local apply=0
    local max_age_days="${TRESTOREBEST_MAX_AGE_DAYS:-7}"

    while (( $# > 0 )); do
        case "$1" in
            --apply)
                apply=1
                ;;
            --max-age-days)
                shift
                max_age_days="${1:-}"
                ;;
            -h|--help)
                cat <<'EOF'
usage: trestorebest [--apply] [--max-age-days N]

Selects the best resurrect snapshot:
  1) newest snapshot with non-shell workloads
  2) fallback to latest snapshot if no better candidate exists

Default is dry-run; --apply repoints "last" and runs restore.sh.
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

    [[ "$max_age_days" == <-> ]] || { echo "invalid --max-age-days: $max_age_days"; return 1; }

    local dir
    dir="$(__resurrect_dir)" || { echo "resurrect directory not found"; return 1; }

    local -a files
    files=("${(@f)$(ls -1t "$dir"/tmux_resurrect_*.txt 2>/dev/null)}")
    if (( ${#files[@]} == 0 )); then
        echo "no resurrect snapshots found in $dir"
        return 1
    fi

    local latest="${files[1]}"
    local selected="$latest"
    local latest_non_shell selected_non_shell age now
    latest_non_shell="$(__snapshot_non_shell_count "$latest")"
    selected_non_shell="$latest_non_shell"
    now="$(date +%s)"
    local max_age_seconds=$(( max_age_days * 86400 ))

    if (( latest_non_shell == 0 )); then
        local f mtime
        for f in "${files[@]}"; do
            mtime=0
            if [[ "$(uname)" == "Darwin" ]]; then
                mtime="$(stat -f%m "$f" 2>/dev/null || echo 0)"
            else
                mtime="$(stat -c%Y "$f" 2>/dev/null || echo 0)"
            fi
            age=$(( now - mtime ))
            (( age < 0 )) && age=0
            (( age <= max_age_seconds )) || continue

            selected_non_shell="$(__snapshot_non_shell_count "$f")"
            if (( selected_non_shell > 0 )); then
                selected="$f"
                break
            fi
        done
    fi

    echo "latest:   $(basename "$latest") non_shell=$latest_non_shell"
    echo "selected: $(basename "$selected") non_shell=$selected_non_shell"

    if (( apply == 0 )); then
        echo "dry-run only. run with --apply to restore selected snapshot."
        return 0
    fi

    local restore_script="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
    [[ -x "$restore_script" ]] || { echo "restore script not found: $restore_script"; return 1; }

    ln -fs "$(basename "$selected")" "$dir/last"
    TMUX="" "$restore_script"
    echo "restore complete from $(basename "$selected")"
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
    local entry
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        printf '  %s\n' "$entry"
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

    local entry
    local count=0
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        git update-index --no-assume-unchanged -- "$entry"
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

tsshcheck() {
    local ssh_port="${TSSHCHECK_PORT:-22}"
    local ssh_identity=""

    while (( $# > 0 )); do
        case "$1" in
            --port)
                shift
                ssh_port="${1:-}"
                [[ "$ssh_port" == <-> ]] || { echo "invalid --port: $ssh_port"; return 1; }
                shift
                ;;
            --identity)
                shift
                ssh_identity="${1:-}"
                [[ -n "$ssh_identity" ]] || { echo "missing value for --identity"; return 1; }
                shift
                ;;
            -h|--help)
                cat <<'EOF'
usage: tsshcheck [--port N] [--identity FILE] <host>

Checks non-interactive SSH reachability with:
  BatchMode=yes
  ConnectTimeout=5
EOF
                return 0
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
        echo "usage: tsshcheck [--port N] [--identity FILE] <host>"
        return 1
    fi

    command -v ssh >/dev/null 2>&1 || { echo "ssh not found"; return 1; }

    local -a ssh_cmd
    ssh_cmd=(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$ssh_port")
    if [[ -n "$ssh_identity" ]]; then
        ssh_cmd+=(-i "$ssh_identity")
    fi
    ssh_cmd+=("$target" "echo ssh-reachable")

    if "${ssh_cmd[@]}" >/dev/null 2>&1; then
        echo "ssh reachability OK: $target:$ssh_port"
        return 0
    fi

    echo "ssh reachability FAILED: $target:$ssh_port"
    return 1
}

tmoshdoctor() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        echo "usage: tmoshdoctor <tailscale-host-or-ip>"
        return 1
    fi

    command -v mosh >/dev/null 2>&1 || { echo "mosh not found"; return 1; }

    tvpncheck "$target" || return 1
    tsshcheck "$target" || return 1

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
