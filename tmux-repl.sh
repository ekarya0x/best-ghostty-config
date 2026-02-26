#!/usr/bin/env bash
set -euo pipefail

PROMPT="${TMUX_REPL_PROMPT:-tmux-repl> }"
TRACE_ENABLED="${TMUX_REPL_TRACE:-0}"
TRACE_DIR="${TMUX_REPL_TRACE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/best-ghostty-config}"
TRACE_FILE="${TMUX_REPL_TRACE_FILE:-${TRACE_DIR}/tmux-repl.log}"
LAUNCHER_PATH="${TMUX_REPL_LAUNCHER:-$HOME/.config/ghostty/ghostty-tmux.sh}"
GHOSTTY_CONFIG_PATH="${TMUX_REPL_GHOSTTY_CONFIG:-$HOME/.config/ghostty/config}"
SHOW_BANNER=1
EXECUTE_LINE=""

ensure_trace_dir() {
    mkdir -p "$TRACE_DIR" 2>/dev/null || true
}

repl_log() {
    [[ "$TRACE_ENABLED" == "1" ]] || return 0
    ensure_trace_dir
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '%s pid=%s %s\n' "$ts" "$$" "$1" >> "$TRACE_FILE" 2>/dev/null || true
}

die() {
    echo "tmux-repl: $*" >&2
    exit 1
}

require_tmux() {
    command -v tmux >/dev/null 2>&1 || die "tmux not found in PATH"
}

in_tmux() {
    [[ -n "${TMUX:-}" ]]
}

normalize_session_target() {
    local raw="${1:-}"
    if [[ -z "$raw" || "$raw" == "current" ]]; then
        if in_tmux; then
            tmux display-message -p '#S' 2>/dev/null
            return 0
        fi
        return 1
    fi

    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        printf 'main-%s\n' "$raw"
        return 0
    fi

    printf '%s\n' "$raw"
}

session_exists() {
    local s="$1"
    tmux has-session -t "$s" 2>/dev/null
}

cmd_help() {
    cat <<'EOF'
Slash commands:
  /help                    Show this help
  /sessions | /ls          List sessions (name, attached, windows)
  /windows [session]       List windows (all or one session)
  /panes [session]         List panes (all or one session)
  /tree                    Show session/window/pane tree
  /choose                  Fuzzy pick a session (requires fzf)
  /attach <session>        Attach (outside tmux) or switch-client (inside tmux)
  /switch <session>        Switch client (inside tmux only)
  /new [name] [dir]        Create session and attach/switch
  /kill [target]           Kill session (target, number N => main-N, or current)
  /save                    tmux-resurrect save now
  /restore                 tmux-resurrect restore now
  /doctor                  Validate launcher/config/plugins/runtime
  /trace on|off|path|tail  REPL trace controls
  /launcher-trace path     Print launcher trace file path
  /config                  Open Ghostty config in $EDITOR (or vi)
  /superfile               Run superfile if installed
  /clear                   Clear screen
  /quit | /exit            Exit REPL

Any line not starting with '/' runs as a shell command (bash -lc).
EOF
}

cmd_sessions() {
    local out
    out="$(tmux list-sessions -F '#{session_name} attached=#{session_attached} windows=#{session_windows} created=#{session_created_string}' 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        echo "no sessions"
        return 0
    fi
    printf '%s\n' "$out" | sort -V
}

cmd_windows() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        local out
        out="$(tmux list-windows -a -F '#{session_name}:#{window_index} active=#{window_active} panes=#{window_panes} name=#{window_name}' 2>/dev/null || true)"
        if [[ -z "$out" ]]; then
            echo "no windows"
            return 0
        fi
        printf '%s\n' "$out" | sort -V
        return 0
    fi

    target="$(normalize_session_target "$target")"
    session_exists "$target" || die "session not found: $target"
    tmux list-windows -t "$target" -F '#{session_name}:#{window_index} active=#{window_active} panes=#{window_panes} name=#{window_name}' 2>/dev/null | sort -V
}

cmd_panes() {
    local target="${1:-}"
    local fmt='#{session_name}:#{window_index}.#{pane_index} active=#{pane_active} dead=#{pane_dead} cmd=#{pane_current_command} cwd=#{pane_current_path}'
    if [[ -z "$target" ]]; then
        local out
        out="$(tmux list-panes -a -F "$fmt" 2>/dev/null || true)"
        if [[ -z "$out" ]]; then
            echo "no panes"
            return 0
        fi
        printf '%s\n' "$out" | sort -V
        return 0
    fi

    target="$(normalize_session_target "$target")"
    session_exists "$target" || die "session not found: $target"
    tmux list-panes -t "$target" -F "$fmt" 2>/dev/null | sort -V
}

