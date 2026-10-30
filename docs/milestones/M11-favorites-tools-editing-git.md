# M11 — Favorites, tools, editing & Git

**Goal:** Add saved favorites, user-defined command tools, external and remote editing, terminal integration and basic Git.
**Ref:** Guide › Ch. 10 Favorites tools editing and Git.

## Items

### M11.01 Favorites manager
- [x] Toolbar button opens the manager with New Favorite, New Favorite Group, Edit, Delete.
- [x] Local paths, iCloud Drive and connections can appear in the same list. Entries can be dragged into groups.

### M11.02 Remote favorite paths *(vendor-documented)*
- [x] A connection favorite can hold several saved paths. Choosing one connects and opens that path.

### M11.03 Sync favorites to iCloud
- [ ] Settings › General › Sync Favorites to iCloud (default off) syncs only the favorites list, not file contents.

### M11.04 Tool list & editor
- [ ] Settings › Tools or Commands › Manage Tools opens the tool list. Add opens the editor.
- [ ] Editor fields: Name, Command, Run for every selected file, Enable for remote files, Show output, Show in Toolbar.

### M11.05 Tool placeholders
- [ ] `$SOURCE_PATH`, `$TARGET_PATH`, `$SOURCE_SELECTION_PATHS`, `$TARGET_SELECTION_PATHS`, `$SOURCE_SELECTION_NAMES`, `$TARGET_SELECTION_NAMES`. Each has an insert button.
- [ ] Paths are shell-quoted automatically. Unit tests cover spaces, quotes and Unicode.

### M11.06 Tool execution & output
- [ ] Tools run through the M07 queue, and the exit code is logged.
- [ ] When Show output is on, stdout and stderr appear in a panel.
- [ ] When Show in Toolbar is on, the tool gets a toolbar button.

### M11.07 External editors
- [ ] Settings › Editing: a table mapping Application to Extensions, with Add, Edit and Remove.
- [ ] Commands › Edit opens the file in the editor mapped to its extension.

### M11.08 Remote editing *(vendor-documented)*
- [ ] Downloads the remote file to a temp folder and watches it for saves. Each save uploads the file and logs the upload.
- [ ] Before the first upload, the user confirms the target account and path.

### M11.09 Terminal integration
- [ ] File › Open in Terminal and a toolbar button open the current local folder in the terminal app chosen in Settings › General › Terminal Application (Terminal, iTerm, etc.).
- [ ] This external terminal stays separate from the built-in terminal panel (M06). Both can be used side by side.

### M11.10 Source control (Git)
- [ ] Commands › Source Control: Add, Add All, Commit (message prompt), Push, Pull.
- [ ] The menu is disabled outside a Git repository. Git output is written to Logs.

## Tickets

M11 ships in tickets, one commit each.

| Ticket | Covers | Status |
|---|---|---|
| T1 Favorites manager and remote paths | M11.01, M11.02 | Done |
| T2 Sync Favorites setting | M11.03 | Open |
| T3 Tool model, placeholders, editor | M11.04, M11.05 | Open |
| T4 Tool execution, output, toolbar | M11.06 | Open |
| T5 External editors and Edit | M11.07 | Open |
| T6 Remote editing | M11.08 | Open |
| T7 Open in Terminal | M11.09 | Open |
| T8 Source control | M11.10 | Open |

## T1 notes

- Go › Manage Favorites… (also a star button in the default toolbar) opens the manager sheet:
  New Favorite, New Favorite Group, Edit and Delete. A favorite is a local folder (Choose…, or the
  iCloud Drive button) or a saved connection with its own list of paths. Groups are one level deep.
- Drag a favorite onto a group heading to file it there. "Move Out" returns it to the top level.
  Deleting a group that holds favorites asks first.
- Go › Favorites lists them, groups as submenus. A connection with several paths shows a submenu with
  one entry per path. Choosing one connects (unless already open) and opens that path in the pane set
  by Settings › General › Open remote connections in. Favorites also appear in Quick Open.
- A connection favorite with no paths opens the profile's own folder. A favorite whose connection was
  deleted shows a notice. Mounted shares (SMB, AFP, NFS) resolve paths under the mount point.
- Stored as the `favorites` Defaults key (JSON). Model and list helpers are in `Core/Favorites`.
- Not done: reordering favorites by drag within the list; the dialogs have not been driven by hand
  on the desktop. Unit tests cover the model, persistence and opening a connection favorite.
