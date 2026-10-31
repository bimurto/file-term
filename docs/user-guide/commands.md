# Command reference

Every menu command, grouped by top-level menu. Submenu paths are named in the description.

- Shortcuts are the defaults. Change them in Settings › Shortcuts ([chapter 3](03-selection-search-and-quick-commands.md#shortcut-customization)).
- A dash means the command has no default shortcut.
- "Local" means the command needs a local folder or local items in the active pane.
- A command that can't run is grayed out. Hold the pointer over it to see why.

## FileTerm

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="app.about"></a>About FileTerm | — | Shows the version and build. | [Ch 11](11-appearance-settings-and-macos.md) |
| <a id="app.checkForUpdates"></a>Check for Updates… | — | Looks up the latest release and offers its download page. Installs nothing. | [Ch 11](11-appearance-settings-and-macos.md) |
| <a id="app.settings"></a>Settings… | ⌘, | Opens the settings window. | [Ch 11](11-appearance-settings-and-macos.md) |
| <a id="app.emptyTrash"></a>Empty Trash… | — | Asks first, then has Finder empty the Trash on every volume. Can't be undone. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="app.hide"></a>Hide FileTerm | ⌘H | Hides the app. | [Ch 11](11-appearance-settings-and-macos.md) |
| <a id="app.quit"></a>Quit FileTerm | ⌘Q | Saves the window state and quits. Refuses while transfers are active. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="app.quitKeepWindows"></a>Quit and Keep Windows | ⌥⌘Q | Quits and restores the windows at the next launch, even with restoration off. | [Ch 2](02-views-windows-and-tabs.md) |

## File

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="file.showBrowser"></a>Show Browser Window | — | Brings a browser window forward, or opens one if none exists. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="file.close"></a>Close Window | ⇧⌘W | Closes the frontmost window. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="file.eject"></a>Eject | — | Ejects the volume selected in the sidebar's Devices section. | [Ch 1](01-navigation-and-panes.md) |
| <a id="file.newWindow"></a>New FileTerm Window | ⌘N | Opens a new window at the Starting Directory. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="file.newTab"></a>New Tab | ⌘T | Opens a tab at the same folder in the active pane, with the default view settings. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="file.closeTab"></a>Close Tab | ⌘W | Closes the current tab. The last tab closes the window. In another window, such as a dialog window, it closes that window. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="file.closeOtherTabs"></a>Close Other Tabs | — | Closes every other tab in the active pane. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="file.find"></a>Find… | ⌘F | Puts the cursor in the toolbar's search field. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="file.closeSearch"></a>Close Search | ⌥⌘F | Closes the results and returns to the folder. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="file.newFolder"></a>New Folder | ⇧⌘N | Creates a folder and starts renaming it. Also works on connections. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.newFolderWithSelection"></a>New Folder With Selection | ⌃⌘N | Moves the selected items into a new folder. Local. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.newFile"></a>New File | ⌥⇧⌘N | Creates an empty file and starts renaming it. Local. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.open"></a>Open | ⌘O | Opens the selected items. On a connection, downloads a temporary copy first. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.openWith"></a>Open With apps | — | File › Open With: one entry per app that can open every selected item, plus Other…. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.iCloud"></a>iCloud Download Now and Remove Download | — | File › iCloud: downloads items, or removes the copy on this Mac. The file stays in iCloud. | [Ch 12](12-additional-capabilities.md) |
| <a id="file.copyDropboxLink"></a>Copy Dropbox Link | — | Copies a shared link for one item in a Dropbox folder. Needs a token. | [Ch 12](12-additional-capabilities.md) |
| <a id="file.openInTerminal"></a>Open in Terminal | — | Opens the active local folder in the external terminal app from Settings › General. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="file.packageContents"></a>Show Package Contents | — | Browses inside a selected package as a folder. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.getInfo"></a>Get Info | ⌘I | Opens an inspector window for each selected local item. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.openInNewTab"></a>Open in New Tab | — | Opens each selected folder in a new tab. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.openInNewWindow"></a>Open in New Window | — | Opens each selected folder in a new window. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.revealInFinder"></a>Reveal in Finder | — | Shows the selected local items in Finder, or the current folder when nothing is selected. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.tag"></a>Tags | — | File › Tags: turns a tag on or off for the selected local items. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="file.share"></a>Share… | — | Opens the macOS share picker for selected local items. | [Ch 11](11-appearance-settings-and-macos.md) |
| <a id="file.tags"></a>Tags… | — | Opens the inspector, where tags can be edited. Local. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.quickLook"></a>Quick Look | ⌘Y | Opens Quick Look for the selected local items, or the current folder when nothing is selected. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.slideshow"></a>Slideshow | — | Plays the selected images. Needs at least one local image. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.print"></a>Print… | ⌘P | Prints one selected local image, PDF or text file. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.copyPath"></a>Copy Path formats | — | File › Copy Path: copies paths as UNIX, URL, Percent-Decoded URL, Name, Terminal or Windows, for the selected local items or the current folder. Local. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.makeAlias"></a>Make Alias | — | Creates a Finder alias next to each selected item. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.makeAliasTo"></a>Make Alias to | — | Creates a Finder alias in the other pane's folder. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.makeSymlink"></a>Make Symlink | — | Creates a symbolic link next to each selected item. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.makeSymlinkTo"></a>Make Symlink to | — | Creates a symbolic link in the other pane's folder. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.copyURL"></a>Copy URL | — | Copies the public web address of items on a connection that has a Base URL. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="file.openURL"></a>Open URL | — | Opens that public web address in your browser. | [Ch 5](05-metadata-preview-and-utilities.md) |

## Edit

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="edit.text"></a>Cut, Copy and Paste | ⌘X, ⌘C, ⌘V | Copy puts selected files on the clipboard, and Paste copies them into the active pane. Cut works only on text. In text fields and the terminal, these act on text. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="edit.selectAll"></a>Select All | ⌘A | Selects everything in the active pane, or all text in a text field or the terminal. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="edit.deselectAll"></a>Deselect All | ⇧⌘A | Clears the selection. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="edit.invertSelection"></a>Invert Selection | ⇧⌘I | Swaps selected and unselected items. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="select.quick"></a>Quick Select… | ⌘S | Selects items by name, extension or tag. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="edit.moveItemsHere"></a>Move Items Here | ⌥⌘V | Moves items on the clipboard into the active pane's folder, after a confirmation. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="edit.undo"></a>Undo | ⌘Z | Undoes the last local file operation, or the last text edit in a text field. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="edit.redo"></a>Redo | ⇧⌘Z | Redoes what Undo reversed. | [Ch 4](04-creating-copying-and-moving.md) |

## View

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="view.preview"></a>Show/Hide Preview | — | Shows or hides the Preview panel. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="view.activities"></a>Show/Hide Activities | — | Shows or hides the Activities panel. | [Ch 7](07-transfers-activities-and-logs.md) |
| <a id="view.logs"></a>Show/Hide Logs | — | Shows or hides the Logs panel. | [Ch 7](07-transfers-activities-and-logs.md) |
| <a id="view.twoPanes"></a>Show Two Panes | — | Switches between one pane and the last two-pane layout. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.swapPanes"></a>Swap Panes | — | Exchanges the two panes, including their tabs. Needs two panes. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.clonePane"></a>Clone Pane | — | Opens the active pane's folder in the other pane. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.single"></a>Single Pane | — | Shows only the active pane. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.vertical"></a>Vertical — Side by Side | — | Shows two panes left and right. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.horizontal"></a>Horizontal — Stacked | — | Shows two panes top and bottom. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.pathBar"></a>Show Path Bar | — | Shows or hides the path bar. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.titleBar"></a>Show Title Bar | — | Shows or hides the title bar. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.toolbar"></a>Show Toolbar | — | Shows or hides the toolbar, which also holds the search field. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.devices"></a>Show Devices | — | Shows or hides the sidebar's Devices section. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.deviceInfo"></a>Show Device Info | — | Shows or hides free space and capacity under each device. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.sidebar"></a>Show Sidebar | — | Shows or hides the sidebar. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.tabBar"></a>Show Tab Bar | — | Shows or hides each pane's tab bar. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.recentFolders"></a>Show Recent Folders | — | Shows or hides the sidebar's Recent Folders section. | [Ch 1](01-navigation-and-panes.md) |
| <a id="view.favorites"></a>Show Favorites | — | Shows or hides the sidebar's Favorites section. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="view.tags"></a>Show Tags | — | Shows or hides the sidebar's Tags section. | [Ch 11](11-appearance-settings-and-macos.md) |
| <a id="view.workspaces"></a>Show Workspaces | — | Shows or hides the sidebar's Workspaces section. | [Ch 12](12-additional-capabilities.md) |
| <a id="view.iCloudDrive"></a>Show iCloud Drive | — | Shows or hides the sidebar's iCloud section. | [Ch 12](12-additional-capabilities.md) |
| <a id="view.asIcons"></a>as Icons | — | Shows the active tab as an icon grid. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.asList"></a>as List | — | Shows the active tab as a list with columns. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.asColumns"></a>as Columns | — | Shows the active tab as hierarchy columns. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.sort"></a>Sort fields | — | View › Sort by: sorts by Name, Kind, Date Added, Date Modified, Date Last Opened, Date Created, Size, Tags, Owner, Group or Permissions. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.descending"></a>Descending Order | — | View › Sort by: reverses the sort. Folders stay first. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.group"></a>Group fields | — | View › Group by: groups by None, Kind, Date Added, Date Modified, Date Last Opened, Date Created, Size or Tags. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.options"></a>Show View Options | — | Opens the View Options dialog, including the icon size label. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.customizeToolbar"></a>Customize Toolbar… | — | Adds, removes and reorders toolbar commands. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.sidebarEditor"></a>Show Sidebar Editor | — | Turns sidebar sections on or off and reorders them. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.saveDefaults"></a>Save View Settings as Defaults | — | Makes the current view settings the defaults for new tabs and folders without saved settings. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.restoreDefaults"></a>Restore Default View Settings | — | Applies the saved defaults to the current scope. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="view.showHidden"></a>Show Hidden Items | ⇧⌘. | Shows or hides hidden items in every pane. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="view.refresh"></a>Refresh | ⌘R | Reloads the tabs in the current window. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="view.autoRefresh"></a>Auto-Refresh | — | Watches open local folders and reloads them when they change. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="view.terminal"></a>Show Terminal | `` ⌃` `` | Shows or hides the built-in terminal. Hiding keeps its sessions. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.focus"></a>Focus Terminal / Pane | `` ⌃⌥` `` | View › Terminal: moves focus between the pane and the terminal. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.link"></a>Link Terminal to Pane | — | View › Terminal: turns following the pane's folder on or off. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.reverseSync"></a>Follow Terminal Directory | — | View › Terminal: turns moving the pane when the shell changes folder on or off. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.sync"></a>Sync Terminal Now | — | View › Terminal: moves the shell to the pane's folder when it's idle. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.reveal"></a>Reveal Terminal Directory in Pane | — | View › Terminal: opens the shell's folder in the pane. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.insertSelection"></a>Insert Selected Paths in Terminal | — | View › Terminal: types the selected local paths, quoted, without running them. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.openSSH"></a>Open SSH Session for Connected Host | — | View › Terminal: types an `ssh` command for an SFTP pane's host and folder, when the shell is idle. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.clear"></a>Clear Terminal | — | View › Terminal: clears the current session. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.find"></a>Find in Terminal… | — | View › Terminal: searches the terminal's text. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.dock"></a>Toggle Terminal Dock | — | View › Terminal: moves the panel between below and right of the panes. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.close"></a>Close Terminal Sessions | — | View › Terminal: hides the panel and ends its sessions. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.followActive"></a>Follow Active Pane | — | View › Terminal: shows the session for the active pane's tab. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.followFirst"></a>Follow Left / Top Pane | — | View › Terminal: shows the session for the first pane's tab. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="terminal.followSecond"></a>Follow Right / Bottom Pane | — | View › Terminal: shows the session for the second pane's tab. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="view.textEncoding"></a>Text Encoding choices | — | View › Text Encoding: reads names on the active FTP, FTP-TLS or SFTP connection as UTF-8, ISO-8859-1, Windows-1252, Shift_JIS, EUC-KR or GB18030. | [Ch 6](06-connections-and-remote-locations.md) |

## Go

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="go.back"></a>Back | — | Goes to the previous folder in this tab's history. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.forward"></a>Forward | — | Goes to the next folder in this tab's history. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.enclosingFolder"></a>Enclosing Folder | — | Goes up one level. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.toFolder"></a>Go to Folder… | — | Opens a local folder by absolute path, with history and Tab completion. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.syncBrowsing"></a>Sync Browsing | — | Mirrors entering a folder and going up in the other pane. Needs two panes. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.connect"></a>Connect… | — | Opens the connection form. | [Ch 6](06-connections-and-remote-locations.md) |
| <a id="go.favorites.manage"></a>Manage Favorites… | — | Opens the Favorites manager. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="go.documents"></a>Documents | — | Opens your Documents folder in the active pane. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.desktop"></a>Desktop | — | Opens your Desktop folder. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.downloads"></a>Downloads | — | Opens your Downloads folder. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.home"></a>Home | — | Opens your home folder. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.library"></a>Library | — | Opens your user Library folder. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.applications"></a>Applications | — | Opens the system Applications folder. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.utilities"></a>Utilities | — | Opens the Utilities folder inside Applications. | [Ch 1](01-navigation-and-panes.md) |
| <a id="quickOpen"></a>Quick Open… | ⎋ | Opens the search for commands, folders, recents, favorites and rename presets. | [Ch 3](03-selection-search-and-quick-commands.md) |
| <a id="go.recent"></a>Recent folders | — | Go › Recent Folders: opens one of the last 20 local folders you visited. | [Ch 1](01-navigation-and-panes.md) |
| <a id="go.favorites.item"></a><a id="go.favorites.empty"></a>Favorites | — | Go › Favorites: opens a saved favorite. A connection favorite connects first if needed. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="go.workspaces.save"></a>Save Workspace… | — | Go › Workspaces: saves the open windows under a name. | [Ch 12](12-additional-capabilities.md) |

## Commands

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="commands.sync"></a>Sync to… | — | Opens the Sync dialog for the two panes. Changes nothing until you click Synchronize. | [Ch 8](08-sync-and-batch-rename.md) |
| <a id="commands.manageTools"></a>Manage Tools… | — | Opens Settings › Tools. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="commands.git"></a>Source Control commands | — | Commands › Source Control: Add, Add All, Commit…, Push and Pull. Local, in a Git repository. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="commands.edit"></a>Edit | — | Opens one file in the editor mapped to its extension. On a connection, uploads your saves after you confirm. | [Ch 10](10-favorites-tools-editing-and-git.md) |
| <a id="commands.copyTo"></a>Copy to… | — | Copies the selection to the other pane's folder. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="commands.copyToAs"></a>Copy to as… | — | Copies one item to the other pane's folder under a new name. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="commands.moveTo"></a>Move to… | — | Moves the selection to the other pane's folder. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="commands.duplicate"></a>Duplicate | ⌘D | Makes a copy in the same folder under a new name. Local. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="commands.rename"></a>Rename | — | Renames one item in place, or opens Batch Rename for several. | [Ch 4](04-creating-copying-and-moving.md) |
| <a id="commands.compress"></a>Compress | — | Makes a zip of the selection in the same folder. Local. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="commands.compressOptions"></a>Compress With Options… | — | Asks for the format, name and destination first. Local. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="commands.extract"></a>Extract | — | Unpacks selected archives next to them. Local. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="commands.extractTo"></a>Extract to… | — | Asks for the destination first. Local. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="file.trash"></a>Move to Trash | ⌘⌫ | Moves local items to the Trash. On a connection, deletes permanently after a confirmation. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="commands.compare"></a>Compare | — | Opens two local files in the external compare tool. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="commands.appCleanup"></a>Delete App and Related Files… | — | Lists a selected app's related files, then moves the app and ticked files to the Trash. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="commands.delete"></a>Delete… | ⌥⌘⌫ | Permanently deletes the selection after a confirmation. Can't be undone. | [Ch 9](09-archives-deletion-and-comparison.md) |
| <a id="commands.checksum"></a>Calculate Checksum… | — | Calculates MD5, SHA-1 or SHA-256 for one local file. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="commands.folderSizes"></a>Calculate All Folder Sizes | — | Works out the size of each local folder in the listing. | [Ch 5](05-metadata-preview-and-utilities.md) |
| <a id="tools.run"></a>Your tools | — | Commands › Tools: runs a tool you defined in Settings › Tools. | [Ch 10](10-favorites-tools-editing-and-git.md) |

## Window

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="window.minimize"></a>Minimize | ⌘M | Minimizes the frontmost window. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="window.zoom"></a>Zoom | — | Zooms the frontmost window. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="window.pinView"></a>Pin View | — | Pins or unpins the current tab. Navigating away from a pinned tab opens a new tab. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="window.moveTabToOtherPane"></a>Move Tab to Other Pane | — | Moves the current tab to the opposite pane and makes that pane active. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="window.bringAll"></a>Bring All to Front | — | Brings all FileTerm windows forward. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="window.previousTab"></a>Previous Tab | ⇧⌘[ | Selects the previous tab in the active pane, wrapping around. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="window.nextTab"></a>Next Tab | ⇧⌘] | Selects the next tab in the active pane, wrapping around. | [Ch 2](02-views-windows-and-tabs.md) |
| <a id="window.tab"></a>Select Tab 1 to 5 | ⌘1 to ⌘5 | Selects that tab in the active pane. | [Ch 2](02-views-windows-and-tabs.md) |

## Commands that appear as you add items

These entries are generated when you have connections, workspaces or sync favorites. They aren't in the tables above.

| Command | Shortcut | What it does | Guide chapter |
|---|---|---|---|
| <a id="go.connections.open"></a><a id="go.connections.empty"></a>Open connections | — | Go › Connections: reveals an open connection in a pane. | [Ch 6](06-connections-and-remote-locations.md) |
| <a id="go.connections.saved"></a>Saved connections | — | Go › Connections: connects and opens a saved connection. | [Ch 6](06-connections-and-remote-locations.md) |
| <a id="go.connections.edit"></a>Edit Saved Connection | — | Go › Connections › Edit Saved Connection: opens the form for that connection. | [Ch 6](06-connections-and-remote-locations.md) |
| <a id="go.connections.disconnect"></a>Disconnect | — | Go › Connections › Disconnect: closes that connection. | [Ch 6](06-connections-and-remote-locations.md) |
| <a id="go.workspaces.load"></a>Saved workspaces | — | Go › Workspaces: loads that workspace and closes the open windows. | [Ch 12](12-additional-capabilities.md) |
| <a id="commands.syncFavorite"></a>Sync favorites | — | Commands › Sync Favorites: shows both folders and opens the Sync dialog with its analysis. | [Ch 8](08-sync-and-batch-rename.md) |
