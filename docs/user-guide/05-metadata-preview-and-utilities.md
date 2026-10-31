# 5 Metadata, preview and utilities

Most commands in this chapter work on local items only. They're grayed out in a remote pane, and they also wait for any running file operation to finish.

## Preview and Get Info

View › Show/Hide Preview opens a panel beside the panes. It follows the first selected local item in the active pane. For a remote item, the panel just asks you to select a local one.

File › Get Info (⌘I) opens a separate inspector window for each selected item.

Both show the same details: path, size, extension, created, modified and accessed dates, hidden state, owner, group and permissions. Click the refresh button to reload them.

## Quick Look and Slideshow

- File › Quick Look (⌘Y) opens the macOS Quick Look panel for the selection.
- File › Slideshow plays the selected images. It needs at least one image in the selection.
- File › Print… (⌘P) prints one selected image, PDF or text file.
- File › Share… opens the macOS share picker for the selection.

## Media and text preview

The Preview panel shows images, PDFs, audio and video.

It can also edit text files of up to 1 MiB in UTF-8, or in UTF-16 with a byte order mark:

1. Select the file with the Preview panel open.
2. Edit the text. "Edited" appears at the top.
3. Click Save.

If you select another item with unsaved edits, FileTerm asks whether to save, discard or keep editing. It asks again when you quit.

Files on connections aren't previewed. To view one, open it with File › Open, which downloads a temporary copy.

## Tags and comments

File › Tags… opens the same inspector as Get Info. In the Preview panel or the inspector:

- Type tags separated by commas, then click Apply Tags.
- Type a Finder comment, then click Apply Comment.

If the storage doesn't support tags or comments, the fields are disabled and say why. Symbolic links can be inspected but not edited.

To manage the tags listed in the sidebar, see [chapter 11](11-appearance-settings-and-macos.md#tag-management).

## Permissions and locking

The same panels can change permissions:

- Edit the octal mode or tick Read, Write and Execute for Owner, Group and Everyone, then click Apply Permissions….
- Choose an owner or group, then click Apply Owner… or Apply Group….
- Toggle Locked.

Each change asks for confirmation, applies to the item only and not to its contents, and needs you to already have the right to make it.

## Opening application

The Preview panel and inspector can change which app opens a file:

1. Choose an application, or click Other….
2. Click Apply to This File, or Change All… to use it for every file of that type. Change All asks first, because it changes a system-wide setting.

## Folder sizes

Commands › Calculate All Folder Sizes works out the size of each local folder in the current listing. A window shows progress and can cancel the work.

- It counts hidden files and package contents and doesn't follow symbolic links.
- Unreadable folders are listed as failures, and no partial total is shown for them.
- The results fill in the Size column, sorting and the status bar's selection total.
- Refreshing or navigating the pane clears the results.

## Copy Path and URLs

File › Copy Path puts the selected items' paths on the clipboard, one per line:

| Format | Result |
|---|---|
| UNIX | The plain path |
| URL | A `file://` URL |
| Percent-Decoded URL | The same URL in readable form, which may not work as a link |
| Name | The name only |
| Terminal | The path quoted for a shell |
| Windows | The path with backslashes. No drive letter is added. |

File › Copy URL and Open URL are for items on a connection that has a Base URL. They copy or open that item's public web address. See [chapter 6](06-connections-and-remote-locations.md#advanced-connection-fields).

## Aliases and symlinks

- File › Make Alias and Make Symlink create the link next to each selected item.
- File › Make Alias to and Make Symlink to create it in the other pane's folder.

New links get unique names and never replace an existing item. The destination must be a writable local volume that supports that link type. An alias can't point to a symbolic link, so use Make Symlink for those.

## Checksums

Commands › Calculate Checksum… works on one regular local file.

1. Choose MD5, SHA-1 or SHA-256.
2. Click Calculate.
3. Optional: paste an expected value to see whether the checksums match.
4. Click Copy Checksum to copy the result.

MD5 and SHA-1 can detect accidental changes, but they don't prove a file wasn't tampered with.
