# M04 — File creation, copying & moving

**Goal:** Add the core local file operations with safe conflict handling and undo.
**Ref:** Guide › Ch. 4 File creation copying and moving.

## Items

### M04.01 New Folder / New Folder With Selection
- [x] New Folder (⇧⌘N) creates a folder and starts inline rename.
- [x] New Folder With Selection (⌃⌘N) moves the selected items into a new folder.

### M04.02 New File
- [x] New File (⌥⇧⌘N) creates an empty file and starts inline rename with the extension editable.

### M04.03 Open / Open With / Show Package Contents
- [x] Open (⌘O) opens the item in its default app.
- [x] Open With lists suitable apps, plus Other… to choose any app.
- [x] Show Package Contents opens a bundle (`.app` and similar) as a folder.

### M04.04 Copy to (pane to pane)
- **Scope:** Commands › Copy to and Copy to as (copy with a new name). Source is the active pane, destination is the other pane.
- [x] A confirmation shows the destination path before copying.
- [x] Source files are still there after the copy.

### M04.05 Clipboard copy / paste
- [x] Edit › Copy then Paste works across folders, tabs and windows in single-pane mode.

### M04.06 Move to / Move Items Here
- [x] Commands › Move to moves the selection to the other pane.
- [x] Edit › Move Items Here moves clipboard items into the current folder.
- [x] Moves within the same volume use rename. Moves across volumes use copy then delete.

### M04.07 Duplicate
- [x] Commands › Duplicate creates "name copy.ext" (or similar) in the same folder without overwriting anything.

### M04.08 Single-item rename
- [x] Commands › Rename with one item selected starts inline rename.
- [x] Changing the extension shows a confirmation.
- [ ] With more than one item selected, this command opens batch rename instead (M09).
  - M04 presents an explicit M09 availability notice rather than silently renaming one item; the batch editor is deferred to M09.

### M04.09 Conflict resolution dialog
- **Scope:** Replace, Replace Older, Keep Both, Skip, Stop, plus Merge for folders. An "apply to all" option.
- [x] Merge copies child items into the folder and asks again about each child conflict.
- [x] Keep Both generates a name that doesn't collide with existing files.

### M04.10 Undo / Redo
- **Scope:** An undo stack for reversible local operations (rename, move, new folder, trash).
- [x] Undo and Redo are disabled, with a reason shown, for operations that can't be undone (permanent delete, remote delete).

## Implementation notes

- Local operations use an app-wide, session-only undo journal, separate from navigation history. Replacements retain backups; undo/redo refuse to overwrite occupied paths or move content changed outside the journal.
- Same-volume moves use exclusive native rename; only `EXDEV` triggers verified copy-then-delete. Folder merges prompt for child conflicts, and Stop leaves completed work undoable.
- Undo/recovery storage is retained in private temporary directories (or destination-volume recovery directories after a cross-volume failure). Automatic history-storage cleanup and persistent history are not implemented; retained files favor recovery over deletion.
- Verification: core operation tests, native clipboard/rename-state tests, and XCUITests for folder creation, file creation with extension confirmation, and rename/undo. Open With, all view modes, and real secondary-volume behavior still merit manual smoke testing.
