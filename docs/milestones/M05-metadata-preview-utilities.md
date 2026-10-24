# M05 — Metadata, preview & file utilities

**Goal:** Add the Preview/Info panel, editable metadata, previews and file utilities (paths, links, checksums).
**Ref:** Guide › Ch. 5 Metadata preview and file utilities.

## Items

### M05.01 Preview panel & Get Info
- **Scope:** View › Show Preview (side panel). File › Get Info (separate window).
- [ ] Fields shown: path, byte size, created/modified dates, extension, hidden status, permissions, owner, group, locked, opening app, tags, comments.

### M05.02 Quick Look, Slideshow, Print
- [ ] Quick Look (⌘Y) opens a floating preview using the system preview service.
- [ ] Slideshow shows the selected images full-screen.
- [ ] Print is enabled only for printable files.

### M05.03 Media & text preview *(vendor-documented)*
- [ ] Image, PDF, audio and video preview in the panel.
- [ ] Text files can be edited in place, with an explicit Save.
- [ ] Remote files are downloaded to a temp cache before preview (works once M08 exists).

### M05.04 Tags & comments
- [ ] Tags can be edited in the Preview panel and from File › Tags.
- [ ] The Comments field is editable and saved where the filesystem supports it. Otherwise it is disabled with a reason.

### M05.05 Permissions editor & Locked
- [ ] rwx checkboxes for owner, group and other, kept in sync with an octal field.
- [ ] Owner and group menus. Locked toggle.
- [ ] Permission changes ask for confirmation and show an error message when they fail.

### M05.06 Opening application association
- [ ] The "Open with" selector changes the default app for this item.
- [ ] Change All applies it to every file of the same type.

### M05.07 Calculate All Folder Sizes
- [ ] Folder sizes are calculated in the background, with progress shown and a way to cancel.
- [ ] The size column shows a placeholder until the calculation finishes.

### M05.08 Copy Path / Copy URL / Open URL
- **Scope:** Copy Path formats: UNIX, URL, Percent-Decoded URL, Name, Terminal (shell-escaped), Windows.
- [ ] Each format is unit-tested with paths containing spaces and Unicode.
- [ ] Copy URL and Open URL are enabled only when the location provides a URL (for example, a remote Base URL from M08).

### M05.09 Aliases & symlinks
- [ ] Make Alias and Make Symlink create the link in the same folder.
- [ ] Make Alias to and Make Symlink to create the link in the other pane.
- [ ] The commands are disabled on filesystems that don't support links.

### M05.10 Calculate Checksum
- [ ] The dialog offers algorithms (MD5, SHA-1, SHA-256 at minimum).
- [ ] The dialog shows the result, a copy button and a field to compare against a pasted value.
