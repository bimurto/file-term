# Known issues

Problems in the app as it stands on 2026-10-31. Missing features and untested protocols are in the [user guide's limits chapter](user-guide/13-limits-and-known-gaps.md), and unfinished work is in the [milestones](milestones/).

**Seen** means someone watched it happen in the running app. **From the code** means it comes from reading the code and hasn't been run. **Not confirmed** means it may not be a real bug.

## App behavior

| Issue | Status | Detail |
|---|---|---|
| Move to Trash deletes permanently on a connection | From the code | In the main menu, the toolbar and with ⌘⌫, `FileOperationCoordinator.trash` runs a permanent server delete under the Move to Trash title. The right-click menu already says Delete… instead. |
| A scrollbar sometimes appears under the toolbar | Seen | It moves the toolbar up about 8 points and comes and goes between launches. A build from before M15 does it too, so M15 didn't cause it. The cause isn't known. The toolbar asks for hidden scroll indicators in `BrowserView`. |
| Copy Dropbox Link shows on every local item without Dropbox | Seen | With no Dropbox set up, the right-click menu shows the item dimmed instead of hiding it. The earlier short menu used the same logic. |
| Share opens in the window's corner | From the code | `file.share` shows the picker at `.zero` of the window's content view, not at the clicked item. |
| Tags… doesn't open a tag editor of its own | From the code | `file.tags` calls the same `showInfo` as Get Info. |
| Only the first seven tags get a color dot | From the code | The rest are in File › Tags. |
| A row in an earlier column offers only Open | Seen | In column view, that row isn't in the current folder, so the commands can't act on it. |

## Right-click menus not fully tested

Details are in [M15](milestones/M15-context-menus.md).

| Issue | Status | Detail |
|---|---|---|
| Remote menu behavior hasn't run against a server | From the code | Covers remote Open, Delete…, disabled Copy and disabled Open With. Docker wasn't running. |
| Eject from the sidebar menu hasn't been run | From the code | No volume was ejected to test it. |
| Running a service from the Services submenu hasn't been tried | Not confirmed | The submenu appears and lists copies of the app menu's items. |
| Turning a tag off with a color dot hasn't been tried | Not confirmed | Turning one on works. |
| The Contents limit of 1000 items hasn't been tried | Not confirmed | No folder that large was opened. |

## Development

| Issue | Status | Detail |
|---|---|---|
| The right-click UI tests have never run | Seen | `FileTermUITests/ContextMenuUITests.swift` stopped with "Timed out while enabling automation mode". It may need approval on screen. It also doesn't cover the sidebar yet. |
