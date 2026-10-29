# M09 — Synchronization & batch rename

**Goal:** Add folder synchronization with a preview step, and rule-based batch rename with a live preview.
**Ref:** Guide › Ch. 8 Synchronization and batch rename.

## Part A — Synchronization

### M09.01 Sync dialog & analysis
- **Scope:** Commands › Sync to and a toolbar button. Requires dual-pane mode.
- [x] The dialog shows both root paths. Synchronize stays disabled until the analysis has finished.

### M09.02 Direction
- [x] Left→Right, Right→Left and Both ways.
- [x] Both ways decides which side wins using modification time, and shows true conflicts to the user.

### M09.03 Scope options
- [x] Options: Synchronize subfolders, Synchronize hidden items, Add items, Don't add empty folders.
- [x] Changing any option re-runs the analysis.

### M09.04 Update & delete rules
- [x] Update items when: the modification date is older, or the size differs.
- [x] Delete orphaned items is **off by default** and highlighted in red in the preview.
- [x] The UI says that the comparison is not byte-by-byte.

### M09.05 Time offset & exclusions
- [x] Time offset correction setting, in seconds or hours.
- [x] Exclude items using glob or regex filters.

### M09.06 Proposed action list
- [x] A table of add, update and delete actions for each file. Actions can be unchecked one by one before Synchronize.
- [x] Running the sync creates M07 queue jobs.

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

## Tickets

M09 ships in tickets, one commit each.

| Ticket | Covers | Status |
|---|---|---|
| T1 Sync analysis, dialog and queue jobs | M09.01–.06 | Done |
| T2 Sync favorites | M09.07 | Open |
| T3 Batch rename engine and dialog | M09.08–.13 | Open |
| T4 Rename validation and presets | M09.14 | Open |

## T1 notes

- Commands › Sync to… (and a toolbar button, `commands.sync`) needs two panes side by side. The
  left pane is the first pane, the right pane the second. The dialog lists both roots, analyses,
  and keeps Synchronize off until the analysis has finished. Every option change re-runs it after
  a short delay (so typing a filter does not scan on each key).
- Analysis (`SyncAnalyzer`, core) lists both trees through the provider layer and compares by
  relative path using modification date and size only, never file contents. Dates within 2 seconds
  count as equal. Symbolic links and special files are skipped, as in copies.
- Time offset is added to the **right** side's dates before comparing (seconds or hours).
- Exclusions: a glob without `/` matches an item's name; a glob with `/` matches the relative path;
  a regex is searched in the relative path. All ignore case. An excluded folder is not entered.
  An invalid regex is reported in the dialog and blocks Synchronize.
- One-way: add what is missing (Add items), update when the target is older and/or the size
  differs, and delete orphans only when that option is on (default off, shown in red). Orphaned
  folders appear as one delete row. A file against a folder is listed as a conflict that cannot be run.
- Both ways: missing items are added to the other side, and the newer side wins. Same time but a
  different size is a true conflict: it is unchecked, and ticking it copies in the shown direction.
  Delete orphaned does nothing here, because without a sync history a deletion cannot be told from
  a new item.
- Synchronize with subfolders off ignores folders entirely and works on the root's files.
- Running creates one queue job per side that changes (so Both ways can make two). Folders are
  created first, then files, then deletes (deepest first). Local to local copies use
  `LocalFileOperations` and keep modification dates; the replaced file is kept for undo storage,
  but sync jobs are not added to Undo history. Local orphans go to the Trash. Remote orphans are
  deleted permanently after one confirmation. Any remote side copies through `ProviderTransfer`,
  which does not preserve modification dates: the dialog warns, and "Size differs" is the
  reliable rule there.
- A failure after at least one action succeeded ends the job as a partial failure (no Retry).
- Not done: the dialog has not been driven by hand on the desktop; unit tests cover the engine,
  runner and dialog model. There is no UI test yet.
