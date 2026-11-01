# M16 — Missing features and changes

**Goal:** Collect the missing features and changes found while using FileTerm.
**Ref:** User requests, not the ForkLift guide. This milestone stays open, and new items are added at the end with the next ID.

## Part A — Sidebar

### M16.01 Drag to add favorites
Favorites could only be added in the Favorites manager, and the sidebar's Favorites section was hidden when it had nothing to show.
- [x] Dragging a local folder onto the sidebar adds it to Favorites.
  - Covered by a UI test.
- [x] Dragging a folder from a remote location adds it as a remote favorite that reopens on that connection.
  - Live UI tests against the WebDAV and SFTP servers in `dev/docker-compose.yml`, including a relaunch and the refusal for an unsaved connection. Other remote protocols weren't tried. Run them with `TEST_RUNNER_FILETERM_LIVE=1`. If FileTerm trusted an older SFTP container, also set `TEST_RUNNER_FILETERM_SFTP_HOST` to another address of this Mac.
- [x] There is a place to drop when Favorites is empty.
  - A "Drop folders here" row. Drops aren't accepted while Favorites is hidden.
- [x] Dragging a file, not a folder, adds nothing.
  - Covered by UI tests, for a local file and for one on WebDAV and SFTP.

### M16.02 Fold sidebar sections
Section headers were plain text with no fold control.
- [x] Every sidebar section can be folded and unfolded from its header.
  - Covered by a UI test.
- [x] Folded sections stay folded after a relaunch.
  - Covered by a settings test.

### M16.03 Wider sidebar and preview
The sidebar stopped at 220 points and the preview at 440.
- [x] Both can be dragged wider than those limits.
  - They now have drag handles and fixed widths, because a raised cap let the split view give the sidebar half the window. The sidebar is covered by a UI test. The preview uses the same handle and wasn't dragged.
- [x] File panes keep their minimum width of 220 points.
  - Covered by a UI test, which drags the sidebar as far as it goes.

### M16.04 Limit recent items
Recent Folders had a fixed limit of 20.
- [x] A setting controls the limit, and the default is 10.
  - Settings › General, from 1 to 50. Covered by settings tests. The stepper itself wasn't clicked.
- [x] The sidebar, Go menu and Quick Open show no more than the limit.
  - All three read the same trimmed list.
- [x] Lowering the limit trims the stored list, including lists saved with up to 20 entries.
  - Covered by settings tests.

### M16.05 Mounted and remote icons
Device rows showed only the volume's icon, and the volume model couldn't tell a network volume from an external disk.
- [ ] Sidebar rows for mounted volumes show an icon beside the name.
  - Open: the code is in, but no external or network volume was mounted to see it. The internal disk correctly shows none.
- [ ] Network volumes and remote favorites show a different icon from local mounted volumes.
  - Open: same as above.
- [ ] Each icon has a tooltip and an accessibility label.
  - Open: same as above.

## Part B — Toolbars

### M16.06 Show Hidden icon
The main toolbar used a "Show hidden" checkbox.
- [x] An icon button replaces the checkbox and shows whether hidden items are on.
  - Seen in the running app.
- [x] It has a tooltip and keeps the `showHiddenToggle` accessibility identifier.
- [x] It stays in sync with View › Show Hidden Items.
  - It runs the same command, which also refreshes other windows. The checkbox didn't.

### M16.07 Terminal toolbar
Terminal actions were in the panel's header controls.
- [x] The terminal panel has a toolbar with icon buttons for Link/Unlink, Reveal Directory in Pane, Open SSH Session, Insert Selected Paths, Clear and Find.
  - Seen in the running app. These actions moved out of the header menu. The lock button moved here too.
- [x] Unavailable buttons are disabled and say why (roadmap rule 1).
  - Reasons are covered by a test. The shell's idle state isn't observed, so a reason can lag until the panel next redraws.

### M16.08 Add the connection toolbar button
A toolbar saved by an older version had no Connect button, because a saved layout was loaded as it was, so new default buttons never reached it. The button that was first taken for Connect was Sync Browsing, the link icon.
- [x] Toolbars saved by an older version gain default buttons they were never offered, in their default positions.
  - Covered by a test using a real saved toolbar.
- [x] A button the user removes doesn't come back.
  - Covered by a settings test.
- [x] Clicking Connect opens the connection form in the front window.
  - Covered by a UI test.
- [x] A new connection can be saved from the form without connecting.
  - Covered by a test of the form's model.
- [x] A saved connection appears in Go › Connections and opens, checked against `dev/docker-compose.yml`.
  - Live UI tests against WebDAV and SFTP.

## Part C — Menus and toolbar layout

### M16.09 Group menu items
Menu bar menus listed commands in the order they're registered, with no separators. `FileTerm/Core/Commands/MenuLayout.swift` now sets their groups.
- [x] Related commands in each menu bar menu sit together, with a separator between groups.
  - Read from the real menus in the running app.
- [x] No separator appears at the top or bottom of a menu, or twice in a row, including when items are hidden.
  - Covered by tests of the rule and of the real File menu.
- [x] Every command stays in the same menu, and its shortcut still works.
  - The layout changes order only, and a test checks every command has a place.

### M16.10 Remove Show Browser Window
Both commands were in the File menu, with Close Window directly after Show Browser Window.
- [x] `file.showBrowser` is gone from the menu and from `docs/user-guide/commands.md:26`.
  - Also removed from chapter 2 of the guide.
- [ ] With no window open, clicking the Dock icon and using New FileTerm Window each still open one.
  - Open: New FileTerm Window is covered by a UI test with the last window closed. The Dock icon's code is unchanged, but it wasn't clicked.
- [x] Close Window moves to the end of the File menu, in the group with Close Tab.
  - Covered by a test on the real menu.

### M16.11 Toolbar spacing and overflow
All toolbar buttons had the same 6-point spacing, and a narrow window scrolled the toolbar sideways with no visible scrollbar. `FileTerm/Core/Commands/ToolbarLayout.swift` now sets the groups and what folds.
- [x] Groups of related buttons have more space between them than buttons in the same group.
  - Seen in the running app.
- [x] When the window gets narrower, similar buttons fold into a dropdown, and they unfold when it's wide enough again.
  - Seen at 678 points wide. Folding rules are covered by tests.
- [x] The dropdown shows the current choice for layouts and view modes.
  - Seen in the running app.
- [x] No button becomes unreachable at the 680-point minimum window width (`FileTerm/Views/BrowserView.swift:54`).
  - Covered by a UI test at about 678 points and a test that folding loses no button.
- [x] Items added in Customize Toolbar still appear and can still be run.
  - The toolbar still builds from the saved list, and tools join it.
- [x] Check whether this also fixes the scrollbar under the toolbar in `docs/known-issues.md:11`, and record the result here.
  - The toolbar no longer scrolls, so it shouldn't return. It came and went between launches, so this isn't confirmed over repeated launches.

### M16.12 Grey out unavailable toolbar buttons
Sync Browsing was disabled in Single Pane but didn't look it, because toolbar buttons always used the primary color. Clicking it did nothing, so it looked broken.
- [x] In Single Pane, Sync Browsing looks grey and its tooltip gives the reason.
  - Seen in the running app. The tooltip text comes from the command and wasn't hovered.
- [x] Every other disabled toolbar button looks grey too.
  - Seen for Back, Forward, Sync to… and Move to Trash.
- [x] Checked buttons keep their accent color.
  - Seen in the running app.
