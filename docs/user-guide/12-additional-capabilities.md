# 12 Additional capabilities

## Workspaces

A workspace saves your open windows, with their tabs, panes and locations, under a name.

1. Arrange your windows.
2. Choose Go › Workspaces › Save Workspace….
3. Type a name and click Save. Using an existing name asks whether to replace it.

To load one, choose it in Go › Workspaces, in the sidebar's Workspaces section, or in Quick Open. Loading opens the workspace's windows and closes the ones that were open. If that would end terminal sessions, FileTerm asks first.

To delete a workspace, right-click it in the sidebar and choose Delete Workspace. A remote tab can't reconnect when a workspace loads, as with session restore.

## iCloud Drive files

The sidebar's iCloud section opens iCloud Drive when that folder exists on your Mac. Favorites can also point to it.

- File › iCloud › Download Now downloads selected items that aren't on this Mac yet.
- File › iCloud › Remove Download removes only the copy on this Mac, after a confirmation. The file stays in iCloud Drive, and you can download it again.

The right-click menu has the same commands. Neither one deletes the file from iCloud. These commands weren't tested against a real iCloud account.

## Dropbox links

File › Copy Dropbox Link puts a shared link for one selected item on the clipboard. It also appears in the right-click menu. It works on files in a Dropbox folder on your Mac. It isn't a Dropbox connection, which isn't built.

It needs an access token:

1. Create a token with the `sharing.write` scope in the Dropbox App Console.
2. Paste it in Settings › Integrations › Dropbox.
3. Click Save Token.

The token is stored in your keychain and sent only to Dropbox. Such tokens can be short-lived, so if Dropbox rejects yours, enter a new one. This feature wasn't tested against the real Dropbox service.

## Default file viewer

Settings › Integrations › Use FileTerm for Reveal and Show in Finder makes FileTerm handle those requests from other apps. It's off by default, and apps pick up the change when they next start.

- A folder opens as itself, and a file opens in its folder with the file selected.
- It doesn't replace the system Open and Save dialogs.
- It doesn't change Finder, the desktop, or double-clicking a folder in Finder.
- Apps that always call Finder directly are unaffected.

Turn it off to go back. FileTerm restores the viewer that was set before. If FileTerm can't start, run this in Terminal and restart the affected apps:

```sh
defaults delete -g NSFileViewer
```

This setting wasn't tested by changing the system value on a real Mac.

## Favorite import and setup

FileTerm can import favorites from the `Favorites.json` file of one older third-party file manager. The Import Favorites dialog names it. FileTerm offers the import once at launch if it finds that file. It's also in Go › Manage Favorites… › Import….

1. If needed, click Choose File… and pick the file.
2. Review the list. Entries already in your favorites are marked "Already added" and start unticked.
3. Click Import.

Your current favorites stay as they are. Only local favorites are imported. Remote entries are listed so you can add them with Go › Connect…. The format comes from a third-party description, and no real file has been tested yet.

## Quick practice for copying

1. Create two empty test folders, and put a small file in one.
2. Open one folder in each pane.
3. Select the file and choose Commands › Copy to…. Click Copy.
4. Confirm the file is in the destination and still in the source.

## Quick practice for renaming

1. Put two test files in a folder and select both.
2. Choose Commands › Rename.
3. From Add Rule, add Add Sequence.
4. Read the before and after names in the preview.
5. Click Cancel. The files are unchanged.

## Quick practice for synchronization

1. Create two small test folder trees and open one in each pane.
2. Choose Commands › Sync to….
3. Choose Left → Right and leave Delete orphaned items off.
4. Read the proposed Add and Update rows.
5. Click Cancel. Nothing changes.

Understand the action list before you synchronize real folders.

## When external prerequisites matter

A menu command being there doesn't mean it can succeed. These also need something outside the app:

| Feature | Needs | If it's missing |
|---|---|---|
| Remote connections | A server and an account with permission | Connect reports what's missing. S3 and B2 need both key fields. |
| Source Control | A local folder inside a Git repository | The commands are grayed out and say why |
| Compare | A supported tool, installed | The command is grayed out and names the tool |
| Tools | The program the command starts | The tool is grayed out and names the missing program |
| Preview | A file type macOS can preview | The panel shows "Preview unavailable" |
| Copy Dropbox Link | Dropbox set up on this Mac, and a token | The command is grayed out and says which |

Next: pick one practice above and try it with test folders. It takes about two minutes.
