# M15 — Context menus

**Goal:** Right-clicking in FileTerm offers what ForkLift offers, in the same order, on the same surfaces.
**Ref:** Observed in the installed ForkLift 4.6 on 2026-10-31, in list view, single pane, on local files.

## How FileTerm differed before this milestone

| Place | ForkLift | FileTerm before M15 |
|---|---|---|
| File row | About 20 grouped items, submenus, tags | Open, Rename, plus Show Package Contents, iCloud and Dropbox when they apply |
| Folder row | File items plus Open in New Tab and Contents › | Same short menu |
| Multi-selection | Full menu acting on all items | List view: no menu. Icon and column views: the clicked item only |
| Unselected row | The row becomes the selection | The selection didn't change on right-click |
| Empty space | New Folder, New File, Get Info, Quick Look, Copy Path, View Options, Services | No menu |
| Column header | Column checklist | No menu, and the columns were fixed |
| Sidebar volume | New Tab, New Window, Eject, Hide from Sidebar | No menu |
| Sidebar favorite or connection | New Tab, New Window, Favorite Manager, Edit, Delete, Hide from Sidebar | Favorites weren't in the sidebar, only the Go menu |
| Sidebar section header | Hide from Sidebar, Favorite Manager, Delete | No menu |
| Sidebar workspace | Not seen | Delete Workspace, FileTerm only |

## How it's built

- The file pane uses `NSMenu`, not SwiftUI's `contextMenu`, in `FileTerm/Views/FileContextMenu.swift`. SwiftUI menus can't host the tag dots or build a submenu only when it opens.
- A right-click changes the selection first, then builds the menu, because every item asks the command registry about the selection.
- The sidebar keeps SwiftUI's `contextMenu`, as its workspace menu already did.
- Get Info, Quick Look, Reveal in Finder, Copy Path and Services now use the current folder when nothing is selected, from the main menu too. The empty-space menu relies on this.

## Part A — Shared behavior

### M15.01 Menus run registry commands
- [x] Menu items run `CommandRegistry` commands on the menu's items, so enablement and disabled reasons have one source.
- [x] Unavailable items stay visible, disabled, with the reason (roadmap rule 1).

### M15.02 Selection rule
- [x] In list, icon and column views, right-clicking an unselected row replaces the selection. Right-clicking inside a multi-selection keeps it.
  - Checked in the running app in all three views. A row in an earlier column isn't in the current folder, so it offers only Open.

### M15.03 Remote Open
- [ ] Open from the menu and double-click both download and open a remote file, as File › Open does.
  - Open: the code is in, but it hasn't run against a server (see M15.22).

### M15.04 Remote labels and gating
- [ ] On non-local panes, Delete… replaces Move to Trash, because the item deletes permanently.
- [ ] Copy is disabled with a reason on non-local panes.
  - Open: both changes are in, but they haven't run against a server (see M15.22).

## Part B — File pane

### M15.05 File menu
- [x] Items in ForkLift's order, with a separator between groups:
  1. Open, Open With ›
  2. Move to Trash
  3. Get Info, Rename, Compress "name", Duplicate, Make Alias, Quick Look, Reveal in Finder, Share…
  4. Copy "name", Copy Path ›
  5. Show View Options
  6. Tags…, color dots
  7. Services ›
- [x] Show Package Contents, iCloud and Dropbox items stay when they apply.

### M15.06 Folder menu
- [x] Adds Open in New Tab after Open, and Contents › in its own group after Open With.

### M15.07 Multi-selection menu
- [x] New Folder with Selection comes first, and Open in New Tab isn't shown.
- [x] Titles use the count: `Rename 2 Items…`, `Compress 2 Items`, `Copy 2 Items`.

### M15.08 Empty-space menu
- [x] All three views offer New Folder, New File, Get Info, Quick Look, Copy Path ›, Show View Options and Services ›.
- [x] Items apply to the current folder.

### M15.09 New commands
- [x] Reveal in Finder, using `NSWorkspace.activateFileViewerSelecting`. Local only.
- [x] Open in New Tab and Open in New Window open the chosen folder.

