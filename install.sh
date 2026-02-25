#!/usr/bin/env bash
set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"

log_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

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
            log_success "$label symlink already established."
            return 0
        fi

        local backup_file="${target}.bak.$(date +%s)"
        log_info "Existing $label config detected. Backing up to: $backup_file"
        mv "$target" "$backup_file"
    fi

    log_info "Linking $target -> $source"
    ln -s "$source" "$target"
    log_success "$label configuration installed."
}

main() {
    link_file "$REPO_DIR/config" "$CONFIG_DIR/config" "Ghostty"
    link_file "$REPO_DIR/tmux.conf" "$HOME/.tmux.conf" "tmux"

    log_success "All configurations installed successfully."
}

main "$@"