cmd_tree() {
    local sessions
    sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)"
    if [[ -z "$sessions" ]]; then
        echo "no sessions"
        return 0
    fi
    printf '%s\n' "$sessions" | sort -V | while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        local attached windows
        attached="$(tmux display-message -p -t "$s" '#{session_attached}' 2>/dev/null || echo 0)"
        windows="$(tmux display-message -p -t "$s" '#{session_windows}' 2>/dev/null || echo 0)"
        echo "session $s attached=${attached} windows=${windows}"
        tmux list-windows -t "$s" -F '  window #{window_index} active=#{window_active} panes=#{window_panes} name=#{window_name}' 2>/dev/null | sort -V
        tmux list-panes -t "$s" -F '    pane #{window_index}.#{pane_index} active=#{pane_active} cmd=#{pane_current_command} cwd=#{pane_current_path}' 2>/dev/null | sort -V
    done
}

cmd_choose() {
    command -v fzf >/dev/null 2>&1 || die "fzf not installed (brew install fzf)"
    local picked target
    picked="$(tmux list-sessions -F '#{session_name} attached=#{session_attached} windows=#{session_windows}' 2>/dev/null | sort -V | fzf --prompt='session> ' --height=40%)"
    [[ -n "$picked" ]] || return 0
    target="${picked%% *}"
    cmd_attach "$target"
}

cmd_attach() {
    local target="${1:-}"
    target="$(normalize_session_target "$target")" || die "usage: /attach <session>"
    session_exists "$target" || die "session not found: $target"

    if in_tmux; then
        tmux switch-client -t "$target"
    else
        tmux attach-session -t "$target"
    fi
}

cmd_switch() {
    in_tmux || die "/switch works inside tmux only"
    local target="${1:-}"
    target="$(normalize_session_target "$target")" || die "usage: /switch <session>"
    session_exists "$target" || die "session not found: $target"
    tmux switch-client -t "$target"
}

cmd_new() {
    local name="${1:-}"
    local cwd="${2:-$PWD}"

    if [[ -z "$name" ]]; then
        if ! session_exists "main"; then
            name="main"
        else
            local i=2
            while session_exists "main-${i}"; do
                i=$((i + 1))
            done
            name="main-${i}"
        fi
    fi

    tmux new-session -Ad -s "$name" -c "$cwd"
    cmd_attach "$name"
}

cmd_kill() {
    local target="${1:-}"
    target="$(normalize_session_target "$target")" || die "usage: /kill <session|current|N>"
    session_exists "$target" || die "session not found: $target"

    if in_tmux; then
        local current fallback
        current="$(tmux display-message -p '#S' 2>/dev/null || true)"
        if [[ "$current" == "$target" ]]; then
            fallback="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -vxF "$current" | head -n1 || true)"
            [[ -n "$fallback" ]] || die "refusing to kill the last session: $current"
            tmux switch-client -t "$fallback"
        fi
    fi

    tmux kill-session -t "$target"
}

run_resurrect_script() {
    local mode="$1"
    local script="$HOME/.tmux/plugins/tmux-resurrect/scripts/${mode}.sh"
    [[ -x "$script" ]] || die "resurrect ${mode}.sh not found: $script"
    TMUX="" "$script"
}

cmd_save() {
    run_resurrect_script "save"
    echo "saved"
}

cmd_restore() {
    run_resurrect_script "restore"
    echo "restored"
}

cmd_trace() {
    local arg="${1:-}"
    case "$arg" in
        on)
            TRACE_ENABLED=1
            ensure_trace_dir
            echo "trace on ($TRACE_FILE)"
            ;;
        off)
            TRACE_ENABLED=0
            echo "trace off"
            ;;
        path)
            echo "$TRACE_FILE"
            ;;
        tail)
            ensure_trace_dir
            tail -n 100 -f "$TRACE_FILE"
            ;;
        *)
            echo "usage: /trace on|off|path|tail"
            return 1
            ;;
    esac
}

cmd_launcher_trace() {
    local key="${GHOSTTY_TMUX_STATE_KEY:-$(id -u)-default-main}"
    key="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_')"
    local state_dir="${GHOSTTY_TMUX_STATE_DIR:-/tmp}"
    local path="${state_dir}/ghostty-tmux-${key}.trace.log"
    echo "$path"
}

