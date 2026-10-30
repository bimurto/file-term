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
- [x] Downloads the remote file to a temp folder and watches it for saves. Each save uploads the file and logs the upload.
- [x] Before the first upload, the user confirms the target account and path.

### M11.09 Terminal integration
- [x] File › Open in Terminal and a toolbar button open the current local folder in the terminal app chosen in Settings › General › Terminal Application (Terminal, iTerm, etc.).
- [x] This external terminal stays separate from the built-in terminal panel (M06). Both can be used side by side.

### M11.10 Source control (Git)
- [x] Commands › Source Control: Add, Add All, Commit (message prompt), Push, Pull.
- [x] The menu is disabled outside a Git repository. Git output is written to Logs.

## Tickets

M11 ships in tickets, one commit each.

| Ticket | Covers | Status |
|---|---|---|
| T1 Favorites manager and remote paths | M11.01, M11.02 | Done |
| T2 Sync Favorites setting | M11.03 | Setting only, sync deferred |
| T3 Tool model, placeholders, editor | M11.04, M11.05 | Done |
| T4 Tool execution, output, toolbar | M11.06 | Done |
| T5 External editors and Edit | M11.07 | Done |
| T6 Remote editing | M11.08 | Done |
| T7 Open in Terminal | M11.09 | Done |
| T8 Source control | M11.10 | Done |

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
- Edit needs exactly one regular file. Remote files are handled by T6.
- `FileOperationCoordinator.openInEditor(_:editors:)` is what T6 reuses for the downloaded copy.
- Not done: opening through `NSWorkspace` has not been driven by hand. Unit tests cover the matching
  rules, the extension parser and persistence.

## T6 notes

- Commands › Edit on a file in a connection downloads it (an `open` job) to a temporary folder, opens
  it in the editor mapped in Settings › Editing, and watches that folder. Editing the same remote file
  again reopens the existing copy instead of downloading over unsaved work.
- The first save asks: "Upload your changes to “name”?" with the account and path (for example
  `Office NAS: /docs/note.txt`). **Upload** confirms for that file until FileTerm quits or the
  connection closes. **Stop Watching** ends the session, keeps the local copy and uploads nothing.
  Nothing is uploaded before this answer.
- Each later save is an `upload` job in the queue (Activities, Logs). The log reads
  `Uploaded note.txt to Office NAS: /docs/note.txt`, and a failure logs `Upload of … failed: …`. The file on the
  server is replaced through a hidden temporary name, as in Copy to…. A save made while the
  question is open goes into the first upload.
- Saves are found by watching the temporary folder, so editors that save by writing a sibling file
  and renaming it are covered. A save is uploaded when its modification time or size differs from
  the last attempt, so a failed upload is retried by saving again, not in a loop.
- If the connection is closed, the session ends with a notice instead of uploading.
- Bug found by the tests and fixed: FSEvents reports `/private/var/...` for the temporary folder, and
  `FolderWatcher` matches paths as text, so no save would ever have been noticed. The folder is now
  handed to the watcher through `realpath`. `FolderWatcher` itself is unchanged and still has this
  limit for any other symlinked folder (the same applies to pane folders).
- Second bug found by a flaky test and fixed: `URL.resourceValues` caches inside the URL, so it kept
  reporting the old size after a save and a real save looked unchanged. The change check now reads
  `FileManager.attributesOfItem`. Twelve repeated runs of the suite pass.
- Not done: the confirmation dialog and a real editor have not been driven by hand; the tests use an
  in-memory server, an injected confirmation and a no-op editor launch, plus one real file-system
  event test.

## T7 notes

- File › Open in Terminal (and a toolbar button, `apple.terminal`) opens the active pane's folder in
  the app chosen in Settings › General › Terminal Application: Terminal (default), iTerm, Ghostty or
  Warp. Apps are looked for in `/Applications`, `~/Applications` and, for Terminal, the system
  Utilities folder. An app that is not installed is marked "(not installed)" in the picker, and the
  command is disabled with the reason.
- Local folders only. A remote or archive pane disables the command.
- The command opens the folder through `NSWorkspace`, so each app decides how to show it (a new
  window or tab at that folder). It does not touch the built-in terminal panel (View › Show
  Terminal): the two share no state and can be open side by side.
- The toolbar button is in the default toolbar, so only new installs see it. Existing users add it
  from View › Customize Toolbar….
- Not done: the apps themselves have not been launched by hand; tests cover where each app is found,
  the setting, and the default toolbar.

## T8 notes

- Commands › Source Control has Add (the selected items), Add All, Commit… (asks for a message),
  Push and Pull. Each runs `/usr/bin/git -C <repository root> …` as a queue job of kind `git`, with
  no shell, so paths and messages need no quoting. The root is the nearest folder at or above the
  current one that holds `.git` (a folder or a worktree file).
- Every item is disabled, with the reason as tooltip, outside a Git repository, in a remote or archive
  pane, and (Add only) with nothing selected. Commit with an empty message does nothing.
- Logs get `$ git -C … <command>`, each output line (stdout, then stderr, at most 500 lines) and
  `Exit code N`. A nonzero exit fails the job and Activities shows git's last error line. Git jobs are
  not retried. The panes refresh afterwards.
- Git never waits for input: `GIT_TERMINAL_PROMPT=0`, `GIT_MERGE_AUTOEDIT=no` and `GIT_EDITOR=true`
  are set, so a push or pull that needs a password fails with git's message instead of hanging.
  Credentials must already work from the command line (keychain helper or SSH agent).
- Push is plain `git push`. A branch with no upstream fails with git's own message, which includes
  the command to run; the upstream is not set for you.
- Tests run real git in temporary repositories: add, add all, commit (quotes and a multi-line
  message), a failing add, and push and pull through a local bare remote.
- Not done: the commit prompt and the menu have not been driven by hand.

## Summary

M11 is implemented except live iCloud sync (M11.03, deferred, see T2). Items not driven by hand on the
desktop are listed in each ticket's notes.
