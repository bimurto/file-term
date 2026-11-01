# Stress test, 2026-11-01

Results from stress testing `/Applications/FileTerm.app` (0.1.0, built 2026-11-01 02:56) in two rounds: first by launching the app and reading its window, then with XCUITest driving menus, clicks and typing. Some areas still weren't tested. See [What wasn't tested](#what-wasnt-tested).

No test crashed the app. One input froze it: see bug 5.

The UI tests ran a copy of the installed app with its bundle ID changed to `com.fileterm.stress.installed` and signed ad hoc, so launching it couldn't close the copies already running. Every copy used its own settings suite and throwaway files. The two copies already running, the SFTP session, the real settings and the keychain weren't touched. No server outside this Mac was contacted.

**Status:**

- **Seen:** happened in the running app.
- **Core test:** happened when a test program called the app's `FileTermCore` code directly, because the UI couldn't reach it. Nobody watched it in the app.
- **Crash log:** comes from a crash report already on this Mac.
- **Not confirmed:** the code does this, but it's not known whether a user can reach it.
- **Fixed:** seen in this test and fixed afterwards. The row describes the old behavior.

## Bugs

### High

| # | Bug | Status | Steps and result | Where |
|---|---|---|---|---|
| 1 | An ordinary permissions problem tells the user to grant Full Disk Access | Fixed | Open a folder set to `chmod 000`. The app says "macOS denied access… FileTerm needs the Full Disk Access permission" and offers Open System Settings. Full Disk Access doesn't get around Unix permissions, so the advice sends the user to the wrong place. | `SystemPermission.required(forPath:)` picks the permission from the path alone. Message at `BrowserView.swift:688`. |
| 2 | A folder deleted while open is reported as empty, then as both missing and empty | Fixed | Open a folder and delete it from outside the app. It still says "This folder is empty". Press Refresh: it shows "The item no longer exists." and "This folder is empty" together. The pane stays on the dead path, the last breadcrumb turns into a file icon, and the folder stays in Recent Folders. Expected: move to the nearest existing parent. | `FileContentView.swift:48` |
| 3 | A folder that changes on disk keeps its old listing | Fixed | Open an empty folder and create 20,000 files in it from outside. 16 seconds later it still says "This folder is empty" and "0 items". Auto-Refresh is off by default, so the pane is wrong until a manual refresh. Finder updates on its own. | `AppSettings.swift:314` |
| 5 | A wildcard freezes the app on a long file name | Fixed | In a folder with a 255-character name of `a`s, open Quick Select and type `*a*a*a*a*a*ab`. Typing the pattern took 79 seconds, then XCUITest reported the main thread busy for 30 seconds and gave up, with no sign of recovery. The app was closed by the test, so how long the freeze lasts is unknown. In a direct test the same match didn't finish in 40 seconds; three repeats took 0.13 seconds. | `PatternMatcher` in `SelectionOps.swift`; `PaneModel.quickSelectPreview` runs it on the main actor |
| 24 | Duplicate and Sync leave hidden folders behind for good | Fixed | Each Duplicate leaves an empty `.FileTerm-recovery-<UUID>` folder next to the file: 8 duplicates left 8. Undo moves the copy into that folder as `item`, so undoing a duplicate frees no disk space. The folders were still there after quitting and relaunching. A Sync that added 4 items left 4, including one inside a subfolder of the destination. Nothing in the code removes them. | `storageURL(onVolumeOf:)`, `LocalFileOperations.swift:815` |
| 25 | Many failed commands show nothing in the window | Fixed | With the panels closed, these change nothing and show no message: renaming onto an existing name, or to `..`, `.` or a 300-character name; Copy or Move of a folder into itself or into the folder it's already in; Extract on a corrupt or 0-byte zip; Undo after the file has gone or its old name is taken; Duplicate on a file deleted from outside. There's no alert, and the screenshots checked show no badge, so it looks like the command worked. With the panels open, a failed copy into itself shows in Activities and Logs, and a corrupt zip and a rename onto an existing name appear in Logs only. | Command error handling |

### Medium

| # | Bug | Status | Steps and result | Where |
|---|---|---|---|---|
| 4 | A new tab opens out of sight, and the tab bar breaks when it overflows | Seen | Press the tab bar's + 20 times. The new active tab stays off-screen, tab titles are cut off at the top, and a scrollbar is drawn over the tabs. The bar never scrolls to the active tab. | `PaneTabBar.swift:11` has no `ScrollViewReader`. |
| 6 | Some archive entries show the wrong name and can't be opened | Core test | In a tar, `new⏎line.txt` is listed as `new\nline.txt` and `back\slash.txt` with its backslash doubled. Reading either fails with "Not found in archive". `bsdtar -tv` escapes these names and the parser keeps the escapes. | `ArchiveProvider.parse` |
| 7 | Extraction has no size check | Core test | A 5.2 MB zip expanded to 5 GB in 1.4 seconds with no warning. The same zip with larger entries could fill the disk. This adds to the malicious-archive threat in [known issues](known-issues.md). | `ArchiveTool.extract` |
| 8 | Folder size fails completely on one unreadable subfolder | Core test | One `chmod 000` folder inside the tree returns "Permission denied" and no total. This is documented, but protected folders are common (for example under `~/Library`), so many trees get no size at all. | `FolderSizeScanner.scan` |
| 9 | FTP files disappear when the owner or group name has a space | Core test | `-rw-r--r-- 1 my user my group 1 Jan 1 2026 file` matches neither listing format, so the file is dropped with no message. | `FTPListing.unixPattern` |
| 10 | Every toolbar button reports "Hidden" or "Shown" to accessibility tools | Seen | Back, Forward, Up and Trash all report a value of `Hidden`, so VoiceOver should announce it (not tried with VoiceOver). Only the buttons that actually toggle something should have this value. | `BrowserView.swift:331` |
| 26 | ⌘S in the file editor opens Quick Select instead of saving | Fixed | Edit a text file in Preview and press ⌘S. The Quick Select sheet opens over the edit and nothing is saved. | Default shortcut `select.quick` |
| 27 | An error banner stays on a folder it has nothing to do with | Fixed | Use Go to Folder on `/private/var/root`, then Cancel. The pane is still on the old folder, under a banner saying "macOS denied access to /var/root" with Open System Settings. The sheet gives different advice for the same failure ("Check the app's Files and Folders permissions"). The banner also stayed through later failed attempts. | `navigationError` |
| 28 | A terminal whose shell has exited looks busy and can't be used | Fixed | Type `exit` in the terminal. The status reads "Paused · Shell busy or awaiting prompt", typed text doesn't appear, and nothing says the shell ended or offers a new one. | Terminal panel |
| 29 | Accessibility queries on a medium folder are very slow and use a lot of memory | Seen | With two panes open and 500 files, an XCUITest query timed out and the app reached 1.6 GB. With 3,000 files it reached 4.3 GB at 100% CPU and the query also timed out. Without such queries, 10,000 files used about 200 MB. VoiceOver walks the same tree, so it may be affected, but it wasn't tried. | File list accessibility |

### Low

| # | Bug | Status | Steps and result | Where |
|---|---|---|---|---|
| 11 | Wildcards miss file names containing a line break | Fixed | `*` and `*.txt` don't match `new⏎line.txt`. The regex doesn't use `dotMatchesLineSeparators`. | `PatternMatcher` |
| 12 | Wildcards treat composed and decomposed accents as different | Fixed | `é*` (composed) misses a file whose name uses `e` plus a combining accent, and `?` doesn't match that accented letter. A plain `é` matches both forms, so the two search modes disagree. | `PatternMatcher` |
| 13 | A bad starting path gives no explanation, and handling is inconsistent | Seen | Missing paths, files, `/dev/null`, broken links and paths over 1024 characters all open Home with no message. An unreadable folder gets a different result: a window titled "FileTerm — Browser" with a "New Tab" tab and "No folder open". The test set the path with `FILETERM_INITIAL_DIRECTORY`, which feeds the same code as the Starting Directory setting. | `AppDelegate.swift:387` |
| 14 | Broken links look the same as working ones | Seen | A broken link, a pair of links pointing at each other, and a link to a real file have the same icon and the Kind "Symbolic Link". | File list |
| 15 | Link names containing ` -> ` get cut short | Core test | In an archive, a link named `sym -> arrow` is listed as `sym`. In an FTP listing, `name -> with -> arrow` becomes `name`. | `ArchiveProvider.parse`, `FTPListing` |
| 16 | Impossible values from an FTP server are accepted | Core test | `size=-5` gives a negative size, `Feb 31` becomes March 3, `99-99-99 99:99PM` becomes a 2007 date, and `modify=99999999999999` becomes the year 10007. | `FTPListing` |
| 17 | An empty archive extracts without any message | Fixed | A 0-byte `.zip` returns no items and no error, and in the app Extract shows nothing. | `ArchiveTool.extract` |
| 18 | One bad entry cancels the whole extraction | Core test | A zip with one `../` entry, or a tar with a link that points outside, extracts nothing. Failing safely is right, and no file escaped. But the good files are thrown away with the rest. | `ArchiveTool.extract` |
| 19 | Folder size fails on very deep folders | Core test | A folder 300 levels deep gives "Too many open files" under a 256-file limit, because the scan keeps a file open for each level. macOS's default soft limit is 256; the app's actual limit wasn't checked. | `FolderSizeScanner.walk` |
| 20 | Layout gets cramped with every panel open | Seen | At the default 1000×672 window with Preview, Activities, Logs and Terminal open, the file list shows about 3 rows and breadcrumbs lose their labels. The window doesn't grow to make room. | `BrowserView` |
| 21 | Awkward labels | Seen | An empty file's size reads "Zero kB", while a 1-byte file reads "1 byte". `.tar.gz` shows as "GZ File". The status bar says "1 items", the copy prompt says "Copy 1 item(s)?", and selecting a folder reads "Zero kB + unknown". A failed connection shows "No route to host (NetFS error 65)". The editor's warning about a file changed on disk is cut off mid-word. `host:port` in the Server field gets "The server name is not valid." without pointing to the Port field. | File list, `ConnectionProfile.swift:142` |
| 30 | The extension warning appears before the name is checked | Seen | Renaming `alpha.txt` to an empty name or `a/b` first asks "Change the filename extension?". Accepting it does nothing and shows no message. Changing only the case of the extension (`ALPHA.TXT`) gets the same warning. | Inline rename |
| 31 | Rename accepts awkward names without a warning | Seen | Names with a leading or trailing space and names containing `:` are created as typed. | Inline rename |
| 32 | Go to Folder rejects `~` and surrounding spaces | Seen | `~` and `  /tmp  ` get "Enter an absolute folder path beginning with /." Finder accepts both forms. A path that never existed gets "The item no longer exists." | Go to Folder |
| 33 | Opening a broken link does nothing | Seen | Double-clicking a broken link or a link pointing at itself shows no message and adds nothing to Logs. | File list |
| 34 | The Activities panel collapses when Logs is open | Seen | At the default window size with both open, Activities is so narrow its title wraps a few letters per line. | `BrowserView` |
| 35 | Some empty or oversized values are accepted | Seen | Save Workspace with an empty name has Save enabled, but nothing is saved and nothing is shown. Connect is enabled with no server. A 200-character tag name is accepted. | Workspace, Connect and Tags forms |
| 36 | Sync opens with the same folder on both sides | Seen | The dialog opens with Synchronize available. It wasn't run. | Sync sheet |
| 37 | The test suite leaves settings files behind | Seen | `~/Library/Preferences` holds 3,591 `com.fileterm.tests.*`, 472 `com.fileterm.uitests.*`, 23 `com.fileterm.m05.*` and 10 `com.fileterm.tests.contextmenu.*` files from earlier test runs. They were left in place. | Test fixtures |

### Not confirmed

| # | Issue | Status | Detail |
|---|---|---|---|
| 22 | The log redactor misses some secret formats | Not confirmed | These pass through unchanged: `ftp://user:pa ss@host/` (space in the password), `PASS hunter2`, a private key header and an AWS `Signature=`. Whether any of them ever reach the Logs panel wasn't checked. See `LogRedactor.redact`. |
| 23 | Three crashes in the menu code on 2026-10-30 | Crash log | `EXC_BAD_ACCESS` in `_checkExpectedExecutor` under `MenuCoordinator.menuNeedsUpdate`, in a debug build, while XCTest was reading the menus. The reports are `~/Library/Logs/DiagnosticReports/FileTerm-2026-10-30-*.ips`. It didn't happen here: the UI tests opened every menu bar menu and the right-click menus on files, folders and links, with no crash report. The crashes were in a debug build and this run used the installed build, so that doesn't show they're fixed. |

## New evidence on a known issue

**Scrollbar under the toolbar** ([known issues](known-issues.md)): it appeared in about 27 of 33 launch screenshots, counted by a rough pixel check, and in 11 of the 12 UI test screenshots looked at. It showed up in empty, large and error folders alike, and the same folder could go either way between launches.

The accessibility tree shows a real scrollbar on the toolbar's scroll view, and it spans about 90–95% of the window width. That suggests the toolbar's contents are slightly wider than the default 1000-point window, so the cause may be width rather than timing. Check this first: `BrowserView.swift:239`.

## What held up

| Test | Result |
|---|---|
| Opening 10,000 files | Under 2 seconds, about 200 MB |
| Opening 50,000 files | About 4 seconds, 478 MB |
| Switching views on 50,000 files | Settled at about 580 MB, CPU back to idle |
| 20 rapid view, pane, hidden-file and refresh clicks on 10,000 files | No crash, CPU back to idle |
| Folder of hostile file names (`-rf`, `$(…)`, ANSI codes, emoji, 255 characters, right-to-left marks) | Opened and counted 44 items; the first 21 rows, as far as `back\slash.txt`, were checked by eye and looked right |
| Symlink pointing at itself | Opens without looping |
| 15 settings keys set to invalid data, wrong types, and a 5,000-item recent list | Started normally every time |
| Copy of the real settings | Opened a window normally |
| 2,000,000 random SFTP packets | No crash |
| 300,000 corrupted FTP listing lines | No crash |
| `../` and absolute names from an FTP server | Dropped |
| Archives with `../`, absolute paths or links pointing outside | No file escaped |
| Corrupt or unrecognized archives (direct test) | Clear error from the code, but the app doesn't show it: see bug 25 |
| Finder-made zip with `__MACOSX` | Extracted correctly |
| Swapping names, chains of renames and case-only renames | Correct order of steps (plan only, no files renamed) |
| Copy onto an existing file | Asks first with Keep Both, Replace Older, Replace, Skip and Stop; the file was unchanged after Skip |
| Cancelling a 1.5 GB copy | Marked Cancelled, no partial file left |
| 15 rapid New Folder commands | 15 folders on disk and 15 rows |
| Move to Trash, then Undo | File restored with its contents |
| Duplicate 8 times, then Undo each | Copies removed (but see bug 24) |
| Preview of a FIFO, a link to `/dev/zero`, a 3 GB file, a 50 MB single-line file, binary, bad image, fake PDF | No hang or crash |
| Saving an edit after the file changed on disk | Refused with a warning, outside change kept |
| Compress on names like `-rf.txt` and `$(touch pwn).txt` | Worked, and nothing ran |
| Quick Select and Search with `[`, `\\`, `(((`, `$(touch pwn)` | No error or crash, and nothing ran |
| Batch rename with `/` in added text | Blocked with "invalid name"; a real run and its Undo worked |
| Sync with Delete orphaned items | Listed the deletion in red first; only the orphan was removed |
| Terminal: 2,000,000 lines, binary output, 12 rapid toggles | No crash; `cd` moved the pane |
| 13 tabs, 9 windows, closing the last window | No crash; Show Browser Window brought one back |

## What wasn't tested

- **Bulk copy and delete through the UI:** selecting hundreds of files made the UI test fail before the copy started (see bug 29), so these ran on one file or a few.
- **Drag and drop:** the two drags tried changed nothing, and the test can't tell whether the app or the test tool caused that.
- **Copy and Paste with the clipboard:** skipped so your clipboard wouldn't be overwritten.
- **Commands on a file deleted from outside, other than Duplicate:** the row had gone by then, so Compress, Checksum, Get Info and Trash weren't tried. Renaming a file that vanishes mid-edit also wasn't completed, because the test lost keyboard focus.
- **Other UI features:** Quick Look, Print, Share, editing tags on files, running a tool, Compare, opening a file in another app, and changing most settings. Set as Default Viewer was deliberately left alone.
- **Remote connections:** no test server was running, and Docker wasn't up.
- **Quick Open with very long input:** the 1,500-character test overran its time limit, so it has no result.
