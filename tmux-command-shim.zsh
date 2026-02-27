#!/usr/bin/env zsh
set -euo pipefail

aliases_file="${TMUX_ALIASES_FILE:-$HOME/.config/ghostty/tmux-aliases.zsh}"
cmd_name="$(basename "$0")"

if [[ ! -f "$aliases_file" ]]; then
    echo "missing tmux aliases file: $aliases_file" >&2
    exit 1
fi

source "$aliases_file"

cmd_type="$(whence -w "$cmd_name" 2>/dev/null || true)"
case "$cmd_type" in
    *"function")
        ;;
    *)
        echo "command shim target is not a function: $cmd_name" >&2
        exit 1
        ;;
esac

"$cmd_name" "$@"
