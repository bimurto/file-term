# Known issues

Problems in the app as it stands on 2026-11-01. Missing features and untested protocols are in the [user guide's limits chapter](user-guide/13-limits-and-known-gaps.md), and unfinished work is in the [milestones](milestones/).

**Seen** means someone watched it happen in the running app. **From the code** means it comes from reading the code and hasn't been run. **Not confirmed** means it may not be a real bug.

## App behavior

| Issue | Status | Detail |
|---|---|---|
| A scrollbar sometimes appeared under the toolbar | Probably fixed | It moved the toolbar up about 8 points and came and went between launches, and the cause was never found. The toolbar no longer scrolls since M16.11, so it shouldn't return. Not confirmed over repeated launches. |
| Copy Dropbox Link shows on every local item without Dropbox | Seen | With no Dropbox set up, the right-click menu shows the item dimmed instead of hiding it. The earlier short menu used the same logic. |
| Share opens in the window's corner | From the code | `file.share` shows the picker at `.zero` of the window's content view, not at the clicked item. |
| Tags… doesn't open a tag editor of its own | From the code | `file.tags` calls the same `showInfo` as Get Info. |
| Only the first seven tags get a color dot | From the code | The rest are in File › Tags. |
| A row in an earlier column offers only Open | Seen | In column view, that row isn't in the current folder, so the commands can't act on it. |

## File operations

| Issue | Status | Detail |
|---|---|---|
| Moves from APFS to exFAT or FAT should always fail | From the code | The copy check includes modification time and permissions, which those volumes don't keep, so it reports changed contents. Checksum copies fail the same way. M04.06 is checked. |
| Inline rename can't change only the case | From the code | Renaming `a.txt` to `A.txt` on case-insensitive APFS throws `destinationExists`. Only `renameBatch` handles this. |
| Sockets and FIFOs block folder operations | From the code | The folder signature throws on them, so Trash, Rename and Move refuse the folder. Trash also hashes everything first, with no way to cancel. |

## Remote locations and sync

| Issue | Status | Detail |
|---|---|---|
| SFTP and FTP errors are never retried | From the code | `TransferQueue.isTemporary` recognizes only URL and POSIX errors, so their timeouts and lost connections fail at once and get the wrong hint. M07.07 and M07.11 are checked. |
| SFTP symlink loops recurse | From the code | `SFTPProvider` reports a link to a folder as a folder, so `ln -s .. up` recurses in sync and in folder copies until the path limit. M09 says links are skipped. |
| A folder-level Replace on S3 fails if the old folder has contents | From the code | Replace renames the old folder aside first, and S3 can't rename a folder with contents. Nothing is lost, and the job reports the error. |
| Folder copies from some S3 servers may report a false change | Not confirmed | Listings with millisecond dates, as on MinIO, are compared with whole-second dates, giving "changed while copied". |
| FTP servers without MLSD may lose dotfiles in folder copies | Not confirmed | The LIST fallback ignores `includeHidden`, so dotfiles are dropped from copies or overwritten with no prompt, and the check fails on the hidden temporary file. |

## Security

These came from the review on 2026-11-01. The threat is a malicious server, file or archive, not the person using the app.

| Issue | Status | Detail |
|---|---|---|
| Downloaded and extracted files have no quarantine mark | From the code | Nothing sets `com.apple.quarantine`, and `bsdtar` drops it when extracting (probed). Gatekeeper's first-launch check doesn't run on an app taken from an extracted archive or opened from a server. Fixing it means marking files at each place that writes them: extraction, `download()` and `ProviderTransfer`. |
| Release builds are ad-hoc signed and not notarized | From the code | `dev/Signing.xcconfig` sets `CODE_SIGN_IDENTITY = -`, and `scripts/create-dmg.sh` has no signing or notarization step. Users must bypass Gatekeeper and can't verify the DMG. The app also has no sandbox. This needs a Developer ID account. |
| Server listings have no size limit | From the code | An endless listing or folder tree can use up memory or hang a job (`SFTPProvider`, `FTPProvider`, `WebDAVProvider`). The caps on entries, bytes and depth haven't been chosen. |
| Dependencies are pinned to tags, not commits | From the code | `scripts/fetch-dependencies.sh` clones by tag and `.github/workflows/ci.yml` uses `actions/checkout@v4`. A moved tag would change what gets built. |
| A crash can leave a login secret in a temp file | From the code | `SSHCommand` and `FTPProvider` write 0600 files to the per-user temp folder and remove them after use. A crash skips that, and nothing removes stale files at launch. |
| A key-type mismatch might look like a new server | Not confirmed | `SFTPProvider.startupError` treats ssh's "No … host key is known" as an unknown host, which offers Trust. In a loopback test with OpenSSH 10.2, RSA known with ed25519 offered, and the reverse, both reported a changed key, which is refused. Other OpenSSH versions weren't tried. |

## Right-click menus not fully tested

Details are in [M15](milestones/M15-context-menus.md).

| Issue | Status | Detail |
|---|---|---|
| Remote menu behavior hasn't run against a server | From the code | Covers remote Open, Delete…, disabled Copy and disabled Open With. Docker wasn't running. |
| Eject from the sidebar menu hasn't been run | From the code | No volume was ejected to test it. |
| Running a service from the Services submenu hasn't been tried | Not confirmed | The submenu appears and lists copies of the app menu's items. |
| Turning a tag off with a color dot hasn't been tried | Not confirmed | Turning one on works. |
| The Contents limit of 1000 items hasn't been tried | Not confirmed | No folder that large was opened. |

## Rules that every milestone must follow

These break the rules in the [roadmap](README.md#rules-that-apply-to-every-milestone).

| Issue | Status | Detail |
|---|---|---|
| Some disabled commands give the wrong reason | From the code | File commands from `metadataUtilityCommands` in `AppDelegate` always say "Select local items in the browser first.", even when the app is busy, loading, or the command's own condition failed. |
| Some disabled buttons give no reason | From the code | Open SSH Session in `TerminalPanel`, the job controls in `TransferPanels`, and the selection-based buttons in the Tools and Editing settings and the Favorites manager. |
| Some long operations skip Activities | From the code | Checksum and folder sizes in `FileUtilityCoordinator`, Empty Trash, iCloud Remove Download, and opening a local archive. Opening a remote archive does use it. M05 may have accepted the first two, because it asks for their own progress and cancel. |
| Removing a tool or editor doesn't ask first | From the code | Remove in the Tools and Editing settings acts at once. Favorites asks for confirmation. |

## Differences between connection types

| Issue | Status | Detail |
|---|---|---|
| WebDAV doesn't refuse to delete the root | From the code | SFTP, FTP and S3 refuse. `WebDAVProvider.delete` sends `DELETE` with no check. Whether a root location can reach it hasn't been checked. |
| Symbolic links behave differently | From the code | SFTP lists a link as what it points to, so folder copies include the target and a link cycle can repeat the tree. FTP and local keep links, copies skip them, and double-clicking an FTP link does nothing. |
| Upload limits and progress stop early on S3 and WebDAV | From the code | Both write the upload to a temporary file first. The bandwidth limit, pause and progress apply to that step, not to the network upload. SFTP and FTP stream. |
| A server's refusal is reported as a macOS one | From the code | WebDAV 403 and SFTP's permission error use `FileSystemError.permissionDenied`, whose text points to macOS and System Settings. S3 has its own error. |
| A stalled FTP transfer can hang | From the code | curl gets only `--connect-timeout`. Jobs on the same server run one at a time, so it can block the others. WebDAV sets a timeout only on its first `OPTIONS` request. |
| Cancel can wait on SFTP | From the code | `SFTPProvider.send` checks for cancellation only before sending, so Cancel waits for the reply or for the connection to drop. FTP and the URLSession providers stop at once. |
| WebDAV doesn't fall back when `If-None-Match` is unsupported | From the code | S3 falls back on a 501 and WebDAV reports the operation as unsupported. Risk is low, because transfers write to unique temporary names. |
| Existence checks differ | From the code | FTP `move` treats any `stat` error as "absent", while S3 passes the error on. S3 `createDirectory` doesn't check at all. Callers check first. |
| Some certificate errors show raw system text | From the code | Certificate mapping is skipped on S3 `read` and on WebDAV `read` and `upload`. |
| WebDAV paths aren't fully normalized | From the code | FTP and SFTP collapse slashes. WebDAV `trimmed` strips only one trailing slash. |

## Settings

| Issue | Status | Detail |
|---|---|---|
| Unreadable saved settings are lost | From the code | `AppSettings` falls back to defaults when decoding fails, with no warning. The next save overwrites the stored favorites or tools. |

## Development

| Issue | Status | Detail |
|---|---|---|
| The right-click UI tests need Automation Mode and skip the sidebar | Seen | `FileTermUITests/ContextMenuUITests.swift` passes, but stops with "Timed out while enabling automation mode" until Automation Mode is allowed. It doesn't cover the sidebar yet. |
| `AppDelegate` does too many jobs | From the code | It has 2122 lines, and `makeCommands` mixes command tables with their handlers. |
| Location types are plain strings | From the code | `"local"` appears 59 times in 24 files, and `hasPrefix("archive:")` in 3 places. `isRemote` is also true for archive panes, so callers must run `rejectsArchiveEdit` first. |
| Remote and local handling repeats | From the code | `isRemote(pane)` branches recur through `FileOperationCoordinator`. |
| Code is duplicated | From the code | `JobReference` has 4 copies. The upload temporary-file loop and `httpDate` are in both S3 and WebDAV, and `normalized` is in both FTP and SFTP. |
| S3 depends on the WebDAV file | From the code | `S3Provider` calls `WebDAVProvider.isCertificateError`, and `HTTPByteReader` also lives in the WebDAV file. They belong in a shared HTTP file. |
