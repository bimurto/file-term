# 6 Connections and remote locations

## What's available

| Protocol | Status | Test result against a server |
|---|---|---|
| SFTP, FTP, FTP-TLS, WebDAV, Amazon S3 | Available | Passed |
| Backblaze B2 | Available | Passed against a stand-in server, not Backblaze's own service |
| SMB | Available | Passed |
| NFS, WebDAV (HTTPS) | Available | Not run |
| AFP (Legacy) | Available | Not run. macOS 26 has no AFP client. |
| VNC | Available | Not applicable. It opens screen sharing, not a file pane. |
| Google Drive, OneDrive, Dropbox | **Not built** | None |
| Rackspace Cloud Files | **Not built** | None |

The four unbuilt protocols appear in the Protocol menu, but you can't connect with them. The form says they're coming, and Connect reports that they aren't available yet.

Dropbox's Copy Dropbox Link command is separate, and it does work with a Dropbox folder on your Mac. See [chapter 12](12-additional-capabilities.md#dropbox-links).

## Connection form

1. Choose Go › Connect… or click the globe button in the toolbar.
2. Choose a Protocol.
3. Fill in the server and account fields. Their labels change with the protocol.
4. Optional: tick Add to Favorites to save the connection under Go › Connections.
5. Click Connect, or click Save to add it to Go › Connections without connecting.

Opening or editing the form never connects. Only the Connect button does. Passwords are stored only in your keychain. When you edit a saved connection, leaving the password empty keeps the saved one.

Settings › General › Open remote connections in chooses the pane: Right Pane by default, Left Pane or Active Pane. Right Pane switches a single-pane window to side by side.

## Advanced connection fields

Click Show Advanced. The fields depend on the protocol:

- **Port:** blank uses the protocol's default.
- **Path:** the folder to open first. For object storage this is Bucket / Prefix.
- **Base URL:** the public web address of the connection's root. It enables File › Copy URL and Open URL. SMB, AFP, NFS and VNC don't have this field.
- **Text Encoding:** for FTP, FTP-TLS and SFTP.
- **Private Key:** for SFTP.
- **Transfer Mode:** for FTP and FTP-TLS. Passive is the default.
- **Allow invalid certificate:** for FTP-TLS.
- **Region:** for object storage.

Local Path, Note and Color Label are saved with the connection, but FileTerm doesn't use them for anything yet.

## SFTP, FTP and FTP-TLS

**SFTP** uses your Mac's `ssh`, so your agent, default keys and SSH config apply.

- The password field takes a password or a key passphrase.
- The first time you connect to a server, an alert shows its key fingerprints. Cancel is the default. Choose to trust the server only if the fingerprints match.
- A changed server key stops the connection, and the app has no override.
- Keyboard-interactive and two-factor logins beyond a single answer aren't supported.
- An empty Path opens your login folder.

**FTP and FTP-TLS:** `/` means the folder the server opens after login, so you can't browse above it. FTP-TLS uses explicit TLS, or implicit TLS on port 990. A self-signed certificate is refused until you tick Allow invalid certificate. Each action logs in again, so large folder trees list slowly.

## WebDAV and WebDAV HTTPS

Enter a bare host name in Server, and put any folder in Path. Connect checks that the server really speaks WebDAV, so an ordinary website is rejected with a clear message. Basic and Digest logins work. Self-signed certificates aren't trusted.

## Amazon S3 and Backblaze B2

The fields are Access Key ID and Secret Access Key for S3, and Application Key ID and Application Key for B2.

- **Endpoint:** S3 defaults to Amazon when empty. B2 needs its `s3.<region>.backblazeb2.com` endpoint. Other S3-compatible servers work too, and `http://host` is accepted for local ones.
- **Path:** `bucket/prefix`. With no bucket, the root lists your buckets. If your key can't list buckets, enter the bucket in Path.

Files over 5 GB are refused. Folders are only name prefixes, so only an empty folder can be renamed or moved. Buckets can't be created or deleted.

## Google Drive, OneDrive, Dropbox and Rackspace

These connections aren't built. Sign-in for Google Drive, OneDrive and Dropbox and the Rackspace account fields don't exist yet, so don't plan on using them.

## SMB, AFP and NFS

These mount through macOS and then browse like a local folder, so local commands work on them. AFP is marked as legacy, and on a Mac with no AFP client the mount reports an error. A share's tab returns to Home when it unmounts.

## VNC

VNC opens the macOS screen-sharing app. It doesn't open a pane and can't list or transfer files.

## Working in a remote pane

These work on SFTP, FTP, FTP-TLS, WebDAV, S3 and B2 connections:

- Open, which downloads a temporary copy. Temporary copies are removed when you quit.
- Copy to…, Copy to as…, Move to…, Paste and Move Items Here.
- Rename, New Folder, Edit, Find and Quick Select.

These work differently or not at all:

- **Move to Trash** is named Delete… here. It and ⌥⌘⌫ permanently delete after a confirmation. A server has no Trash.
- Duplicate, New File, New Folder With Selection, Open With and Undo are local only.
- ⌘C doesn't put remote items on the clipboard, and remote items can't be dragged out of a pane. Use Copy to… instead.
- Preview, Get Info, Quick Look and the other commands in [chapter 5](05-metadata-preview-and-utilities.md) are local only.
- Tools run only if you've turned on Enable for remote files ([chapter 10](10-favorites-tools-editing-and-git.md#custom-command-tools)).
- Copies across locations don't keep permissions, ownership, extended attributes or modification dates. Symbolic links and special files are skipped.

## Encoding and multiple connections

View › Text Encoding changes how file names are read on the active FTP, FTP-TLS or SFTP connection. The choices are UTF-8, ISO-8859-1, Windows-1252, Shift_JIS, EUC-KR and GB18030.

- The change applies right away and only to the open connection. The saved value in the form stays the same.
- A name that isn't valid in the chosen encoding shows `�` and can't be used until you pick an encoding that fits.

You can have several connections open at once, in different panes and tabs. Copying between two servers streams the data through your Mac.

## Open connections and saved connections

Go › Connections lists:

- Open connections, which reveals that connection in a pane.
- Saved connections, which connects and opens it.
- Edit Saved Connection, a submenu that opens the form. The form has a Delete button there.
- Disconnect, a submenu of open connections.

Connections don't reconnect after you quit and reopen FileTerm.
