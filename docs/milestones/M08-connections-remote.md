# M08 — Connections & remote locations

**Goal:** Add remote providers behind the M00.02 filesystem abstraction, with a connection form for each protocol.
**Ref:** Guide › Ch. 6 Connections and remote locations.

## Items

### M08.01 Connection form
- **Scope:** Connect toolbar button and Go › Connect. A protocol picker. Basic fields: Server, Username, Password, Add to Favorites.
- [x] Opening or editing the form never connects. A connection starts only when Connect is pressed.
- [x] Credentials are stored in the system keychain, not in plain text.

### M08.02 Advanced fields
- **Scope:** Show Advanced: Port, Path, Local Path, Base URL, Text Encoding, Note, Color Label.
- [x] Which fields appear depends on the protocol (configured per protocol).
- [x] Base URL is passed to Copy URL/Open URL (M05.08).

### M08.03 SFTP
- [x] Default port 22. Password and SSH key authentication *(key auth is vendor-documented)*.
- [x] Host key verification prompt on first connect.
- [x] Built-in terminal extension (M06.10): offer an explicit SSH session for the connected SFTP host and path. Never inject local `cd` commands into remote sessions; honor host-key verification and credential handling.

### M08.04 FTP & FTP-TLS
- [x] Passive and active modes. Explicit TLS for FTP-TLS.

### M08.05 WebDAV & WebDAV HTTPS
- [x] Rejects non-WebDAV endpoints with a clear error (an ordinary website URL is not a WebDAV endpoint).

### M08.06 Amazon S3 & Backblaze B2
- [x] Bucket and object listing, with prefixes shown as folders.
- [x] Access and permission errors are reported for each bucket.

### M08.07 Google Drive, OneDrive, Dropbox
- [ ] OAuth sign-in in the browser that returns to the app.
- [ ] Tokens refresh automatically.

### M08.08 Rackspace Cloud Files
- [ ] Separate protocol entry with its own account fields.

### M08.09 SMB, AFP, NFS
- [x] Mount or connect through OS networking, then browse with the local provider.
- [x] AFP is marked as legacy, or hidden when the OS doesn't support it.

### M08.10 VNC handoff
- [x] Opens the system screen-sharing client. It does not open as a file-browsing pane.

### M08.11 Remote pane placement
- [x] Settings › General › Open remote connections in (default: Right Pane) is applied.

### M08.12 Text encoding
- [x] View › Text Encoding re-decodes remote file names on the fly.

### M08.13 Multiple connections & server-to-server copy *(vendor-documented)*
- [x] Several connections can be open at the same time, in different panes and tabs.
- [x] Copying between two remote locations streams data through the app using the M07 queue.

### M08.14 Go › Connections menu
- [x] Lists open and saved connections, and fills the submenu stubbed in M01.08.

## Tickets

M08 ships in tickets, implemented in order. Protocols not yet built are listed in the connection
form; pressing Connect names the ticket that adds them.

| Ticket | Covers | Status |
|---|---|---|
| T1 Connection foundation + OS-networked mounts | M08.01, .02, .09, .10, .11, .14 | Done |
| T2 Remote provider plumbing + WebDAV | M08.05, .13 (multiple connections) | Done |
| T3 Cross-provider copy through the M07 queue | M08.13 (server-to-server) | Done |
| T3b Remote move, delete, rename, new folder, paste; open remote files via temp download | Follow-up to T3 | Done (drag and drop left out) |
| T4 Amazon S3 & Backblaze B2 | M08.06 | Done |
| T5 FTP & FTP-TLS | M08.04 | Done |
| T6 SFTP, host-key prompt, SSH terminal | M08.03 | Done |
| T7 Text encoding | M08.12 | Done |
| T8 Rackspace Cloud Files | M08.08 | Open |
| T9 Google Drive, OneDrive, Dropbox | M08.07 | Open |

## T1 notes

- Connect… (Go menu and toolbar) opens the form. Opening or editing it never connects; only
  Connect, or choosing a saved favorite in Go › Connections, does.
