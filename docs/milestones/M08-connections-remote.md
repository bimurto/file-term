# M08 — Connections & remote locations

**Goal:** Add remote providers behind the M00.02 filesystem abstraction, with a connection form for each protocol.
**Ref:** Guide › Ch. 6 Connections and remote locations.

## Items

### M08.01 Connection form
- **Scope:** Connect toolbar button and Go › Connect. A protocol picker. Basic fields: Server, Username, Password, Add to Favorites.
- [ ] Opening or editing the form never connects. A connection starts only when Connect is pressed.
- [ ] Credentials are stored in the system keychain, not in plain text.

### M08.02 Advanced fields
- **Scope:** Show Advanced: Port, Path, Local Path, Base URL, Text Encoding, Note, Color Label.
- [ ] Which fields appear depends on the protocol (configured per protocol).
- [ ] Base URL is passed to Copy URL/Open URL (M05.08).

### M08.03 SFTP
- [ ] Default port 22. Password and SSH key authentication *(key auth is vendor-documented)*.
- [ ] Host key verification prompt on first connect.
- [ ] Built-in terminal extension (M06.10): offer an explicit SSH session for the connected SFTP host and path. Never inject local `cd` commands into remote sessions; honor host-key verification and credential handling.

### M08.04 FTP & FTP-TLS
- [ ] Passive and active modes. Explicit TLS for FTP-TLS.

### M08.05 WebDAV & WebDAV HTTPS
- [ ] Rejects non-WebDAV endpoints with a clear error (an ordinary website URL is not a WebDAV endpoint).

### M08.06 Amazon S3 & Backblaze B2
- [ ] Bucket and object listing, with prefixes shown as folders.
- [ ] Access and permission errors are reported for each bucket.

### M08.07 Google Drive, OneDrive, Dropbox
- [ ] OAuth sign-in in the browser that returns to the app.
- [ ] Tokens refresh automatically.

### M08.08 Rackspace Cloud Files
- [ ] Separate protocol entry with its own account fields.

### M08.09 SMB, AFP, NFS
- [ ] Mount or connect through OS networking, then browse with the local provider.
- [ ] AFP is marked as legacy, or hidden when the OS doesn't support it.

### M08.10 VNC handoff
- [ ] Opens the system screen-sharing client. It does not open as a file-browsing pane.

### M08.11 Remote pane placement
- [ ] Settings › General › Open remote connections in (default: Right Pane) is applied.

### M08.12 Text encoding
- [ ] View › Text Encoding re-decodes remote file names on the fly.

### M08.13 Multiple connections & server-to-server copy *(vendor-documented)*
- [ ] Several connections can be open at the same time, in different panes and tabs.
- [ ] Copying between two remote locations streams data through the app using the M07 queue.

### M08.14 Go › Connections menu
- [ ] Lists open and saved connections, and fills the submenu stubbed in M01.08.
