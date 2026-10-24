# M02 — Views, windows and tabs

## Decisions

- Each pane owns independent tabs, histories and view options.
- Pinned tabs retain their location; navigation opens an unpinned tab.
- View settings explicitly apply to This Tab or This Folder. Folder settings and
  saved defaults persist globally; tabs retain their own chosen scope.
- List, icon and Miller-column modes share sorting, grouping and selection.
- Missing filesystem metadata sorts last and has a visible unknown group.
- Toolbar items come from registry commands; customization and sidebar order persist.
- Browser windows own independent models. Menus route to the active browser window.
- Restore defaults off; new windows use Home until Starting Directory changes.
- Quit and Keep Windows saves an explicit one-shot restoration request.
- Native window actions use public AppKit APIs and availability guards.

## Verification

Run focused core tests for sorting, grouping, tabs, pinning and session snapshots.
Run native tests for preference persistence and window routing, then UI tests for
all three views, tabs, multiple windows, customization and session restoration.
Retain M01 regressions, strict formatting and a native build.
