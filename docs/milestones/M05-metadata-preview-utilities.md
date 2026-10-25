# M05 — Metadata, preview & file utilities

**Goal:** Add the Preview/Info panel, editable metadata, previews and file utilities (paths, links, checksums).
**Ref:** Guide › Ch. 5 Metadata preview and file utilities.

## Items

### M05.01 Preview panel & Get Info
- **Scope:** View › Show Preview (side panel). File › Get Info (separate window).
- [x] Fields shown: path, byte size, created/modified dates, extension, hidden status, permissions, owner, group, locked, opening app, tags, comments.

### M05.02 Quick Look, Slideshow, Print
- [x] Quick Look (⌘Y) opens a floating preview using the system preview service.
- [x] Slideshow shows the selected images full-screen.
- [x] Print is enabled only for printable files.

### M05.03 Media & text preview *(vendor-documented)*
- [x] Image, PDF, audio and video preview in the panel.
- [x] Text files can be edited in place, with an explicit Save.
- [ ] Remote files are downloaded to a temp cache before preview (deferred until M08 provides remote connections).

### M05.04 Tags & comments
- [x] Tags can be edited in the Preview panel and from File › Tags.
- [x] The Comments field is editable and saved where the filesystem supports it. Otherwise it is disabled with a reason.

### M05.05 Permissions editor & Locked
- [x] rwx checkboxes for owner, group and other, kept in sync with an octal field.
- [x] Owner and group menus. Locked toggle.
- [x] Permission changes ask for confirmation and show an error message when they fail.

### M05.06 Opening application association
- [x] The "Open with" selector changes the default app for this item.
- [x] Change All applies it to every file of the same type.

### M05.07 Calculate All Folder Sizes
- [x] Folder sizes are calculated in the background, with progress shown and a way to cancel.
- [x] The size column shows a placeholder until the calculation finishes.

### M05.08 Copy Path / Copy URL / Open URL
- **Scope:** Copy Path formats: UNIX, URL, Percent-Decoded URL, Name, Terminal (shell-escaped), Windows.
- [x] Each format is unit-tested with paths containing spaces and Unicode.
- [x] Copy URL and Open URL are enabled only when the location provides a URL (for example, a remote Base URL from M08).

### M05.09 Aliases & symlinks
- [x] Make Alias and Make Symlink create the link in the same folder.
- [x] Make Alias to and Make Symlink to create the link in the other pane.
- [x] The commands are disabled on filesystems that don't support links.

### M05.10 Calculate Checksum
- [x] The dialog offers algorithms (MD5, SHA-1, SHA-256 at minimum).
- [x] The dialog shows the result, a copy button and a field to compare against a pasted value.

## Implementation notes

Implemented local-first with native Quick Look, PDFKit, AVKit and AppKit printing; no new external dependencies.

- Preview follows the active pane's first selected local item. Get Info opens an independent inspector for each selected item. Metadata loads asynchronously; symlink leaves are inspect-only. Tags/comments use Finder extended attributes, with unsupported storage disabled and explained. Permission, ownership and Locked edits are nonrecursive, confirmed, and require the current user's existing authorization; ACLs are not rewritten.
- Text editing supports lossless UTF-8 and BOM-marked UTF-16 up to 1 MiB, with explicit Save. Selection changes prompt for dirty edits; removing the panel or closing an inspector preserves them in an Unsaved Edits window. Quitting checks all live editing sessions. Saves revalidate external changes before atomic publication and retain a hidden sibling backup (`.<filename>.fileterm-backup-<UUID>`). Backups are intentionally retained for recovery and can be removed manually. Arbitrary noncooperating POSIX writers retain a narrow check/rename race; file coordination is not an exclusive filesystem transaction.
- Open with changes the item's default using public NSWorkspace APIs. Change All confirms the system-wide content-type association. Automated tests do not modify real application associations.
- Folder sizes count logical bytes per directory entry (including hidden/package contents and hard links), never follow symlinks, and report unreadable-tree failures instead of publishing partial totals. Cancellation retains already completed folders. Results feed the column, sorting, and selection totals; refresh/navigation invalidates them.
- Windows Copy Path replaces separators only; it does not invent drive letters or UNC mappings. Copy Path › URL produces local file URLs. Separate Copy URL/Open URL commands stay disabled with a reason because local locations have no public Base URL; the provider API is ready for M08.
- Aliases and symlinks use unique names and exclusive publication; same-folder commands place each link beside its source, including search results. “to” commands use the opposite visible pane. Volume support is checked and errors surfaced. These creations and metadata/text edits are not added to the M04 move-based undo journal.
- MD5 and SHA-1 are compatibility checksums, not security guarantees. Checksum calculations stream bounded chunks, report progress, and support cancellation.

### Validation

Core tests cover path formats with Unicode/spaces/shell metacharacters, permissions, known checksum vectors, bounded streaming and cancellation, safe traversal, link collisions/alias resolution, and folder-size/search-result integration. Native tests cover text round trips/conflicts/backups, metadata edits and replacement-inode guards, and utility models. Targeted XCUITests exercise Preview/Get Info, unsaved-editor recovery and Save, and the existing panel/settings smoke flow.

Verified in this implementation: `swift test` passed 73 tests; native FileTermTests plus the two targeted UI flows passed 28 tests with zero failures/skips. Strict formatting passes for all M05 changed/new Swift files, and `git diff --check` passes. Repository-wide formatting remains blocked by existing violations in AppSettings.swift, BuiltInSearch.swift, FindViews.swift, SpotlightSearch.swift and SelectionSearchTests.swift; those unrelated files were not reformatted.

Manual platform matrix still recommended: Quick Look/slideshow fullscreen interaction, audio/video formats and playback cleanup, physical printing, opening-app consent/Change All, alternate/read-only volumes, and privileged owner/group changes. Remote cache/writeback and public URL actions require M08; Activities/Logs integration follows M07.
