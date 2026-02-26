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
readonly CLAIMED_FILE="/tmp/ghostty-tmux-claimed"
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

# ---------------------------------------------------------------------------
# Reattachment helper — find existing unattached sessions from a prior launch
# ---------------------------------------------------------------------------
# When Ghostty restores tabs after a restart, the old tmux sessions (main-2,
# main-3, ...) are still alive but detached.  Instead of creating brand-new
# sessions that orphan the old ones, we pick the lowest-numbered unattached
# session that hasn't already been claimed in this launch batch.
find_unattached_session() {
    local claimed=""
    if [[ -f "$CLAIMED_FILE" ]]; then
        claimed="$(cat "$CLAIMED_FILE")"
    fi

    local best="" best_num=999999
    while IFS=' ' read -r name attached; do
        if [[ "$attached" == "0" && "$name" =~ ^${BASE_SESSION}-([0-9]+)$ ]]; then
            local num="${BASH_REMATCH[1]}"
            if ! printf '%s\n' "$claimed" | grep -qxF "$name"; then
                if (( num < best_num )); then
                    best="$name"
                    best_num="$num"
                fi
            fi
        fi
    done < <(tmux_exec list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null || true)

    if [[ -n "$best" ]]; then
        printf '%s\n' "$best"
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Resurrect restore — recover sessions after a system reboot
# ---------------------------------------------------------------------------
# When the tmux server died (reboot, kill-server) but tmux-resurrect has a
# saved snapshot, we restore it synchronously so the session-selection logic
# below sees the recovered sessions and can reattach tabs to them.
resurrect_restore_if_needed() {
    local restore_script="${HOME}/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

    # Resurrect may store saves in XDG_DATA_HOME or the legacy ~/.tmux path.
    local save_link=""
    local candidate
    for candidate in \
        "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/last" \
        "${HOME}/.tmux/resurrect/last"; do
        if [[ -L "$candidate" || -f "$candidate" ]]; then
            save_link="$candidate"
            break
        fi
    done

    # Only attempt if resurrect is installed and has save data.
    [[ -x "$restore_script" ]] || return 0
    [[ -n "$save_link" ]] || return 0

    # Only restore when the server has no sessions (fresh start after reboot).
    if tmux_exec list-sessions 2>/dev/null | grep -q .; then
        return 0
    fi

    # Start a temporary session to bootstrap the tmux server so the
    # restore script has a running server to talk to.
    tmux_exec new-session -d -s "_bgc_restore" -c "$HOME" 2>/dev/null || return 0

    # Run the restore script (it creates sessions/windows/panes from the
    # save file using normal tmux commands).
    TMUX="" "$restore_script" 2>/dev/null || true

    # Give tmux a moment to finish processing restore commands.
    sleep 1

    # Clean up the bootstrap session if real sessions were restored.
    if tmux_exec has-session -t "$BASE_SESSION" 2>/dev/null; then
        tmux_exec kill-session -t "_bgc_restore" 2>/dev/null || true
    else
        # Restore didn't recreate the base session (save was incomplete or
        # empty).  Rename the bootstrap so the rest of the script can use it.
        tmux_exec rename-session -t "_bgc_restore" "$BASE_SESSION" 2>/dev/null || true
    fi
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
        rm -f "$CLAIMED_FILE"
    fi
fi

# Read and increment the pending-instance counter.
pending=$(cat "$PENDING_FILE" 2>/dev/null || echo "0")
pending=$((pending + 1))
echo "$pending" > "$PENDING_FILE"

# 0. If the tmux server is empty (reboot, kill-server) and resurrect has a
#    saved snapshot, restore it now before making any session decisions.
resurrect_restore_if_needed

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

# 3. Determine whether to reuse an existing session or create a new one.
#    - pending == 1 means we are the FIRST instance in this launch batch.
#      If no clients are attached yet, reuse the base session (fresh Ghostty
#      launch or Cmd+Q → reopen).
#    - pending > 1 means another instance already claimed the base session
#      (even if it hasn't finished exec-ing yet). Try to reattach to an
#      existing unattached session first so that Ghostty-restart correctly
#      reconnects tabs 2+ to their previous tmux sessions instead of
#      orphaning them.
client_count="$(tmux_exec list-clients -F '#{client_pid}' 2>/dev/null | wc -l | tr -d '[:space:]' || echo "0")"

if (( pending == 1 && client_count == 0 )); then
    echo "$BASE_SESSION" >> "$CLAIMED_FILE"
    attach_or_print "$BASE_SESSION"
fi

# In a batch restore (pending > 1), try to reattach to existing detached
# sessions that match the BASE_SESSION-N naming pattern before creating
# new ones.  The claimed-sessions file prevents the race where two
# instances both see the same session as unattached (lock is released
# before exec completes the attach).
if (( pending > 1 )); then
    unattached="$(find_unattached_session || true)"
    if [[ -n "$unattached" ]]; then
        echo "$unattached" >> "$CLAIMED_FILE"
        attach_or_print "$unattached"
    fi
fi

# Either this is a single-tab open (Cmd+T, pending == 1, client_count > 0)
# or no unattached sessions remain — create a brand-new session.
# Record it in the claimed file so a subsequent instance (whose lock-acquire
# may win before our exec completes) won't see it as "unattached".
next_session="$(create_next_session)"
echo "$next_session" >> "$CLAIMED_FILE"
attach_or_print "$next_session"
