# M03 — Selection, search & quick commands

**Goal:** Add fast selection, a Quick Open launcher, search, hidden files and customizable shortcuts.
**Ref:** Guide › Ch. 3 Selection search and quick commands.

## Items

### M03.01 Basic selection model
- **Scope:** Click, Cmd-click and Shift-click selection. Edit › Select All, Deselect All, Invert Selection.
- [x] Invert Selection swaps selected and unselected items in the current listing.
- [x] Status bar shows the selected count and size (from M01.06).

### M03.02 Quick Select (⌘S)
- **Scope:** Select items by matching name, extension or tag. Add to or remove from the current selection. *(matching modes are vendor-documented)*
- [x] The resulting selection count is shown before any command runs.

### M03.03 Quick Open launcher (Esc)
- **Scope:** Fuzzy launcher for commands and destinations, built on the command registry.
- [x] Finds commands by name and runs them.
- [x] Finds folders and recent locations.
- [x] Extension points for devices, favorites, applications and rename presets *(vendor-documented, filled in later milestones)*.

### M03.04 Find UI
- **Scope:** File › Find and a toolbar Search field, with a criteria panel and a folder-scope indicator.
- [x] Results show in a result view, and the results can be selected for later commands.

### M03.05 Search engines
- **Scope:** (a) Built-in scanning search that also works on remote providers. (b) Spotlight search for local files, including file contents. A toggle to include subfolders.
- [x] User can pick the engine. Spotlight is disabled for remote locations.

### M03.06 Search vs selection behavior
- [x] Quick Select never changes the browsing location. Search opens a separate result scope that can be closed to return to the folder.

### M03.07 Show hidden toggle
- **Scope:** Toolbar checkbox "Show hidden".
- [x] Hidden items look visually different (for example, dimmed).
- [x] This toggle is separate from the sync "hidden items" option (M09).

### M03.08 Refresh & auto-refresh
- **Scope:** View › Refresh. Optionally watch the filesystem for changes.
- [x] Changes made in another app appear after Refresh, or automatically if watching is on.

### M03.09 Shortcut customization
- **Scope:** Settings › Shortcuts with a searchable command list, a shortcut editor, conflict detection and Restore Defaults.
- [x] Assigning a shortcut that is already used shows a conflict warning.
- [x] 4.6 defaults are seeded: Quick Select ⌘S, Quick Open Esc, New Folder ⇧⌘N, New Folder With Selection ⌃⌘N, New File ⌥⇧⌘N, Open ⌘O, Quick Look ⌘Y.
