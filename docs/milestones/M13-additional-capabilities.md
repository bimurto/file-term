# M13 — Additional documented capabilities

**Goal:** Add the vendor-documented features that were not tested in the installed 4.6 app.
**Ref:** Guide › Ch. 12 Additional documented capabilities.

## Items

### M13.01 Workspaces
- [ ] Save the current windows, tabs, panes and locations as a named workspace. Load it later.
- [ ] Workspaces can be found in Quick Open and the sidebar.

### M13.02 iCloud Drive files
- [ ] iCloud Drive appears in the sidebar and favorites.
- [ ] Download Now and Remove Download commands. Remove Download keeps the file in the cloud, and the UI says so.

### M13.03 Dropbox links
- [ ] Context menu "Copy Dropbox Link" for items in a Dropbox folder. Disabled when the Dropbox integration isn't available.

### M13.04 Default file viewer
- [ ] An opt-in setting, with documentation, that makes the app handle "Reveal/Show in Finder" requests.
- [ ] The setting can be reverted, and the UI says it doesn't replace system Open/Save dialogs.

### M13.05 Favorites import
- [ ] Import favorites from an older config (e.g., ForkLift 3) during setup, with a preview and no overwriting by default.

### M13.06 Prerequisite detection
- [ ] A shared helper checks prerequisites and reports what's missing: accounts and permissions for remote connections, a repository for Git, an installed compare tool, preview support for the file type, and CLI programs needed by tools.
