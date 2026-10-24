# M11 — Favorites, tools, editing & Git

**Goal:** Add saved favorites, user-defined command tools, external and remote editing, terminal integration and basic Git.
**Ref:** Guide › Ch. 10 Favorites tools editing and Git.

## Items

### M11.01 Favorites manager
- [ ] Toolbar button opens the manager with New Favorite, New Favorite Group, Edit, Delete.
- [ ] Local paths, iCloud Drive and connections can appear in the same list. Entries can be dragged into groups.

### M11.02 Remote favorite paths *(vendor-documented)*
- [ ] A connection favorite can hold several saved paths. Choosing one connects and opens that path.

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
