#!/usr/bin/env bash
# ============================================================================
# Comprehensive test suite for best-ghostty-config persistence system
# Tests every code path in ghostty-tmux.sh, tmux.conf, install.sh, and config
# Uses isolated tmux sockets — live sessions are never touched.
# ============================================================================

PASS=0; FAIL=0; TOTAL=0
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${REPO_DIR}/ghostty-tmux.sh"
INSTALL_SCRIPT="${REPO_DIR}/install.sh"
TMUX_CONF_FILE="${REPO_DIR}/tmux.conf"
GHOSTTY_CONFIG_FILE="${REPO_DIR}/config"
TMUX_ALIASES_FILE="${REPO_DIR}/tmux-aliases.zsh"
SOCKET="bgctest$$"
STATE_KEY="bgctest-state-${SOCKET}"
LOCK_DIR="/tmp/ghostty-tmux-${STATE_KEY}.lock"
BATCH_FILE="/tmp/ghostty-tmux-${STATE_KEY}.batch"
PENDING_FILE="/tmp/ghostty-tmux-${STATE_KEY}.pending"
CLAIMED_FILE="/tmp/ghostty-tmux-${STATE_KEY}.claimed"
MODE_FILE="/tmp/ghostty-tmux-${STATE_KEY}.mode"
FILL_FILE="/tmp/ghostty-tmux-${STATE_KEY}.fill"
FILL_MARK_FILE="/tmp/ghostty-tmux-${STATE_KEY}.fill-mark"
TRACE_FILE="/tmp/ghostty-tmux-${STATE_KEY}.trace.log"

green() { printf '\033[1;32m%s\033[0m\n' "$1"; }
red()   { printf '\033[1;31m%s\033[0m\n' "$1"; }
bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

check() {
    TOTAL=$((TOTAL + 1))
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
        green "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        red "  FAIL: $desc"
        red "        expected='$expected'  got='$actual'"
    fi
}

check_ok() {
    TOTAL=$((TOTAL + 1))
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        green "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        red "  FAIL: $desc"
    fi
}

wipe() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$LOCK_DIR" "$BATCH_FILE" "$PENDING_FILE" "$CLAIMED_FILE" "$MODE_FILE" "$FILL_FILE" "$FILL_MARK_FILE" "$TRACE_FILE"
}

trap 'wipe' EXIT

# Helper: run the launcher in NO_ATTACH mode on the isolated socket
run() {
    GHOSTTY_TMUX_SOCKET_NAME="$SOCKET" \
    GHOSTTY_TMUX_STATE_KEY="$STATE_KEY" \
    GHOSTTY_TMUX_NO_ATTACH=1 \
    "$@" \
    "$SCRIPT" 2>/dev/null
}

sess_count() {
    tmux -L "$SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d ' '
}

sess_list() {
    tmux -L "$SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | sort
}

# ============================================================================
bold ""
bold "╔══════════════════════════════════════════════════╗"
bold "║  BEST-GHOSTTY-CONFIG — COMPREHENSIVE TEST SUITE ║"
bold "╚══════════════════════════════════════════════════╝"
bold ""

# ============================================================================
bold "─── 1. SCRIPT FUNDAMENTALS ───"
# ============================================================================
check_ok "ghostty-tmux.sh: bash -n syntax" bash -n "$SCRIPT"
check_ok "install.sh: bash -n syntax" bash -n "$INSTALL_SCRIPT"
check_ok "ghostty-tmux.sh: executable" test -x "$SCRIPT"
check_ok "install.sh: executable" test -x "$INSTALL_SCRIPT"
check_ok "tmux binary reachable" command -v tmux
check_ok "zsh binary reachable" command -v zsh
check_ok "tmux-aliases.zsh: zsh -n syntax" zsh -n "$TMUX_ALIASES_FILE"

# Verify shebang
shebang=$(head -1 "$SCRIPT")
check "shebang is #!/usr/bin/env bash" "#!/usr/bin/env bash" "$shebang"
check_ok "auto-fill restore default present" grep -q 'AUTO_FILL_RESTORE="${GHOSTTY_TMUX_AUTO_FILL_RESTORE:-0}"' "$SCRIPT"