cmd_doctor() {
    local sessions_count clients_count
    sessions_count="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d '[:space:]' || echo 0)"
    clients_count="$(tmux list-clients -F '#{client_pid}' 2>/dev/null | wc -l | tr -d '[:space:]' || echo 0)"

    echo "tmux version: $(tmux -V 2>/dev/null || echo missing)"
    echo "launcher: $LAUNCHER_PATH"
    if [[ -x "$LAUNCHER_PATH" ]]; then
        echo "launcher executable: yes"
    else
        echo "launcher executable: no"
    fi
    if [[ -f "$GHOSTTY_CONFIG_PATH" ]]; then
        grep '^command = ' "$GHOSTTY_CONFIG_PATH" || true
    else
        echo "ghostty config not found: $GHOSTTY_CONFIG_PATH"
    fi
    echo "sessions: ${sessions_count}"
    echo "clients:  ${clients_count}"
    echo "@resurrect-processes: $(tmux show -gqv @resurrect-processes 2>/dev/null || echo unset)"
    echo "@continuum-save-interval: $(tmux show -gqv @continuum-save-interval 2>/dev/null || echo unset)"
    echo "@continuum-restore: $(tmux show -gqv @continuum-restore 2>/dev/null || echo unset)"
}

cmd_config() {
    local editor="${EDITOR:-vi}"
    "$editor" "$GHOSTTY_CONFIG_PATH"
}

cmd_superfile() {
    if command -v superfile >/dev/null 2>&1; then
        exec superfile
    fi
    if command -v spf >/dev/null 2>&1; then
        exec spf
    fi
    die "superfile not found. Install: https://github.com/yorukot/superfile"
}

run_shell_line() {
    local line="$1"
    repl_log "shell cmd=${line}"
    bash -lc "$line"
}

handle_slash_line() {
    local line="$1"
    local raw="${line#/}"
    local cmd="${raw%% *}"
    local args=""
    if [[ "$raw" == *" "* ]]; then
        args="${raw#* }"
    fi
    local -a argv=()
    if [[ -n "$args" ]]; then
        read -r -a argv <<< "$args"
    fi

    repl_log "slash cmd=${cmd} args=${args}"
    case "$cmd" in
        h|help) cmd_help ;;
        sessions|ls) cmd_sessions ;;
        windows|wins) cmd_windows "${argv[0]:-}" ;;
        panes) cmd_panes "${argv[0]:-}" ;;
        tree) cmd_tree ;;
        choose) cmd_choose ;;
        attach|a) cmd_attach "${argv[0]:-}" ;;
        switch|s) cmd_switch "${argv[0]:-}" ;;
        new|n) cmd_new "${argv[0]:-}" "${argv[1]:-$PWD}" ;;
        kill|k) cmd_kill "${argv[0]:-}" ;;
        save) cmd_save ;;
        restore) cmd_restore ;;
        doctor) cmd_doctor ;;
        trace) cmd_trace "${argv[0]:-}" ;;
        launcher-trace) cmd_launcher_trace ;;
        config) cmd_config ;;
        superfile) cmd_superfile ;;
        clear) clear ;;
        q|quit|exit) return 100 ;;
        *) echo "unknown slash command: /${cmd} (try /help)" ; return 1 ;;
    esac
}

handle_line() {
    local line="$1"
    [[ -n "${line//[[:space:]]/}" ]] || return 0
    if [[ "${line:0:1}" == "/" ]]; then
        handle_slash_line "$line"
        return $?
    fi
    run_shell_line "$line"
}

print_banner() {
    [[ "$SHOW_BANNER" == "1" ]] || return 0
    cat <<'EOF'
tmux-repl
Type /help for slash commands. Non-slash input runs as shell.
EOF
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --execute|-c)
                [[ $# -ge 2 ]] || die "--execute requires an argument"
                EXECUTE_LINE="$2"
                shift 2
                ;;
            --no-banner)
                SHOW_BANNER=0
                shift
                ;;
            --trace)
                TRACE_ENABLED=1
                shift
                ;;
            --help|-h)
                cmd_help
                exit 0
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done
}

main() {
    require_tmux
    parse_args "$@"

    if [[ -n "$EXECUTE_LINE" ]]; then
        handle_line "$EXECUTE_LINE"
        exit $?
    fi

    print_banner
    while true; do
        if ! IFS= read -r -p "$PROMPT" line; then
            echo ""
            break
        fi

        if ! handle_line "$line"; then
            rc=$?
            if (( rc == 100 )); then
                break
            fi
            if (( rc != 0 )); then
                echo "command failed (rc=$rc)"
            fi
        fi
    done
}

main "$@"