- Passwords are stored only in the keychain (`com.fileterm.connection`, account = profile ID).
  Saved profiles in Defaults contain no password. Editing with an empty password keeps the saved one.
- Advanced fields per protocol are configured in `ConnectionKind.advancedFields`.
- SMB, AFP (marked legacy) and NFS mount through NetFS and are browsed with the local provider.
  VNC opens the system screen-sharing client and no pane.
- Settings › General › Open remote connections in (default Right Pane) picks the pane; Right
  switches a single-pane window to side by side.
- Copy URL / Open URL use the connection's Base URL for items under its mount.
- Go › Connections lists open connections, saved favorites, Edit and Disconnect items.
- Not done in T1: connection state is not restored across launches; an AFP entry is not hidden
  on systems without AFP support (the mount reports the error).

## T2 notes

- `ProviderRegistry` is shared by every pane and tab; connections register their provider there.
  Later protocols (S3, FTP, SFTP) plug in the same way through `ValidatingProvider`.
- WebDAV browses and reads. Provider-level write, move and delete exist but are not reachable from
  the UI: remote panes keep copy, rename and delete disabled until T3.
- Connect validates the server first (OPTIONS must send a `DAV` header and PROPFIND must return a
  207 multistatus). Ordinary websites are rejected with a clear message; a wrong password is
  reported as an authentication error.
- Basic and Digest authentication are supported. Self-signed certificates are not trusted.
- `read` pulls the body through `URLSession.bytes`, one byte at a time into 64 KiB chunks. Fine for
  browsing and preview; T3 may need a faster path for large transfers.
- Remote tabs fall back to Home when a session is restored; reconnecting is not restored.
- Several connections at once is covered by tests with stand-in providers. Copying between two
  remote locations remains open (T3).

## T3 notes

- Copy to… and Copy to as… work between any two locations (local, WebDAV, and later protocols).
  Move, Duplicate, Rename, Trash, New Folder and Paste remain local-only; the disabled-command
  reason says so. They are tracked as T3b.
- `ProviderTransfer` streams chunk by chunk through the M07 queue, so Activities show progress,
  speed and ETA, Pause/Cancel work, and the Replace/Merge policies, retry and verification apply.
- Each file is written to a hidden `.<name>.fileterm-<id>.part` sibling and moved into place when
  complete. A crash mid-copy can leave a `.part` file behind; cancel and failure remove it.
- Replace uploads first, then deletes the old item and moves the new one in, so a failed upload
  never loses the original. Folder conflicts offer Merge, Keep Both, Skip and Stop (no Replace).
- Upload and download limits apply by direction. Remote to remote ("relay") consumes both budgets.
  Copies to the same server run one at a time; copies to different servers run together.
- A failure after at least one item was committed hides Retry (same rule as local copies).
- Not preserved across locations: permissions, ownership, extended attributes and modification
  dates. Symbolic links and special files are skipped and counted as skipped.
- Cross-provider copies add no undo entry.

## T3b notes

- In a remote pane these now work: Open, Rename, New Folder, Move to…, Move Items Here, Paste
  (local files from the clipboard) and Move to Trash. Duplicate, New File, New Folder With
  Selection, Open With and Undo stay local-only.
- Move to Trash on a remote item is a permanent delete after a confirmation. It cannot be undone.
- Move to… involving a remote side copies first, then deletes the sources. The sources are kept
  if any item was skipped, failed or the copy was stopped. Moving into the same folder is refused.
  A local source moved to a server is deleted permanently, not trashed.
- Rename checks that the name is free. In S3/B2 only an empty folder can be renamed or moved (a
  folder is only a key prefix); one with items must be copied. WebDAV renames folders natively.
- `FILETERM_LIVE=1 swift test --disable-sandbox --filter LiveServerTests` runs the edit and move
  checks against the servers in `dev/docker-compose.yml`.