check "tmux-aliases: normalize numeric target" "main-6" "$(zsh -c 'source "'"$TMUX_ALIASES_FILE"'"; __tmux_normalize_target 6')"

# ============================================================================
bold ""
bold "─── 2. BASE_SESSION SANITIZATION ───"
# ============================================================================
wipe

# Colons stripped
r=$(GHOSTTY_TMUX_BASE_SESSION="my:session" run)
check "colon → hyphen" "my-session" "$r"
wipe

# Dots stripped
r=$(GHOSTTY_TMUX_BASE_SESSION="my.session" run)
check "dot → hyphen" "my-session" "$r"
wipe

# Spaces stripped
r=$(GHOSTTY_TMUX_BASE_SESSION="my session" run)
check "space → hyphen" "my-session" "$r"
wipe

# Multiple special chars
r=$(GHOSTTY_TMUX_BASE_SESSION="a:b.c d" run)
check "multiple specials → a-b-c-d" "a-b-c-d" "$r"
wipe

# Clean name passes through
r=$(GHOSTTY_TMUX_BASE_SESSION="work" run)
check "clean name preserved" "work" "$r"
wipe

# ============================================================================
bold ""
bold "─── 3. CUSTOM BASE_SESSION ───"
# ============================================================================
r1=$(GHOSTTY_TMUX_BASE_SESSION="dev" run)
r2=$(GHOSTTY_TMUX_BASE_SESSION="dev" run)
r3=$(GHOSTTY_TMUX_BASE_SESSION="dev" run)
check "custom base: inst 1 → dev" "dev" "$r1"
check "custom base: inst 2 → dev-2" "dev-2" "$r2"
check "custom base: inst 3 → dev-3" "dev-3" "$r3"
wipe

# ============================================================================
bold ""
bold "─── 4. FRESH BATCH LAUNCH (4 tabs) ───"
# ============================================================================
r1=$(run); r2=$(run); r3=$(run); r4=$(run)
check "batch: tab 1 → main" "main" "$r1"
check "batch: tab 2 → main-2" "main-2" "$r2"
check "batch: tab 3 → main-3" "main-3" "$r3"
check "batch: tab 4 → main-4" "main-4" "$r4"
check "batch: session count = 4" "4" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 5. GHOSTTY RESTART (reattach to surviving sessions) ───"
# ============================================================================
# Sessions survive from test 4. Clear batch state to simulate fresh launch.
rm -f "$BATCH_FILE" "$PENDING_FILE" "$CLAIMED_FILE" "$MODE_FILE" "$FILL_FILE" "$FILL_MARK_FILE"
r1=$(run); r2=$(run); r3=$(run); r4=$(run)
check "reattach: tab 1 → main" "main" "$r1"
check "reattach: tab 2 → main-2" "main-2" "$r2"
check "reattach: tab 3 → main-3" "main-3" "$r3"
check "reattach: tab 4 → main-4" "main-4" "$r4"
check "reattach: no orphans (still 4)" "4" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 6. DOUBLE RESTART (reattach twice in a row) ───"
# ============================================================================
rm -f "$BATCH_FILE" "$PENDING_FILE" "$CLAIMED_FILE" "$MODE_FILE" "$FILL_FILE" "$FILL_MARK_FILE"
r1=$(run); r2=$(run); r3=$(run); r4=$(run)
check "2nd reattach: tab 1 → main" "main" "$r1"
check "2nd reattach: tab 2 → main-2" "main-2" "$r2"
check "2nd reattach: tab 3 → main-3" "main-3" "$r3"
check "2nd reattach: tab 4 → main-4" "main-4" "$r4"
check "2nd reattach: still 4 sessions" "4" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 7. PARTIAL RESTORE (5 sessions, 3 tabs) ───"
# ============================================================================
wipe
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-2
tmux -L "$SOCKET" new-session -d -s main-3
tmux -L "$SOCKET" new-session -d -s main-4
tmux -L "$SOCKET" new-session -d -s main-5
r1=$(run); r2=$(run); r3=$(run)
check "partial: tab 1 → main" "main" "$r1"
check "partial: tab 2 → main-2" "main-2" "$r2"
check "partial: tab 3 → main-3" "main-3" "$r3"
check "partial: all 5 sessions preserved" "5" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 8. OVERFLOW (2 sessions, 4 tabs) ───"
# ============================================================================
wipe
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-2
r1=$(run); r2=$(run); r3=$(run); r4=$(run)
check "overflow: tab 1 → main" "main" "$r1"
check "overflow: tab 2 → main-2" "main-2" "$r2"
check "overflow: tab 3 → main-3 (new)" "main-3" "$r3"
check "overflow: tab 4 → main-4 (new)" "main-4" "$r4"
check "overflow: grew to 4" "4" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 9. NON-SEQUENTIAL SESSIONS (gaps) ───"
# ============================================================================
wipe
# Simulate sessions with gaps: main, main-3, main-7
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-3
tmux -L "$SOCKET" new-session -d -s main-7
r1=$(run); r2=$(run); r3=$(run)
check "gaps: tab 1 → main" "main" "$r1"
check "gaps: tab 2 → main-3 (lowest unattached)" "main-3" "$r2"
check "gaps: tab 3 → main-7 (next lowest)" "main-7" "$r3"
# A 4th tab should create a new session, filling gap at main-2
rm -f "$BATCH_FILE" "$PENDING_FILE" "$CLAIMED_FILE" "$MODE_FILE" "$FILL_FILE" "$FILL_MARK_FILE"
# Need to re-enter batch mode — start a fresh batch with existing 3 sessions
wipe
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-3
tmux -L "$SOCKET" new-session -d -s main-7
r1=$(run); r2=$(run); r3=$(run); r4=$(run)
check "gaps+overflow: tab 4 → main-2 (fills gap)" "main-2" "$r4"

