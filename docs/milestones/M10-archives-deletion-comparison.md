# M10 — Archives, deletion & comparison

**Goal:** Add archive create/extract/browse, safe deletion including app cleanup, and an external compare tool.
**Ref:** Guide › Ch. 9 Archives deletion and comparison.

## Items

### M10.01 Compress
- [ ] Commands › Compress creates a zip with default settings.
- [ ] Compress With Options lets the user choose format, destination and name.

### M10.02 Extract / Extract to
- [ ] Extract unpacks next to the archive.
- [ ] Extract to unpacks into the other pane or a chosen folder. An option creates a new empty folder for the contents.

### M10.03 Archive handling settings
- [ ] Settings › General: Handle archives with ForkLift (default on), Treat archives as folders (default off).
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
