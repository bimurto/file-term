# M04 — File creation, copying & moving

**Goal:** Add the core local file operations with safe conflict handling and undo.
**Ref:** Guide › Ch. 4 File creation copying and moving.

## Items

### M04.01 New Folder / New Folder With Selection
- [ ] New Folder (⇧⌘N) creates a folder and starts inline rename.
- [ ] New Folder With Selection (⌃⌘N) moves the selected items into a new folder.

### M04.02 New File
- [ ] New File (⌥⇧⌘N) creates an empty file and starts inline rename with the extension editable.

### M04.03 Open / Open With / Show Package Contents
- [ ] Open (⌘O) opens the item in its default app.
- [ ] Open With lists suitable apps, plus Other… to choose any app.
- [ ] Show Package Contents opens a bundle (`.app` and similar) as a folder.

### M04.04 Copy to (pane to pane)
- **Scope:** Commands › Copy to and Copy to as (copy with a new name). Source is the active pane, destination is the other pane.
- [ ] A confirmation shows the destination path before copying.
- [ ] Source files are still there after the copy.

### M04.05 Clipboard copy / paste
- [ ] Edit › Copy then Paste works across folders, tabs and windows in single-pane mode.

### M04.06 Move to / Move Items Here
- [ ] Commands › Move to moves the selection to the other pane.
- [ ] Edit › Move Items Here moves clipboard items into the current folder.
- [ ] Moves within the same volume use rename. Moves across volumes use copy then delete.

### M04.07 Duplicate
- [ ] Commands › Duplicate creates "name copy.ext" (or similar) in the same folder without overwriting anything.

### M04.08 Single-item rename
- [ ] Commands › Rename with one item selected starts inline rename.
- [ ] Changing the extension shows a confirmation.
- [ ] With more than one item selected, this command opens batch rename instead (M09).

### M04.09 Conflict resolution dialog
- **Scope:** Replace, Replace Older, Keep Both, Skip, Stop, plus Merge for folders. An "apply to all" option.
- [ ] Merge copies child items into the folder and asks again about each child conflict.
- [ ] Keep Both generates a name that doesn't collide with existing files.

### M04.10 Undo / Redo
- **Scope:** An undo stack for reversible local operations (rename, move, new folder, trash).
- [ ] Undo and Redo are disabled, with a reason shown, for operations that can't be undone (permanent delete, remote delete).
