# M02 — Views, windows & tabs

**Goal:** Add view modes, sorting and grouping, tabs, multiple windows and session restore.
**Ref:** Guide › Ch. 2 Views windows and tabs.

## Items

### M02.01 Icon view
- [ ] View › as Icons plus a toolbar control. Thumbnails/icons in a grid.

### M02.02 List view
- [ ] View › as List with metadata columns. Clicking a column heading sorts by it.

### M02.03 Column view
- [ ] View › as Columns showing the folder hierarchy (Miller columns).
- [ ] The view mode can be set separately for each pane and works in both single and dual layouts.

### M02.04 Sorting
- **Scope:** Sort by Name, Kind, Date Added, Date Modified, Date Last Opened, Date Created, Size, Tags, Owner, Group, Permissions, plus a Descending Order toggle.
- [ ] Sort choice is kept per folder or per view, following the view-options scope.

### M02.05 Grouping
- **Scope:** Group by Kind, Date Added, Date Modified, Date Last Opened, Date Created, Size, Tags, None.
- [ ] Groups appear as sections. Items are sorted inside each group.

### M02.06 View options panel & defaults
- **Scope:** View › Show View Options. Save View Settings as Defaults. Restore Default View Settings.
- [ ] The dialog shows which scope a change applies to before it is saved.

### M02.07 Toolbar & sidebar customization
- **Scope:** Show or hide the toolbar and sidebar. Customize Toolbar. Show Sidebar Editor.
- [ ] Toolbar items are added from the command registry, and the layout persists.

### M02.08 Tabs
- **Scope:** File › New Tab, Close Tab, Close Other Tabs. View › Show Tab Bar. Window › Previous/Next Tab. Shortcuts to select tabs 1–5.
- [ ] Each tab keeps its own location and history.

### M02.09 Pin View
- **Scope:** Window › Pin View keeps a pinned location while you work in other tabs.
- [ ] Define how a pinned tab behaves when you navigate in it (for example, open a new tab instead). Document the decision.

### M02.10 Multiple windows & window layout
- **Scope:** File › New ForkLift Window. Window › Minimize, Zoom, Fill, Center, Move & Resize, Full Screen Tile, Bring All to Front, window list.
- [ ] OS-specific window actions are hidden when the OS doesn't support them.

### M02.11 Quit & restore session
- **Scope:** Quit and Keep Windows. Settings › General › Restore windows and tabs on startup. Starting Directory.
- [ ] After a restart, windows, tabs, pane layout and locations are restored when the setting is on.
- [ ] When restore is off, new windows open at Starting Directory.
