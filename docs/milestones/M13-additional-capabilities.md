# M13 — Additional documented capabilities

**Goal:** Add the vendor-documented features that were not tested in the installed 4.6 app.
**Ref:** Guide › Ch. 12 Additional documented capabilities.

## Items

### M13.01 Workspaces
- [x] Save the current windows, tabs, panes and locations as a named workspace. Load it later.
- [x] Workspaces can be found in Quick Open and the sidebar.

### M13.02 iCloud Drive files
- [x] iCloud Drive appears in the sidebar and favorites.
- [x] Download Now and Remove Download commands. Remove Download keeps the file in the cloud, and the UI says so.

### M13.03 Dropbox links
- [x] Context menu "Copy Dropbox Link" for items in a Dropbox folder. Disabled when the Dropbox integration isn't available.

### M13.04 Default file viewer
- [x] An opt-in setting, with documentation, that makes the app handle "Reveal/Show in Finder" requests.
- [x] The setting can be reverted, and the UI says it doesn't replace system Open/Save dialogs.

### M13.05 Favorites import
- [x] Import favorites from an older config (e.g., ForkLift 3) during setup, with a preview and no overwriting by default.

### M13.06 Prerequisite detection
- [x] A shared helper checks prerequisites and reports what's missing: accounts and permissions for remote connections, a repository for Git, an installed compare tool, preview support for the file type, and CLI programs needed by tools.

## Tickets

| Ticket | Covers | Status |
|---|---|---|
| T1 Workspaces | M13.01 | Done |
| T2 iCloud Drive files | M13.02 | Done, not run against an iCloud account |
| T3 Dropbox links | M13.03 | Done with a pasted token, not run against Dropbox |
| T4 Default file viewer | M13.04 | Done, the system setting was not changed on a real Mac |
| T5 Favorites import | M13.05 | Local favorites only |
| T6 Prerequisite detection | M13.06 | Done, Git and preview checks not connected to their features |

## Notes

- **Workspaces** are in Go › Workspaces, the sidebar and Quick Open. Loading closes the open windows, and asks first if that would end terminal sessions.
- **Dropbox** uses the sharing API. This project has no registered Dropbox app, so there is no sign-in: the user creates a token in the Dropbox App Console and pastes it in Settings › Integrations. Such tokens can be short-lived. An item in a team space may need more than this sends.
- **Default file viewer**: see [default-file-viewer.md](../default-file-viewer.md). It sets `NSFileViewer` only, not the `public.folder` handler, so double-clicking a folder in Finder is unchanged.
- **Favorites import** is not a step in the M12.08 first-run guide. It is offered once at launch when ForkLift 3 favorites exist, and is always in the Favorites manager. The format comes from a third-party parser, not from a real file: no real `Favorites.json` has been tried. Remote favorites are listed and left out because their keys are not documented.
- **Prerequisites**: tools, Compare and connections use the shared helper. M11 T8 has its own Git check and the preview panel has no unsupported-file state yet, so `.gitRepository` and `.previewSupport` have no callers.
