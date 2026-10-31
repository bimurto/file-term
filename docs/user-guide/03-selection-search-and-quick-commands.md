# 3 Selection, search and quick commands

## Basic selection

Click an item to select it. ⌘-click adds or removes one item. ⇧-click selects a range.

- Edit › Select All (⌘A) selects everything in the active pane. In a text field or the terminal, it selects text instead.
- Edit › Deselect All (⇧⌘A) clears the selection.
- Edit › Invert Selection (⇧⌘I) swaps selected and unselected items.

None of these change the current folder. For selection in icon view, see [chapter 2](02-views-windows-and-tabs.md#working-in-icon-view).

## Quick Select

Edit › Quick Select… (⌘S) selects items by a pattern.

1. Under Match, choose Name, Extension or Tag.
2. Type the pattern. Matching ignores case. Plain text means "contains". `*` and `?` work as wildcards against the whole value, such as `*.txt`.
3. Under Mode, choose Replace Selection, Add to Selection or Remove from Selection.
4. Check the count, which reads "N of M items will be selected".
5. Click Select.

## Quick Open

Press Esc to open Quick Open. It finds commands, folders in the current listing, recent folders, favorites and rename presets, and you can type letters from anywhere in the name.

- ↑ and ↓ choose a result, Return runs it, Esc closes the window.
- Each command shows its menu path and shortcut. An unavailable command is grayed out and shows the reason.

Esc doesn't open Quick Open while you're editing text, in the terminal, in a dialog, or while a search is open.

## Find

File › Find… (⌘F) puts the cursor in the toolbar's search field. The search field is part of the toolbar, so the toolbar must be visible. Find looks in the active pane's current folder, and the field shows that folder's name.

1. Type your search text.
2. Optional: click the sliders button beside the field to set the criteria.
3. Press Return.

The criteria are:

- **Match:** Name, Extension, Tag and File contents. Name is used if you turn them all off.
- **Include subfolders:** on by default.
- **Include hidden items:** off by default.
- **Engine:** Built-in or Spotlight.

Results replace the pane's listing, under a banner showing the search text, folder, count and engine. Click Close Search in the banner, or choose File › Close Search (⌥⌘F), to return to the folder with its earlier selection.

## Search engines

- **Built-in** scans folders directly. It works in local folders, on connections and inside archives opened as folders.
- **Spotlight** uses the macOS index. It works only for local folders, so a remote search falls back to Built-in. Folders Spotlight doesn't index won't appear.

## Search versus selection

Quick Select only marks items in the current folder. It never changes your location.

Find opens a separate result list that you close to return. Use Quick Select when you want to act on items you can already see. Use Find when you need to look through subfolders or file contents.

Search results aren't a drop target, so you can't drop files onto them.

## Hidden items

View › Show Hidden Items (⇧⌘.) or the Show hidden checkbox in the toolbar shows hidden items in every pane, dimmed. This setting is separate from Synchronize hidden items in the Sync dialog.

## Refresh

- View › Refresh (⌘R) reloads the open panes in the current window and keeps selections where it can.
- View › Auto-Refresh watches the local folders open in your tabs and reloads them when they change. It also refreshes when you return to FileTerm. It's off by default.

Remote folders aren't watched. Use Refresh for them.

## Shortcut customization

Settings › Shortcuts lists commands with their current shortcuts. Search by command name, menu or shortcut.

To change a shortcut:

1. Click Edit next to the command.
2. Click the recorder field and press the new keys.
3. If another command already uses them, a warning names it. Click Reassign to take the shortcut, or Cancel.
4. Click Done.

Clear removes a command's shortcut, and Restore Default returns one command to its default. Restore Defaults at the top resets all of them.

Generated entries for recent folders, connections and favorites aren't in this list. See [commands.md](commands.md) for the defaults.
