# best-ghostty-config

A curated, production-ready configuration for [Ghostty](https://ghostty.org/) with integrated tmux. One-click install.

## Install

```bash
git clone https://github.com/ekarya0x/best-ghostty-config.git ~/.ghostty-config
cd ~/.ghostty-config && chmod +x install.sh && ./install.sh
```

`install.sh` handles everything: installs tmux if missing, wires Ghostty to a launcher script that fixes the tab/session bug, disables the macOS Ctrl+Space conflict, checks for JetBrains Mono, and symlinks configs into place. Existing configs are backed up with a `.bak` timestamp.

| Source | Target | Notes |
|---|---|---|
| `config` | `~/.config/ghostty/config` | XDG location |
| `ghostty-tmux.sh` | `~/.config/ghostty/ghostty-tmux.sh` | Launcher used by `command = ...` |
| `config` | `~/Library/Application Support/com.mitchellh.ghostty/config` | macOS App Support (higher priority — must also be symlinked) |
| `tmux.conf` | `~/.tmux.conf` | |

## Update Local Install

```bash
cd ~/.ghostty-config
git pull --ff-only
./install.sh
tmux source-file ~/.tmux.conf
```

Then fully quit Ghostty (`Cmd+Q`) and relaunch.

## Requirements

- [Ghostty](https://ghostty.org/) 1.2+
- [tmux](https://github.com/tmux/tmux) 3.2+ (`install.sh` will offer to `brew install` it)
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/) font

## Troubleshooting

**Is this an immediate-fix issue?**

Yes. If config precedence is wrong, tmux workflows fail completely. If `Ctrl+Space` is intercepted, use the built-in fallback prefix `Ctrl+A`.

**Ghostty crashes on launch with `exec: tmux: not found`**

This config launches tmux through `~/.config/ghostty/ghostty-tmux.sh`. That launcher adds common Homebrew paths and resolves tmux robustly. Re-run `install.sh` so the launcher symlink and `command = ...` line are refreshed.

**New Ghostty tabs still mirror one tmux session**

Previous versions had a race condition: when Ghostty restores saved tabs (`window-save-state = always`), all tabs launch `ghostty-tmux.sh` nearly simultaneously. Every instance checked `has_attached_clients()` before any client finished attaching, saw zero clients, and fell through to the base session — mirroring every tab. The current launcher uses `mkdir`-based atomic locking with a pending-instance counter to serialize concurrent launches. The first instance claims the base session; all others create independent sessions.

If tabs still mirror after updating, re-run `install.sh` and verify:

```bash
grep '^command = ' ~/.config/ghostty/config
readlink ~/.config/ghostty/ghostty-tmux.sh
```

Expected command target: an absolute path ending in `/.config/ghostty/ghostty-tmux.sh`.

**tmux keybindings don't work (Ctrl+Space prefix ignored)**

macOS captures `Ctrl+Space` for input source switching. Fix: System Settings → Keyboard → Keyboard Shortcuts → Input Sources → uncheck "Select the previous input source." `install.sh` offers to do this automatically.
If `Ctrl+Space` still does not reach tmux, use `Ctrl+A` as fallback prefix (configured as `prefix2`).
This config also maps `C-@` (NUL), since some terminals send `Ctrl+Space` as `C-@`.

**Right-click tmux menu works, but keyboard keybinds do not**

This means tmux is running, but prefix key delivery is failing. Re-apply live config and verify prefix mapping:

```bash
tmux source-file ~/.tmux.conf
tmux show -gv prefix
tmux show -gv prefix2
tmux list-keys -T root | grep 'C-@'
```

Then test `Ctrl+Space` + `h` and `Ctrl+A` + `h`.

**Config changes have no effect**

Ghostty on macOS reads from `~/Library/Application Support/com.mitchellh.ghostty/config` with higher priority than `~/.config/ghostty/config`. If a stale file exists at the App Support path, it shadows the XDG symlink. Re-run `install.sh` to fix both locations.

**Am I being hacked if I see an App Support config overriding my dotfile?**

Usually no. This is normal Ghostty/macOS path precedence, not evidence of compromise by itself. The installer now always manages both config locations to prevent shadowing.

### Verification Checklist (Pass/Fail)

Run these after install:

```bash
ls -la ~/.config/ghostty/config
ls -la ~/.config/ghostty/ghostty-tmux.sh
ls -la "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
grep '^command = ' ./config
grep -n 'PlistBuddy' ./install.sh
grep -n '^set -g prefix C-Space' ./tmux.conf
grep -n '^set -g prefix2 C-a' ./tmux.conf
grep -n 'bind -n C-@ switch-client -T prefix' ./tmux.conf
/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:60:enabled" "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
```

Expected:

- both config paths are symlinks to this repo's `config`
- `~/.config/ghostty/ghostty-tmux.sh` exists and is executable
- `command = .../ghostty-tmux.sh`
- `install.sh` contains `PlistBuddy`-based Ctrl+Space handling
- `tmux.conf` has `prefix = C-Space`, `prefix2 = C-a`, and `C-@` prefix alias
- symbolic hotkey 60 prints `false`

---

## What This Config Changes (vs. Ghostty Defaults)

Every setting below differs from the stock Ghostty 1.2.3 defaults. Settings left at their default are not included in the config file.

### Typography

| Setting | Default | Ours | Why |
|---|---|---|---|
| `font-family` | *(system monospace)* | `JetBrains Mono` | Purpose-built for code. Tall x-height, clear distinction between `0O`, `1lI`, `[]{}`. |
| `font-size` | `13` | `15` | 13pt is small on Retina. 15pt is readable at arm's length without wasting space. |
| `font-thicken` | `false` | `true` | Adds sub-pixel weight to thin strokes. Prevents hairline stems from disappearing on high-DPI. |
| `adjust-cell-height` | *0* | `2` | 2px extra line spacing. Reduces visual density without losing terminal rows. |
| `font-feature` | *(none)* | `calt`, `liga` | Enables contextual alternates and ligatures: `!=`, `=>`, `>=`, `<=`, `||` render as single glyphs. |

### Theme

| Setting | Default | Ours | Why |
|---|---|---|---|
| `theme` | *(none)* | `light:Catppuccin Latte,dark:Catppuccin Mocha` | Auto-switches with macOS system appearance. Catppuccin is the most actively maintained theme ecosystem across terminals, editors, and system UI. |
| `window-theme` | `auto` | `auto` | Matches window chrome to system light/dark. Explicitly set for clarity. |

### Window

| Setting | Default | Ours | Why |
|---|---|---|---|
| `background-opacity` | `1` | `0.8` | 80% opacity. Lets the desktop bleed through for spatial context without sacrificing readability. |
| `background-blur` | `false` | `20` | Blurs the background behind the transparent window. Intensity 20 is the Ghostty-recommended value. Prevents text-on-text interference from windows behind. |
| `macos-titlebar-style` | `transparent` | `tabs` | Integrates Ghostty tabs into the macOS titlebar. Saves vertical space. Gives tabs first-class visibility. |
| `window-colorspace` | `srgb` | `display-p3` | Wide color gamut. Uses the full range of modern Mac displays. Catppuccin's pastels look noticeably richer in P3. |
| `window-padding-x` | `2` | `12` | 12px horizontal padding. Text doesn't touch the window edge. |
| `window-padding-y` | `2` | `12` | 12px vertical padding. Same reasoning. |
| `window-padding-balance` | `false` | `true` | When the window doesn't perfectly align to the cell grid, this centers the content instead of leaving dead space on one side. |
| `window-height` | `0` *(auto)* | `30` | 30-row default. Tall enough for most workflows without dominating the screen. |
| `window-width` | `0` *(auto)* | `120` | 120-column default. Fits side-by-side on a 13" screen. Wide enough for code + line numbers. |
| `window-save-state` | `default` | `always` | Restores window position, size, tabs, and splits on relaunch. `default` only restores on macOS with the system feature enabled; `always` guarantees it. |
| `confirm-close-surface` | `true` | `false` | No confirmation dialog when closing a pane. tmux handles session persistence, so closing Ghostty is never destructive. |

### Cursor

| Setting | Default | Ours | Why |
|---|---|---|---|
| `cursor-style` | `block` | `bar` | Thin bar cursor. Consistent with modern editors (VS Code, Zed, Sublime). Easier to track insertion point in text. |
| `cursor-style-blink` | *(unset)* | `true` | Blinking bar is easier to locate after glancing away. |
| `cursor-opacity` | `1` | `0.9` | Slightly translucent. Prevents the cursor from fully obscuring the character beneath it. |
| `cursor-color` | *(theme default)* | `cell-foreground` | Cursor always matches the text color. Works in both light and dark themes without manual color management. |

### Splits

| Setting | Default | Ours | Why |
|---|---|---|---|
| `unfocused-split-opacity` | `0.7` | `0.85` | Default 0.7 dims too aggressively — unfocused splits become hard to read. 0.85 gives a clear focus indicator while keeping content legible. |

### Quick Terminal

| Setting | Default | Ours | Why |
|---|---|---|---|
| `quick-terminal-screen` | `main` | `mouse` | Dropdown appears on whichever screen your mouse is on. The default `main` forces you to look at your primary display regardless of where you're working. |
| `quick-terminal-animation-duration` | `0.2` | `0.15` | Faster animation. 0.2 feels sluggish when toggling rapidly. 0.15 is perceptible but doesn't waste time. |

`quick-terminal-position` (`top`) and `quick-terminal-autohide` (`true`) match the defaults and are set explicitly for readability.

### Mouse

| Setting | Default | Ours | Why |
|---|---|---|---|
| `mouse-hide-while-typing` | `false` | `true` | Hides the mouse cursor when you start typing. Prevents the pointer from occluding terminal output. Standard behavior in every modern editor. |
| `copy-on-select` | `true` | `clipboard` | Default `true` copies to the selection clipboard only. `clipboard` copies to both the selection clipboard and the system clipboard, so `Cmd+V` works everywhere. |
| `mouse-scroll-multiplier` | `precision:1,discrete:3` | `2` | Normalizes scroll speed across all input devices to 2x. The default's 3x discrete is too fast for trackpads when you're reading logs. |

### Shell Integration

| Setting | Default | Ours | Why |
|---|---|---|---|
| `shell-integration-features` | `cursor,no-sudo,title,no-ssh-env,no-ssh-terminfo,path` | `no-cursor,sudo,title,ssh-env,ssh-terminfo` | **sudo:** Preserves Ghostty shell integration through `sudo` (the default strips it). **ssh-env/ssh-terminfo:** Propagates terminfo over SSH so remote hosts render correctly. **no-cursor:** Lets the config control cursor style rather than the shell integration overriding it. |

### Clipboard & Security

| Setting | Default | Ours | Why |
|---|---|---|---|
| `clipboard-read` | `ask` | `allow` | Default `ask` prompts every time an application reads the clipboard (e.g., tmux's OSC 52). `allow` lets tmux and other tools access the clipboard without interruption. |

`clipboard-paste-protection`, `clipboard-paste-bracketed-safe`, `clipboard-write`, and `clipboard-trim-trailing-spaces` all match their defaults and are set explicitly for documentation.

### macOS

| Setting | Default | Ours | Why |
|---|---|---|---|
| `macos-option-as-alt` | *(disabled)* | `left` | Left Option key sends Alt escape sequences. Required for terminal keybindings like `Alt+B` (word back), `Alt+F` (word forward), `Alt+D` (delete word). Right Option is preserved for special characters (accents, symbols). |

### tmux

| Setting | Default | Ours | Why |
|---|---|---|---|
| `command` | *(none)* | `~/.config/ghostty/ghostty-tmux.sh` | Launcher script with `mkdir`-based atomic locking and a pending-instance counter. Prevents the race condition where simultaneous tab restores all attach to the base session. First tab gets `main`; subsequent tabs get independent sessions (`main-2`, `main-3`, ...). |

### Scrollback

| Setting | Default | Ours | Why |
|---|---|---|---|
| `scrollback-limit` | `10000000` (10MB) | `25000000` (25MB) | 2.5x the default. Large builds, log tailing, and verbose test output regularly exceed 10MB. 25MB covers virtually any single-session workflow. |

---

## Keybinding Diff (vs. Ghostty Defaults)

Ghostty ships with a set of default keybindings. This config replaces or adds the following. Keybindings not listed here use their Ghostty defaults unchanged.

### Added (not in defaults)

| Key | Action | Why |
|---|---|---|
| `global:Ctrl + `` ` | `toggle_quick_terminal` | System-wide dropdown terminal. No default exists for this — you must bind it yourself. |
| `Cmd + Shift + S` | `toggle_secure_input` | Prevents keyloggers from reading keystrokes. Useful when typing passwords. No default binding. |
| `Cmd + Shift + W` | `close_tab` | Closes the entire tab. Default only has `close_surface` (single pane) and `close_window`. |
| `Cmd + Shift + Left/Right` | `previous_tab` / `next_tab` | Arrow-based tab switching. Default uses `Cmd+Shift+[` and `Cmd+Shift+]`. Arrow keys are more intuitive and don't require finding bracket keys. |
| `Cmd + Ctrl + Shift + Left/Right` | `move_tab:-1` / `move_tab:1` | Reorder tabs. No default binding exists. |
| `Cmd + D` | `new_split:right` | Split right. Default uses `Cmd+D` for nothing — this follows the iTerm2/VS Code convention. |
| `Cmd + Alt + Arrow` | `goto_split:direction` | Directional split navigation. Default uses `Cmd+[` / `Cmd+]` for previous/next (non-directional). Arrow-based is spatial — you go where you look. |
| `Cmd + Ctrl + Arrow` | `resize_split:direction,10` | Resize splits. Same keys as navigation but with `Ctrl` added. Default has this too but our directional set is more complete. |
| `Cmd + Shift + E` | `equalize_splits` | Reset all splits to equal size. Default uses `Cmd+Ctrl+=`. Ours is one key fewer. |
| `Cmd + Shift + F` | `toggle_split_zoom` | Zoom/unzoom a split to fill the window. Default uses `Cmd+Shift+Enter`. `F` is mnemonic for "fullscreen". |

### Changed (different from defaults)

| Key | Default Action | Our Action | Why |
|---|---|---|---|
| `Cmd + Shift + ,` | `reload_config` | `reload_config` *(same)* | Preserved from defaults. The previous version of this config had a bug where this was overridden by `move_tab:-1` — fixed. |
| `Cmd + Shift + I` | *(not bound)* | `inspector:toggle` | Default binds this to `Cmd+Alt+I`. We use `Cmd+Shift+I` to match browser DevTools muscle memory. |

### Removed (defaults we don't override)

All other Ghostty defaults remain active. This includes:
- `Cmd + C` / `Cmd + V` — copy/paste
- `Cmd + N` — new window
- `Cmd + Q` — quit
- `Cmd + A` — select all
- `Cmd + Z` — undo
- Arrow key selection adjustment
- Page up/down scrolling
- `Cmd + Home/End` — scroll to top/bottom

---

## tmux Config

Ghostty handles the terminal (theme, rendering, opacity, blur). tmux handles the multiplexer (panes, windows, session persistence). This separation means:

- **Persistence.** tmux sessions survive when Ghostty closes, when your laptop sleeps, and when SSH connections drop.
- **Session-per-tab.** each new Ghostty tab creates an independent tmux session (`main`, `main-2`, `main-3`, ...), eliminating mirrored tabs.
- **Remote attach.** `ssh your-host -t tmux attach -t <session-name>` from any device — phone, tablet, another laptop — over Tailscale or any SSH transport.
- **Portable layout.** Your pane arrangement travels with the session, not the terminal window.

### tmux Keybindings

Prefix: **`Ctrl + Space`** (fallback: **`Ctrl + A`**)

Press and release the prefix, then press the action key.

#### Panes

| Key | Action |
|---|---|
| `prefix + \|` | Split right |
| `prefix + -` | Split down |
| `prefix + h / j / k / l` | Navigate panes (vim-style) |
| `prefix + H / J / K / L` | Resize panes (5 cells, repeatable) |
| `prefix + z` | Zoom/unzoom pane to fill window |
| `prefix + > / <` | Swap pane forward/backward |
| `prefix + x` | Kill pane |

#### Windows

| Key | Action |
|---|---|
| `prefix + c` | New window |
| `prefix + n / p` | Next / previous window |
| `prefix + 1-9` | Jump to window by number |
| `prefix + X` | Kill window |

#### Sessions

| Key | Action |
|---|---|
| `prefix + d` | Detach (session keeps running) |

```bash
tmux attach -t main               # reattach to main locally
tmux attach -t main-2             # reattach to another tab session
ssh host -t tmux attach -t main-2 # reattach remotely
tmux ls                           # list sessions
```

#### Copy Mode

| Key | Action |
|---|---|
| `prefix + [` | Enter copy mode |
| `v` | Start selection |
| `y` | Copy and exit |
| `/ or ?` | Search forward / backward |
| `Escape` | Cancel |

#### Utility

| Key | Action |
|---|---|
| `prefix + r` | Reload tmux config |

### tmux Settings (vs. tmux Defaults)

| Setting | Default | Ours | Why |
|---|---|---|---|
| `prefix` | `C-b` | `C-Space` (`prefix2`: `C-a`, `C-@` alias) | `Ctrl+Space` is ergonomic, `Ctrl+A` is a robust fallback, and `C-@` alias covers terminals that encode `Ctrl+Space` as NUL. |
| `default-terminal` | `screen` | `tmux-256color` | Correct terminfo for 256-color and true-color support. `screen` misidentifies capabilities. |
| `terminal-overrides` | *(none)* | `xterm-ghostty:RGB` | Tells tmux that Ghostty supports 24-bit true color. Without this, tmux falls back to 256-color approximation. |
| `extended-keys` | `off` | `on` | Enables CSI-u key reporting. Applications inside tmux receive full modifier information (Ctrl+Shift+A vs Ctrl+A). |
| `escape-time` | `500` | `0` | Default waits 500ms after Escape to see if it's part of a sequence. This makes Vim mode-switching feel broken. 0 means instant. |
| `history-limit` | `2000` | `50000` | 2000 lines is nothing. 50000 covers long builds and log output without meaningful memory cost. |
| `base-index` | `0` | `1` | Windows start at 1. Matches keyboard layout — `1` is the leftmost number key. |
| `pane-base-index` | `0` | `1` | Same reasoning for panes. |
| `renumber-windows` | `off` | `on` | When you close window 2 of 4, the remaining windows become 1, 2, 3 instead of 1, 3, 4. |
| `mouse` | `off` | `on` | Click to select pane, drag to resize, scroll to browse history. |
| `set-clipboard` | `external` | `on` | Enables OSC 52 clipboard integration. Copies inside tmux go to the system clipboard via Ghostty. |
| `mode-keys` | `emacs` | `vi` | Vi keybindings in copy mode. |
| Split bindings | `"` / `%` | `\|` / `-` | Visual mnemonics. `\|` draws a vertical divider, `-` draws a horizontal one. Default bindings are arbitrary. |
| Navigation | `arrow keys` | `h / j / k / l` | Vim-style. Hands stay on home row. |
| Resize | `Ctrl+arrow` | `H / J / K / L` (repeatable) | Same directional keys as navigation but shifted. `-r` flag means you press prefix once, then tap the key repeatedly. |

---

## File Structure

```
best-ghostty-config/
  config              Ghostty configuration
  ghostty-tmux.sh     tmux launcher (fixes tab/session behavior)
  tmux.conf           tmux configuration
  install.sh          Symlink installer with backup
  docs/
    cheatsheet/
      keybindings.md  Full keybinding reference
```

## License

[MIT](LICENSE)
