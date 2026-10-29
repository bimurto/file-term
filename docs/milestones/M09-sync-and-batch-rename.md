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
- [x] Add to Favorites saves the roots and all options.
- [x] Running a saved sync always opens the analysis preview first.

## Part B — Batch rename

### M09.08 Batch rename dialog
- **Scope:** Opens when more than one item is selected and Rename or Return is pressed.
- [x] Shows a two-column Original → New preview and the number of items affected.
- [x] Buttons: Cancel, Rename, Add to Favorites.

### M09.09 Rule engine & Apply to
- [x] Ordered list of rules (add, remove, reorder).
- [x] Apply to: name only, extension only, or full name.

### M09.10 Replace Text rule
- [x] Occurrences: first, last or all. Replacement text. Case-sensitive toggle.

### M09.11 Change Case rule
- [x] lower, UPPER, Title, Sentence.

### M09.12 Add Sequence rule
- [x] Start with, Step value, Padding, Position, Prefix, Suffix.
- [x] Numbers follow the order shown in the dialog (e.g. `1sample-two.txt`, `2sample-one.txt`).

### M09.13 Add Text & Add Date rules
- [x] Insert text, or a date (file date or current date), at a chosen position and format.

### M09.14 Validation & rename presets
- [x] Shows a warning for duplicate target names, invalid characters and extension changes before Rename is enabled.
- [x] Rename presets are saved as favorites and appear in Quick Open (M03.03).

## Tickets

M09 ships in tickets, one commit each.

| Ticket | Covers | Status |
|---|---|---|
| T1 Sync analysis, dialog and queue jobs | M09.01–.06 | Done |
| T2 Sync favorites | M09.07 | Done |
| T3 Batch rename engine and dialog | M09.08–.13 | Done |
| T4 Rename validation and presets | M09.14 | Done |

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

## T2 notes

- Add to Favorites (in the Sync dialog) asks for a name, then saves both roots and every option
  (direction, scope, update and delete rules, offset, exclusions) in Defaults under `syncFavorites`.
  Saved favorites contain no passwords.
- Commands › Sync Favorites lists them (and Quick Open finds them). Choosing one shows both folders
  side by side, then **opens the dialog and analyses**. Nothing is submitted until Synchronize.
- A dialog opened from a favorite offers Update Favorite (overwrites it with the current options)
  and Remove from Favorites.
- A favorite on a remote connection needs that connection to be open: otherwise a notice asks you
  to connect first. Connection state is not restored across launches (M08), so the same applies
  after a restart.
- Not done: renaming or reordering favorites outside the dialog; the Favorites manager is M11.

## T3 notes

- Rename (Commands › Rename, the context menu or **Return in the list view**) with more than one
  item selected opens Batch Rename; with one item it still renames inline. Return in the icon and
  column views is not wired; use Commands › Rename there.
- Rules (`RenameRule`, core) are an ordered list: add from the Add Rule menu, remove, and move up
  or down. Each rule has Apply to: name only, extension only or full name. Folders have no
  extension, and a name like `.hidden` has none either. Extension-only Add Text on a file without
  an extension adds one.
- Replace Text: first, last or all occurrences, replacement text, Case sensitive (off by default,
  so `OLD` matches `old`). Change Case: lower, UPPER, Title, Sentence. Add Sequence: Start with,
  Step, Padding (digits), Prefix, Suffix and Position (start, end or at an index). Add Text and
  Add Date use the same positions; Add Date takes the file's modified or created date, or the
  current date, with a `DateFormatter` pattern such as `yyyy-MM-dd`. A file without that date is
  left unchanged.
- Sequence numbers follow the order shown in the pane (grouping included), so
  `sample-two.txt`, `sample-one.txt` become `1sample-two.txt`, `2sample-one.txt`.
- Rename runs as one `.rename` queue job. Local items use `LocalFileOperations.renameBatch`: one
  undo step, and swaps (`a`↔`b`) or case-only changes go through temporary names
  (`RenameSequencer`), so APFS's case-insensitivity does not block `a.txt` → `A.txt`. Remote items
  use `ProviderItemOperations.rename` with the same ordering; a failure after the first success is
  reported as a partial failure. All items of a remote batch must be on the pane's connection.
- A target that equals the name of an item that is *not* being renamed stops the job with
  "already exists" (earlier renames stay, and local ones can be undone). T4 warns before that.

## T4 notes

- The preview has a Warning column and a summary line. **Errors** keep Rename off: a duplicate
  name (two items of one folder get the same name, ignoring case), an invalid name (empty, `.`,
  `..`, over 255 bytes, or containing `/`, `:` or a null character), or a name already taken by an
  item that is not being renamed. A name given up by another item of the same batch is free, so a
  swap is allowed. An **extension change** on a file is a warning: tick Allow extension changes to
  enable Rename.
- "Already taken" is checked against the names in the pane's current folder only. Items from other
  folders (search results) are still checked for duplicates, and the job stops with an
  "already exists" error if a name is taken there.
- Add to Favorites asks for a name and saves the rule list as a rename preset (Defaults key
  `renamePresets`). The Presets menu in the dialog loads or deletes one.
- Quick Open lists presets (kind "rename preset", via `QuickOpenExtensionPoints.renamePresets`).
  Choosing one with several items selected opens Batch Rename with its rules loaded; with fewer
  selected the entry is shown disabled.
- Not done: UI tests for the two dialogs (they need an interactive desktop), and presets do not
  yet appear in the Favorites manager (M11).
