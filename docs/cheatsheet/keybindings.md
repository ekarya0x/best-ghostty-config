# Keybindings

Two layers: **Ghostty** (terminal, `Cmd` combos) and **tmux** (multiplexer, prefix + key).

tmux prefix: **Ctrl+Space** — fallback: **Ctrl+A**
Press prefix, release, then press the action key.

---

## Ghostty

### Global (works from any app)

| Key | Action |
|---|---|
| `Ctrl+Backtick (\`)` | Toggle quick terminal (drops from top of screen) |

### App

| Key | Action |
|---|---|
| `Cmd+Shift+P` | Command palette (search all actions) |
| `Ctrl+Cmd+F` | Fullscreen |
| `Cmd+Shift+,` | Reload config |
| `Cmd+Shift+S` | Secure keyboard input (blocks keyloggers) |
| `Cmd+Shift+I` | Inspector |

### Tabs

| Key | Action |
|---|---|
| `Cmd+T` | New tab (creates new tmux session) |
| `Cmd+W` | Close pane |
| `Cmd+Shift+W` | Close entire tab |
| `Cmd+Shift+←` / `→` | Previous / next tab |
| `Cmd+1` – `9` | Jump to tab |
| `Cmd+Ctrl+Shift+←` / `→` | Move tab left / right |

### Splits

| Key | Action |
|---|---|
| `Cmd+D` | Split right |
| `Cmd+Shift+D` | Split down |
| `Cmd+Alt+←` `→` `↑` `↓` | Focus split in direction |
| `Cmd+Ctrl+←` `→` `↑` `↓` | Resize split (10px) |
| `Cmd+Shift+E` | Equalize all splits |
| `Cmd+Shift+F` | Zoom / unzoom current split |

### Font size

| Key | Action |
|---|---|
| `Cmd+=` | Bigger |
| `Cmd+-` | Smaller |
| `Cmd+0` | Reset to 15pt |

---

## tmux

All keys below require the prefix first. Example: `Ctrl+Space` then `|` splits right.

### Panes

| Key | Action |
|---|---|
| `\|` | Split right (vertical divider) |
| `-` | Split down (horizontal divider) |
| `h` `j` `k` `l` | Navigate left / down / up / right (vim) |
| `H` `J` `K` `L` | Resize 5 cells (repeatable — tap without re-pressing prefix) |
| `z` | Zoom / unzoom pane to fill window |
| `x` | Kill pane |
| `>` / `<` | Swap pane forward / backward |

### Windows (tmux tabs)

| Key | Action |
|---|---|
| `c` | New window |
| `n` / `p` | Next / previous window |
| `1` – `9` | Jump to window by number |
| `X` | Kill window (uppercase) |

### Sessions

| Key | Action |
|---|---|
| `d` | Detach — session keeps running in background |
| `s` | Session picker (tree view) |

### Copy mode (vi keys)

Enter with `prefix + [`, then:

| Key | Action |
|---|---|
| `h` `j` `k` `l` | Navigate |
| `v` | Start selection |
| `y` | Copy selection and exit |
| `/` | Search forward |
| `?` | Search backward |
| `n` / `N` | Next / previous match |
| `Esc` or `q` | Exit copy mode |

### Persistence (tmux-resurrect)

| Key | Action |
|---|---|
| `Ctrl+S` | Save all sessions to disk (manual snapshot) |
| `Ctrl+R` | Restore sessions from last snapshot |

Auto-save runs every 5 minutes via tmux-continuum. Manual save before risky operations.

### Utility

| Key | Action |
|---|---|
| `r` | Reload tmux config |

---

## Shutdown & survival

| Action | How | What survives |
|---|---|---|
| Leave safely | `Cmd+Q` or `prefix+d` | Everything |
| Close one pane | `prefix+x` | Other panes, windows, sessions |
| Close one window | `prefix+X` | Other windows, sessions |
| Kill one session | `tmux kill-session -t name` | Other sessions |
| Kill all tmux | `tmux kill-server` | Resurrect snapshot on disk |
| System reboot | — | Resurrect snapshot + Ghostty tab state |

---

## Session management

```bash
tmux ls                                              # list sessions
tmux attach -t main                                  # reattach
tmux attach -t main-2
tmux switch-client -t main-2                         # hop (from inside tmux)
tmux kill-session -t main-2                          # kill one
tmux kill-server                                     # kill all
tmux new-session -Ad -s api -c ~/Projects/api        # named session
tmux ls -F '#{session_name} attached=#{session_attached}'   # attachment status
ssh host -t tmux attach -t main                      # remote attach
```

---

## Mouse

| Action | What happens |
|---|---|
| Click pane | Focus it |
| Drag pane border | Resize |
| Scroll | Browse output history |
| Select text | Copies to system clipboard |
| `Cmd+click` URL | Opens in browser |

---

## Quick terminal

| Key | Action |
|---|---|
| `Ctrl+Backtick (\`)` | Toggle from anywhere on macOS |

Drops from the top of whichever screen your mouse is on. Auto-hides on click-away. 0.15s animation. Requires Accessibility permissions and Login Items in System Settings.

---

## Common confusion

- **Ghostty tab ≠ tmux window.** `Cmd+T` = new Ghostty tab + new tmux session. `prefix+c` = new tmux window inside the current session.
- **Mirroring is expected** when two clients attach to the same session. The launcher prevents it by giving each tab its own session.
- **`Cmd+Q` is safe.** Ghostty closes. tmux sessions survive. That's the point.
- **Three persistence layers.** Ghostty restores tabs/windows. tmux keeps sessions/processes alive in memory. tmux-resurrect saves to disk every 5 minutes. Quit, reboot, come back — everything is still there.
