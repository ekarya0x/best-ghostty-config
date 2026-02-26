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
readonly STATE_DIR="${GHOSTTY_TMUX_STATE_DIR:-/tmp}"
STATE_KEY="${GHOSTTY_TMUX_STATE_KEY:-$(id -u)-${SOCKET_NAME:-default}-${BASE_SESSION}}"
STATE_KEY="$(printf '%s' "$STATE_KEY" | tr -c 'A-Za-z0-9._-' '_')"
readonly STATE_KEY
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
readonly LOCK_DIR="${STATE_DIR}/ghostty-tmux-${STATE_KEY}.lock"
readonly PENDING_FILE="${STATE_DIR}/ghostty-tmux-${STATE_KEY}.pending"
readonly CLAIMED_FILE="${STATE_DIR}/ghostty-tmux-${STATE_KEY}.claimed"
readonly MODE_FILE="${STATE_DIR}/ghostty-tmux-${STATE_KEY}.mode"
readonly FILL_FILE="${STATE_DIR}/ghostty-tmux-${STATE_KEY}.fill"
readonly LOCK_STALE_SECONDS=5
readonly PENDING_STALE_SECONDS=3
readonly FILL_STALE_SECONDS=25
readonly TRACE_ENABLED="${GHOSTTY_TMUX_TRACE:-0}"
readonly TRACE_FILE="${GHOSTTY_TMUX_TRACE_FILE:-${STATE_DIR}/ghostty-tmux-${STATE_KEY}.trace.log}"

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

mkdir -p "$STATE_DIR" 2>/dev/null || true

trace_log() {
    [[ "$TRACE_ENABLED" == "1" ]] || return 0
    local msg="$1"
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '%s pid=%s key=%s msg=%s\n' "$ts" "$$" "$STATE_KEY" "$msg" >> "$TRACE_FILE" 2>/dev/null || true
}

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

tmux_client_count() {
    tmux_exec list-clients -F '#{client_pid}' 2>/dev/null | wc -l | tr -d '[:space:]' || echo "0"
}

