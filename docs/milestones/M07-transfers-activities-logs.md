# M07 — Transfers, activities & logs

**Goal:** Build a transfer engine with a queue, configurable policies, retries, bandwidth limits and visible Activities and Logs.
**Ref:** Guide › Ch. 7 Transfers activities and logs.

## Items

### M07.01 Operation queue engine
- **Scope:** One job model for copy, move, rename, delete and compress, with states: queued, running, paused, completed, failed, cancelled.
- [x] Every file operation from M04 runs through the queue.

### M07.02 Activities panel
- **Scope:** Toolbar button and View › Show Activities.
- [x] Shows progress, speed, ETA and state for each job.
- [x] Each job has Cancel and Pause/Resume.

### M07.03 Logs panel
- **Scope:** Toolbar button and View › Show Logs.
- [x] Records each operation with timestamp, source, destination and result or error message.
- [x] Log entries can be copied or exported.

### M07.04 Replace policy (default: Ask)
- **Scope:** Settings › Transfers › Replace policy. Options: Ask plus automatic choices that map to the M04.09 options.
- [x] A non-Ask policy resolves conflicts without opening the dialog, and the log records which choice was made.

### M07.05 Resume & Merge policies (default: Ask)
- [ ] When a destination supports resume, an interrupted transfer continues from the last byte written.
- [x] Merge policy controls how folder conflicts are handled automatically.

### M07.06 Bandwidth limits
- [x] Separate upload and download switches, each with a rate field.
- [x] Throttling is verified with a test.

### M07.07 Automatic retry
- [x] "Automatically retry failed transfers" toggle, plus Max. number of retries (default 5).
- [x] Only temporary errors (network timeouts, resets) are retried. Authentication, permission and missing-destination errors fail immediately.

### M07.08 Max simultaneous transfers
- [x] Concurrency limit (default 5) is applied to the whole queue.

### M07.09 Queue reordering *(vendor-documented)*
- [x] Queued jobs can be reordered by drag or with move-up/down controls in Activities.

### M07.10 Completion verification
- [x] When a job finishes, it shows a summary: items succeeded, skipped and failed.
- [x] Optional setting: verify copies by size, or by checksum using M05.10.

### M07.11 Failure diagnostics
- [x] A failed job shows the source path, destination path and error message, with a hint (connectivity, credentials, free space or permissions).
- [ ] "Retry" button available on failed jobs.

## Implementation notes and remaining work

- The app-wide queue schedules independent local operation actors, with conservative subtree
  reservations to protect replacements and history. Undo/redo are exclusive queue barriers.
  Jobs and logs are in-memory and shared across windows, not persisted across launches.
- Pause/resume preserves the open transfer and byte position in this session. **Durable
  interrupted-transfer resume is not implemented**; the future resume-policy control is disabled.
- Upload/download limits share separate aggregate budgets, tested with concurrent consumers.
  Local copies have no upload/download direction and are not throttled by these settings.
  Remote execution will use those budgets when M08 providers are introduced.
- Compression has a queue job kind; actual archive execution remains part of M10.
- Retry is offered for failures with no committed mutations. Partially committed failures retain
  undo history and disable replay to prevent duplicate copies or repeated moves; retrying only
  unfinished items remains follow-up work. Undo/redo failures must be retried with a fresh
  command, not an old Activities job.
- Summaries count merged child outcomes. Metadata-only operations show unknown byte progress;
  same-volume moves generally finish without streaming bytes. Speed is elapsed-time average.
- Existing mandatory SHA-256 undo/source-integrity safeguards remain enabled independently of
  the optional copy-verification preference. Checksum copy verification currently uses the
  transfer engine's bounded SHA-256 implementation rather than calling the M05 utility.
