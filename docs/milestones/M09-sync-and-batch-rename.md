# M09 — Synchronization & batch rename

**Goal:** Add folder synchronization with a preview step, and rule-based batch rename with a live preview.
**Ref:** Guide › Ch. 8 Synchronization and batch rename.

## Part A — Synchronization

### M09.01 Sync dialog & analysis
- **Scope:** Commands › Sync to and a toolbar button. Requires dual-pane mode.
- [ ] The dialog shows both root paths. Synchronize stays disabled until the analysis has finished.

### M09.02 Direction
- [ ] Left→Right, Right→Left and Both ways.
- [ ] Both ways decides which side wins using modification time, and shows true conflicts to the user.

### M09.03 Scope options
- [ ] Options: Synchronize subfolders, Synchronize hidden items, Add items, Don't add empty folders.
- [ ] Changing any option re-runs the analysis.

### M09.04 Update & delete rules
- [ ] Update items when: the modification date is older, or the size differs.
- [ ] Delete orphaned items is **off by default** and highlighted in red in the preview.
- [ ] The UI says that the comparison is not byte-by-byte.

### M09.05 Time offset & exclusions
- [ ] Time offset correction setting, in seconds or hours.
- [ ] Exclude items using glob or regex filters.

### M09.06 Proposed action list
- [ ] A table of add, update and delete actions for each file. Actions can be unchecked one by one before Synchronize.
- [ ] Running the sync creates M07 queue jobs.

### M09.07 Sync favorites
- [ ] Add to Favorites saves the roots and all options.
- [ ] Running a saved sync always opens the analysis preview first.

## Part B — Batch rename

### M09.08 Batch rename dialog
- **Scope:** Opens when more than one item is selected and Rename or Return is pressed.
- [ ] Shows a two-column Original → New preview and the number of items affected.
- [ ] Buttons: Cancel, Rename, Add to Favorites.

### M09.09 Rule engine & Apply to
- [ ] Ordered list of rules (add, remove, reorder).
- [ ] Apply to: name only, extension only, or full name.

### M09.10 Replace Text rule
- [ ] Occurrences: first, last or all. Replacement text. Case-sensitive toggle.

### M09.11 Change Case rule
- [ ] lower, UPPER, Title, Sentence.

### M09.12 Add Sequence rule
- [ ] Start with, Step value, Padding, Position, Prefix, Suffix.
- [ ] Numbers follow the order shown in the dialog (e.g. `1sample-two.txt`, `2sample-one.txt`).

### M09.13 Add Text & Add Date rules
- [ ] Insert text, or a date (file date or current date), at a chosen position and format.

### M09.14 Validation & rename presets
- [ ] Shows a warning for duplicate target names, invalid characters and extension changes before Rename is enabled.
- [ ] Rename presets are saved as favorites and appear in Quick Open (M03.03).