# ============================================================================
bold ""
bold "─── 10. FORCE_NEW_SESSION ENV VAR ───"
# ============================================================================
wipe
run >/dev/null  # create base
sleep 4
rm -f "$BATCH_FILE" "$PENDING_FILE" "$CLAIMED_FILE" "$MODE_FILE" "$FILL_FILE" "$FILL_MARK_FILE"
r=$(GHOSTTY_TMUX_FORCE_NEW_SESSION=1 run)
check "force new: creates main-2" "main-2" "$r"
r=$(GHOSTTY_TMUX_FORCE_NEW_SESSION=1 run)
check "force new: creates main-3" "main-3" "$r"

# ============================================================================
bold ""
bold "─── 11. STALE LOCK RECOVERY ───"
# ============================================================================
wipe
mkdir -p "$LOCK_DIR"
touch -t 202501010000 "$LOCK_DIR" 2>/dev/null || true
r=$(run)
check "stale lock: recovers → main" "main" "$r"
check_ok "stale lock: lock dir removed" test ! -d "$LOCK_DIR"

# ============================================================================
bold ""
bold "─── 11B. DELAYED RESTORE BURST STABILITY ───"
# ============================================================================
wipe
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-2
tmux -L "$SOCKET" new-session -d -s main-3
tmux -L "$SOCKET" new-session -d -s main-4
r1=$(run)
sleep 4
r2=$(run)
sleep 4
r3=$(run)
check "delayed burst: call 1 → main" "main" "$r1"
check "delayed burst: call 2 → main-2" "main-2" "$r2"
check "delayed burst: call 3 → main-3" "main-3" "$r3"

# ============================================================================
bold ""
bold "─── 12. STALE PENDING + CLAIMED CLEANUP ───"
# ============================================================================
wipe
# Create pending and claimed files, then make them stale
echo "5" > "$PENDING_FILE"
echo "main" > "$CLAIMED_FILE"
echo "main-2" >> "$CLAIMED_FILE"
touch -t 202501010000 "$PENDING_FILE" 2>/dev/null || true
r=$(run)
check "stale batch: resets → main" "main" "$r"
# After stale cleanup, pending should be 1 (this instance)
pending_val=$(cat "$PENDING_FILE" 2>/dev/null)
check "stale batch: pending reset to 1" "1" "$pending_val"

