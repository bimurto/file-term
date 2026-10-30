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
- [x] Settings › Tools or Commands › Manage Tools opens the tool list. Add opens the editor.
- [x] Editor fields: Name, Command, Run for every selected file, Enable for remote files, Show output, Show in Toolbar.

### M11.05 Tool placeholders
- [x] `$SOURCE_PATH`, `$TARGET_PATH`, `$SOURCE_SELECTION_PATHS`, `$TARGET_SELECTION_PATHS`, `$SOURCE_SELECTION_NAMES`, `$TARGET_SELECTION_NAMES`. Each has an insert button.
- [x] Paths are shell-quoted automatically. Unit tests cover spaces, quotes and Unicode.

### M11.06 Tool execution & output
- [x] Tools run through the M07 queue, and the exit code is logged.
- [x] When Show output is on, stdout and stderr appear in a panel.
- [x] When Show in Toolbar is on, the tool gets a toolbar button.

### M11.07 External editors
- [x] Settings › Editing: a table mapping Application to Extensions, with Add, Edit and Remove.
- [x] Commands › Edit opens the file in the editor mapped to its extension.

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
| T2 Sync Favorites setting | M11.03 | Setting only, sync deferred |
| T3 Tool model, placeholders, editor | M11.04, M11.05 | Done |
| T4 Tool execution, output, toolbar | M11.06 | Done |
| T5 External editors and Edit | M11.07 | Done |
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

## T2 notes

- Settings › General › Sync Favorites to iCloud (default off) is saved as `syncFavoritesToICloud`.
  **Live sync is deferred, so the M11.03 box stays unticked.** FileTerm is ad-hoc signed with no
  entitlements. iCloud key-value sync needs a developer team and an iCloud entitlement, and an ad-hoc
  build carrying that entitlement does not launch. The pane says so next to the toggle.
- `FavoritesSyncPayload` (Core) is what would be synced: a version number and the favorites list,
  nothing else, so file contents can never be included. Data from a newer version is refused.
- Also fixed: Settings › Shortcuts no longer lists the dynamic Go › Favorites entries.

## T3 notes

- Settings › Tools lists the tools with Add, Edit (or double-click) and Remove. Commands › Manage
  Tools… opens that pane. The editor has Name, Command, Run for every selected file, Enable for
  remote files, Show output and Show in Toolbar. Running the tools is T4; until then they are only
  saved.
- Each placeholder has an Insert button that appends it to the end of the command (the text field has
  no cursor to insert at). Source is the active pane, target is the other pane.
- Substituted paths and names are quoted as one literal shell word each (`'it'\''s'`), several are
  space-separated, and a missing value becomes an empty string. The command is scanned once, so a
  file named `$TARGET_PATH` is not expanded a second time. `$SOURCE_PATHS` or `$SOURCE_PATH_X` are
  not placeholders and stay as written; `$SOURCE_PATH/x` works.
- Run for every selected file gives one command line per selected item (the target selection is
  unchanged) and none when nothing is selected.
- Enable for remote files means the placeholders carry remote paths and the command runs on this Mac;
  nothing is downloaded.
- Unit tests quote spaces, single and double quotes, `$()` and backticks, backslashes and Unicode,
  and check the result by having `/bin/sh` split it back into the original words.

## T4 notes

- Tools appear in Commands › Tools (and in Quick Open, and Settings › Shortcuts so each can get a
  shortcut). A tool runs as `/bin/sh -c <command>` in the active pane's folder, or in your home folder
  when that pane is remote, as a queue job of kind `tool`.
- The Logs panel gets `$ <command>` and `Exit code N` per command line. A nonzero exit fails the job
  and the Activities row says which code. Tool jobs are never retried automatically or with Retry,
  because rerunning an arbitrary command is not known to be safe. Cancel stops the running process.
- Show output opens a window with each command, its exit code, and output and error sections
  (Copy All, Close). It opens after the run, also when the run failed. Output is not streamed while
  the tool runs.
- Show in Toolbar adds a hammer button after the toolbar items. Tools are never added to the saved
  toolbar list, so a removed tool leaves no stale button.
- A tool is disabled, with the reason as its tooltip and in Quick Open, when: no folder is open; either
  pane is remote and Enable for remote files is off; either pane is an archive opened as a folder;
  or Run for every selected file has no selection.
- `ProcessRunner.capture` is new in Core: it returns the exit status with stdout and stderr and does
  not throw on a nonzero exit. `run` now shares its launch code and behaves as before.
- Not done: the output window and toolbar button have not been driven by hand on the desktop. Tests
  run real commands through the queue (exit codes, per-file runs, working folder) and check the
  availability rules.

## T5 notes

- Settings › Editing is a table of Application and Extensions with Add, Edit and Remove. The editor
  picks an `.app` (Choose… or a typed path) and takes extensions separated by commas or spaces
  (`swift, .MD txt`). A row whose application no longer exists is shown in red.
- Commands › Edit opens the one selected file in the first row, in list order, that lists one of its
  extensions. Matching ignores case and works on whole suffixes, so `tar.gz` matches `a.tar.gz` and
  `gitignore` matches `.gitignore`, while `swift` does not match `x.notswift`.
- With no matching row Edit opens the file in its default application. If the mapped application is
  missing, the file opens in the default application and a notice says so.
- Edit needs exactly one regular file. Remote files are refused for now, with the reason in the
  tooltip; T6 turns that into download, edit and upload.
- `FileOperationCoordinator.openInEditor(_:editors:)` is what T6 reuses for the downloaded copy.
- Not done: opening through `NSWorkspace` has not been driven by hand. Unit tests cover the matching
  rules, the extension parser and persistence.
