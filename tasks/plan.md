# M01 — Navigation and panes

Implement the approved M01 plan using the existing AppKit/SwiftUI shell and core.

## Decisions

- Two persistent panes; single mode keeps the active pane visible.
- Vertical means side by side; horizontal means stacked.
- Independent successful-navigation histories, with stale-result protection.
- Sync Browsing mirrors only entering a child and Enclosing Folder.
- Store 20 deduplicated recent local folders and UI visibility preferences.
- Selected sizes sum known metadata without recursive folder scans.
- Devices use native enumeration and workspace notifications; ejection is injectable.
- Session restore, remote connections and file operations remain later milestones.

## Verification

Run core tests after model changes, native unit tests after app integration,
strict Swift formatting, project generation and native UI tests. Use fake volume
services for eject tests; never eject a real device during automated verification.
