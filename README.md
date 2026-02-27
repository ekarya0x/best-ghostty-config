# best-ghostty-config

Ghostty + tmux. Persistent sessions, independent tabs, Catppuccin theme, sane defaults. Survives app restarts and system reboots.

## Architecture

```
┌─ Ghostty ─────────────────────────────────────────────────┐
│  Tab 1              Tab 2              Tab 3              │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐      │
│  │ tmux client│    │ tmux client│    │ tmux client│      │
│  └─────┬──────┘    └─────┬──────┘    └─────┬──────┘      │
└────────┼─────────────────┼─────────────────┼──────────────┘
         │                 │                 │
         ▼                 ▼                 ▼
┌─ tmux server (background process) ────────────────────────┐
│  session: main      session: main-2    session: main-3    │
│   └─ windows         └─ windows        └─ windows        │
│      └─ panes           └─ panes          └─ panes       │
├───────────────────────────────────────────────────────────┤
│  tmux-resurrect: snapshots to disk every 5 min            │
│  tmux-continuum: auto-saves, ghostty-tmux.sh: auto-restores│
└───────────────────────────────────────────────────────────┘
```

Each Ghostty tab gets its own tmux session. No mirroring. The launcher (`ghostty-tmux.sh`) handles session assignment with atomic locking plus per-burst claim tracking: restart restores reattach existing detached sessions, normal interactive tab/pane/window creation gets fresh sessions, and restore mode can auto-open extra Ghostty tabs so every existing tmux session gets reattached.

## Three layers of persistence

| Layer | What it saves | Survives Ghostty quit | Survives reboot |
|---|---|---|---|
| **Ghostty** (`window-save-state`) | Tab count, window position, split layout | Yes | Yes |
| **tmux server** (in-memory) | Sessions, panes, running processes | Yes | No |
| **tmux-resurrect** (disk snapshots) | Session layout, working dirs, programs | N/A | Yes |

**Ghostty quit → reopen:** Ghostty restores tabs. tmux server never stopped. Launcher reattaches each tab to its previous session, then auto-opens missing tabs so remaining detached sessions are also restored.

**System reboot:** Ghostty restores tabs. tmux server is dead. Launcher detects empty server, finds resurrect snapshot on disk, restores all sessions, then reattaches tabs. Claude Code instances restart via `~claude` (replays original command with all flags).

**tmux-continuum** auto-saves a snapshot every 5 minutes. Manual save: `prefix + Ctrl+S`. Manual restore: `prefix + Ctrl+R`.

## Install

```bash
git clone https://github.com/ekarya0x/best-ghostty-config.git ~/.ghostty-config
cd ~/.ghostty-config && ./install.sh
```

Quit Ghostty (`Cmd+Q`), relaunch.

The installer:
- Installs tmux via Homebrew if missing
- Installs TPM + tmux-resurrect + tmux-continuum
- Symlinks config files with timestamped backups
- Installs tmux aliases (`tls`, `tgo`, `tprev`, `tkill`, `tprune`)
- Fixes the macOS Ctrl+Space input source conflict
- Checks for JetBrains Mono
- Reloads tmux if running

### Symlinks

| Source | Target |
|---|---|
| `config` | `~/.config/ghostty/config` |
| `config` | `~/Library/Application Support/com.mitchellh.ghostty/config` |
| `ghostty-tmux.sh` | `~/.config/ghostty/ghostty-tmux.sh` |
| `tmux-aliases.zsh` | `~/.config/ghostty/tmux-aliases.zsh` |
| `tmux.conf` | `~/.tmux.conf` |

### Update

```bash
cd ~/.ghostty-config && git pull --ff-only && ./install.sh
```

### Requirements

