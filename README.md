# best-ghostty-config

Ghostty + tmux, wired together. Persistent sessions, independent tabs, sane defaults, Catppuccin theme.

## How it works

```
┌─ Ghostty (terminal app) ──────────────────────────┐
│                                                     │
│   Tab 1            Tab 2            Tab 3           │
│  ┌───────────┐   ┌───────────┐   ┌───────────┐     │
│  │ tmux      │   │ tmux      │   │ tmux      │     │
│  │ client ───┤   │ client ───┤   │ client ───┤     │
│  └───────────┘   └───────────┘   └───────────┘     │
└─────────┬──────────────┬──────────────┬─────────────┘
          │              │              │
          ▼              ▼              ▼
┌─ tmux server (background process) ─────────────────┐
│                                                     │
│  session: main     session: main-2   session: main-3│
│   └─ windows        └─ windows       └─ windows    │
│      └─ panes          └─ panes         └─ panes   │
└─────────────────────────────────────────────────────┘
```

**Ghostty** is the terminal UI — fonts, theme, opacity, keybindings.
**tmux** is the persistence layer — sessions, panes, processes that survive after Ghostty closes.

Each Ghostty tab connects to its own tmux session. No mirroring. The launcher (`ghostty-tmux.sh`) handles this with atomic locking so even simultaneous tab restores get separate sessions.

### Why persistence is so strong

Two layers working together:

1. **Ghostty** restores window position, size, and tab layout on relaunch (`window-save-state = always`)
2. **tmux** keeps sessions, windows, panes, and running processes alive in the background

Quit Ghostty → reopen → everything is exactly where you left it. By design.

## Quick reference

