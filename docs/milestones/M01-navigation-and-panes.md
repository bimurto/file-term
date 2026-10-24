# M01 — Navigation & panes

**Goal:** Add single and dual-pane browsing, history, direct Go destinations, devices and pane helpers.
**Ref:** Guide › Ch. 1 Navigation and panes.

## Items

### M01.01 Pane layouts
- **Scope:** Single Pane, Vertical and Horizontal layouts. Toolbar controls plus View › Show Two Panes.
- [ ] Switching layout keeps each pane's location.
- [ ] Clicking a pane makes it active, and the active pane is visibly highlighted.
- [ ] Commands use the active pane as source and the other pane as target.

### M01.02 Enter folder & Enclosing Folder
- **Scope:** Double-click to enter a folder. Go › Enclosing Folder moves to the parent.
- [ ] Enclosing Folder is disabled at the filesystem root.

### M01.03 Back / Forward history
- **Scope:** Each pane keeps its own navigation history.
- [ ] Back after Enclosing Folder returns to the child folder. Moving to a parent and going back are separate operations.

### M01.04 Go menu standard locations
- **Scope:** Documents, Desktop, Downloads, Home, Library, Applications, Utilities.
- [ ] Each entry opens the correct folder in the active pane.

### M01.05 Interactive path bar
- **Scope:** Clickable ancestor segments.
- [ ] Clicking an ancestor opens that folder.
- [ ] View can show or hide the path bar, title bar and toolbar.

### M01.06 Status bar
- **Scope:** Item count, selected size, free disk space.
- [ ] Values update when the selection or location changes.

### M01.07 Go to Folder
- **Scope:** Dialog that accepts an absolute path and opens it on Return.
- [ ] An invalid path shows an error and does not navigate.
- [ ] The path bar shows the resolved path after navigation.

### M01.08 Recent Folders & Connections submenu
- **Scope:** Go › Recent Folders (MRU list) and Go › Connections (filled in M08).
- [ ] Recent list is stored and capped at N entries.

### M01.09 Devices in sidebar
- **Scope:** Internal and mounted volumes. View › Show Devices, Show Device Info. File › Eject.
- [ ] Mounting or unmounting a volume updates the sidebar automatically.
- [ ] Eject is enabled only for ejectable volumes.

### M01.10 Swap Panes & Clone Pane
- **Scope:** View › Swap Panes exchanges the two pane locations. View › Clone Pane sets the opposite pane to the active pane's location.
- [ ] Both commands are disabled in single-pane mode.

### M01.11 Sync Browsing
- **Scope:** Go › Sync Browsing. When on, entering or leaving a folder in one pane repeats the same relative step in the other pane.
- [ ] If the matching subfolder doesn't exist, the other pane stays put and the user is told.
- [ ] Sync Browsing never copies or changes files.
