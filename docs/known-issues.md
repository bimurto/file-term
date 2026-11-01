# Known issues

Problems in the app as it stands on 2026-11-01. Missing features and untested protocols are in the [user guide's limits chapter](user-guide/13-limits-and-known-gaps.md), and unfinished work is in the [milestones](milestones/).

**Seen** means someone watched it happen in the running app. **From the code** means it comes from reading the code and hasn't been run. **Not confirmed** means it may not be a real bug.

## App behavior

| Issue | Status | Detail |
|---|---|---|
| A scrollbar sometimes appears under the toolbar | Seen | It moves the toolbar up about 8 points and comes and goes between launches. A build from before M15 does it too, so M15 didn't cause it. The cause isn't known. The toolbar asks for hidden scroll indicators in `BrowserView`. |
| Copy Dropbox Link shows on every local item without Dropbox | Seen | With no Dropbox set up, the right-click menu shows the item dimmed instead of hiding it. The earlier short menu used the same logic. |
| Share opens in the window's corner | From the code | `file.share` shows the picker at `.zero` of the window's content view, not at the clicked item. |
| Tags… doesn't open a tag editor of its own | From the code | `file.tags` calls the same `showInfo` as Get Info. |
| Only the first seven tags get a color dot | From the code | The rest are in File › Tags. |
| A row in an earlier column offers only Open | Seen | In column view, that row isn't in the current folder, so the commands can't act on it. |

## Can lose data

Fix these first, in this order.

| Issue | Status | Detail |
|---|---|---|
| Sync deletes the hidden and excluded contents of an orphan folder | From the code | An orphan folder is one delete row, but hidden, excluded and symlinked children were never scanned, and they go with it. Remote deletes are permanent. The code is in `SyncAnalyzer` and `FileOperationCoordinator+Sync`. |
| Quitting deletes unsaved remote edits | From the code | `removeTemporaryDownloads` runs at every quit. After a failed upload or Stop Watching, that removes the only copy of the edits with no warning. M11 says Stop Watching keeps the local copy. |
| A remote move can delete its only copy | From the code | With a connection path of `/docs/`, the same-folder guard in `ProviderTransfer.move` compares `/docs` to `/docs/` and passes. Replace then overwrites the file with itself and the source is deleted. |
| Replace can lose the local destination | From the code | `LocalFileOperations` moves the destination to the temporary folder before copying. After a cancel or a full disk, it isn't put back. Undo lasts only for the session. |
| Remote replace isn't safe | From the code | `ProviderTransfer` deletes the target before moving the temporary file into place, and deletes the temporary file too if that move fails. Remote Edit on SFTP also drops the execute permission, replaces a symlink with a regular file and overwrites server changes without checking. |

## File operations

| Issue | Status | Detail |
|---|---|---|
| Moves from APFS to exFAT or FAT should always fail | From the code | The copy check includes modification time and permissions, which those volumes don't keep, so it reports changed contents. Checksum copies fail the same way. M04.06 is checked. |
| Inline rename can't change only the case | From the code | Renaming `a.txt` to `A.txt` on case-insensitive APFS throws `destinationExists`. Only `renameBatch` handles this. |
| Every copy leaves a recovery folder | From the code | A successful copy or Duplicate leaves an empty `.FileTerm-recovery-<uuid>` in the destination, and Sync picks it up when hidden items are on. Undoing a copy keeps its data there. |
| A failed batch rename isn't rolled back | From the code | If a later step fails, for example a name taken since the preview, swapped files stay under hidden `.fileterm-rename-<uuid>` names. |
| Sockets and FIFOs block folder operations | From the code | The folder signature throws on them, so Trash, Rename and Move refuse the folder. Trash also hashes everything first, with no way to cancel. |
| A remote Copy to as… name isn't validated | From the code | An empty name targets the folder itself, and Replace then deletes it. Local copies check the name. |

## Remote locations and sync

| Issue | Status | Detail |
|---|---|---|
| SFTP and FTP errors are never retried | From the code | `TransferQueue.isTemporary` recognizes only URL and POSIX errors, so their timeouts and lost connections fail at once and get the wrong hint. M07.07 and M07.11 are checked. |
| SFTP symlink loops recurse | From the code | `SFTPProvider` reports a link to a folder as a folder, so `ln -s .. up` recurses in sync and in folder copies until the path limit. M09 says links are skipped. |
| WebDAV names are decoded twice | From the code | `a%20b.txt` is listed as `a b.txt`, so operations hit the wrong file or fail. |
| Sync treats names that differ only in case as separate items | From the code | SFTP `Foo` and `foo` synced to APFS are two adds, and the second silently replaces the first. A destination symlink is also replaced under an add row. |
| Two Edits during a download make two copies | From the code | `RemoteEditCoordinator` registers the session only after the download, so the copies overwrite each other. Guide chapter 10 says editing again reopens the existing copy. |
| Folder copies from some S3 servers may report a false change | Not confirmed | Listings with millisecond dates, as on MinIO, are compared with whole-second dates, giving "changed while copied". |
| FTP servers without MLSD may lose dotfiles in folder copies | Not confirmed | The LIST fallback ignores `includeHidden`, so dotfiles are dropped from copies or overwritten with no prompt, and the check fails on the hidden temporary file. |

## Right-click menus not fully tested

Details are in [M15](milestones/M15-context-menus.md).

| Issue | Status | Detail |
|---|---|---|
| Remote menu behavior hasn't run against a server | From the code | Covers remote Open, Delete…, disabled Copy and disabled Open With. Docker wasn't running. |
| Eject from the sidebar menu hasn't been run | From the code | No volume was ejected to test it. |
| Running a service from the Services submenu hasn't been tried | Not confirmed | The submenu appears and lists copies of the app menu's items. |
| Turning a tag off with a color dot hasn't been tried | Not confirmed | Turning one on works. |
| The Contents limit of 1000 items hasn't been tried | Not confirmed | No folder that large was opened. |

## Development

| Issue | Status | Detail |
|---|---|---|
| The right-click UI tests have never run | Seen | `FileTermUITests/ContextMenuUITests.swift` stopped with "Timed out while enabling automation mode". It may need approval on screen. It also doesn't cover the sidebar yet. |