```
GHOSTTY (Cmd-based)                     tmux (prefix first, then key)
                                        prefix = Ctrl+Space or Ctrl+A

Ctrl+`            quick terminal        |         split right
Cmd+T             new tab               -         split down
Cmd+W             close pane            h/j/k/l   navigate (vim)
Cmd+Shift+W       close tab             H/J/K/L   resize (repeatable)
Cmd+Shift+←/→     prev/next tab         z         zoom pane
Cmd+1–9           jump to tab           x         kill pane
Cmd+D             split right           >/<       swap pane
Cmd+Shift+D       split down            c         new window
Cmd+Alt+Arrow     focus split           n/p       next/prev window
Cmd+Ctrl+Arrow    resize split          1–9       jump to window
Cmd+Shift+E       equalize splits       X         kill window
Cmd+Shift+F       zoom split            d         detach
Cmd+Shift+P       command palette       s         session picker
Cmd+Shift+,       reload config         [         copy mode
Cmd+Shift+S       secure input          r         reload config
Cmd+Shift+I       inspector
Cmd+= / - / 0    font size             Copy: v=select y=copy Esc=exit
Ctrl+Cmd+F        fullscreen            Search: /=fwd ?=back n/N=next
```

Full reference: [`docs/cheatsheet/keybindings.md`](docs/cheatsheet/keybindings.md)

## Shutdown & cleanup

| I want to... | Do this | What survives |
|---|---|---|
| Leave safely, keep work running | `prefix+d` or `Cmd+Q` | Everything |
| Close one pane | `prefix+x` | Other panes, windows, sessions |
| Close one tmux window | `prefix+X` | Other windows, sessions |
| Kill one session | `tmux kill-session -t <name>` | Other sessions |
| Kill all tmux | `tmux kill-server` | Nothing |

## Install

```bash
git clone https://github.com/ekarya0x/best-ghostty-config.git ~/.ghostty-config
cd ~/.ghostty-config && chmod +x install.sh && ./install.sh
```

The installer handles tmux installation, config symlinking with timestamped backups, launcher wiring, the macOS Ctrl+Space conflict, JetBrains Mono detection, and live tmux reload.

| Source | Target |
|---|---|
| `config` | `~/.config/ghostty/config` |
| `config` | `~/Library/Application Support/com.mitchellh.ghostty/config` |
| `ghostty-tmux.sh` | `~/.config/ghostty/ghostty-tmux.sh` |
| `tmux.conf` | `~/.tmux.conf` |

### Update

```bash
cd ~/.ghostty-config && git pull --ff-only && ./install.sh
```

Quit Ghostty (`Cmd+Q`) and relaunch.

### Requirements

- [Ghostty](https://ghostty.org/) 1.2+
- [tmux](https://github.com/tmux/tmux) 3.2+ (installer offers `brew install`)
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/)

## Daily workflows

### Persistent mode (default)

Work normally. Leave with `Cmd+Q` or `prefix+d`. Reopen later — everything is still there.

```bash
tmux ls                    # see what's running
tmux attach -t main        # reattach to a session
tmux attach -t main-2
```

### Clean slate

```bash
tmux kill-session -t main    # kill one
tmux kill-session -t main-2  # kill another
tmux kill-server             # or nuke everything
```

### Named sessions

Name sessions after projects instead of `main-N`:

```bash
tmux new-session -Ad -s api -c ~/Projects/api
tmux new-session -Ad -s web -c ~/Projects/web
tmux attach -t api
```

### Session hopping

```bash
tmux switch-client -t main-2         # from inside tmux
# or: prefix + s                     # session picker
```

### Cleanup stale sessions

```bash
tmux ls -F '#{session_name} attached=#{session_attached}'
tmux kill-session -t main-3          # kill detached ones you don't need
```

### Remote attach

```bash
ssh your-host -t tmux attach -t main
```

## Common confusion

**Ghostty tab ≠ tmux window.** `Cmd+T` creates a Ghostty tab (and a new tmux session). `prefix+c` creates a tmux window inside the current session. Different layers.

**Mirroring is not a bug.** Two clients on the same session will mirror. The launcher prevents this by giving each tab its own session. If you manually `tmux attach -t main` twice, they mirror — that's correct.

**`Cmd+Q` is safe.** It disconnects Ghostty clients. tmux sessions keep running.

**"I quit and reopened and everything is still there."** Correct. To terminate sessions, kill them explicitly (see shutdown table).

**If restoration feels too sticky,** change `window-save-state` from `always` to `default`. tmux persistence still works — you just lose Ghostty's tab/window restoration.

## Ghostty settings

Every setting below differs from stock defaults.

### Typography

| Setting | Value | Note |
|---|---|---|
| `font-family` | `JetBrains Mono` | Clear `0O` `1lI` `[]{}` distinction |
| `font-size` | `15` | Readable on Retina without wasting space |
| `font-thicken` | `true` | Prevents thin strokes from vanishing on HiDPI |
| `adjust-cell-height` | `2` | 2px extra line spacing |
| `font-feature` | `calt`, `liga` | Ligatures: `!=` `=>` `>=` `<=` `\|\|` as glyphs |

### Theme

| Setting | Value | Note |
|---|---|---|
| `theme` | `light:Catppuccin Latte, dark:Catppuccin Mocha` | Follows macOS appearance |
| `window-theme` | `auto` | Chrome matches system |

### Window

| Setting | Value | Note |
|---|---|---|
| `background-opacity` | `0.8` | 80% — desktop shows through |
| `background-blur` | `20` | Blurs what's behind the window |
| `macos-titlebar-style` | `tabs` | Tabs in titlebar, saves vertical space |
| `window-colorspace` | `display-p3` | Wide gamut on modern Macs |
| `window-padding-x` / `y` | `12` | 12px padding all sides |
| `window-padding-balance` | `true` | Centers content in the cell grid |
| `window-height` × `width` | `30` × `120` | 30 rows, 120 columns |
| `window-save-state` | `always` | Restores layout on relaunch |
| `confirm-close-surface` | `false` | No close dialog — tmux handles persistence |

### Input & cursor

| Setting | Value | Note |
|---|---|---|
| `cursor-style` | `bar` | Thin bar |
| `cursor-style-blink` | `true` | Easier to spot after looking away |
| `cursor-opacity` | `0.9` | Slightly translucent |
| `cursor-color` | `cell-foreground` | Adapts to light/dark automatically |
| `unfocused-split-opacity` | `0.85` | Default 0.7 dims too hard |
| `mouse-hide-while-typing` | `true` | Hides pointer during input |
| `copy-on-select` | `clipboard` | Selection goes to system clipboard |
| `mouse-scroll-multiplier` | `2` | Normalized scroll speed |
| `macos-option-as-alt` | `left` | Left Option = Alt (`Alt+B`, `Alt+F`, `Alt+D`) |

### Quick terminal

| Setting | Value | Note |
|---|---|---|
| `quick-terminal-screen` | `mouse` | Drops on screen where your mouse is |
| `quick-terminal-animation-duration` | `0.15` | Snappier than default 0.2s |

### Shell & clipboard

| Setting | Value | Note |
|---|---|---|
| `shell-integration-features` | `no-cursor,sudo,title,ssh-env,ssh-terminfo` | sudo passthrough, SSH terminfo propagation, config-controlled cursor |
| `clipboard-read` | `allow` | No prompt when tmux reads clipboard via OSC 52 |

### tmux & scrollback

| Setting | Value | Note |
|---|---|---|
| `command` | `~/.config/ghostty/ghostty-tmux.sh` | Each tab gets its own session via atomic locking |
| `scrollback-limit` | `25000000` (25MB) | 2.5× default for large builds and logs |

## tmux settings

| Setting | Default | Ours | Note |
|---|---|---|---|
| `prefix` | `C-b` | `C-Space` + `C-a` fallback + `C-@` alias | Ergonomic with robust fallbacks |
| `default-terminal` | `screen` | `tmux-256color` | Correct color terminfo |
| `terminal-overrides` | — | `xterm-ghostty:RGB` | 24-bit true color |
| `extended-keys` | `off` | `on` | Full modifier reporting |
| `escape-time` | `500` | `10` | Near-instant Escape, safe over high-latency SSH |
| `history-limit` | `2000` | `50000` | 50K lines per pane |
| `base-index` | `0` | `1` | Windows start at 1, matches keyboard |
| `renumber-windows` | `off` | `on` | No gaps after closing a window |
| `mouse` | `off` | `on` | Click, drag, scroll |
| `set-clipboard` | `external` | `on` | OSC 52 clipboard |
| `mode-keys` | `emacs` | `vi` | Vi in copy mode |
| Splits | `"` / `%` | `\|` / `-` | Visual: `\|` vertical, `-` horizontal |
| Navigation | arrows | `h/j/k/l` | Vim, home row |
| Resize | `Ctrl+arrow` | `H/J/K/L` | Same keys shifted, repeatable |

## Troubleshooting

**Ghostty crashes with `exec: tmux: not found`**

The launcher adds Homebrew paths before resolving tmux. Re-run `install.sh` to refresh the symlink and `command` line.

**New tabs still mirror one session**

The launcher serializes simultaneous launches with atomic locking. If tabs still mirror:

```bash
grep '^command = ' ~/.config/ghostty/config    # should point to launcher
readlink ~/.config/ghostty/ghostty-tmux.sh     # should point to repo
```

**Ctrl+Space doesn't work**

macOS captures it for input source switching. System Settings → Keyboard → Keyboard Shortcuts → Input Sources → uncheck "Select the previous input source." Installer offers to do this. Use `Ctrl+A` as immediate fallback.

**Config changes have no effect**

macOS reads `~/Library/Application Support/com.mitchellh.ghostty/config` with higher priority. A stale file there shadows your config. Re-run `install.sh` to fix both locations.

**Keyboard binds don't work but right-click tmux does**

Prefix delivery is failing. Reload and verify:

```bash
tmux source-file ~/.tmux.conf
tmux show -gv prefix       # C-Space
tmux show -gv prefix2      # C-a
```

### Verification

```bash
ls -la ~/.config/ghostty/config                                          # symlink
ls -la ~/.config/ghostty/ghostty-tmux.sh                                 # exists, executable
ls -la "$HOME/Library/Application Support/com.mitchellh.ghostty/config"  # symlink
grep '^command = ' ~/.config/ghostty/config                              # points to launcher
tmux show -gv prefix                                                     # C-Space
tmux show -gv prefix2                                                    # C-a
```

## File structure

```
best-ghostty-config/
  config              Ghostty settings + keybindings
  ghostty-tmux.sh     Launcher — independent sessions per tab
  tmux.conf           tmux settings + keybindings
  install.sh          Symlinker, dependency checks, backups
  docs/
    cheatsheet/
      keybindings.md  Printable keybinding reference
```

## License

[MIT](LICENSE)