- Open downloads the file to a temporary folder as a queue job and opens it with the default
  application. Edits are not uploaded back. The temporary folder is removed on quit.
- Not done: drag and drop to or from remote panes (the app has no drop targets yet), copying
  remote items to the clipboard.

## T5 notes

- `FTPProvider` runs the system `/usr/bin/curl`, one process and connection per operation.
  Network.framework cannot upgrade an open connection to TLS, which explicit FTP-TLS needs; curl
  already handles passive, active and both TLS modes. Cost: each action logs in again, so big
  folder trees list more slowly than with a persistent connection.
- The user name and password are written to a private temporary curl config (mode 0600, deleted
  when the process ends), never passed as arguments, so `ps` does not show them.
- Advanced › Transfer Mode picks passive (default) or active. FTP-TLS uses explicit TLS
  (`AUTH TLS`); port 990 switches to implicit `ftps://`. A self-signed certificate is refused
  with a message until Allow invalid certificate is ticked (FTP-TLS only).
- Paths are relative to the login folder; "/" is the folder the server opens after login, so
  folders above it cannot be browsed.
- Listings use MLSD, falling back to Unix or DOS `LIST` when the server refuses it. Times from
  `LIST` carry no zone and are read as UTC.
- FTP cannot refuse an overwrite itself, so a write first checks the destination; another client
  could still create it in between.
- File names follow the connection's Text Encoding (T7); UTF-8 by default.
- Live checks: `FILETERM_LIVE=1 swift test --disable-sandbox --filter LiveFTPTests` against the
  `ftp` service in `dev/docker-compose.yml` (about 80 seconds; that image takes two seconds per
  login). Active mode is expected to fail inside Docker.

## T4 notes

- One `S3Provider` serves Amazon S3, Backblaze B2 (through its S3-compatible API) and other
  S3-compatible servers such as MinIO. Requests use AWS Signature V4 (`S3Signer`, checked against
  the examples published by AWS) and path-style addressing (`https://endpoint/bucket/key`).
- Endpoint: a bare host uses https; `http://host` is accepted for local servers. S3 defaults to
  Amazon when empty; B2 needs its `s3.<region>.backblazeb2.com` endpoint. The Advanced Region field
  falls back to the region in the host name, then us-east-1. Credentials are the access key ID and
  secret (B2: application key ID and key), the secret in the keychain.
- Path takes `bucket/prefix`. With no bucket the root lists buckets. Restricted keys that cannot
  list buckets are told to enter the bucket in Path.
- Permission errors name the bucket they belong to. A bucket in another region is retried once in
  its own region, which is remembered.
- Folders are key prefixes; New Folder (inside Copy) writes a zero-byte `prefix/` marker.
  Buckets cannot be created or deleted.
- Uploads and server-side copies are single requests, so files over 5 GB are refused (multipart
  is follow-up work). A move is CopyObject plus DeleteObject.
- Uploads use `If-None-Match: *`; stores that do not support it (HTTP 501) fall back to a HEAD
  check, which is not atomic.
- Not covered: presigned URLs, object versions, storage classes, ACLs, and public-URL generation
  beyond the connection's Base URL. Reads on a bucket in an unseen region fail until a listing has
  discovered its region.

## T6 notes

- `SFTPProvider` runs the system `/usr/bin/ssh -s sftp`: one long-lived process per connection,
  with a small SFTP version 3 client over its pipes (`SFTPPacket`). ssh does the transport, keys,
  the agent and `~/.ssh/config`. macOS `curl` has no SFTP, so the T5 approach did not apply.
- Sign-in: Advanced › Private Key picks a key file (`-i`, `IdentitiesOnly`); without one, ssh uses
  the agent and default keys. The password field holds the password or the key passphrase. It
  reaches ssh through a one-shot `SSH_ASKPASS` script (0600 secret in a 0700 temporary folder),
  deleted as soon as SFTP starts or the process ends, and never appears in `ps`. With no
  password, ssh runs in `BatchMode` and cannot hang on a prompt.