# ============================================================================
bold ""
bold "─── 13. CLAIMED FILE CORRECTNESS ───"
# ============================================================================
wipe
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-2
tmux -L "$SOCKET" new-session -d -s main-3
r1=$(run); r2=$(run); r3=$(run)
claimed=$(sort "$CLAIMED_FILE" 2>/dev/null)
expected=$(printf 'main\nmain-2\nmain-3')
check "claimed: tracks all 3" "$expected" "$claimed"

# New session creation also tracked
r4=$(run)
claimed_last=$(tail -1 "$CLAIMED_FILE" 2>/dev/null)
check "claimed: new session '$r4' also tracked" "$r4" "$claimed_last"

# ============================================================================
bold ""
bold "─── 14. FIND_UNATTACHED_SESSION ORDERING ───"
# ============================================================================
wipe
# Create sessions out of order
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-10
tmux -L "$SOCKET" new-session -d -s main-5
tmux -L "$SOCKET" new-session -d -s main-2
tmux -L "$SOCKET" new-session -d -s main-8
r1=$(run); r2=$(run)
check "ordering: tab 1 → main" "main" "$r1"
check "ordering: tab 2 → main-2 (lowest)" "main-2" "$r2"
r3=$(run)
check "ordering: tab 3 → main-5 (next lowest)" "main-5" "$r3"
r4=$(run)
check "ordering: tab 4 → main-8" "main-8" "$r4"
r5=$(run)
check "ordering: tab 5 → main-10" "main-10" "$r5"

# ============================================================================
bold ""
bold "─── 15. FOREIGN SESSIONS IGNORED ───"
# ============================================================================
wipe
tmux -L "$SOCKET" new-session -d -s main
tmux -L "$SOCKET" new-session -d -s main-2
tmux -L "$SOCKET" new-session -d -s other-session
tmux -L "$SOCKET" new-session -d -s work
tmux -L "$SOCKET" new-session -d -s main-notanumber
r1=$(run); r2=$(run); r3=$(run)
check "foreign: tab 1 → main" "main" "$r1"
check "foreign: tab 2 → main-2" "main-2" "$r2"
# Restore mode now reattaches non-base detached sessions too.
check "foreign: tab 3 → main-notanumber (reattach existing)" "main-notanumber" "$r3"
# No new session needed in this case.
total=$(sess_count)
check "foreign: still 5 total sessions" "5" "$total"

# ============================================================================
bold ""
bold "─── 16. LARGE SESSION COUNT (20 sessions) ───"
# ============================================================================
wipe
tmux -L "$SOCKET" new-session -d -s main
for i in $(seq 2 20); do
    tmux -L "$SOCKET" new-session -d -s "main-$i"
done
check "20 sessions created" "20" "$(sess_count)"
# Reattach to all 20
results=()
for i in $(seq 1 20); do
    results+=("$(run)")
done
check "large: tab 1 → main" "main" "${results[0]}"
check "large: tab 2 → main-2" "main-2" "${results[1]}"
check "large: tab 10 → main-10" "main-10" "${results[9]}"
check "large: tab 20 → main-20" "main-20" "${results[19]}"
check "large: still 20 sessions" "20" "$(sess_count)"
# 21st tab creates new
r21=$(run)
check "large: tab 21 → main-21 (new)" "main-21" "$r21"

# ============================================================================
bold ""
bold "─── 17. RESURRECT INFRASTRUCTURE ───"
# ============================================================================
save_dir="$HOME/.local/share/tmux/resurrect"
check_ok "resurrect save script exists" test -x "$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
check_ok "resurrect restore script exists" test -x "$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
check_ok "resurrect save symlink exists" test -L "$save_dir/last"
check_ok "pane_contents.tar.gz captured" test -f "$save_dir/pane_contents.tar.gz"
check_ok "continuum plugin installed" test -f "$HOME/.tmux/plugins/tmux-continuum/continuum.tmux"

