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
- [ ] Default port 22. Password and SSH key authentication *(key auth is vendor-documented)*.
- [ ] Host key verification prompt on first connect.
- [ ] Built-in terminal extension (M06.10): offer an explicit SSH session for the connected SFTP host and path. Never inject local `cd` commands into remote sessions; honor host-key verification and credential handling.

### M08.04 FTP & FTP-TLS
- [ ] Passive and active modes. Explicit TLS for FTP-TLS.

### M08.05 WebDAV & WebDAV HTTPS
- [x] Rejects non-WebDAV endpoints with a clear error (an ordinary website URL is not a WebDAV endpoint).

### M08.06 Amazon S3 & Backblaze B2
- [ ] Bucket and object listing, with prefixes shown as folders.
- [ ] Access and permission errors are reported for each bucket.

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
- [ ] View › Text Encoding re-decodes remote file names on the fly.

### M08.13 Multiple connections & server-to-server copy *(vendor-documented)*
- [x] Several connections can be open at the same time, in different panes and tabs.
- [ ] Copying between two remote locations streams data through the app using the M07 queue.

### M08.14 Go › Connections menu
- [x] Lists open and saved connections, and fills the submenu stubbed in M01.08.

## Tickets

M08 ships in tickets, implemented in order. Protocols not yet built are listed in the connection
form; pressing Connect names the ticket that adds them.

| Ticket | Covers | Status |
|---|---|---|
| T1 Connection foundation + OS-networked mounts | M08.01, .02, .09, .10, .11, .14 | Done |
| T2 Remote provider plumbing + WebDAV | M08.05, .13 (multiple connections) | Done |
| T3 Cross-provider copy through the M07 queue | M08.13 (server-to-server) | Open |
| T4 Amazon S3 & Backblaze B2 | M08.06 | Open |
| T5 FTP & FTP-TLS | M08.04 | Open |
| T6 SFTP, host-key prompt, SSH terminal | M08.03 | Open |
| T7 Text encoding | M08.12 | Open |
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
