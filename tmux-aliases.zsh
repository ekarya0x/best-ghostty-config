#!/usr/bin/env zsh

# tmux shortcuts for fast session navigation and safe cleanup.
# Load from ~/.zshrc:
#   [[ -f ~/.config/ghostty/tmux-aliases.zsh ]] && source ~/.config/ghostty/tmux-aliases.zsh

alias tls='tmux ls -F "#{session_name} attached=#{session_attached} windows=#{session_windows}"'
alias tmain='tgo main'

tgo() {
    local target="$1"
    if [[ -z "$target" ]]; then
        echo "usage: tgo <session>"
        tls
        return 1
    fi

    if ! tmux has-session -t "$target" 2>/dev/null; then
        echo "session not found: $target"
        tls
        return 1
    fi

    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$target"
    else
        tmux attach-session -t "$target"
    fi
}

tnew() {
    local name="${1:-}"
    local cwd="${2:-$PWD}"

    if [[ -z "$name" ]]; then
        if ! tmux has-session -t "main" 2>/dev/null; then
            name="main"
        else
            local i=2
            while tmux has-session -t "main-${i}" 2>/dev/null; do
                i=$((i + 1))
            done
            name="main-${i}"
        fi
    fi

    tmux new-session -Ad -s "$name" -c "$cwd" || return 1
    tgo "$name"
}

tprev() {
    if [[ -z "${TMUX:-}" ]]; then
        echo "tprev works inside tmux only"
        return 1
    fi

    local current target
    current="$(tmux display-message -p '#S' 2>/dev/null)"
    target="$(tmux list-sessions -F '#{session_name} #{session_last_attached}' \
        | awk -v current="$current" '$1 != current { print }' \
        | sort -k2,2nr \
        | head -n1 \
        | awk '{print $1}')"

    if [[ -z "$target" ]]; then
        echo "no other sessions available"
        return 1
    fi

    tmux switch-client -t "$target"
}

tkill() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        if [[ -n "${TMUX:-}" ]]; then
            target="$(tmux display-message -p '#S' 2>/dev/null)"
        else
            echo "usage: tkill <session>"
            return 1
        fi
    fi

    if ! tmux has-session -t "$target" 2>/dev/null; then
        echo "session not found: $target"
        tls
        return 1
    fi

    if [[ -n "${TMUX:-}" ]]; then
        local current fallback
        current="$(tmux display-message -p '#S' 2>/dev/null)"
        if [[ "$target" == "$current" ]]; then
            fallback="$(tmux list-sessions -F '#{session_name}' | grep -vxF "$current" | head -n1)"
            if [[ -z "$fallback" ]]; then
                echo "refusing to kill last session: $current"
                return 1
            fi
            tmux switch-client -t "$fallback" || return 1
        fi
    fi

    tmux kill-session -t "$target"
}

tkillc() {
    if [[ -z "${TMUX:-}" ]]; then
        echo "tkillc works inside tmux only"
        return 1
    fi
    tkill "$(tmux display-message -p '#S' 2>/dev/null)"
}

tprune() {
    local keep=""
    local killed=0

    if [[ -n "${TMUX:-}" ]]; then
        keep="$(tmux display-message -p '#S' 2>/dev/null)"
    fi

    while IFS=' ' read -r session attached; do
        if [[ "$attached" == "0" && "$session" == main-* && "$session" != "$keep" ]]; then
            tmux kill-session -t "$session" && echo "killed: $session"
            killed=$((killed + 1))
        fi
    done < <(tmux ls -F '#{session_name} #{session_attached}' 2>/dev/null)

    echo "pruned $killed session(s)"
}