# Verify save file format
save_file="$save_dir/last"
pane_count=$(grep -c '^pane' "$save_file" 2>/dev/null || echo 0)
window_count=$(grep -c '^window' "$save_file" 2>/dev/null || echo 0)
state_count=$(grep -c '^state' "$save_file" 2>/dev/null || echo 0)
check "save: has pane entries (count=$pane_count)" "yes" "$( (( pane_count > 0 )) && echo yes || echo no)"
check "save: has window entries (count=$window_count)" "yes" "$( (( window_count > 0 )) && echo yes || echo no)"
check "save: has state entry" "yes" "$( (( state_count > 0 )) && echo yes || echo no)"

# Claude processes captured
claude_count=$(grep -c 'claude' "$save_file" 2>/dev/null || echo 0)
check "save: claude processes captured (count=$claude_count)" "yes" "$( (( claude_count > 0 )) && echo yes || echo no)"

# Working directories captured
wd_count=$(grep ':/Users/' "$save_file" 2>/dev/null | wc -l | tr -d ' ')
check "save: working directories captured (count=$wd_count)" "yes" "$( (( wd_count > 0 )) && echo yes || echo no)"

# ============================================================================
bold ""
bold "─── 18. RESURRECT RESTORE GUARDS ───"
# ============================================================================
wipe
# When sessions already exist, restore should be skipped
tmux -L "$SOCKET" new-session -d -s main
# resurrect_restore_if_needed checks list-sessions — since main exists, it returns early
r=$(run)
check "restore guard: sessions exist → no double-restore" "main" "$r"
check "restore guard: still just 1 session" "1" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 19. TMUX.CONF PLUGIN SETTINGS (live server) ───"
# ============================================================================
rv=$(tmux show -gv @resurrect-capture-pane-contents 2>/dev/null || echo "MISSING")
check "@resurrect-capture-pane-contents" "on" "$rv"

rv=$(tmux show -gv @continuum-save-interval 2>/dev/null || echo "MISSING")
check "@continuum-save-interval" "5" "$rv"

rv=$(tmux show -gv @continuum-restore 2>/dev/null || echo "MISSING")
check "@continuum-restore" "off" "$rv"

rv=$(tmux show -gv @resurrect-processes 2>/dev/null || echo "MISSING")
check "@resurrect-processes" "~claude" "$rv"

kb_save=$(tmux list-keys 2>/dev/null | grep 'save.sh' | wc -l | tr -d ' ')
check "keybinding: prefix+C-s → resurrect save" "yes" "$( (( kb_save > 0 )) && echo yes || echo no)"

kb_restore=$(tmux list-keys 2>/dev/null | grep 'restore.sh' | wc -l | tr -d ' ')
check "keybinding: prefix+C-r → resurrect restore" "yes" "$( (( kb_restore > 0 )) && echo yes || echo no)"

# Continuum auto-save is tracking
ts=$(tmux show -gv @continuum-save-last-timestamp 2>/dev/null || echo "NONE")
check "continuum: auto-save timestamp exists" "yes" "$( [[ "$ts" != "NONE" && "$ts" != "" ]] && echo yes || echo no)"

# ============================================================================
bold ""
bold "─── 20. TMUX.CONF CORE SETTINGS ───"
# ============================================================================
tc_file="$TMUX_CONF_FILE"
check_ok "default-terminal = tmux-256color" grep -q 'default-terminal "tmux-256color"' "$tc_file"
check_ok "escape-time = 10" grep -q 'escape-time 10' "$tc_file"
check_ok "history-limit = 50000" grep -q 'history-limit 50000' "$tc_file"
check_ok "base-index = 1" grep -q 'base-index 1' "$tc_file"
check_ok "renumber-windows on" grep -q 'renumber-windows on' "$tc_file"
check_ok "mouse on" grep -q 'mouse on' "$tc_file"
check_ok "set-clipboard on" grep -q 'set-clipboard on' "$tc_file"
check_ok "mode-keys vi" grep -q 'mode-keys vi' "$tc_file"
check_ok "prefix C-Space" grep -q 'prefix C-Space' "$tc_file"
check_ok "prefix2 C-a" grep -q 'prefix2 C-a' "$tc_file"
check_ok "unbind C-b" grep -q 'unbind C-b' "$tc_file"
check_ok "TPM init at bottom" grep -q "run.*tpm/tpm" "$tc_file"

