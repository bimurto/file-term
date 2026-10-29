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
- [ ] When "treat as folders" is on, archives open as browsable folders, locally and remotely *(remote browsing is vendor-documented)*.
- [ ] Search and filter work inside an archive opened as a folder.

### M10.04 Move to Trash
- [ ] Commands › Move to Trash and the Delete toolbar button move local items to the system Trash, and the action can be undone.
- [ ] ForkLift › Empty Trash is a separate command that asks for confirmation.

### M10.05 Delete (permanent)
- [ ] Commands › Delete asks for confirmation and says clearly that the deletion is permanent.
- [ ] For remote items, the dialog says they will not go to the Mac's Trash.

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
| T2 Archives as folders | M10.03 | Open |
| T3 Trash, Delete, Empty Trash | M10.04, .05 | Open |
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
- Settings added: `handleArchives` (on) and `archivesAsFolders` (off, takes effect in T2). They are
  stored as separate Defaults keys.
- Not done: the dialogs have not been driven by hand on the desktop; unit tests cover the engine and
  the settings. There is no UI test.
