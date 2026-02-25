# Keybindings Cheat Sheet

This config ships two layers of keybindings: Ghostty (the terminal) and tmux (the multiplexer inside it). Ghostty keybindings use `Cmd` combos. tmux keybindings use a prefix key (`Ctrl+Space`) followed by a single key.

When you open Ghostty, tmux launches automatically into a persistent session called `main`.

---

## Ghostty Keybindings

### Global

These work from anywhere on macOS, even when Ghostty is not focused.

| Key | Action |
|---|---|
| `Ctrl + `` ` | Toggle quick terminal (dropdown from top of screen) |

### Application

| Key | Action |
|---|---|
| `Cmd + Shift + P` | Open command palette (search all actions) |
| `Ctrl + Cmd + F` | Toggle fullscreen |
| `Cmd + Shift + ,` | Reload configuration from disk |
| `Cmd + Shift + S` | Toggle secure keyboard input |
| `Cmd + Shift + I` | Toggle terminal inspector |

### Tabs

| Key | Action |
|---|---|
| `Cmd + T` | New tab |
| `Cmd + W` | Close current pane |
| `Cmd + Shift + W` | Close entire tab |
| `Cmd + Shift + Left` | Switch to previous tab |
| `Cmd + Shift + Right` | Switch to next tab |
| `Cmd + 1` through `Cmd + 9` | Jump to tab by number |
| `Cmd + Ctrl + Shift + Left` | Move current tab left |
| `Cmd + Ctrl + Shift + Right` | Move current tab right |

### Splits (Ghostty-level)

Ghostty has its own split system independent of tmux. These create Ghostty-native splits.

| Key | Action |
|---|---|
| `Cmd + D` | Split right |
| `Cmd + Shift + D` | Split down |
| `Cmd + Alt + Left` | Focus split to the left |
| `Cmd + Alt + Right` | Focus split to the right |
| `Cmd + Alt + Up` | Focus split above |
| `Cmd + Alt + Down` | Focus split below |
| `Cmd + Ctrl + Left` | Resize split left by 10 |
| `Cmd + Ctrl + Right` | Resize split right by 10 |
| `Cmd + Ctrl + Up` | Resize split up by 10 |
| `Cmd + Ctrl + Down` | Resize split down by 10 |
| `Cmd + Shift + E` | Equalize all splits |
| `Cmd + Shift + F` | Zoom/unzoom current split |

### Font Size

| Key | Action |
|---|---|
| `Cmd + =` | Increase font size |
| `Cmd + -` | Decrease font size |
| `Cmd + 0` | Reset font size to default (15pt) |

---

## tmux Keybindings

tmux keybindings require pressing the prefix key first, then the action key. The prefix is:

**`Ctrl + Space`**

Press and release the prefix, then press the action key. Example: to split a pane right, press `Ctrl+Space`, release, then press `|`.

### Panes

Panes are subdivisions within a single tmux window. You can have as many as you want.

| Key | Action |
|---|---|
| `prefix + \|` | Split pane right (vertical divider) |
| `prefix + -` | Split pane down (horizontal divider) |
| `prefix + h` | Move focus to pane on the left |
| `prefix + j` | Move focus to pane below |
| `prefix + k` | Move focus to pane above |
| `prefix + l` | Move focus to pane on the right |
| `prefix + H` | Resize pane left by 5 cells (repeatable) |
| `prefix + J` | Resize pane down by 5 cells (repeatable) |
| `prefix + K` | Resize pane up by 5 cells (repeatable) |
| `prefix + L` | Resize pane right by 5 cells (repeatable) |
| `prefix + z` | Zoom current pane to fill the window (toggle) |
| `prefix + >` | Swap current pane with the next one |
| `prefix + <` | Swap current pane with the previous one |
| `prefix + x` | Kill current pane |

Resize keys are repeatable: after pressing the prefix once, you can press `H`, `J`, `K`, or `L` multiple times without re-pressing the prefix.

### Windows (tmux tabs)

Windows are tmux's equivalent of tabs. Each window can contain its own set of panes.

| Key | Action |
|---|---|
| `prefix + c` | Create new window |
| `prefix + n` | Next window |
| `prefix + p` | Previous window |
| `prefix + 1` through `prefix + 9` | Jump to window by number |
| `prefix + X` | Kill current window (uppercase X) |

### Sessions

Sessions are the persistence layer. They survive when you close Ghostty, when your laptop sleeps, or when an SSH connection drops.

| Key | Action |
|---|---|
| `prefix + d` | Detach from session (session keeps running) |

Reattach from any terminal:

```
tmux attach -t main
```

Reattach over SSH (e.g. via Tailscale):

```
ssh your-host -t tmux attach -t main
```

List all sessions:

