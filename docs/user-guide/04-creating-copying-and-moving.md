# 4 Creating, copying and moving

## New Folder

File › New Folder (⇧⌘N) creates a folder named "untitled folder" in the active pane and starts renaming it. It also works on connections.

File › New Folder With Selection (⌃⌘N) creates a folder and moves the selected items into it. It works in local folders only.

## New File

File › New File (⌥⇧⌘N) creates an empty file named "untitled" and starts renaming it, so you can type the extension too. It works in local folders only.

## Open and Open With

- File › Open (⌘O) opens the selected items. Folders open in the pane, and files open in their default app.
- File › Open With lists apps that can open every selected item. Other… lets you choose any app.
- File › Show Package Contents browses inside a package, such as an `.app`, as a folder.

Opening a file from a connection downloads a temporary copy first. Edits to that copy aren't sent back. To edit a remote file, use Commands › Edit ([chapter 10](10-favorites-tools-editing-and-git.md#remote-editing)).

## Right-click menus

Right-clicking an item selects it, unless it's already part of a selection. The menu then acts on everything selected. Unavailable items stay visible but dimmed, and their tooltip says why.

- **On a file:** Open, Open With, Move to Trash, Get Info, Rename, Compress, Duplicate, Make Alias, Quick Look, Reveal in Finder, Share, Copy, Copy Path, Show View Options, tags and Services. Show Package Contents, iCloud and Dropbox items appear when they apply.
- **On a folder:** the same, plus Open in New Tab and Contents, which lists what's inside.
- **On several items:** the same, with New Folder with Selection first.
- **On empty space:** New Folder, New File, Get Info, Quick Look, Copy Path, Show View Options and Services, for the current folder.
- **On a remote item:** Delete… replaces Move to Trash, because a server delete is permanent.
- **On a column header:** choose which columns the list shows.

The color dots turn a tag on or off. The first seven tags in Settings › Tags appear there, and every tag is in File › Tags.

## Copy to

Commands › Copy to… copies the selection from the active pane to the other pane's folder.

1. Open the destination folder in the other pane.
2. Select the items in the source pane.
3. Choose Commands › Copy to….
4. Check the destination in the dialog, then click Copy.

Commands › Copy to as… does the same for one item and lets you type a new name for the copy. Both commands work between local folders and connections, and between two connections.

## Clipboard copying

- Edit › Copy (⌘C) puts the selected items on the clipboard.
- Edit › Paste (⌘V) copies them into the active pane's folder.
- Edit › Cut (⌘X) works only in text fields. There's no cut for files. Use Move Items Here instead.

In a text field or the terminal, these three commands act on text as usual.

## Move to and Move Items Here

- Commands › Move to… moves the selection to the other pane's folder, after a confirmation.
- Edit › Move Items Here (⌥⌘V) moves items on the clipboard into the active pane's folder, after a confirmation. Copy them with ⌘C first.

When a remote location is involved, FileTerm copies first, then deletes the sources. The sources are kept if any item was skipped or failed, or if you stop the copy. A local source moved to a server is deleted permanently and doesn't go to the Trash.

## Drag and drop

You can drop local files on a pane to put them in its folder:

- A drop on the same volume moves the items.
- A drop on another volume copies them.
- Holding ⌥ always copies.
- A drop on a remote pane always copies.

To be asked each time, turn on Settings › General › Ask for confirmation for drag operations. It's off by default.

Items in a remote pane can't be dragged out. Use Copy to… instead. You can also drag local files into the built-in terminal to insert their quoted paths.

## Duplicate

Commands › Duplicate (⌘D) makes a copy in the same folder, with a new name that doesn't overwrite anything. It works in local folders only.

## Rename

Commands › Rename with one item selected lets you edit its name in place. Changing the extension asks for confirmation first.

With several items selected, Rename opens Batch Rename ([chapter 8](08-sync-and-batch-rename.md#open-batch-rename)). In list view, Return on several selected items does the same.

Rename also works on connections. See the limits for object storage in [chapter 6](06-connections-and-remote-locations.md#amazon-s3-and-backblaze-b2).

## Conflicts

When an item with the same name already exists, FileTerm follows Settings › Transfers. The default is to ask. The dialog shows both paths and offers:

- **Keep Both:** copies under a name that doesn't collide.
- **Replace:** replaces the existing item.
- **Replace Older:** replaces it only if it's older.
- **Skip:** leaves this item alone.
- **Stop:** stops the operation.
- **Merge:** for folders, copies the contents into the existing folder and asks again for any conflict inside it.

Tick Apply to all conflicts to use your answer for the rest of the operation.

On connections, folder conflicts offer Merge, Keep Both, Skip and Stop, without Replace.

## Undo and Redo

Edit › Undo (⌘Z) and Redo (⇧⌘Z) reverse local file operations such as local copies, moves, renames and Move to Trash. They're unavailable while another file operation runs. In a text field they act on the text.

Undoing a copy or a duplicate moves it to the Trash, and Redo brings it back unless the Trash was emptied. On a volume with no Trash, Undo fails and the copy stays where it is.

Replace moves the old local version to the Trash, and puts it back if the job fails or is cancelled. On a volume with no Trash, the old version stays in a hidden `.FileTerm-recovery-` folder beside the item so Undo still works. On connections, the old version stays under a hidden name until the new one is in place.

These can't be undone:

- Delete… on local items.
- Anything done on a connection, and any copy or move to or from one.
- Sync jobs, Compress and Extract.
- Aliases, symlinks, and metadata or text edits.

When Undo is grayed out, hold the pointer over it for the reason.