# ============================================================================
bold ""
bold "─── 21. GHOSTTY CONFIG ───"
# ============================================================================
gc="$GHOSTTY_CONFIG_FILE"
check_ok "window-save-state = always" grep -q 'window-save-state = always' "$gc"
check_ok "command = ghostty-tmux.sh" grep -q 'command = ~/.config/ghostty/ghostty-tmux.sh' "$gc"
check_ok "confirm-close-surface = false" grep -q 'confirm-close-surface = false' "$gc"
check_ok "window-inherit-working-directory = true" grep -q 'window-inherit-working-directory = true' "$gc"
check_ok "macos-titlebar-style = tabs" grep -q 'macos-titlebar-style = tabs' "$gc"
check_ok "shell-integration = detect" grep -q 'shell-integration = detect' "$gc"
check_ok "copy-on-select = clipboard" grep -q 'copy-on-select = clipboard' "$gc"
check_ok "quick-terminal keybind" grep -q 'toggle_quick_terminal' "$gc"

# ============================================================================
bold ""
bold "─── 22. INSTALL.SH STRUCTURE ───"
# ============================================================================
is="$INSTALL_SCRIPT"
check_ok "has check_tmux()" grep -q 'check_tmux()' "$is"
check_ok "has check_font()" grep -q 'check_font()' "$is"
check_ok "has check_macos_ctrl_space()" grep -q 'check_macos_ctrl_space()' "$is"
check_ok "has install_tpm_plugins()" grep -q 'install_tpm_plugins()' "$is"
check_ok "has prepare_launcher_script()" grep -q 'prepare_launcher_script()' "$is"
check_ok "has link_file()" grep -q 'link_file()' "$is"
check_ok "has link_tmux_aliases()" grep -q 'link_tmux_aliases()' "$is"
check_ok "has remove_deprecated_files()" grep -q 'remove_deprecated_files()' "$is"
check_ok "has ensure_zsh_sources_tmux_aliases()" grep -q 'ensure_zsh_sources_tmux_aliases()' "$is"
check_ok "has handle_macos_app_support()" grep -q 'handle_macos_app_support()' "$is"
check_ok "has reload_tmux_if_running()" grep -q 'reload_tmux_if_running()' "$is"
check_ok "main calls install_tpm_plugins" bash -c 'grep -A30 "^main()" "'"$is"'" | grep -q install_tpm_plugins'
check_ok "main calls reload_tmux_if_running" bash -c 'grep -A30 "^main()" "'"$is"'" | grep -q reload_tmux_if_running'
check_ok "main calls link_tmux_aliases" bash -c 'grep -A30 "^main()" "'"$is"'" | grep -q link_tmux_aliases'
check_ok "main calls remove_deprecated_files" bash -c 'grep -A30 "^main()" "'"$is"'" | grep -q remove_deprecated_files'
check_ok "TPM cloned with --depth 1" grep -q 'clone --depth 1' "$is"

# ============================================================================
bold ""
bold "─── 23. SYMLINK INTEGRITY ───"
# ============================================================================
# Resolve the real repo path (may be behind a symlink like ~/best-ghostty-config → ~/Projects/Tools/...)
repo="$(cd "$REPO_DIR" && pwd -P)"
xdg_config="$HOME/.config/ghostty/config"
xdg_launcher="$HOME/.config/ghostty/ghostty-tmux.sh"
xdg_tmux_aliases="$HOME/.config/ghostty/tmux-aliases.zsh"
xdg_legacy_aliases="$HOME/.config/ghostty/dmux-aliases.zsh"
tmux_conf="$HOME/.tmux.conf"

if [[ -L "$xdg_config" ]]; then
    target=$(readlink "$xdg_config")
    check "symlink: config → repo" "$repo/config" "$target"
else
    check "symlink: config exists" "symlink" "missing"
fi

