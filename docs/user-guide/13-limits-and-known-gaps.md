# 13 Limits and known gaps

This chapter lists what isn't built, what wasn't verified, and what's still open. It comes from the project's milestone documents and from reading the code.

## Not built

| Feature | State |
|---|---|
| Google Drive, OneDrive and Dropbox connections | Listed in the connection form, but you can't connect. There's no browser sign-in and no token refresh. |
| Rackspace Cloud Files connection | Listed in the connection form, but you can't connect. |
| Sync Favorites to iCloud | The setting is saved, but nothing syncs. |
| Resuming a partial transfer after a restart or interruption | Pause and Resume work within a session only. The Resume policy control is grayed out. |
| Retrying only the unfinished items of a partly finished job | Retry is unavailable once part of a job has taken effect. |
| Previewing remote files | The Preview panel is local only. Open downloads a temporary copy instead. |
| Notifications | The first-run window can request permission, but FileTerm doesn't send any. |
| Other interface languages | English only. See below. |
| Extra tool placeholders | None have been defined beyond the six in [chapter 10](10-favorites-tools-editing-and-git.md#tool-placeholders). |

## Remote protocol test results

Each protocol was to be tested for connect, list, upload, download, rename and delete against a test server.

| Protocol | Result | Note |
|---|---|---|
| SFTP, FTP, FTP-TLS, WebDAV, Amazon S3 | Passed | Against local test servers |
| Backblaze B2 | Passed | Against a stand-in server, not Backblaze's own service |
| SMB | Passed | Through a real macOS mount |
| NFS | Passed | Through a real macOS mount, against the NFS server built into macOS |
| WebDAV over HTTPS | Passed | Against a local test server with its own certificate. An untrusted certificate is refused. |
| AFP | Not run | No test server, and macOS 26 has no AFP client |
| VNC | Not applicable | Screen sharing can't list or transfer files |
| Rackspace, Google Drive, OneDrive, Dropbox | Not run | Not built |

Also not exercised live: logging in to SFTP with a key, and file names in non-UTF-8 encodings on a real server. Connections don't reconnect after a restart.

## Performance with very large folders

Measured on a folder of 100,000 empty files in a release build:

| Measure | Result | Target |
|---|---|---|
| List and prepare one pane | 5.2 s | Under 6 s |
| Longest main thread stall while listing | 0.12 s | 0.25 s |
| App settles with both panes on that folder | About 11 s | None set |
| Longest main thread stall copying 1 GB | 0.003 s | 0.25 s |

Not measured:

- How smoothly a list that long scrolls.
- Selecting everything in a folder that large. Open With asks macOS about each selected item, so expect that to be slow.

A folder of 100,000 subfolders is slower still, because folders also ask Spotlight for their last opened date.

## Behavior to watch for

- **Log redaction** matches common credential shapes, so it can't catch every secret. Read a log before sharing it.
- **Rubber-band selection** covers only icons currently laid out, and the view doesn't scroll as you drag.
- **Return** opens items only in list view. It isn't wired in icon and column views.
- **Saved fields that do nothing yet.** A connection's Local Path, Note and Color Label are stored but not used.
- **Archives opened as folders** show the path inside the archive in the path bar, and a remote archive is fully downloaded first.
- **Compress and Extract** aren't in Undo, and neither are sync jobs, copies across locations or anything done on a connection.

## Language support

Interface text and menus can look up translations, and the English strings are extracted. Alert text, command titles, and messages built in code are still hard-coded, so the app can't be fully translated yet.

## Not driven by hand

Automated tests cover the engines behind these features, but the milestone notes say the dialogs and flows weren't run by hand on a desktop, or weren't run against the real service:

- The Sync, Batch Rename and archive dialogs. Empty Trash and the delete dialogs. The App Deleter.
- The tool output window and toolbar button. The remote upload prompt with a real editor. External terminal apps. The Git commit prompt and menu.
- Quick Look and slideshow in full screen, audio and video formats, physical printing, changing owner or group with privileges, and read-only volumes.
- A macOS Service or Share actually running. The tests confirm only that the menus list them.
- iCloud Drive against a real account, Dropbox links against the real service, the default file viewer changing the real system setting, and favorites import with a real file.

Automated tests do run the copy, rename and sync practice scenarios from [chapter 12](12-additional-capabilities.md) end to end.

## Privacy notes

FileTerm has no crash reporter and writes no log file. Logs stay in memory until you copy or export them. See [chapter 7](07-transfers-activities-and-logs.md#what-logs-leave-out).
