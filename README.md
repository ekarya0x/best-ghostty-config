# Ghostty Configuration

The best production-ready configuration for the [Ghostty](https://ghostty.org/) terminal emulator.

## Features

- **Dynamic Theming:** Auto-switches between Catppuccin Latte (Light) and Mocha (Dark).
- **Typography:** JetBrains Mono with ligatures and thickened strokes.
- **Windowing:** Native macOS tabs in titlebar, 80% opacity with 20px blur, inherits working directory on new tabs and splits.
- **tmux Integration:** Auto-launches a persistent tmux session. Pane splitting, vim-style navigation, resize, zoom. Sessions survive disconnects and can be reattached from any device over SSH/Tailscale.
- **Workflow:** Quake-style global dropdown terminal, 25MB scrollback buffer, and 45+ keybindings.
- **Security:** Bracketed paste protection, controlled clipboard access, and trailing whitespace trimming on copy.

## Automated Installation

```bash
git clone https://github.com/ekarya0x/best-ghostty-config.git ~/.ghostty-config
cd ~/.ghostty-config
chmod +x install.sh
./install.sh
```

This symlinks both `config` and `tmux.conf` to their expected locations. Existing configs are backed up automatically.

## tmux Keybindings

Prefix: `Ctrl+Space`

| Key | Action |
|---|---|
| `prefix + \|` | Split pane right |
| `prefix + -` | Split pane down |
| `prefix + h/j/k/l` | Navigate panes (vim-style) |
| `prefix + H/J/K/L` | Resize panes |
| `prefix + z` | Zoom/unzoom current pane |
| `prefix + x` | Kill pane |
| `prefix + c` | New window |
| `prefix + n/p` | Next/previous window |
| `prefix + 1-9` | Go to window by number |
| `prefix + d` | Detach session |
| `prefix + r` | Reload tmux config |

## Remote Attach

Sessions persist across disconnects. Reattach from anywhere:

```bash
ssh your-host -t tmux attach -t main
```

## Requirements

- [Ghostty](https://ghostty.org/) terminal emulator
- [tmux](https://github.com/tmux/tmux)
- JetBrains Mono font

## License

[MIT](LICENSE)
