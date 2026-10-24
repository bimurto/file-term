# M00 — Foundation & app shell

**Goal:** Create a running application window with one file-list pane, a path bar, a status bar and placeholders for the Preview, Activities and Logs panels.
**Ref:** Guide › Start here, Two minute first action, Coverage limit.

## Items

### M00.01 Project skeleton
- **Scope:** Repository layout, build tooling, lint/test setup, CI.
- [x] App builds and launches with an empty main window.
- [ ] Unit test runner and one smoke test pass in CI.

  Local verification passes: seven core tests, one settings test and one native UI
  smoke test. `.github/workflows/ci.yml` is ready; a hosted run is pending a Git remote.

### M00.02 Filesystem abstraction layer
- **Scope:** Define a `Location`/`FileSystemProvider` interface (list, stat, read, write, move, delete). Start with a local implementation. Remote providers come in M08.
- [x] Local provider lists a directory with name, size, kind, dates.
- [x] Interface supports adding remote providers later without changes.

### M00.03 Main window layout
- **Scope:** Toolbar, file list area, path bar above the list, status bar below it.
- [x] Path bar shows the current folder.
- [x] Toolbar has Preview, Activities and Logs buttons (they can be stubs).

### M00.04 Single-pane file list
- **Scope:** Basic list of the current folder. Double-click a folder to open it.
- [x] Opening **Downloads** shows its contents (the guide's "two minute first action").

### M00.05 Command registry
- **Scope:** Central registry of commands (id, title, menu path, shortcut, enabled predicate). Menus, toolbar, Quick Open and shortcut settings will all use it.
- [x] Each command has an `isEnabled(context)` check and a "disabled reason" message.
- [x] Main menu bar is built from the registry: File, Edit, View, Go, Commands, Window.

### M00.06 Settings storage
- **Scope:** Persistent settings with categories: General, Transfers, Shortcuts, Tags, Tools, Editing, Themes (seven categories from the guide). M06 adds an eighth category, Terminal.
- [x] Settings window has seven category tabs (contents can be empty).
- [x] Values persist across restarts.