### M15.10 Open With submenu
- [x] The default app comes first, labeled `(default)`, then a separator, the other apps A–Z with icons, a separator, and Other….
- [x] Reuses `openWithCommands` (`FileTerm/App/AppDelegate.swift:1687`).
- [ ] Disabled on remote locations until a chosen app is honored there.
  - Open: the code is in, but it hasn't run against a server (see M15.22).

### M15.11 Contents submenu
- [x] Lists a folder's direct children with icons, built when the submenu opens. Local only.
- [x] Very large folders are capped, so opening the menu doesn't stall the app (see M14.12).
  - The cap is 1000 items. It hasn't been tried on a folder that size.

### M15.12 Copy Path submenu
- [x] Reuses `CopyPathFormatter` and keeps FileTerm's full list, including Percent-Decoded URL, which ForkLift doesn't have.

### M15.13 Tags
- [x] Color dots toggle a tag on the selection through `FileMetadataService`, and Tags… opens the editor. Local only.
  - The first seven tags get a dot, and every tag is in File › Tags. Turning a tag on was run in the app. Turning one off wasn't.

### M15.14 Services submenu
- [x] Offers the selected files to Services (`FileTerm/App/BrowserWindowController.swift:123`).
  - The submenu lists copies of what AppKit put in the app menu's Services. It appears only when a service accepts the selection. Running a service from it wasn't tried.

## Part C — Column header

### M15.15 Column checklist
- [x] Right-clicking the header toggles Size, Kind, Modified, Created, Added, Last Opened, Tags, Owner, Group and Permissions, using `TableColumnCustomization`.
- [x] Name is always shown, and choices persist.

## Part D — Sidebar

### M15.16 Per-item Hide from Sidebar
- [x] A stored setting hides one item, and there's a way to bring it back. Today only whole sections can be hidden (`FileTerm/App/AppDelegate.swift:664`).

### M15.17 Volume menu
- [x] Open in New Tab, Open in New Window, Eject when the volume can be ejected, Hide from Sidebar.
- [ ] Eject acts on the clicked row, not on the volume selected in the sidebar.
  - Open: the code is in, but no volume was ejected to test it.

### M15.18 Favorites section
- [x] The sidebar shows favorites and connections, using `settings.favorites` and `sidebarSections`.

### M15.19 Favorite and connection menu
- [x] Open in New Tab, Open in New Window, Reveal in Favorite Manager, then Edit, Delete and Hide from Sidebar.
- [x] Delete asks for confirmation (roadmap rule 2).
- [x] Reuses `FavoritesManagerSheet`.

### M15.20 Section header menu
- [x] Hide from Sidebar on every section, plus Reveal in Favorite Manager on Favorites.

## Part E — Acceptance

### M15.21 UI tests
- [ ] XCUITest `rightClick()` covers each surface.
  - Open: `FileTermUITests/ContextMenuUITests.swift` covers the file pane but has never run, because macOS timed out enabling UI automation. It doesn't cover the sidebar yet. The menus were checked by hand in the running app instead.

### M15.22 Remote check
- [ ] Against `dev/docker-compose.yml`, Open, Rename and Delete… work, and local-only items are disabled with a reason.
  - Open: Docker wasn't running, so nothing has been tried on a server.

### M15.23 User guide
- [x] Update `docs/user-guide/04-creating-copying-and-moving.md:21`, which describes today's short menu.

## Remote behavior

ForkLift's own menus on remote locations weren't observed, so this follows FileTerm's gating (`FileTerm/App/AppDelegate.swift:1341`).

| Location | Items |
|---|---|
| SFTP, FTP, FTPS, WebDAV, S3, B2: enabled | Open, Rename, Delete…, New Folder |
| SFTP, FTP, FTPS, WebDAV, S3, B2: disabled with a reason | Everything else |
| SMB, AFP, NFS | Same as local, because they're browsed as mounted folders |

## Not included

- **Media columns** (Dimensions, Duration, Album and similar): FileTerm has no data for them.
- **Delete on a section header:** what it deletes in ForkLift wasn't tested.
- **Tabs, path bar, terminal and preview menus:** not checked in ForkLift.
- **Icon view, column view and dual-pane menus in ForkLift:** not checked, so M15.05–M15.08 assume they match list view.
