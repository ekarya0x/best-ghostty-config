#!/usr/bin/env bash
set -euo pipefail

# Ghostty runs commands in a non-interactive shell with a minimal PATH.
# Add common Homebrew/system paths so tmux can be found reliably.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

readonly BASE_SESSION="${GHOSTTY_TMUX_BASE_SESSION:-main}"
readonly SOCKET_NAME="${GHOSTTY_TMUX_SOCKET_NAME:-}"
START_DIR="${PWD:-$HOME}"
if [[ ! -d "$START_DIR" ]]; then
    START_DIR="$HOME"
fi

resolve_tmux_bin() {
    if [[ -n "${TMUX_BIN:-}" && -x "${TMUX_BIN}" ]]; then
        printf '%s\n' "${TMUX_BIN}"
        return 0
    fi

    if command -v tmux >/dev/null 2>&1; then
        command -v tmux
        return 0
    fi

    local candidate
    for candidate in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

TMUX_BIN="$(resolve_tmux_bin || true)"
if [[ -z "$TMUX_BIN" ]]; then
    echo "best-ghostty-config: tmux not found. Install tmux and re-run ./install.sh" >&2
    exit 127
fi

tmux_exec() {
    if [[ -n "$SOCKET_NAME" ]]; then
        "$TMUX_BIN" -L "$SOCKET_NAME" "$@"
    else
        "$TMUX_BIN" "$@"
    fi
}

has_attached_clients() {
    # list-clients prints one line per attached client and returns non-zero
    # if no server exists.
    local count
    count="$(tmux_exec list-clients -F '#{client_pid}' 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
    [[ "${count:-0}" -gt 0 ]]
}

create_next_session() {
    local idx=2
    local session_name=""

    # Try predictable names first (main-2, main-3, ...).
    while (( idx < 10000 )); do
        session_name="${BASE_SESSION}-${idx}"
        if tmux_exec new-session -d -s "$session_name" -c "$START_DIR" 2>/dev/null; then
            printf '%s\n' "$session_name"
            return 0
        fi
        idx=$((idx + 1))
    done

    # Extremely unlikely fallback if sequence is exhausted.
    session_name="${BASE_SESSION}-$(date +%Y%m%d-%H%M%S)-$$"
    tmux_exec new-session -d -s "$session_name" -c "$START_DIR"
    printf '%s\n' "$session_name"
}

# If this shell was launched from inside tmux, remove TMUX to avoid nested
# client warnings when creating/attaching sessions.
unset TMUX || true

if ! tmux_exec has-session -t "$BASE_SESSION" 2>/dev/null; then
    exec tmux_exec new-session -s "$BASE_SESSION" -c "$START_DIR"
fi

# Existing server behavior:
# - No attached clients: reopen primary session (expected on a fresh app launch).
# - At least one attached client: this is typically a new Ghostty tab, so create
#   a fresh independent session (main-2, main-3, ...).
if has_attached_clients; then
    next_session="$(create_next_session)"
    exec tmux_exec attach-session -t "$next_session"
fi

exec tmux_exec attach-session -t "$BASE_SESSION"
