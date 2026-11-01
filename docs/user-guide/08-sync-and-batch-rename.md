# 8 Sync and batch rename

## Open a sync comparison

1. Show two panes with the two folders open. Left means the first pane, right the second.
2. Choose Commands › Sync to… or click the toolbar button.
3. Wait for the analysis to finish. Synchronize stays off until it does.
4. Read the action list. Untick anything you don't want.
5. Click Synchronize, or Cancel to change nothing.

Each option change runs the analysis again. Items are compared by modification date and size, not by content, and dates within 2 seconds count as equal. Symbolic links and special files are skipped.

## Direction

- **Left → Right** and **Right → Left** change only the destination side.
- **Both ways** adds missing items to each side, and the newer file wins. Files with the same date but different sizes are a true conflict. A conflict starts unticked, and you pick its direction in the list before ticking it.

A file on one side against a folder on the other is reported but can't be run.

## Scope and additions

- **Synchronize subfolders** is on by default. With it off, only files directly in the two folders are handled.
- **Synchronize hidden items** is off by default.
- **Add items** copies what's missing. It's on by default.
- **Don't add empty folders** skips folders with nothing to copy.

## Updates and deletions

Under Update items when:

- **Modification date is older** is on by default.
- **Size differs** is off by default. Use it when a connection is involved, because copies to remote locations don't keep modification dates. The dialog warns you about this.

**Delete orphaned items**, in red, removes items that exist only on the destination side. It's off by default. Both ways never deletes, because without a sync history a deletion looks the same as a new item.

Local orphans go to the Trash. Remote orphans are deleted permanently, after one confirmation.

A folder holding anything the comparison left out, such as hidden items, excluded items or links, is never deleted. Only the items the preview lists go, and the folder stays with the rest.

Sync jobs aren't added to Undo. A failure after at least one action succeeded ends as a partial failure, with no Retry.

## Time offsets and exclusions

**Time offset** is added to the right side's dates before comparing, in seconds or hours. Use it when two clocks or time zones disagree.

**Exclude items:** click + to add a filter.

- A glob without `/`, such as `*.log`, matches an item's name.
- A glob with `/` matches the relative path.
- A regular expression is searched for in the relative path.

Matching ignores case. An excluded folder isn't entered. An invalid regular expression is reported in the dialog and blocks Synchronize.

A folder that can't be read on either side stops the analysis too, because its twin's contents would otherwise look orphaned. The dialog names the folder. Exclude the folder and the analysis runs again, or fix the problem and reopen the dialog.

## Saved sync favorites

In the Sync dialog, Add to Favorites asks for a name, then saves both folders and every option. No passwords are stored.

Commands › Sync Favorites lists them, and Quick Open finds them. Choosing one shows both folders side by side and opens the dialog with a fresh analysis. Nothing changes until you click Synchronize.

A dialog opened from a favorite offers Update Favorite and Remove from Favorites. A favorite on a connection needs that connection to be open first.

## Open batch rename

1. Select several items.
2. Choose Commands › Rename. In list view you can also press Return.

Items are numbered in the order the pane shows them.

## Rule types

Add rules from the Add Rule menu. They run from top to bottom, and you can move or remove each one. Each rule's Apply to setting is Name only, Extension only or Full name. Folders have no extension.

- **Replace Text:** find and replace, for the first, last or all occurrences. Case sensitive is off by default.
- **Change Case:** lower, UPPER, Title or Sentence.
- **Add Sequence:** a number. See below.
- **Add Text:** text at the start, the end or a position you enter.
- **Add Date:** the file's modified or created date, or the current date. Use a format such as `yyyy-MM-dd`.
- **Add Metadata:** a value read from the file. See below.

### Add Metadata

Choose a Field and a position:

| Group | Fields |
|---|---|
| EXIF, from images | Date Taken, Camera, Dimensions |
| ID3 and media tags, from audio and video | Title, Artist, Album, Track |
| File | Created, Modified, Size in Bytes |

- Date fields use a format such as `yyyy-MM-dd`.
- An item without the chosen field keeps its name.
- EXIF and ID3 fields are read from local files only. Remote files can use only the File fields.
- `/` and `:` in a value become `-`, because tags such as `AC/DC` contain characters a file name can't.

## Sequences

Add Sequence has Start with, Step, Padding (the minimum number of digits), Prefix, Suffix and Position. With Padding set to 3, Start with 1 and Step 1, the numbers are 001, 002, 003.

## Preview and reuse

The table shows Original, New and Warning for every item, and a count of items to be renamed. Nothing changes until you click Rename.

- **Errors** turn the Rename button off: duplicate names, invalid names, or a name already taken by an item you aren't renaming.
- **An extension change** is a warning. Tick Allow extension changes to continue.

"Already taken" is checked against the pane's current folder. For search results that span folders, the job stops with an error if a name is taken elsewhere, and earlier renames stay in place.

To cancel, click Cancel. Your files stay as they were.

Add to Favorites saves the rule list as a preset. Load or delete presets from the dialog's Presets menu. Quick Open also lists them, and choosing one with several items selected opens Batch Rename with its rules loaded.

A batch of local items is one Undo step.
