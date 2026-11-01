# 9 Archives, deletion and comparison

## Compress

These commands work on local items and need Settings › General › Handle archives with FileTerm, which is on by default.

- Commands › Compress makes a zip next to the items. It's named after the item, or `Archive.zip` for several items.
- Commands › Compress With Options… lets you choose:
  - **Format:** Zip, Tar, Gzip tar, Bzip2 tar or XZ tar.
  - **Name:** the archive's name.
  - **Save in:** this folder, the other pane's local folder, or Choose….

A taken name gets a number, such as ` 2`. A failed or cancelled job removes its partial file. Jobs appear in Activities and aren't in Undo.

## Extract and Extract to

- Commands › Extract unpacks selected archives next to them.
- Commands › Extract to… lets you choose the destination, and can create a new folder for the contents.

FileTerm extracts zip, tar, tar.gz, tar.bz2, tar.xz, tgz, tbz, tbz2, txz, 7z and rar. It can create only the first five.

Nothing existing is overwritten. One top-level item lands as itself. Several items go into a folder named after the archive. Taken names get a number.

## Archive handling settings

Two settings in Settings › General decide what opening an archive does:

| Handle archives | Treat archives as folders | Double-click or File › Open |
|---|---|---|
| On | Off (default) | Extracts next to the archive |
| On | On | Opens the archive in the pane as a read-only folder |
| Off | Either | Opens it with the system's default app |

Inside an archive opened as a folder:

- Find, Quick Select, Open and Copy to… work.
- Rename, New Folder, Move to Trash, Tools, Edit, and moving items in or out are refused.
- Enclosing Folder at the archive's root returns to the folder that holds it.
- The path bar shows the path inside the archive, not the archive's name.

An archive on a connection is fully downloaded before it opens, so a large one takes time. Restoring a session can't reopen an archive.

## Move to Trash

Commands › Move to Trash (⌘⌫) moves local items to the Trash without asking, and you can undo it.

On a connection it's named Delete… and is a permanent delete, after a confirmation. See [chapter 6](06-connections-and-remote-locations.md#working-in-a-remote-pane).

FileTerm › Empty Trash… asks first, then has Finder empty the Trash on every volume. The first use shows a macOS permission prompt for controlling Finder. It can't be undone.

## Delete

Commands › Delete… (⌥⌘⌫) removes items permanently, without using the Trash. The dialog says so, and Cancel is the default button. It can't be undone.

Use it only when you're sure. For anything you might want back, use Move to Trash.

## App Deleter

Moving an app to the Trash can also remove the files it left in your Library folder.

Settings › General › Detect application when deleting is on by default. With it on, Move to Trash on an `.app` first shows the list of related files. Commands › Delete App and Related Files… shows the same list for one selected app, whatever the setting says.

1. Read the list. Nothing is ticked at first.
2. Tick the files to remove, or tick Select all related files.
3. Click Move to Trash. Only ticked files go with the app, and the whole job can be undone. Cancel moves nothing.

The list covers your own Library folder, such as Preferences, Caches, Application Support, Containers, Logs and LaunchAgents. FileTerm finds items by the app's identifier, and by its name in a few folders. It doesn't search the system-wide `/Library`, and Delete… doesn't offer this list.

## File comparison

Commands › Compare opens two local files in an external tool.

1. Select two files in the active pane, or one file in each pane. Two in the active pane take priority.
2. Choose Commands › Compare.

Choose the tool in Settings › General › Compare tool: FileMerge (the default), Kaleidoscope, BBEdit or Visual Studio Code. Tools that aren't found are marked "(not installed)". FileMerge needs Xcode. FileTerm has no built-in comparison, and folders can't be compared this way.

## Compare versus sync versus checksum

| You want to | Use | Result |
|---|---|---|
| See how two files differ | Compare | Opens an external tool. Changes nothing. |
| See how two folders differ, and optionally align them | Sync to… | A list of actions by date and size. Changes nothing until you click Synchronize. |
| Prove a file's contents match a known value | Calculate Checksum… | A digest and an optional match result |

## Command availability

| Command | Needs | When unavailable |
|---|---|---|
| Compress, Compress With Options… | Local selection, Handle archives on | Says to select items, or names the setting |
| Extract, Extract to… | Every selected item is a local archive, Handle archives on | Says to select an archive, or names the setting |
| Compare | Two files, or one in each pane, with the tool installed | Names the missing tool or the selection needed |
| Delete App and Related Files… | One local `.app` | Says to select an application |
| Empty Trash… | A Trash not known to be empty | "The Trash is empty." |

Hold the pointer over a grayed-out menu item to see its reason.
