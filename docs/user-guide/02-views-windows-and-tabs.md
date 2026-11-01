# 2 Views, windows and tabs

## Icon, List and Column views

Each tab has its own view. Choose it with View › as Icons, as List or as Columns, or with the toolbar buttons.

- **List** has sortable columns: Name, Size, Kind, Modified, Created, Added, Last Opened, Tags, Owner, Group and Permissions. Click a heading to sort by it.
- **Columns** shows the folder hierarchy from left to right. A single click on a folder enters it.
- **Icons** shows a grid of icons with names.

### Working in icon view

The icon grid supports the keyboard and rubber-band selection:

- **Arrow keys** move through the grid. With nothing selected, any arrow starts at the first item. At an edge, the selection stays where it is.
- **Type-to-select** jumps to the first item whose name starts with what you type. Case and accents are ignored. A pause of more than one second starts a new attempt.
- **Rubber band:** drag from an empty area to select the icons the rectangle touches. Hold ⌘ or ⇧ to add to the current selection. A drag that starts on an icon drags that file instead.

The band selects only icons that are currently laid out, and the view doesn't scroll as you drag.

Return doesn't open items in icon or column view. Use a double-click or File › Open (⌘O).

### File size under icons

To show each file's size under its icon:

1. Choose View › Show View Options.
2. Turn on Show File Size in Icon View.
3. Click Apply.

Items with no known size show no label. The option is off by default.

## Sorting

View › Sort by offers Name, Kind, Date Added, Date Modified, Date Last Opened, Date Created, Size, Tags, Owner, Group and Permissions. Descending Order is in the same submenu.

Folders always stay first. Items with an unknown value sort last in both directions. Date Last Opened comes from Spotlight, so it's unknown on volumes that aren't indexed.

## Grouping

View › Group by offers None, Kind, Date Added, Date Modified, Date Last Opened, Date Created, Size and Tags. Groups appear as sections, sorted inside each group.

- Date groups are Today, Yesterday, This Week, This Month, Older and Unknown.
- Size groups run from Folders and Empty up to 1 GB or Larger.
- An item with several tags appears under each of them.

## View options and defaults

View › Show View Options opens a dialog for the view, sort, group and icon size settings. Apply to sets the scope:

- **This Tab:** the settings follow the tab from folder to folder.
- **This Folder:** the settings are saved for this folder and shared by tabs that use This Folder.

Click Apply to use the settings. Save View Settings as Defaults, in the dialog or the View menu, sets the defaults for new tabs and for folders without saved settings. View › Restore Default View Settings applies those defaults to the current scope.

## Toolbar and sidebar

- View › Show Toolbar, Show Sidebar, Show Tab Bar, Show Path Bar and Show Title Bar each show or hide that part of the window. These choices are remembered.
- View › Customize Toolbar… adds, removes and reorders toolbar commands. It offers top-level commands from the File, View, Go and Commands menus, and Restore Default Toolbar resets the list.
- View › Show Sidebar Editor turns sidebar sections on or off and changes their order.
- When the window gets narrower, similar toolbar buttons fold into dropdowns: pane layout and view mode first, then panels, then everything but navigation under More.
- A greyed-out toolbar button can't run right now. Hold the pointer over it to see why.
- Click a sidebar section's header to fold or unfold it. Folded sections stay folded after a relaunch.
- Drag the divider beside the sidebar or preview to resize it. File panes keep a minimum width.

Sidebar sections are Devices, Recent Folders, Tags, iCloud Drive, Workspaces and Favorites. Network volumes and external disks show an icon beside their name. iCloud Drive appears only when that folder exists, and Workspaces only when you've saved one. Each section also has its own command in the View menu.

## Tabs

Each pane has its own tabs, and each tab keeps its own location, history and view.

- File › New Tab (⌘T) opens a tab at the same folder, with the default view settings.
- File › Close Tab (⌘W) closes the current tab. Closing the last tab in the active pane closes the window.
- File › Close Other Tabs leaves only the current tab.
- Window › Previous Tab (⇧⌘[) and Next Tab (⇧⌘]) move through the active pane's tabs.
- ⌘1 to ⌘5 select a tab in the active pane.

### Move a tab to the other pane

Window › Move Tab to Other Pane moves the current tab to the opposite pane, with its folder, history and view, and makes that pane active.

- In single-pane mode, FileTerm first switches to your last two-pane layout.
- If it was the pane's only tab, the pane keeps a new tab at the same folder, because a pane always has at least one tab.

## Pin View

Window › Pin View protects a tab's location. A pinned tab shows a pin icon. Navigating away from it, including with Back and Forward, opens a new unpinned tab with the same view options, so the pinned tab stays where it is. Choose Pin View again to unpin. You can still close a pinned tab.

## Windows and screen layout

File › New FileTerm Window (⌘N) opens a window at the Starting Directory, with its own panes and tabs. Menu commands act on the frontmost window.

- File › Close Window (⇧⌘W) closes the frontmost window.
- Window › Minimize, Zoom and Bring All to Front work as in other Mac apps.

The Window menu also lists open windows. macOS can add its own layout and tiling entries there, and these depend on your macOS version.

## Quit and restore

Settings › General › Restore windows and tabs on startup is off by default.

- **Off:** FileTerm opens one window at the Starting Directory, which is Home unless you change it.
- **On:** FileTerm reopens your windows, tabs, histories, layouts, view settings and window positions.
- FileTerm › Quit and Keep Windows (⌥⌘Q) restores them at the next launch, once, even with the setting off.

A saved folder that no longer exists falls back to the Starting Directory. An invalid Starting Directory falls back to Home. Remote tabs don't reconnect on restore, and shells and their scrollback aren't saved across launches.

FileTerm won't quit while transfers are running. Wait for them, or cancel them in Activities first.
