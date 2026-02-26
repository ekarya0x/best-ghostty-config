#!/usr/bin/env bash
set -euo pipefail

# Ghostty runs commands in a non-interactive shell with a minimal PATH.
# Add common Homebrew/system paths so tmux can be found reliably.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

BASE_SESSION="${GHOSTTY_TMUX_BASE_SESSION:-main}"
# tmux session names cannot contain colons or periods, and spaces cause quoting
# headaches. Strip them so a bad env var doesn't silently break session creation.
BASE_SESSION="${BASE_SESSION//[: .]/-}"
readonly BASE_SESSION
readonly SOCKET_NAME="${GHOSTTY_TMUX_SOCKET_NAME:-}"
readonly NO_ATTACH="${GHOSTTY_TMUX_NO_ATTACH:-0}"
readonly FORCE_NEW_SESSION="${GHOSTTY_TMUX_FORCE_NEW_SESSION:-0}"
START_DIR="${PWD:-$HOME}"
if [[ ! -d "$START_DIR" ]]; then
    START_DIR="$HOME"
fi

# ---------------------------------------------------------------------------
# Concurrency control
# ---------------------------------------------------------------------------
# When Ghostty restores saved state (window-save-state = always), it launches
# every tab nearly simultaneously. Without serialization each instance races
# to check has_attached_clients(), sees zero clients (because none have
# finished attaching yet), and falls through to attach to the base session —
# resulting in every tab mirroring the same tmux session.
#
# We use mkdir(2) as an atomic lock and a monotonic pending-instance counter
# so the first instance claims the base session while subsequent ones always
# create independent sessions. The counter file resets itself after a short
# staleness window (PENDING_STALE_SECONDS) so normal single-tab opens later
# in the day are unaffected.
# ---------------------------------------------------------------------------
readonly LOCK_DIR="/tmp/ghostty-tmux.lock"
readonly PENDING_FILE="/tmp/ghostty-tmux-pending"
readonly LOCK_STALE_SECONDS=5
readonly PENDING_STALE_SECONDS=3

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

exec_tmux() {
    if [[ -n "$SOCKET_NAME" ]]; then
        exec "$TMUX_BIN" -L "$SOCKET_NAME" "$@"
    fi
    exec "$TMUX_BIN" "$@"
}

# ---------------------------------------------------------------------------
# Locking helpers
# ---------------------------------------------------------------------------
acquire_lock() {
    local attempts=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        attempts=$((attempts + 1))
        # After ~LOCK_STALE_SECONDS, assume the holder died and force-remove.
        if (( attempts > LOCK_STALE_SECONDS * 20 )); then
            rm -rf "$LOCK_DIR" 2>/dev/null || true
            attempts=0
        fi
        sleep 0.05
    done
}

release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}

# Clean up lock on unexpected exit (trap is cleared before exec).
trap 'release_lock' EXIT

# ---------------------------------------------------------------------------
# Session helpers
# ---------------------------------------------------------------------------
attach_or_print() {
    local session_name="$1"

    # Release the lock BEFORE exec replaces this process.
    release_lock
    trap - EXIT

    if [[ "$NO_ATTACH" == "1" ]]; then
        printf '%s\n' "$session_name"
        exit 0
    fi

    exec_tmux attach-session -t "$session_name"
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

file_age_seconds() {
    local file="$1"
    local mtime now
    now="$(date +%s)"
    if [[ "$(uname)" == "Darwin" ]]; then
        mtime=$(stat -f%m "$file" 2>/dev/null || echo "$now")
    else
        mtime=$(stat -c%Y "$file" 2>/dev/null || echo "$now")
    fi
    echo $(( now - mtime ))
}

# If this shell was launched from inside tmux, remove TMUX to avoid nested
# client warnings when creating/attaching sessions.
unset TMUX || true

# ---------------------------------------------------------------------------
# Session selection — all decisions happen inside the lock
# ---------------------------------------------------------------------------
acquire_lock

# Clean up stale pending counter (e.g., from a previous batch that finished).
if [[ -f "$PENDING_FILE" ]]; then
    local_age="$(file_age_seconds "$PENDING_FILE")"
    if (( local_age > PENDING_STALE_SECONDS )); then
        rm -f "$PENDING_FILE"
    fi
fi

# Read and increment the pending-instance counter.
pending=$(cat "$PENDING_FILE" 2>/dev/null || echo "0")
pending=$((pending + 1))
echo "$pending" > "$PENDING_FILE"

# 1. No tmux server or no base session → create base session detached, then
#    attach. The session exists before any other instance can run, preventing
#    duplicates.
if ! tmux_exec has-session -t "$BASE_SESSION" 2>/dev/null; then
    tmux_exec new-session -d -s "$BASE_SESSION" -c "$START_DIR"
    attach_or_print "$BASE_SESSION"
fi

# 2. Force new session requested via env var.
if [[ "$FORCE_NEW_SESSION" == "1" ]]; then
    next_session="$(create_next_session)"
    attach_or_print "$next_session"
fi

# 3. Determine whether to reuse the base session or create a new one.
#    - pending == 1 means we are the FIRST instance in this launch batch.
#      If no clients are attached yet, reuse the base session (fresh Ghostty
#      launch or Cmd+Q → reopen).
#    - pending > 1 means another instance already claimed the base session
#      (even if it hasn't finished exec-ing yet). Always create a new session.
client_count="$(tmux_exec list-clients -F '#{client_pid}' 2>/dev/null | wc -l | tr -d '[:space:]' || echo "0")"

if (( pending == 1 && client_count == 0 )); then
    attach_or_print "$BASE_SESSION"
fi

# At least one client attached or another instance already claimed base.
next_session="$(create_next_session)"
attach_or_print "$next_session"
