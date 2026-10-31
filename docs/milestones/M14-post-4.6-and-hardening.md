# M14 — Post-4.6 additions & release hardening

**Goal:** Catch up with features added after 4.6, and confirm the main workflows work end to end before release.
**Ref:** Guide › Ch. 12 (Quick practice sections), Ch. 13 Version differences and sources.

## Part A — Post-4.6 features *(post-4.6)*

### M14.01 Metadata-based batch rename (4.7.1)
- [x] New rename rule that inserts EXIF, ID3 or file metadata fields (extends M09).
  - Embedded fields are read from local files only. An item without the chosen field keeps its name.

### M14.02 Shell PATH inheritance (4.7.1)
- [x] Tools, the external terminal launch and built-in terminal sessions (M06) inherit the user's login-shell PATH.
  - Git commands get it too. macOS ignores the launch environment when the external terminal app is already running.
  - A built-in session opened before the lookup finishes starts with the inherited PATH. With Login Shell on, its own startup files still set PATH.

### M14.03 Icon view file-size info (4.7.2)
- [x] Optional size label under icons.

### M14.04 Icon view navigation & selection improvements (4.7.3)
- [x] Arrow keys move through the grid, type-to-select works, and rubber-band selection works.
  - The band selects only icons currently laid out, and it doesn't auto-scroll.

### M14.05 Move tab to other pane (4.7.6)
- [x] Window menu command that moves the current tab to the opposite pane.

### M14.06 Go to Folder history & extra tool placeholders
- [x] Go to Folder keeps a history and autocompletes from it.
  - The history holds the last 20 folders reached through this dialog. Tab completes the top suggestion, and clicking one goes there.
- [ ] Add new placeholders to M11.05 as they are defined.
  - Open: no new placeholders have been defined yet, so none were added.

## Part B — Acceptance scenarios (end-to-end tests)

### M14.07 Copy practice scenario
- [x] Create two disposable folders, open one in each pane, then Copy to. The file exists at the destination **and** is still in the source.

### M14.08 Rename practice scenario
- [x] Two disposable files. Add a Sequence rule, check the preview, Cancel. The files are unchanged.

### M14.09 Sync practice scenario
- [x] Two small folder trees. One-way sync with deletion off. Check the proposed add/update list, Cancel. Nothing changes.

### M14.10 Remote smoke tests
- [ ] For each protocol in M08, run connect, list, upload, download, rename and delete against test servers (docker-based where possible).
  - Open: the protocols marked "not run" below have no result yet.
  - Run with `FILETERM_LIVE=1 swift test --filter RemoteSmokeTests` and, for SMB, `TEST_RUNNER_FILETERM_LIVE=1 xcodebuild … test -only-testing:FileTermTests/MountedShareSmokeTests`.

  | Protocol | Result | Note |
  |---|---|---|
  | SFTP, FTP, FTP-TLS, WebDAV, Amazon S3 | Passed | Against `dev/docker-compose.yml`. FTP needs its server to finish starting first. |
  | Backblaze B2 | Passed | Against the `s3` stand-in, so not Backblaze's own service. |
  | SMB | Passed | Through the real NetFS mount, on port 1445. |
  | NFS | Not run | The `nfs` container can't load its kernel module under Colima. |
  | WebDAV over HTTPS | Passed | Through a TLS proxy in `dev/docker-compose.yml`. The test trusts the proxy's own certificate through a test-only option, so a certificate macOS trusts by itself wasn't exercised. An untrusted certificate is refused. |
  | AFP | Not run | No test server, and macOS 26 has no AFP client. |
  | VNC | Not applicable | Screen sharing can't list or transfer files. |
  | Rackspace, Google Drive, OneDrive, Dropbox | Not run | Providers aren't built yet. |

## Part C — Hardening

### M14.11 Privacy review
- [x] Logs and crash reports leave out credentials, tokens and (optionally) personal paths.
  - Every transfer log line passes through `LogRedactor`, which matches common credential shapes, so it can't promise to catch every secret. Hide Personal Paths applies to Copy All and Export.
  - FileTerm has no crash reporter and writes no log file. Logs stay in memory until someone copies or exports them.

### M14.12 Performance
- [x] A folder with 100k entries lists in an acceptable time. Large transfers don't freeze the UI.
  - Listing in 5.2 s was accepted in place of the proposed 3 s, because the UI stays responsive meanwhile. Large transfers meet their target.
  - Run with `FILETERM_PERF=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceBenchmarks`. It fails if listing reaches 6 s, which leaves room for variation between runs.

  | Measure, on 100k empty files in a release build | Before | After | Target |
  |---|---|---|---|
  | List and prepare one pane | 28.2 s | 5.2 s | Under 6 s |
  | Longest main thread stall while listing | 0.62 s (first accurate reading, after the first listing fix) | 0.12 s | 0.25 s |
  | Real app settles with both panes on that folder | Busy past 91 s, Debug build | About 11 s | None set |
  | Longest main thread stall copying 1 GB | 0.001 s | 0.003 s | 0.25 s |

  - The app figures come from timing a launched app until its CPU use settles, because XCUITest can't drive the app while it lists this folder. They don't show how smoothly the 100k list scrolls, and that wasn't measured.
  - Selecting everything in a folder this large isn't measured. Open With asks macOS about each selected item, so expect that to be slow.
  - A folder of 100k subfolders stays slower, because folders still ask Spotlight for their last opened date.
  - Going further means loading tags and file kinds after the listing, about 1.5 s of what's left.

### M14.13 Documentation
- [x] A user guide mirroring the source chapters, plus an in-app help link for each command.
  - The guide is in `docs/user-guide/`. Help links open it on GitHub, so they work only once it's pushed to `main`.
  - Generated commands, such as one per recent folder, share one entry per family.
