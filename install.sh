#!/usr/bin/env bash
set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
readonly TARGET_FILE="$CONFIG_DIR/config"
readonly SOURCE_FILE="$REPO_DIR/config"

log_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

main() {
    [[ -f "$SOURCE_FILE" ]] || log_error "Source config missing: $SOURCE_FILE"

    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_info "Creating directory: $CONFIG_DIR"
        mkdir -p "$CONFIG_DIR"
    fi

    if [[ -e "$TARGET_FILE" || -L "$TARGET_FILE" ]]; then
        local current_link
        current_link=$(readlink "$TARGET_FILE" || true)

        if [[ "$current_link" == "$SOURCE_FILE" ]]; then
            log_success "Symlink already established."
            exit 0
        fi

        local backup_file="${TARGET_FILE}.bak.$(date +%s)"
        log_info "Existing configuration detected. Backing up to: $backup_file"
        mv "$TARGET_FILE" "$backup_file"
    fi

    log_info "Linking $TARGET_FILE -> $SOURCE_FILE"
    ln -s "$SOURCE_FILE" "$TARGET_FILE"

    log_success "Ghostty configuration installed successfully."
}

main "$@"