if [[ -L "$xdg_launcher" ]]; then
    target=$(readlink "$xdg_launcher")
    check "symlink: launcher → repo" "$repo/ghostty-tmux.sh" "$target"
else
    check "symlink: launcher exists" "symlink" "missing"
fi

if [[ -L "$xdg_tmux_aliases" ]]; then
    target=$(readlink "$xdg_tmux_aliases")
    check "symlink: tmux aliases → repo" "$repo/tmux-aliases.zsh" "$target"
elif [[ -L "$xdg_legacy_aliases" ]]; then
    target=$(readlink "$xdg_legacy_aliases")
    check "symlink: legacy aliases → repo" "$repo/dmux-aliases.zsh" "$target"
else
    check "symlink: tmux aliases exists" "symlink" "missing (run ./install.sh)"
fi

if [[ -L "$tmux_conf" ]]; then
    target=$(readlink "$tmux_conf")
    check "symlink: tmux.conf → repo" "$repo/tmux.conf" "$target"
else
    check "symlink: tmux.conf exists" "symlink" "missing"
fi

# ============================================================================
bold ""
bold "─── 24. PENDING COUNTER MONOTONIC INCREMENT ───"
# ============================================================================
wipe
run >/dev/null
p1=$(cat "$PENDING_FILE" 2>/dev/null)
check "pending after 1 launch" "1" "$p1"
run >/dev/null
p2=$(cat "$PENDING_FILE" 2>/dev/null)
check "pending after 2 launches" "2" "$p2"
run >/dev/null
p3=$(cat "$PENDING_FILE" 2>/dev/null)
check "pending after 3 launches" "3" "$p3"

# ============================================================================
bold ""
bold "─── 25. LOCK FILE CLEANUP ───"
# ============================================================================
wipe
run >/dev/null
check "lock released after run" "no" "$( [[ -d "$LOCK_DIR" ]] && echo yes || echo no)"

# ============================================================================
bold ""
bold "─── 26. CUSTOM BASE_SESSION WITH HYPHENS ───"
# ============================================================================
wipe
tmux -L "$SOCKET" new-session -d -s my-app
tmux -L "$SOCKET" new-session -d -s my-app-2
tmux -L "$SOCKET" new-session -d -s my-app-3
r1=$(GHOSTTY_TMUX_BASE_SESSION="my-app" run)
r2=$(GHOSTTY_TMUX_BASE_SESSION="my-app" run)
r3=$(GHOSTTY_TMUX_BASE_SESSION="my-app" run)
check "hyphen base: tab 1 → my-app" "my-app" "$r1"
check "hyphen base: tab 2 → my-app-2" "my-app-2" "$r2"
check "hyphen base: tab 3 → my-app-3" "my-app-3" "$r3"

# ============================================================================
bold ""
bold "─── 27. SINGLE TAB AFTER STALE (normal Cmd+T behavior) ───"
# ============================================================================
wipe
# First: create a batch of 3
r1=$(run); r2=$(run); r3=$(run)
# Wait for stale
sleep 4
rm -f "$BATCH_FILE" "$PENDING_FILE" "$CLAIMED_FILE" "$MODE_FILE" "$FILL_FILE" "$FILL_MARK_FILE"
# Single launch — pending resets to 1, but client_count=0 in NO_ATTACH
# So it attaches to main (base). This is correct: a fresh single-tab launch
# after sessions are running reuses the base.
r=$(run)
check "post-stale single: returns main (base)" "main" "$r"

# ============================================================================
bold ""
bold "─── 28. EMPTY SERVER FRESH START ───"
# ============================================================================
wipe
# No sessions, no pending, no claimed
r=$(run)
check "cold start: creates main" "main" "$r"
check "cold start: exactly 1 session" "1" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 29. RESURRECT SAVE PATH DETECTION ───"
# ============================================================================
# Verify the XDG path is detected
xdg_save="$HOME/.local/share/tmux/resurrect/last"
check "XDG resurrect path exists" "yes" "$( [[ -L "$xdg_save" || -f "$xdg_save" ]] && echo yes || echo no)"