tmux_session_count() {
    tmux_exec list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d '[:space:]' || echo "0"
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
    trace_log "select session=${session_name} pending=${pending:-0} mode=${BATCH_MODE:-unknown}"

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
            trace_log "create session=${session_name} path=${START_DIR}"
            printf '%s\n' "$session_name"
            return 0
        fi
        idx=$((idx + 1))
    done

    # Extremely unlikely fallback if sequence is exhausted.
    session_name="${BASE_SESSION}-$(date +%Y%m%d-%H%M%S)-$$"
    tmux_exec new-session -d -s "$session_name" -c "$START_DIR"
    trace_log "create session=${session_name} path=${START_DIR} fallback=1"
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

BATCH_MODE=""
set_batch_mode_if_needed() {
    if [[ -f "$MODE_FILE" ]]; then
        BATCH_MODE="$(cat "$MODE_FILE" 2>/dev/null || true)"
    fi

    if [[ "$BATCH_MODE" == "restore" || "$BATCH_MODE" == "normal" ]]; then
        return 0
    fi

    local session_count client_count
    session_count="$(tmux_session_count)"
    client_count="$(tmux_client_count)"

    if (( session_count > 0 && client_count == 0 )); then
        BATCH_MODE="restore"
    else
        BATCH_MODE="normal"
    fi

    printf '%s\n' "$BATCH_MODE" > "$MODE_FILE"
    trace_log "batch_mode=${BATCH_MODE} session_count=${session_count} client_count=${client_count}"
}

session_is_claimed() {
    local session_name="$1"
    local claimed=""
    if [[ -f "$CLAIMED_FILE" ]]; then
        claimed="$(cat "$CLAIMED_FILE")"
    fi
    printf '%s\n' "$claimed" | grep -qxF "$session_name"
}

claimed_line_count() {
    if [[ -f "$CLAIMED_FILE" ]]; then
        wc -l < "$CLAIMED_FILE" | tr -d '[:space:]'
    else
        echo "0"
    fi
}

wait_for_claim_growth() {
    local before="$1"
    local after="$before"
    local i=0
    while (( i < 20 )); do
        after="$(claimed_line_count)"
        if (( after > before )); then
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

count_unclaimed_unattached_sessions() {
    local count=0
    local name attached
    while IFS=' ' read -r name attached; do
        [[ -n "$name" ]] || continue
        [[ "$attached" == "0" ]] || continue
        [[ "$name" == "_bgc_restore" ]] && continue
        if ! session_is_claimed "$name"; then
            count=$((count + 1))
        fi
    done < <(tmux_exec list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null || true)

    printf '%s\n' "$count"
}

open_ghostty_tab() {
    # Auto-fill tabs is only needed on macOS where Ghostty restore may reopen
    # fewer tabs than detached tmux sessions.
    [[ "$(uname)" == "Darwin" ]] || return 1
    [[ -x /usr/bin/osascript ]] || return 1

    if /usr/bin/osascript >/dev/null 2>&1 <<'APPLESCRIPT'
tell application "Ghostty" to activate
tell application "System Events"
    keystroke "t" using command down
end tell
APPLESCRIPT
    then
        trace_log "fill open_tab=ok"
        return 0
    fi
    trace_log "fill open_tab=failed"
    return 1
}

fill_restore_tabs_if_needed() {
    # Only meaningful for real interactive launches.
    [[ "$NO_ATTACH" == "1" ]] && return 0
    [[ "$BATCH_MODE" == "restore" ]] || return 0
    [[ "$pending" -eq 1 ]] || return 0

    # One helper per batch.
    if [[ -f "$FILL_FILE" ]]; then
        trace_log "fill skip=already_running"
        return 0
    fi
    printf '%s\n' "$$" > "$FILL_FILE"
    trace_log "fill start"

    (
        trap 'rm -f "$FILL_FILE"' EXIT

        # Let Ghostty finish launching its own restored tabs first.
        sleep 1.0
        local iter=0
        while (( iter < 120 )); do
            acquire_lock
            local missing
            missing="$(count_unclaimed_unattached_sessions)"
            release_lock

            if [[ -z "$missing" || "$missing" -le 0 ]]; then
                trace_log "fill done missing=${missing:-0}"
                exit 0
            fi

            local before
            before="$(claimed_line_count)"

            open_ghostty_tab || exit 0
            if ! wait_for_claim_growth "$before"; then
                trace_log "fill stop=no_claim_growth before=${before} missing=${missing}"
                exit 0
            fi
            iter=$((iter + 1))
            sleep 0.2
        done
        trace_log "fill stop=max_iter"
    ) >/dev/null 2>&1 &
}

# ---------------------------------------------------------------------------
# Reattachment helper — find existing unattached sessions from a prior launch
# ---------------------------------------------------------------------------
# When Ghostty restores tabs after a restart, the old tmux sessions (main-2,
# main-3, ...) are still alive but detached.  Instead of creating brand-new
# sessions that orphan the old ones, we pick the lowest-numbered unattached
# session that hasn't already been claimed in this launch batch.
find_unattached_session() {
    local best=""
    local best_rank=""
    while IFS=' ' read -r name attached; do
        [[ -n "$name" ]] || continue
        [[ "$attached" == "0" ]] || continue
        [[ "$name" == "_bgc_restore" ]] && continue
        [[ "$name" == "$BASE_SESSION" ]] && continue
        if session_is_claimed "$name"; then
            continue
        fi

        local rank=""
        if [[ "$name" =~ ^${BASE_SESSION}-([0-9]+)$ ]]; then
            rank="$(printf '0-%08d' "${BASH_REMATCH[1]}")"
        else
            rank="1-${name}"
        fi

        if [[ -z "$best_rank" || "$rank" < "$best_rank" ]]; then
            best="$name"
            best_rank="$rank"
        fi
    done < <(tmux_exec list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null || true)

    if [[ -n "$best" ]]; then
        printf '%s\n' "$best"
        return 0
    fi
    return 1
}

cleanup_stale_batch_files_if_needed() {
    if [[ -f "$FILL_FILE" ]]; then
        local fill_age
        fill_age="$(file_age_seconds "$FILL_FILE")"
        if (( fill_age > FILL_STALE_SECONDS )); then
            trace_log "cleanup stale_fill age=${fill_age}"
            rm -f "$FILL_FILE"
        fi
    fi

    # If no batch is active, clear stale metadata from prior launches.
    if [[ ! -f "$PENDING_FILE" ]]; then
        rm -f "$CLAIMED_FILE" "$MODE_FILE"
    fi

    # Clean up stale pending counter (e.g., from a previous batch that finished).
    if [[ -f "$PENDING_FILE" ]]; then
        local local_age
        local_age="$(file_age_seconds "$PENDING_FILE")"
        if (( local_age > PENDING_STALE_SECONDS )); then
            trace_log "cleanup stale_batch age=${local_age}"
            rm -f "$PENDING_FILE"
            rm -f "$CLAIMED_FILE"
            rm -f "$MODE_FILE"
        fi
    fi
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

cleanup_stale_batch_files_if_needed

# Read and increment the pending-instance counter.
pending=$(cat "$PENDING_FILE" 2>/dev/null || echo "0")
pending=$((pending + 1))
echo "$pending" > "$PENDING_FILE"
trace_log "launch pending=${pending} no_attach=${NO_ATTACH} force_new=${FORCE_NEW_SESSION}"

# 0. If the tmux server is empty (reboot, kill-server) and resurrect has a
#    saved snapshot, restore it now before making any session decisions.
resurrect_restore_if_needed

# Persist batch mode once per launch burst:
#   - restore: Ghostty relaunch with detached surviving sessions
#   - normal:  regular interactive tab/pane creation
set_batch_mode_if_needed

# Start a background helper that opens any missing Ghostty tabs to ensure
# every detached tmux session gets reattached during restore launches.
fill_restore_tabs_if_needed

# 1. No tmux server or no base session → create base session detached, then
#    attach. The session exists before any other instance can run, preventing
#    duplicates.
if ! tmux_exec has-session -t "$BASE_SESSION" 2>/dev/null; then
    trace_log "base_missing create_base=${BASE_SESSION}"
    tmux_exec new-session -d -s "$BASE_SESSION" -c "$START_DIR"
    attach_or_print "$BASE_SESSION"
fi

# 2. Force new session requested via env var.
if [[ "$FORCE_NEW_SESSION" == "1" ]]; then
    trace_log "force_new=1"
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
client_count="$(tmux_client_count)"

if (( pending == 1 && client_count == 0 )); then
    trace_log "attach_base first_in_batch client_count=0"
    echo "$BASE_SESSION" >> "$CLAIMED_FILE"
    attach_or_print "$BASE_SESSION"
fi

# In restore mode (Ghostty relaunch), reattach tabs 2+ to existing detached
# sessions before creating anything new. In normal mode (live usage), always
# create a fresh session for each new tab/pane/window.
if [[ "$BATCH_MODE" == "restore" && "$pending" -gt 1 ]]; then
    unattached="$(find_unattached_session || true)"
    if [[ -n "$unattached" ]]; then
        trace_log "reattach existing=${unattached}"
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
