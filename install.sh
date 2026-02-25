#!/usr/bin/env bash
set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
readonly MACOS_CONFIG="$HOME/Library/Application Support/com.mitchellh.ghostty"

log_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_success() { echo -e "\033[1;32m[OK]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERR]\033[0m $1" >&2; exit 1; }

# --- Dependency checks ---

check_tmux() {
    if command -v tmux &>/dev/null; then
        log_success "tmux found: $(command -v tmux)"
        return 0
    fi

    log_warn "tmux is not installed."
    log_info "This config sets 'command = <path>/tmux new-session -A -s main'."
    log_info "Ghostty will crash on launch without tmux."
    echo ""

    if command -v brew &>/dev/null; then
        read -rp "$(echo -e "\033[1;34m[INFO]\033[0m") Install tmux via Homebrew? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            brew install tmux
        else
            log_error "tmux is required. Install manually: brew install tmux"
        fi
    else
        log_error "tmux is required. Install: https://github.com/tmux/tmux/wiki/Installing"
    fi
}

check_font() {
    # Best-effort check for JetBrains Mono on macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        if system_profiler SPFontsDataType 2>/dev/null | grep -qi "JetBrains Mono"; then
            log_success "JetBrains Mono font found."
        else
            log_warn "JetBrains Mono not detected. Install: https://www.jetbrains.com/lp/mono/"
            log_info "Ghostty will fall back to the system monospace font without it."
        fi
    fi
}

check_macos_ctrl_space() {
    if [[ "$(uname)" != "Darwin" ]]; then
        return 0
    fi

    # Key 60 = "Select the previous input source" (Ctrl+Space).
    # We use PlistBuddy because defaults dictionary updates do NOT overwrite
    # existing keys — they silently no-op, which is why the previous fix failed.
    local plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"

    if [[ ! -f "$plist" ]]; then
        log_warn "Symbolic hotkeys plist not found. Cannot check Ctrl+Space status."
        log_info "Manually check: System Settings > Keyboard > Keyboard Shortcuts > Input Sources"
        return 0
    fi

    local enabled
    enabled=$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:60:enabled" "$plist" 2>/dev/null || echo "unknown")

    if [[ "$enabled" == "true" || "$enabled" == "unknown" ]]; then
        echo ""
        log_warn "macOS captures Ctrl+Space for input source switching."
        log_warn "This blocks the tmux prefix key (Ctrl+Space)."
        log_info "Fix: System Settings > Keyboard > Keyboard Shortcuts > Input Sources"
        log_info "     Uncheck 'Select the previous input source' (^Space)"
        echo ""
        read -rp "$(echo -e "\033[1;34m[INFO]\033[0m") Disable it automatically? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            if disable_macos_ctrl_space "$plist"; then
                # Activate without logout
                /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
                log_success "Ctrl+Space released from macOS. tmux prefix will now work."
            else
                log_warn "Automatic disable failed. Disable manually in System Settings."
            fi
        else
            log_warn "tmux prefix (Ctrl+Space) will not work until you disable this manually."
        fi
    else
        log_success "macOS Ctrl+Space shortcut already disabled."
    fi
}

disable_macos_ctrl_space() {
    local plist="$1"

    if /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:60:enabled false" "$plist" &>/dev/null; then
        return 0
    fi

    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys dict" "$plist" &>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60 dict" "$plist" &>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:60:enabled" "$plist" &>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:60:enabled bool false" "$plist" &>/dev/null
}

# --- Path patching ---

patch_tmux_path() {
    local tmux_path
    tmux_path="$(command -v tmux 2>/dev/null)" || log_error "tmux not found after dependency check."

    local config_file="$REPO_DIR/config"
    local current
    current="$(grep '^command = ' "$config_file" || true)"

    local expected="command = ${tmux_path} new-session -A -s main"
    if [[ "$current" == "$expected" ]]; then
        log_success "tmux path already correct: $tmux_path"
        return 0
    fi

    if [[ -z "$current" ]]; then
        log_info "No 'command' line in config. Appending tmux auto-launch command."
        echo "$expected" >> "$config_file"
    else
        log_info "Patching tmux path: $tmux_path"
        sed -i.tmp "s|^command = .*|$expected|" "$config_file"
        rm -f "${config_file}.tmp"
    fi
    log_success "Config patched: $expected"
}

# --- Symlink management ---

link_file() {
    local source="$1" target="$2" label="$3"

    [[ -f "$source" ]] || log_error "Source missing: $source"

    local target_dir
    target_dir="$(dirname "$target")"
    if [[ ! -d "$target_dir" ]]; then
        log_info "Creating directory: $target_dir"
        mkdir -p "$target_dir"
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        local current_link
        current_link=$(readlink "$target" || true)

        if [[ "$current_link" == "$source" ]]; then
            log_success "$label: symlink OK."
            return 0
        fi

        local backup_file="${target}.bak.$(date +%s)"
        log_info "$label: backing up existing config to ${backup_file##*/}"
        mv "$target" "$backup_file"
    fi

    ln -s "$source" "$target"
    log_success "$label: $target -> $source"
}

handle_macos_app_support() {
    # Ghostty on macOS reads ~/Library/Application Support/com.mitchellh.ghostty/config
    # with HIGHER priority than ~/.config/ghostty/config.
    # Always manage this path so a future auto-generated file cannot shadow the repo config.
    [[ "$(uname)" == "Darwin" ]] || return 0

    link_file "$REPO_DIR/config" "$MACOS_CONFIG/config" "Ghostty (macOS App Support)"
}

reload_tmux_if_running() {
    if ! command -v tmux &>/dev/null; then
        return 0
    fi

    if tmux ls &>/dev/null; then
        if tmux source-file "$HOME/.tmux.conf" &>/dev/null; then
            log_success "Reloaded tmux config in running server."
            local p1 p2
            p1="$(tmux show -gv prefix 2>/dev/null || echo "unknown")"
            p2="$(tmux show -gv prefix2 2>/dev/null || echo "unknown")"
            log_info "tmux prefixes active: ${p1} (primary), ${p2} (fallback)"
        else
            log_warn "tmux server detected but config reload failed. Run: tmux source-file ~/.tmux.conf"
        fi
    fi
}

# --- Main ---

main() {
    echo ""
    echo "  best-ghostty-config installer"
    echo "  =============================="
    echo ""

    check_tmux
    check_font
    check_macos_ctrl_space
    patch_tmux_path

    echo ""
    link_file "$REPO_DIR/config" "$XDG_CONFIG/config" "Ghostty (XDG)"
    handle_macos_app_support
    link_file "$REPO_DIR/tmux.conf" "$HOME/.tmux.conf" "tmux"
    reload_tmux_if_running

    echo ""
    log_success "Done. Quit Ghostty (Cmd+Q) and relaunch."
    echo ""
}

main "$@"
