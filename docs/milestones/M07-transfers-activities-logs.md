# M07 — Transfers, activities & logs

**Goal:** Build a transfer engine with a queue, configurable policies, retries, bandwidth limits and visible Activities and Logs.
**Ref:** Guide › Ch. 7 Transfers activities and logs.

## Items

### M07.01 Operation queue engine
- **Scope:** One job model for copy, move, rename, delete and compress, with states: queued, running, paused, completed, failed, cancelled.
- [ ] Every file operation from M04 runs through the queue.

### M07.02 Activities panel
- **Scope:** Toolbar button and View › Show Activities.
- [ ] Shows progress, speed, ETA and state for each job.
- [ ] Each job has Cancel and Pause/Resume.

### M07.03 Logs panel
- **Scope:** Toolbar button and View › Show Logs.
- [ ] Records each operation with timestamp, source, destination and result or error message.
- [ ] Log entries can be copied or exported.

### M07.04 Replace policy (default: Ask)
- **Scope:** Settings › Transfers › Replace policy. Options: Ask plus automatic choices that map to the M04.09 options.
- [ ] A non-Ask policy resolves conflicts without opening the dialog, and the log records which choice was made.

### M07.05 Resume & Merge policies (default: Ask)
- [ ] When a destination supports resume, an interrupted transfer continues from the last byte written.
- [ ] Merge policy controls how folder conflicts are handled automatically.

### M07.06 Bandwidth limits
- [ ] Separate upload and download switches, each with a rate field.
- [ ] Throttling is verified with a test.

### M07.07 Automatic retry
- [ ] "Automatically retry failed transfers" toggle, plus Max. number of retries (default 5).
- [ ] Only temporary errors (network timeouts, resets) are retried. Authentication, permission and missing-destination errors fail immediately.

### M07.08 Max simultaneous transfers
- [ ] Concurrency limit (default 5) is applied to the whole queue.

### M07.09 Queue reordering *(vendor-documented)*
- [ ] Queued jobs can be reordered by drag or with move-up/down controls in Activities.

### M07.10 Completion verification
- [ ] When a job finishes, it shows a summary: items succeeded, skipped and failed.
- [ ] Optional setting: verify copies by size, or by checksum using M05.10.

### M07.11 Failure diagnostics
- [ ] A failed job shows the source path, destination path and error message, with a hint (connectivity, credentials, free space or permissions).
- [ ] "Retry" button available on failed jobs.
