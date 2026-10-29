# M10 — Archives, deletion & comparison

**Goal:** Add archive create/extract/browse, safe deletion including app cleanup, and an external compare tool.
**Ref:** Guide › Ch. 9 Archives deletion and comparison.

## Items

### M10.01 Compress
- [x] Commands › Compress creates a zip with default settings.
- [x] Compress With Options lets the user choose format, destination and name.

### M10.02 Extract / Extract to
- [x] Extract unpacks next to the archive.
- [x] Extract to unpacks into the other pane or a chosen folder. An option creates a new empty folder for the contents.

### M10.03 Archive handling settings
- [x] Settings › General: Handle archives with ForkLift (default on), Treat archives as folders (default off).
- [x] When "treat as folders" is on, archives open as browsable folders, locally and remotely *(remote browsing is vendor-documented)*.
- [x] Search and filter work inside an archive opened as a folder.

### M10.04 Move to Trash
- [x] Commands › Move to Trash and the Delete toolbar button move local items to the system Trash, and the action can be undone.
- [x] ForkLift › Empty Trash is a separate command that asks for confirmation.

### M10.05 Delete (permanent)
- [x] Commands › Delete asks for confirmation and says clearly that the deletion is permanent.
- [x] For remote items, the dialog says they will not go to the Mac's Trash.

### M10.06 App Deleter
- [ ] When Settings › General › Detect application when deleting is on, deleting a `.app` shows a list of related files (prefs, caches, support folders).
- [ ] Every related file is shown with a checkbox, and none is deleted without the user confirming.

### M10.07 Compare tool integration
- [ ] Settings › General › Compare Tool (default FileMerge / Xcode).
- [ ] Commands › Compare opens the two selected files, or one file from each pane, in that tool.
- [ ] If the tool isn't installed, the command is disabled and says why.

### M10.08 Command availability rules
- [ ] Extract requires an archive. Compare requires two files and an installed tool. App cleanup requires a `.app`. Each case shows a disabled reason.

## Tickets

M10 ships in tickets, one commit each.

| Ticket | Covers | Status |
|---|---|---|
| T1 Compress, Extract, archive settings | M10.01, .02, first item of .03, Extract part of .08 | Done |
| T2 Archives as folders | M10.03 | Done |
| T3 Trash, Delete, Empty Trash | M10.04, .05 | Done |
| T4 App Deleter | M10.06, App cleanup part of .08 | Open |
| T5 Compare tool | M10.07, Compare part of .08 | Open |

## T1 notes

- Compress, Compress With Options…, Extract and Extract to… are in the Commands menu. They work on
  local items only and need Settings › General › Handle archives with FileTerm (on by default).
  With it off, the commands are disabled and say so.
- Tools: `/usr/bin/ditto` (a single folder to zip, as Finder does) and `/usr/bin/bsdtar` (everything
  else). Formats created: zip, tar, tar.gz, tar.bz2, tar.xz. Extraction also reads `.tgz`, `.tbz2`,
  `.txz`, `.7z` and `.rar` through bsdtar.
- A new archive is named after the item (`docs.zip`), or `Archive.zip` for several items, and gets
  ` 2`, ` 3` … when the name is taken. A failed or cancelled compress removes its partial file.
- Extract unpacks into a hidden staging folder and then moves the result, so nothing existing is
  overwritten. One top-level item lands as itself; several items, or the "Create a new folder"
  option, go into a folder named after the archive. Taken names get ` 2`, ` 3` ….
- Compress With Options and Extract to use an alert with a format/name/destination form
  (this folder, the other pane when it is a local folder, or Choose…).
- Double-clicking an archive, or Open, extracts it next to the archive when Handle archives is on.
- Jobs run in the queue as `compress` and `extract`. They are not in Undo history.
- Settings added: `handleArchives` (on) and `archivesAsFolders` (off, see T2). They are
  stored as separate Defaults keys.
- Not done: the dialogs have not been driven by hand on the desktop; unit tests cover the engine and
  the settings. There is no UI test.

## T2 notes

- With Settings › Treat archives as folders on (and Handle archives on), double-click, Return or
  Commands › Open on an archive opens it in the pane as a read-only folder. Go Up at the archive
  root returns to the folder that holds the archive; Back and Forward work as usual.
- `ArchiveProvider` (core) is a read-only `FileSystemProvider`. It reads the table of contents once
  with `bsdtar -tv` and extracts a file only when it is read, into a temporary folder that is
  deleted when the read ends. Because it is a provider, Find (name and contents), Quick Select,
  Open and Copy to… work inside an archive through the same code as remote panes.
- Finder's `__MACOSX` folders and `._` files are not listed. Dates are as precise as `bsdtar -tv`
  prints them (minutes; recent items have no year, so the latest non-future year is assumed).
- Remote: an archive on a server (or inside another archive) is downloaded in full as an `open`
  queue job, then browsed. The copy is deleted when no tab shows the archive, or at quit.
- Rename, New Folder, Move to Trash, and Copy or Move into an archive show "This archive is
  read-only". Moving out of an archive is refused too, because it would delete the source.
- A closed archive is detected when a navigation happens (`onVisit`) or a window closes. Pane
  history that still points at a closed archive shows an error when you go Back to it. A restored
  session cannot reopen an archive; that tab falls back as for any missing provider.
- Not done: the path bar shows the path inside the archive, not the archive's name; large remote
  archives are downloaded completely before they open; not driven by hand on the desktop.

## T3 notes

- Move to Trash (⌘⌫) moved from the File menu to Commands, and Delete… (⌥⌘⌫) sits next to it. The
  Delete button is in the default toolbar (`file.trash`); saved toolbars keep their own list, and
  Customize Toolbar can add it. Local Move to Trash asks nothing and can be undone, as before.
- Delete… on local items asks first. The dialog says the deletion is permanent and the items will
  not go to the Trash; Cancel is the default button. It is not added to Undo history.
- On a server, Delete… and Move to Trash show the remote delete dialog, which now also says the
  items will not go to the Mac's Trash.
- FileTerm › Empty Trash… is separate. It asks (with the item count when macOS lets FileTerm read
  `~/.Trash`), then asks Finder to empty the Trash through AppleScript, so every volume is covered.
  The first use shows macOS's Automation prompt (`NSAppleEventsUsageDescription`). It is disabled
  with "The Trash is empty." only when the count is known to be zero. It is not undoable.
- Not done: Empty Trash and the delete dialogs have not been driven by hand on the desktop (the
  Finder prompt needs an interactive session); unit tests cover the permanent delete engine and the
  toolbar default.
