# M14 — Post-4.6 additions & release hardening

**Goal:** Catch up with features added after 4.6, and confirm the main workflows work end to end before release.
**Ref:** Guide › Ch. 12 (Quick practice sections), Ch. 13 Version differences and sources.

## Part A — Post-4.6 features *(post-4.6)*

### M14.01 Metadata-based batch rename (4.7.1)
- [ ] New rename rule that inserts EXIF, ID3 or file metadata fields (extends M09).

### M14.02 Shell PATH inheritance (4.7.1)
- [x] Tools, the external terminal launch and built-in terminal sessions (M06) inherit the user's login-shell PATH.
  - Git commands get it too. macOS ignores the launch environment when the external terminal app is already running.
  - A built-in session opened before the lookup finishes starts with the inherited PATH. With Login Shell on, its own startup files still set PATH.

### M14.03 Icon view file-size info (4.7.2)
- [x] Optional size label under icons.

### M14.04 Icon view navigation & selection improvements (4.7.3)
- [ ] Arrow keys move through the grid, type-to-select works, and rubber-band selection works.

### M14.05 Move tab to other pane (4.7.6)
- [x] Window menu command that moves the current tab to the opposite pane.

### M14.06 Go to Folder history & extra tool placeholders
- [ ] Go to Folder keeps a history and autocompletes from it.
- [ ] Add new placeholders to M11.05 as they are defined.

## Part B — Acceptance scenarios (end-to-end tests)

### M14.07 Copy practice scenario
- [ ] Create two disposable folders, open one in each pane, then Copy to. The file exists at the destination **and** is still in the source.

### M14.08 Rename practice scenario
- [ ] Two disposable files. Add a Sequence rule, check the preview, Cancel. The files are unchanged.

### M14.09 Sync practice scenario
- [ ] Two small folder trees. One-way sync with deletion off. Check the proposed add/update list, Cancel. Nothing changes.

### M14.10 Remote smoke tests
- [ ] For each protocol in M08, run connect, list, upload, download, rename and delete against test servers (docker-based where possible).

## Part C — Hardening

### M14.11 Privacy review
- [ ] Logs and crash reports leave out credentials, tokens and (optionally) personal paths.

### M14.12 Performance
- [ ] A folder with 100k entries lists in an acceptable time. Large transfers don't freeze the UI.

### M14.13 Documentation
- [ ] A user guide mirroring the source chapters, plus an in-app help link for each command.