- [Ghostty](https://ghostty.org/) 1.2+
- [tmux](https://github.com/tmux/tmux) 3.2+
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/)

## Quick reference

```
GHOSTTY (Cmd-based)                     TMUX (prefix + key)
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
Cmd+Shift+,       reload config         [         copy mode (vi)
Cmd+= / - / 0     font size             r         reload config
Ctrl+Cmd+F        fullscreen            Ctrl+S    save sessions (resurrect)
Shift+Return      newline in prompt     Ctrl+R    restore sessions (resurrect)
```

Full reference: [`docs/cheatsheet/keybindings.md`](docs/cheatsheet/keybindings.md)

## How the launcher works

`ghostty-tmux.sh` runs once per Ghostty tab. It decides which tmux session to connect to.

**Concurrency control.** Ghostty restores tabs concurrently. Without serialization, multiple launcher instances can bind to the same session. The launcher uses `mkdir` as an atomic lock (POSIX-guaranteed), a batch heartbeat file, and a claimed-sessions file. State files are namespaced by uid + socket + base session so parallel sockets/tests cannot collide.

**Session selection logic:**

1. **Resurrect check.** If the tmux server is empty and a resurrect snapshot exists, restore it first. This handles reboots.
2. **Base session.** If session `main` doesn't exist, create it and attach.
3. **Force new.** If `GHOSTTY_TMUX_FORCE_NEW_SESSION=1`, always create a new session.
4. **Batch mode.** Recompute mode each launch: `restore` when sessions exist but tmux has zero attached clients, otherwise `normal`.
5. **Claim base once.** If there are zero clients and `main` is not yet claimed in this launch burst, claim and attach `main`.
6. **Restore mode attach.** In restore mode, attach the next unattached unclaimed session (prefers `main-N`, then other names).
7. **Normal mode / fallback.** If no reusable detached session remains, create the next `main-N`.
8. **Restore tab fill.** In restore mode, a one-shot helper opens extra Ghostty tabs (macOS) when detached sessions outnumber restored tabs.

A **claimed-sessions file** tracks session assignments inside the current launch burst. This prevents the race where instance N releases the lock before `exec tmux attach` has fully registered a client.

**Environment variables:**

| Variable | Default | Effect |
|---|---|---|
| `GHOSTTY_TMUX_BASE_SESSION` | `main` | Base session name |
| `GHOSTTY_TMUX_SOCKET_NAME` | _(default socket)_ | Named tmux socket (`-L`) |
| `GHOSTTY_TMUX_NO_ATTACH` | `0` | Print session name instead of attaching |
| `GHOSTTY_TMUX_FORCE_NEW_SESSION` | `0` | Always create a new session |
| `GHOSTTY_TMUX_STATE_DIR` | `/tmp` | Directory for lock/batch/pending/claimed/mode files |
| `GHOSTTY_TMUX_STATE_KEY` | `uid-socket-base` | Namespace key for state files |
| `GHOSTTY_TMUX_TRACE` | `0` | Enable launcher trace logging |
| `GHOSTTY_TMUX_TRACE_FILE` | `.../ghostty-tmux-<key>.trace.log` | Custom launcher trace path |
| `TMUX_BIN` | _(auto-detected)_ | Explicit tmux binary path |

## Daily workflows

### Default: persistent mode

Work normally. Close Ghostty with `Cmd+Q`. Reopen later. Everything is where you left it.

```bash
tmux ls                       # list all sessions
tmux attach -t main-2         # reattach manually
```

### Session hopping

```bash
tmux switch-client -t main-2  # from inside tmux
# or: prefix + s              # interactive session picker
```

### Why tabs are named `main`, `main-2`, `main-3`

- `main` is the configured base session name (`GHOSTTY_TMUX_BASE_SESSION`, default: `main`).
- The first attached tab in a launch batch claims `main`.
- Additional tabs get numeric suffixes (`main-2`, `main-3`, ...).
- You can jump/kill with either full names (`main-6`) or numeric shorthand via aliases (`tgo 6`, `tkill 6`).

### Fast visibility of everything

```bash
tls                 # sessions + attached flag + window count
twin                # all windows across all sessions
tpanes              # all panes with cwd + running command
ttree               # interactive tree (sessions/windows/panes)
```

### tmux aliases (installed by `install.sh`)

```bash
tls                 # compact session list
twin                # all tmux windows (across sessions)
tpanes              # all panes (with cwd + command)
ttree               # built-in tree chooser (sessions/windows/panes)
tgo main-3          # jump/attach to a session
tnew                # create next main-N and attach
tprev               # switch to most recently used other session
tkill main-3        # kill one session safely
tkillc              # kill current session and hop to another
tprune              # kill detached main-* sessions
```

### Named project sessions

```bash
tmux new-session -Ad -s api -c ~/Projects/api
tmux new-session -Ad -s web -c ~/Projects/web
```

### Clean up

```bash
tmux kill-session -t main-3   # kill one
tmux kill-server              # kill everything
```

### Remote attach

```bash
ssh host -t tmux attach -t main
```

### Cleanup stale sessions

```bash
tmux ls -F '#{session_name} attached=#{session_attached}'
# Kill anything showing attached=0 that you don't need
```

## Shutdown & survival

| Action | How | What survives |
|---|---|---|
| Leave safely | `Cmd+Q` or `prefix+d` | Everything |
| Close one pane | `prefix+x` | Other panes, windows, sessions |
| Close one window | `prefix+X` | Other windows, sessions |
| Kill one session | `tmux kill-session -t name` | Other sessions |
| Kill all tmux | `tmux kill-server` | Resurrect snapshot on disk |
| System reboot | — | Resurrect snapshot + Ghostty tab state |

## Ghostty settings

Every setting below differs from stock defaults.

### Typography

| Setting | Value | Why |
|---|---|---|
| `font-family` | `JetBrains Mono` | Clear `0O` `1lI` `[]{}` distinction |
| `font-size` | `15` | Readable on Retina without wasting space |
| `font-thicken` | `true` | Prevents thin strokes vanishing on HiDPI |
| `adjust-cell-height` | `2` | 2px extra line spacing for readability |
| `font-feature` | `calt`, `liga` | Ligatures: `!=` `=>` `>=` `<=` render as glyphs |

### Theme

| Setting | Value | Why |
|---|---|---|
| `theme` | `light:Catppuccin Latte, dark:Catppuccin Mocha` | Follows macOS appearance |
| `window-theme` | `auto` | Window chrome matches system |

### Window

| Setting | Value | Why |
|---|---|---|
| `background-opacity` | `0.8` | Desktop shows through |
| `background-blur` | `20` | Frosted glass effect |
| `macos-titlebar-style` | `tabs` | Tabs in titlebar saves vertical space |
| `window-colorspace` | `display-p3` | Wide gamut on modern Macs |
| `window-padding-x/y` | `12` | 12px breathing room on all sides |
| `window-padding-balance` | `true` | Centers content in the cell grid |
| `window-save-state` | `always` | Restores tab layout on relaunch |
| `confirm-close-surface` | `false` | No close dialog — tmux handles persistence |

### Cursor

| Setting | Value | Why |
|---|---|---|
| `cursor-style` | `bar` | Thin insertion bar |
| `cursor-style-blink` | `true` | Visible after looking away |
| `cursor-opacity` | `0.9` | Slightly translucent |
| `cursor-color` | `cell-foreground` | Adapts to light/dark theme |

### Input

| Setting | Value | Why |
|---|---|---|
| `unfocused-split-opacity` | `0.85` | Stock 0.7 dims too aggressively |
| `mouse-hide-while-typing` | `true` | Pointer disappears during input |
| `copy-on-select` | `clipboard` | Select text → system clipboard |
| `mouse-scroll-multiplier` | `2` | Faster scrolling |
| `macos-option-as-alt` | `left` | Left Option = Alt for shell shortcuts |

### Quick terminal

| Setting | Value | Why |
|---|---|---|
| `quick-terminal-screen` | `mouse` | Drops on whichever screen the cursor is on |
| `quick-terminal-animation-duration` | `0.15` | Snappier than stock 0.2s |

### Shell & clipboard

| Setting | Value | Why |
|---|---|---|
| `shell-integration-features` | `no-cursor,sudo,title,ssh-env,ssh-terminfo` | tmux controls cursor; sudo passthrough and SSH terminfo propagation enabled |
| `clipboard-read/write` | `allow` | No prompt for OSC 52 clipboard operations |
| `scrollback-limit` | `25000000` | 25MB — 2.5× default for large builds |

## tmux settings

| Setting | Stock | Ours | Why |
|---|---|---|---|
| prefix | `C-b` | `C-Space` + `C-a` fallback | Ergonomic, robust fallback |
| `default-terminal` | `screen` | `tmux-256color` | Correct color terminfo |
| `terminal-overrides` | — | `xterm-ghostty:RGB` | 24-bit true color |
| `escape-time` | `500` | `10` | Near-instant Escape, safe over SSH |
| `history-limit` | `2000` | `50000` | 50K lines per pane |
| `base-index` | `0` | `1` | Matches keyboard layout |
| `renumber-windows` | `off` | `on` | No gaps after closing windows |
| `mouse` | `off` | `on` | Click, drag, scroll |
| `set-clipboard` | `external` | `on` | OSC 52 clipboard passthrough |
| `mode-keys` | `emacs` | `vi` | Vi bindings in copy mode |
| Splits | `"` / `%` | `\|` / `-` | Visual mnemonics |
| Navigation | arrows | `h/j/k/l` | Vim home row |
| Resize | `Ctrl+arrow` | `H/J/K/L` | Same keys, shifted, repeatable |

### Persistence plugins

| Plugin | Setting | Value | Why |
|---|---|---|---|
| tmux-resurrect | `@resurrect-capture-pane-contents` | `on` | Saves scrollback text |
| tmux-resurrect | `@resurrect-processes` | `~claude` | Restores Claude Code with original args |
| tmux-continuum | `@continuum-save-interval` | `5` | Snapshot every 5 minutes |
| tmux-continuum | `@continuum-restore` | `off` | `ghostty-tmux.sh` handles restore to avoid timing races |

## Troubleshooting

**Ghostty crashes: `exec: tmux: not found`**
The launcher adds Homebrew paths before resolving tmux. Re-run `./install.sh`.

**Tabs mirror the same session.**
Check that the launcher is wired correctly:
```bash
grep '^command = ' ~/.config/ghostty/config     # should point to launcher
readlink ~/.config/ghostty/ghostty-tmux.sh      # should point to repo
```

For deep tracing of rebinding/flicker:
```bash
TRACE_FILE="/tmp/ghostty-launch-trace.log"
rm -f "$TRACE_FILE"
GHOSTTY_TMUX_TRACE=1 GHOSTTY_TMUX_TRACE_FILE="$TRACE_FILE" ~/.config/ghostty/ghostty-tmux.sh >/dev/null
tail -n 200 "$TRACE_FILE"
```
Look for repeated `select session=main` lines in the same launch burst key; that indicates incorrect claim state.

**Ctrl+Space doesn't work.**
macOS captures it for input source switching. System Settings → Keyboard → Keyboard Shortcuts → Input Sources → uncheck "Select the previous input source." Use `Ctrl+A` as fallback.

**Config changes have no effect.**
macOS reads `~/Library/Application Support/com.mitchellh.ghostty/config` with higher priority. A stale file there shadows yours. Re-run `./install.sh`.

**Sessions lost after reboot.**
Verify resurrect is installed and has save data:
```bash
ls -la ~/.local/share/tmux/resurrect/last       # should exist
ls ~/.tmux/plugins/tmux-resurrect/              # should exist
tmux show -g @continuum-save-interval           # should show 5
```

**Prefix keys don't work but mouse does.**
Reload and verify:
```bash
tmux source-file ~/.tmux.conf
tmux show -gv prefix     # C-Space
tmux show -gv prefix2    # C-a
```

### Full verification

```bash
ls -la ~/.config/ghostty/config                                         # symlink → repo
ls -la ~/.config/ghostty/ghostty-tmux.sh                                # symlink → repo
ls -la ~/.config/ghostty/tmux-aliases.zsh                               # symlink → repo
ls -la "$HOME/Library/Application Support/com.mitchellh.ghostty/config" # symlink → repo
ls -la ~/.tmux.conf                                                     # symlink → repo
ls -la ~/.tmux/plugins/tmux-resurrect/                                  # plugin installed
ls -la ~/.tmux/plugins/tmux-continuum/                                  # plugin installed
ls -la ~/.local/share/tmux/resurrect/last                               # save data exists
GHOSTTY_TMUX_TRACE=1 ~/.config/ghostty/ghostty-tmux.sh >/dev/null       # emit trace logs
tmux show -gv prefix                                                    # C-Space
tmux show -gv prefix2                                                   # C-a
tmux show -gv @resurrect-processes                                      # ~claude
tmux show -gv @continuum-save-interval                                  # 5
```

## Common confusion

**Ghostty tab ≠ tmux window.** `Cmd+T` creates a Ghostty tab (and a new tmux session). `prefix+c` creates a tmux window inside the current session. Different layers.

**Mirroring is not a bug.** Two clients on the same session will mirror. The launcher prevents this by giving each tab its own session. If you manually `tmux attach -t main` from two terminals, they mirror — that's correct tmux behavior.

**`Cmd+Q` is safe.** It disconnects clients. tmux sessions keep running.

**"I rebooted and everything came back."** tmux-resurrect saved a snapshot. The launcher restored it on first tab launch. Claude Code instances were restarted with their original command and flags.

**"I rebooted and everything is gone."** Resurrect auto-saves every 5 minutes. If you installed recently and never triggered a save, there's no snapshot. Manual save: `prefix + Ctrl+S`.

## Testing

```bash
./test.sh
```

Runs 151 assertions across 31 test groups on an isolated tmux socket. Covers batch launches, delayed restore bursts, reattachment, gap-filling, race conditions, parallel stress, resurrect infrastructure, plugin settings, config correctness, symlink integrity, and launch latency benchmarks. Does not touch live sessions.

## File structure

```
best-ghostty-config/
  config              Ghostty settings + keybindings
  ghostty-tmux.sh     Session launcher — atomic locking, reattachment, resurrect restore
  tmux-aliases.zsh    tmux helper aliases for jump/kill/prune workflows
  tmux.conf           tmux settings + keybindings + persistence plugins
  install.sh          Symlinks, dependency checks, TPM + plugin installation
  test.sh             151-assertion test suite
  docs/
    cheatsheet/
      keybindings.md  Printable keybinding reference
```

## License

[MIT](LICENSE)
