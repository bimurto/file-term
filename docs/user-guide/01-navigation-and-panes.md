# 1 Navigation and panes

## Single and dual panes

A window shows one pane or two. Choose the layout in the View menu or with the toolbar buttons:

- View › Single Pane shows only the active pane. The hidden pane keeps its tabs and state.
- View › Vertical — Side by Side puts the panes left and right.
- View › Horizontal — Stacked puts them top and bottom.
- View › Show Two Panes switches between single pane and the last two-pane layout you used.

Click a pane to make it active. The active pane has a colored outline. Commands use it as their source, and the other visible pane as their target.

## Open and move up

- Double-click opens an item: a folder opens in the pane, and a file opens in its default app.
- File › Open (⌘O) does the same for the selected item.
- Go › Enclosing Folder moves up one level.
- Go › Back and Go › Forward follow the history of the current tab. Each tab has its own history.
- The Go menu also has Documents, Desktop, Downloads, Home, Library, Applications and Utilities.

The Back, Forward and Enclosing Folder commands have no default shortcut. To add one, use Settings › Shortcuts. See [chapter 3](03-selection-search-and-quick-commands.md#shortcut-customization).

If a folder can't be opened, the pane keeps its current folder, listing and selection, and shows the error. For a folder that macOS protects, the message names the missing permission and offers an Open System Settings button.

## Path and status bars

The path bar sits above the file list. Click any parent folder in it to go there. In a remote pane it shows the path as text. Turn it on or off with View › Show › Path Bar.

The status bar sits below the file list and shows:

- The number of visible items.
- The number of selected items and their total size. "+ unknown" means some selected items, usually folders, have no known size. To get folder sizes, see [chapter 5](05-metadata-preview-and-utilities.md#folder-sizes).
- The free space on the volume.

## Go to Folder

Go › Go to Folder… opens a dialog with the current path filled in.

1. Type an absolute path that starts with `/`. `~` is not accepted.
2. Press Return or click Go.

A wrong path shows an error, and your current folder doesn't change.

The dialog keeps a history of the last 20 folders you reached through it. As you type, it suggests up to six earlier folders that contain your text, with folders that start with it listed first.

- Press Tab to put the top suggestion in the field. This doesn't go there yet.
- Click a suggestion to go there straight away.

Go to Folder works with local folders only. For a remote location, use Go › Favorites or a connection's saved paths ([chapter 10](10-favorites-tools-editing-and-git.md#favorite-paths)).

## Recent Folders and connections

Go › Recent Folders lists the local folders you visited most recently, newest first. It keeps 10 by default, and Settings › General changes the limit, from 1 to 50. The same list appears in the sidebar, under Recent Folders, and in Quick Open. Visits to remote folders aren't recorded.

Go › Connections lists open and saved connections. See [chapter 6](06-connections-and-remote-locations.md#open-connections-and-saved-connections).

## Devices

The sidebar's Devices section lists mounted volumes. Click one to open it in the active pane. The list updates when a volume mounts, unmounts or is renamed.

- View › Show › Devices shows or hides the section.
- View › Show › Device Info adds free space and capacity under each name. It's off by default.
- File › Eject ejects the volume selected in the sidebar. It needs the sidebar and Devices section to be visible and an ejectable volume to be selected. Failures appear in an alert.

If a volume unmounts while a tab shows it, that tab returns to Home.

## Swap and clone panes

Both commands need two panes and no navigation in progress.

- View › Swap Panes exchanges the two panes, including their tabs and selections. The active position on screen stays where it was.
- View › Clone Pane opens the active pane's folder in the other pane.

## Sync Browsing

Go › Sync Browsing mirrors folder navigation in the other pane. It's handy for comparing two similar folder trees.

- Entering a folder enters the folder with the same name in the other pane.
- Enclosing Folder moves both panes up.
- Back, Forward, the path bar and direct destinations such as Go › Home stay independent.

If the matching folder doesn't exist, the other pane stays put and a notice explains why. Switching to a single pane turns Sync Browsing off. It never changes any files. For syncing files, see [chapter 8](08-sync-and-batch-rename.md).