- Host keys are always checked strictly. ssh trusts `~/.ssh/known_hosts` plus FileTerm's own
  `~/Library/Application Support/FileTerm/known_hosts`; only the second is ever written. A new
  server stops the connection, `ssh-keyscan` fetches its keys, and an alert shows the SHA256
  fingerprints (Cancel is the default button). Trust saves all of them and retries once.
- A changed key is a hard error naming both files; there is no override in the app.
- Paths are absolute server paths. An empty Path opens the login folder (`REALPATH .`); a relative
  one is relative to it (`ValidatingProvider.resolveRoot`, new, default unchanged for the other
  protocols). Links to folders and files are shown as what they point to; deleting a link removes
  the link only.
- Writes open with `CREAT|EXCL`, so an existing file is refused by the server. A failed or
  cancelled write removes the partial file.
- Requests are sequential 32 KiB reads and writes, so large transfers are limited by round-trip
  time. Pipelining is follow-up work.
- Open SSH Session (panel menu, View › Terminal): types an explicit `ssh -t … 'cd <folder> && exec
  "$SHELL" -l'` into the local shell, only when it is idle at a prompt. ssh asks for any password
  itself. Folder sync stays paused for the remote pane, and while ssh runs the shell is busy and
  not in the foreground, so no local `cd` reaches the remote shell. A server that confines SFTP
  to a jail, or has no shell for the account, may not match or accept the session.
- Tests: `SFTPProviderTests` run against macOS's own `/usr/libexec/sftp-server` through a
  stand-in for ssh. `FILETERM_LIVE=1 swift test --disable-sandbox --filter LiveSFTPTests` uses
  the `sftp` service in `dev/docker-compose.yml` (password login, host-key flow, edits). Key
  login needs an authorized key mounted into that container and was not exercised live.
- Not covered: keyboard-interactive or two-factor prompts beyond a single answer, ssh
  `ProxyJump` passwords, connection state across launches.

## T7 notes

- Scope: FTP, FTP-TLS and SFTP, the kinds that show the Text Encoding field. WebDAV and S3 names
  are UTF-8 in URLs by specification. The encodings are `TextEncoding.names` (UTF-8, ISO-8859-1,
  Windows-1252, Shift_JIS, EUC-KR, GB18030), mapped through
  `CFStringConvertIANACharSetNameToEncoding`.
- The form's value is the starting encoding. View › Text Encoding (enabled when the active pane
  is on an FTP or SFTP connection) switches the open connection without reconnecting: the provider
  changes encoding, every tab on that connection has its current path and history re-read from the
  same server bytes, and the tab is re-listed. The switch is not saved to the favorite.
- A path the old encoding had already lost (it contains U+FFFD) cannot be rebuilt; that tab moves
  to the connection's root.
- Decoding falls back to lossy UTF-8 when the bytes are not valid in the chosen encoding, and
  encoding falls back to UTF-8 for characters the encoding cannot hold. A name that is invalid in
  the chosen encoding therefore shows `�` and cannot be addressed until another encoding fits.
- FTP: URLs percent-encode each path part from its bytes in the chosen encoding. FTP commands
  (`RNFR`, `RNTO`, `MKD`, `DELE`, `RMD`) moved from curl arguments, which can only carry UTF-8,
  into the private 0600 curl config as raw bytes. Backslash and quote are escaped on the encoded
  bytes: in Shift_JIS `0x5C` can be the second byte of a character.
- SFTP: only names and paths use the encoding. Status messages and ssh/curl error text stay UTF-8.
- Tests: `TextEncodingTests`, `SFTPPacketTests`, `FTPProviderTests` and
  `ConnectionCoordinatorTests` cover the byte handling and the live switch. APFS cannot hold a
  non-UTF-8 name, so the end-to-end check is `namesFollowTheTextEncoding` in `LiveFTPTests` and
  `LiveSFTPTests`. It needs Docker, which was off, so it has not been run.