# Verify the target file is a valid resurrect save
target=$(readlink "$xdg_save" 2>/dev/null || echo "$xdg_save")
check "save file starts with tmux_resurrect_" "yes" "$(basename "$target" | grep -q '^tmux_resurrect_' && echo yes || echo no)"

# ============================================================================
bold ""
bold "─── 30. BENCHMARK: LAUNCH LATENCY ───"
# ============================================================================
wipe
# Single cold launch
t_start=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)
run >/dev/null
t_end=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)
cold_ms=$(python3 -c "print(int(($t_end - $t_start) * 1000))" 2>/dev/null || echo "N/A")
dim "  Cold launch: ${cold_ms}ms"
check "cold launch < 2500ms" "yes" "$( [[ "$cold_ms" != "N/A" && "$cold_ms" -lt 2500 ]] && echo yes || echo no)"

# Warm sequential launch (session exists)
rm -f "$BATCH_FILE" "$PENDING_FILE" "$CLAIMED_FILE" "$MODE_FILE" "$FILL_FILE" "$FILL_MARK_FILE"
t_start=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)
run >/dev/null
t_end=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)
warm_ms=$(python3 -c "print(int(($t_end - $t_start) * 1000))" 2>/dev/null || echo "N/A")
dim "  Warm launch: ${warm_ms}ms"
check "warm launch < 1000ms" "yes" "$( [[ "$warm_ms" != "N/A" && "$warm_ms" -lt 1000 ]] && echo yes || echo no)"

# Batch of 10 sequential launches
wipe
t_start=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)
for i in $(seq 1 10); do run >/dev/null; done
t_end=$(python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s)
batch_ms=$(python3 -c "print(int(($t_end - $t_start) * 1000))" 2>/dev/null || echo "N/A")
dim "  10-tab batch: ${batch_ms}ms (avg $( [[ "$batch_ms" != "N/A" ]] && echo "$((batch_ms / 10))" || echo "N/A")ms/tab)"
check "10-tab batch < 10000ms" "yes" "$( [[ "$batch_ms" != "N/A" && "$batch_ms" -lt 10000 ]] && echo yes || echo no)"
check "10-tab batch: 10 sessions created" "10" "$(sess_count)"

# ============================================================================
bold ""
bold "─── 31. STRESS: RAPID 10-TAB PARALLEL LAUNCH ───"
# ============================================================================
wipe
# Launch 10 instances truly in parallel via background jobs
pids=()
for i in $(seq 1 10); do
    GHOSTTY_TMUX_SOCKET_NAME="$SOCKET" GHOSTTY_TMUX_STATE_KEY="$STATE_KEY" GHOSTTY_TMUX_NO_ATTACH=1 "$SCRIPT" > "/tmp/bgc_par_$i" 2>/dev/null &
    pids+=($!)
done
# Wait for all to complete
for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
# Collect results
par_results=()
for i in $(seq 1 10); do
    par_results+=("$(cat "/tmp/bgc_par_$i" 2>/dev/null)")
    rm -f "/tmp/bgc_par_$i"
done
# Verify: exactly 10 unique sessions, all named main or main-N
unique_sessions=$(printf '%s\n' "${par_results[@]}" | sort -u | wc -l | tr -d ' ')
check "parallel: 10 unique session names" "10" "$unique_sessions"
check "parallel: 10 tmux sessions" "10" "$(sess_count)"
# Verify main is among the results
has_main=$(printf '%s\n' "${par_results[@]}" | grep -cxF 'main')
check "parallel: 'main' claimed exactly once" "1" "$has_main"
# No duplicates
dup_count=$(printf '%s\n' "${par_results[@]}" | sort | uniq -d | wc -l | tr -d ' ')
check "parallel: no duplicate assignments" "0" "$dup_count"

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
bold "════════════════════════════════════════════════════════"
if (( FAIL == 0 )); then
    green "  ALL $TOTAL TESTS PASSED"
else
    red "  $FAIL FAILED / $TOTAL TOTAL  ($PASS passed)"
fi
bold "════════════════════════════════════════════════════════"
echo ""

exit $FAIL