```
tmux ls
```

### Copy Mode

Enter copy mode to scroll through output and copy text using vi-style keys.

| Key | Action |
|---|---|
| `prefix + [` | Enter copy mode |
| `v` | Start selection (in copy mode) |
| `y` | Copy selection and exit copy mode |
| `Escape` | Cancel and exit copy mode |
| `q` | Exit copy mode |

Standard vi navigation works in copy mode: `h/j/k/l` to move, `/` to search forward, `?` to search backward, `n/N` for next/previous match.

### Utility

| Key | Action |
|---|---|
| `prefix + r` | Reload tmux config |

---

## Mouse

Mouse is fully enabled in both Ghostty and tmux.

- Click a tmux pane to focus it.
- Drag a pane border to resize it.
- Scroll to move through output history.
- Select text to copy it to the system clipboard automatically.
- `Cmd + click` a URL to open it in your browser.

---

## Quick Terminal

The quick terminal is a dropdown terminal that slides from the top of your screen. It works globally across all macOS spaces.

| Key | Action |
|---|---|
| `Ctrl + `` ` | Toggle quick terminal |

Properties:
- Drops down from the top of the screen your mouse is on.
- Auto-hides when you click away.
- Animates in 0.15 seconds.
- Appears on whichever screen your mouse is on.
- Requires macOS Accessibility permissions (System Settings > Privacy & Security > Accessibility) and Login Items.

---

## Config Settings Reference

### What this config sets

| Setting | Value | What it does |
|---|---|---|
| `font-family` | JetBrains Mono | Monospace font with clear character distinction |
| `font-size` | 15 | Font size in points |
| `font-thicken` | true | Thicker strokes for better readability on Retina |
| `adjust-cell-height` | 2 | Extra 2px vertical spacing between lines |
| `font-feature` | calt, liga | Contextual alternates and ligatures (e.g. `!=` renders as a single glyph) |
| `theme` | Catppuccin Latte / Mocha | Auto-switches light/dark with macOS system appearance |
| `background-opacity` | 0.8 | 80% opaque background |
| `background-blur` | 20 | Blur behind the transparent background (intensity 20) |
| `macos-titlebar-style` | tabs | Tabs integrated into the macOS titlebar |
| `window-colorspace` | display-p3 | Wide color gamut rendering |
| `window-padding-x/y` | 12 | 12px padding on all sides |
| `window-padding-balance` | true | Centers content when window doesn't align to cell grid |
| `window-height` | 30 | Default 30 rows tall |
| `window-width` | 120 | Default 120 columns wide |
| `window-save-state` | always | Restores window position, size, and layout on relaunch |
| `window-inherit-working-directory` | true | New tabs and splits start in the same directory |
| `confirm-close-surface` | false | No confirmation dialog when closing a pane |
| `cursor-style` | bar | Thin bar cursor |
| `cursor-style-blink` | true | Cursor blinks |
| `cursor-opacity` | 0.9 | 90% opaque cursor |
| `unfocused-split-opacity` | 0.85 | Dims unfocused splits to 85% |
| `mouse-hide-while-typing` | true | Hides mouse cursor while you type |
| `copy-on-select` | clipboard | Selecting text automatically copies to clipboard |
| `link-url` | true | URLs are clickable |
| `mouse-scroll-multiplier` | 2 | Normalized 2x scroll speed across all input devices |
| `shell-integration` | detect | Auto-detects your shell for integration features |
| `clipboard-paste-protection` | true | Warns before pasting potentially dangerous content |
| `clipboard-trim-trailing-spaces` | true | Strips trailing whitespace when copying |
| `macos-option-as-alt` | left | Left Option key behaves as Alt |
| `command` | tmux new-session -A -s main | Auto-launches tmux on every new Ghostty window |
| `scrollback-limit` | 25000000 | 25MB scrollback buffer |

### What tmux sets

| Setting | Value | What it does |
|---|---|---|
| `default-terminal` | tmux-256color | Correct terminal identification for color support |
| `terminal-overrides` | xterm-ghostty:RGB | Enables true 24-bit color in Ghostty |
| `extended-keys` | on | Full modifier key reporting to applications |
| `escape-time` | 0 | No delay after pressing Escape |
| `history-limit` | 50000 | 50,000 lines of scrollback per pane |
| `base-index` | 1 | Windows numbered starting at 1 |
| `pane-base-index` | 1 | Panes numbered starting at 1 |
| `renumber-windows` | on | Windows renumber when one is closed |
| `automatic-rename` | on | Window names update to show the running command |
| `mouse` | on | Full mouse support |
| `set-clipboard` | on | Clipboard integration via OSC 52 |
| `mode-keys` | vi | Vi-style keys in copy mode |
