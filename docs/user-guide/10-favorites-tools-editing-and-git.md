# 10 Favorites, tools, editing and Git

## Favorites manager

Go › Manage Favorites… opens the manager. Changes save immediately.

1. Click New Favorite.
2. Name it and choose a Kind: Folder or Connection.
3. For a folder, type a path, click Choose…, or click iCloud Drive.
4. Click Save.

New Favorite Group adds a group, and you drag a favorite onto it to file it there. Move Out takes it back out. Groups don't nest. Edit and Delete act on the selected row.

Favorites appear in Go › Favorites, in Quick Open and in the sidebar. Right-click one in the sidebar to open it in a new tab or window, edit it, delete it or hide it.

## Favorite paths

A Connection favorite can hold several saved paths. Add them with Add Path.

- With no paths, choosing the favorite opens the connection's own folder.
- With one path, choosing it connects and opens that path.
- With several, Go › Favorites shows a submenu with one entry per path.

Choosing a connection favorite connects first if needed. To save a connection in the first place, see [chapter 6](06-connections-and-remote-locations.md#connection-form).

## iCloud favorites sync

Settings › General › Sync Favorites to iCloud **doesn't sync yet**. You can turn it on, and FileTerm saves your choice, but nothing is sent to iCloud. The setting says this too. Live sync isn't built.

## Custom command tools

A tool is a shell command you run from Commands › Tools. Choose Commands › Manage Tools… or Settings › Tools.

1. Click Add.
2. Enter a Name and a Command.
3. Click Insert next to any placeholders you need.
4. Set the options below.
5. Click Save.

- **Run for every selected file:** runs once per selected item, instead of once with the whole selection.
- **Enable for remote files:** allows the tool when either pane is remote. Remote items are passed as their remote paths, and nothing is downloaded.
- **Show output:** opens a window after the run with each command, its exit code and its output, including after a failure. Output isn't shown while the tool runs.
- **Show in Toolbar:** adds a hammer button to the toolbar.

Tools run as jobs in Activities, with `/bin/sh`, in the active pane's folder. Remote panes use your home folder instead. Logs records each command and its exit code. A nonzero exit fails the job. Cancel stops the running process. Tools are never retried.

A tool is unavailable when no folder is open, when either pane is an archive opened as a folder, when a pane is remote and the remote option is off, or when it runs per file with nothing selected. It's also unavailable if FileTerm can't find the command's program.

## Tool placeholders

Source means the active pane, and target means the other pane.

| Placeholder | Value |
|---|---|
| `$SOURCE_PATH` | Folder of the active pane |
| `$TARGET_PATH` | Folder of the other pane |
| `$SOURCE_SELECTION_PATHS` | Selected items in the active pane, as full paths |
| `$TARGET_SELECTION_PATHS` | Selected items in the other pane, as full paths |
| `$SOURCE_SELECTION_NAMES` | Selected items in the active pane, as names |
| `$TARGET_SELECTION_NAMES` | Selected items in the other pane, as names |

FileTerm passes each value to the shell as a variable, so nothing in a file name can run as a command.

- **No quotes:** `$SOURCE_PATH` is one word, even with spaces in the path, and each selected item in `$SOURCE_SELECTION_PATHS` is its own word. A missing value leaves no word.
- **Double quotes:** `"$SOURCE_SELECTION_PATHS"` is one word, with the items joined by spaces. A missing value is empty.
- **Single quotes:** `'$SOURCE_PATH'` stays as that text, as it does anywhere in a shell. Use double quotes to get the value.

Don't pass a value to `eval`, or into a nested command as `sh -c "... $SOURCE_PATH"`, because that shell would read the file name as code. Inside `sh -c '...'`, write `"$SOURCE_PATH"`: the nested shell reads the variable safely.

## Your shell's PATH

Mac apps opened from Finder start with a short PATH, so programs from Homebrew, nvm and similar wouldn't normally be found. FileTerm asks your login shell for its PATH when it starts, and gives it to Tools, Source Control commands, File › Open in Terminal and built-in terminal sessions.

- If the lookup fails, or takes longer than 10 seconds, the app's own PATH stays in place.
- macOS ignores this PATH if the external terminal app is already running.
- With Login shell on in Settings › Terminal, a built-in session's own startup files still set PATH.
- The check that grays out a tool when its program is missing uses this PATH too, once the lookup has finished.

## External editors

Settings › Editing maps applications to file extensions. Commands › Edit opens one selected file in the first row that lists its extension.

1. Click Add.
2. Click Choose… and pick an app.
3. Enter extensions separated by commas or spaces, such as `swift, md, txt`.
4. Click Save.

With no matching row, the file opens in its default app. A row whose app is missing shows in red, and Edit then opens the default app with a notice. Matching ignores case and works on whole suffixes, so `tar.gz` matches `a.tar.gz`.

## Remote editing

Commands › Edit on a file in a connection:

1. Downloads a temporary copy and opens it in the mapped editor.
2. Asks on your first save: "Upload your changes?", naming the account and path.
3. **Upload** replaces the file on the server, now and on every later save, until you quit or the connection closes. **Stop Watching** keeps the local copy and uploads nothing.

Nothing is uploaded before you answer. Each upload appears in Activities and Logs. To retry a failed upload, save again.

If the file changed on the server since you opened or last uploaded it, FileTerm asks before replacing it. Saving through a symbolic link on SFTP changes the file it points to, and a replaced file keeps its permissions on SFTP.

If you quit with edits the server never received, after a failed upload or Stop Watching, FileTerm offers to keep them in `Downloads/FileTerm Remote Edits`.
 Editing the same file again reopens the existing copy, so unsaved work isn't overwritten. Files inside an archive can't be edited.

## Terminal integration

**External terminal:** File › Open in Terminal opens the active local folder in the app chosen in Settings › General › Terminal application: Terminal (the default), iTerm, Ghostty or Warp.

**Built-in terminal:** View › Show Terminal (`` ⌃` ``) opens a panel docked below or to the right of the panes. `` ⌃⌥` `` moves focus between pane and terminal. Each tab has its own shell session. Hiding the panel keeps sessions running. Close Terminal Sessions, closing a tab or closing the window ends them. If a shell exits, the panel says so and offers New Shell.

With shell integration on, pane and terminal follow each other's folder only at an empty shell prompt. A running command or unsubmitted text pauses this.

The View › Terminal submenu holds the rest. Insert Selected Paths in Terminal types quoted local paths without running them. Open SSH Session for Connected Host types an `ssh` command for an SFTP pane's host and folder when the shell is idle. The [command reference](commands.md#view) describes each entry.

Settings › Terminal sets the shell path, login and interactive flags, integration, font, cursor and scrollback. Shell integration supports zsh, bash and fish. Other shells work without folder following. Shell changes apply to new sessions.

## Git commands

Commands › Source Control has Add (the selected items), Add All, Commit… (asks for a message), Push and Pull. They work only in a local folder inside a Git repository.

Output and the exit code appear in Logs. A failure shows Git's last error line in Activities, and the panes refresh afterwards.

- Git never waits for input, so a push or pull that needs a password fails with Git's message. Credentials must already work from the command line.
- Push is a plain `git push`. A branch with no upstream fails with Git's own message, and FileTerm doesn't set the upstream for you.
