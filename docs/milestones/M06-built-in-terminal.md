# M06 — Built-in terminal (follows pane directory)

**Goal:** Add a terminal panel inside the window. Its working directory follows the active pane, and, if the user turns it on, the pane follows the terminal when the user runs `cd`.
**Ref:** New feature. ForkLift itself only opens an external terminal (see M11.09 › Terminal integration).
**Depends on:** M01 (panes and active pane), M02 (tabs and windows), M05 (path formatting and quoting from M05.08).

## Approved implementation decisions

- Use SwiftTerm for the emulator and local PTY.
- Sessions belong to pane-tab identities, not native window tabs. Each pane tab keeps its own shell, working directory and scrollback; the drawer displays the selected linked pane tab's session.
- Link pane and terminal bidirectionally by default only while the shell is idle at an empty prompt. Foreground commands suspend both directions; pending input must never be overwritten. Background jobs alone do not suspend linking.
- When a command finishes, the latest pane navigation made while paused wins. Otherwise, the terminal working directory wins, so a manually entered `cd` updates its pane.
- Explicit unlinking and disabling reverse synchronization remain available. Closing a pane tab/window terminates its sessions. Hiding the drawer retains sessions; its explicit Close action terminates them.

## Items

### M06.01 Terminal emulator component
- **Scope:** Embed a terminal emulator backed by a real PTY. Start the user's login shell (`$SHELL -l`).
- [x] Runs interactive programs correctly (`vim`, `top`, `less`), including colors, resize and Unicode.
- [x] The shell process ends cleanly when the panel or window closes.

### M06.02 Terminal panel layout
- **Scope:** A resizable drawer below the panes, with a docking option on the right. View › Show Terminal, a toolbar button and a default shortcut (⌃`).
- [x] The panel's size, visibility and docking position persist per window and are restored by M02.11.
- [x] Keyboard focus moves between the panes and the terminal with a shortcut.

### M06.03 Shell integration scripts
- **Scope:** Automatically inject small zsh, bash and fish snippets that report the current directory (OSC 7) and mark where prompts and commands start and end (OSC 133).
- [x] The user's rc files are not changed permanently. Injection happens through the launch environment or arguments.
- [x] Unsupported shells still work, without the integration features.

### M06.04 Follow pane → terminal
- **Scope:** When the active pane's location changes, run `cd -- '<path>'` in the shell, using shell-safe quoting.
- [x] Works for normal navigation, Go menu entries, Go to Folder, the path bar, Back/Forward and Sync Browsing.
- [x] Paths with spaces, quotes, `$` and Unicode work (unit-tested).
- [x] The injected `cd` is kept out of shell history where the shell allows it (for example, a leading space with `HIST_IGNORE_SPACE`).

### M06.05 Busy-shell safety
- **Scope:** Only send `cd` when the shell is idle at a prompt. Check with OSC 133 state, or by checking that the terminal's foreground process group is the shell.
- [x] While a program is running, `cd` is never typed into it. The panel shows an "out of sync" badge with a "Sync now" button.
- [x] Text typed but not yet run at the prompt is kept. Either `cd` waits, or it is applied through the shell integration without touching the input line.

### M06.06 Follow terminal → pane (reverse sync)
- **Scope:** When OSC 7 reports a new directory after a `cd`, open that directory in the linked pane.
- [x] Can be turned on or off separately from pane → terminal.
- [x] If the reported directory is outside the local filesystem or doesn't exist, the pane stays where it is.

### M06.07 Loop & race prevention
- [x] A change triggered by one side doesn't echo back (pane → `cd` → OSC 7 → pane must not navigate again).
- [x] Fast navigation is debounced, so only the final location is sent.

### M06.08 Follow mode & linking
- **Scope:** Modes: Follow active pane (default), Follow left/top pane, Follow right/bottom pane, Unlinked.
- [x] Making the other pane active sends `cd` in "Follow active pane" mode.
- [x] A lock button in the panel header switches between linked and unlinked, and shows which pane is linked.

### M06.09 Sessions per tab
- **Scope:** Each window tab (M02.08) has its own terminal session. Optionally, several terminal sub-tabs inside the panel.
- [x] Switching window tabs switches the terminal session, and each session keeps its own scrollback and directory.

### M06.10 Non-local locations
- [x] When the linked pane is remote (M08), an archive (M10.03) or a search result (M03.04), following pauses and shows a reason.
- [x] Later extension: for SFTP connections, offer to open an SSH session to the same host and path. Track this in M08.

### M06.11 File ↔ terminal interactions
- [x] Dragging files from a pane into the terminal inserts their shell-quoted paths.
- [x] A command inserts the selected paths, or `$SOURCE_SELECTION_PATHS`-style text, at the prompt.
- [x] "Reveal terminal directory in pane" for when reverse sync is off.
- [x] File paths printed in the terminal can be Cmd-clicked to reveal them in the pane.

### M06.12 Appearance & basics
- [x] Font, size, cursor style and scrollback length are configurable. The color scheme follows the app theme (M12.01).
- [x] Copy and paste, find in scrollback, Clear, and clickable URLs.

### M06.13 Settings & shortcuts
- **Scope:** A new **Settings › Terminal** category (the eighth category; extends M00.06). It holds the shell path, login/interactive flags, follow mode, reverse sync, shell integration on/off and appearance.
- [x] All terminal commands are in the command registry (M00.05), so they appear in Quick Open and can be rebound (M03.09).

### M06.14 Tests
- [x] Integration tests for zsh and bash covering: follow on navigate, no injection while `sleep 5` runs, reverse sync on `cd`, no loops, and quoting edge cases.
