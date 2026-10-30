# FileTerm

Native macOS file browser with single, side-by-side and stacked panes,
independent navigation histories, interactive breadcrumbs, standard Go destinations,
recent folders, mounted devices and Sync Browsing. Each pane supports icon, list
and hierarchy-column views, independent tabs, and saved view settings. Multiple
windows and optional session restoration are available.

M05 adds a metadata Preview panel and Get Info windows, native media/text previews,
Quick Look, slideshow and printing, editable Finder metadata and permissions,
application associations, cancellable folder sizes and checksums, Copy Path formats,
and safe aliases/symlinks. See [M05 status and limitations](docs/milestones/M05-metadata-preview-utilities.md).
Remote preview caching and public Base URLs remain deferred to M08.

M07 adds a shared operation queue, Activities controls, copyable/exportable Logs,
Transfers settings, cooperative local copies, conflict policies, verification and
safe retry diagnostics. See [M07 status and limitations](docs/milestones/M07-transfers-activities-logs.md).
Interrupted-transfer recovery across launches and retry of partially committed batches remain open.

M08 adds Go › Connect… with a per-protocol form, keychain-stored passwords, SMB/AFP/NFS
mounts, a VNC handoff, remote pane placement, Base URLs for Copy/Open URL and Go › Connections.
Copy to… streams between local and remote locations through the transfer queue.
Remaining protocols ship in follow-up tickets; see [M08 tickets](docs/milestones/M08-connections-remote.md).

M09 adds Commands › Sync to… for two panes: an analysis preview with direction, scope, update,
delete, time-offset and exclusion options, and a checkable action list that runs as queue jobs.
See [M09 tickets](docs/milestones/M09-sync-and-batch-rename.md). Selecting several items and choosing Rename (or pressing Return in the list view) opens Batch Rename: ordered rules
(Replace Text, Change Case, Add Sequence, Add Text, Add Date) with a live Original → New preview, warnings for duplicate or invalid names and extension changes,
and saved rename presets that appear in Quick Open.

M10 adds Commands › Compress, Compress With Options…, Extract and Extract to… (zip, tar, tar.gz, tar.bz2, tar.xz),
Settings › General archive options and Treat archives as folders (read-only browsing and search
inside zip/tar files), Delete… and Empty Trash…, an App Deleter that lists an app's related files, and
Commands › Compare with FileMerge or another tool. See [M10 tickets](docs/milestones/M10-archives-deletion-comparison.md).

M11 adds Go › Favorites with a manager (folders, iCloud Drive, connections with several saved paths,
groups), user-defined Tools with shell-quoted placeholders that run through the queue, external
editors with Commands › Edit (including uploading remote edits on save), File › Open in Terminal, and
Commands › Source Control (Add, Add All, Commit, Push, Pull). Syncing favorites through iCloud is not
available yet. See [M11 tickets](docs/milestones/M11-favorites-tools-editing-git.md).

## Run

Requires macOS 14+ and Xcode 16+ with Swift 6.

1. Download the pinned tools and packages:

   ```sh
   bash scripts/fetch-dependencies.sh
   ```

2. Generate the project:

   ```sh
   bash scripts/generate-project.sh
   open FileTerm.xcodeproj
   ```

3. Select **FileTerm → My Mac** and press **⌘R**. Choose **Go → Downloads**.

XcodeGen 2.44.1, Defaults 8.2.0 and Settings 3.1.1 are downloaded from their
official repositories into `.build/`. The generator archive is SHA-256 checked;
package commits are checked before project generation. No system-wide install
or Apple developer account is needed for the ad-hoc development build.

`project.yml` is the source of truth for the generated Xcode project. Regenerate
after adding files or changing build settings. Do not edit downloaded packages.

## Verify

```sh
swift test
swift format lint --strict --recursive FileTerm FileTermCoreTests FileTermTests FileTermUITests Package.swift
xcodebuild -project FileTerm.xcodeproj -scheme FileTerm \
  -destination 'platform=macOS' -derivedDataPath .build/xcode test
```

The dependency-free Swift package tests filesystem operations, independent pane
histories, tabs, session snapshots, metadata sorting/grouping, navigation races,
Sync Browsing and command availability. Xcode runs
settings/navigation/device tests and native UI tests, including view modes,
multiple windows, restoration and minimum-size layouts. UI tests require an interactive desktop and Xcode's normal automation permission.
CI runs core tests, the native build and settings tests; run the UI test locally.

If an agent environment prevents SwiftPM's nested sandbox from starting, use
`swift test --disable-sandbox` inside that environment. Xcode builds may still
need to run in the native Xcode app when package-resolution services are blocked.

## Built-in terminal

View > Show Terminal (Control-`) opens the SwiftTerm-backed terminal drawer.
Control-Option-` moves focus between the pane and terminal. The drawer can dock
below or to the right of the panes; its visibility, position and size are saved
with each restored window.

Each pane tab owns an independent shell session. Changing tabs switches sessions
without losing scrollback or running programs. Hiding the drawer retains sessions;
closing its sessions, closing their pane tabs, or closing the window terminates them.

With shell integration enabled, pane and terminal directories follow each other
only at an empty shell prompt. Running foreground commands and unsubmitted input
pause linking. If you navigate the pane while paused, its latest directory wins
at the next prompt; otherwise a terminal `cd` updates its pane. Search and non-local
locations pause following. Use the header controls to unlink, disable reverse
following, synchronize safely, or reveal the terminal directory in the pane.

Settings > Terminal configures the shell, startup flags, integration, linking,
font, cursor and scrollback. zsh, bash and fish use temporary integration scripts;
user startup files are not permanently edited. Bash login profiles that replace
`PROMPT_COMMAND` can prevent integration from loading; the terminal remains usable
and synchronization stays paused rather than injecting bootstrap commands.
Other shells remain usable without automatic directory synchronization. Shell processes and scrollback are not
serialized across app launches. All terminal actions are available in Quick Open
and Settings > Shortcuts.

## Structure

- `FileTerm/Core`: provider-neutral locations, async provider protocol, local
  Foundation provider, observable pane model and command registry.
- `FileTerm/App`, `Commands`, `Views`: AppKit lifecycle and menus with SwiftUI
  presentation, native path control and system file icons.
- `FileTerm/Settings`: Defaults-backed settings and eight SwiftUI panes hosted
  by the Settings package.
- `FileTerm/Terminal`: SwiftTerm-backed PTY sessions, temporary shell integration,
  and the per-pane-tab terminal drawer.

Filesystem work runs in a dedicated actor. Reads are pull-based 64 KiB chunks;
writes consume chunks and refuse existing destinations. Moves also refuse an
existing destination. Delete is permanent at the provider layer. These mutation
methods have no user-facing commands in M00; later commands must confirm
destructive operations before calling them.

With restoration off, browsing starts in single-pane mode at Starting Directory
(default Home), hides hidden items and sorts folders first by name. Both pane models start at the same location. Click a pane to make
it the command source; the other visible pane is the target. Single-pane mode
keeps the active pane visible and retains the hidden pane's tabs and state.

Double-click directories to enter them. Enclosing Folder moves up; Back and
Forward follow each pane's own history. Breadcrumb ancestors and Go destinations
navigate the active pane. Go to Folder accepts absolute paths, resolves symlinks,
and reports invalid paths without changing the current folder. Standard text
editing shortcuts work in its path field. Failed navigation preserves the folder,
listing, selection and history; obsolete requests cannot replace newer results.
Permission errors do not request broad access automatically.

View > as Icons, as List and as Columns select a view for the active tab in
its pane. List headings sort by their metadata; Sort by and Group by offer all
M02 fields. Folders stay first, and unknown metadata sorts last in both directions.
Date Last Opened uses Spotlight's last-used metadata and is unknown when the
volume is not indexed. Column view starts at the current folder and keeps
visited ancestors visible as you enter child folders. Clicking a file in an
ancestor column makes that containing folder current before selecting the file.

Show View Options explicitly selects This Tab or This Folder. Tab settings follow
the tab across navigation; folder settings are shared by tabs using folder scope.
Save View Settings as Defaults supplies new tabs/windows and folders without
saved overrides. Restore Default View Settings applies those defaults to the
current scope.

File > New Tab (Command-T) duplicates the current location with an independent
history and saved default view options. Command-1 through Command-5 select a tab
in the active pane. Previous/Next Tab cycle within that pane. Close Tab closes
the window when its last active-pane tab is closed. Window > Pin View preserves
the pinned tab's location: navigating away opens a new unpinned tab with the
same view options. Tabs can still be explicitly closed or unpinned.

Customize Toolbar chooses commands from the registry and changes their order.
Show Sidebar Editor controls the Devices and Recent Folders sections and their
order. Toolbar, sidebar and tab-bar visibility and customization persist.

File > New FileTerm Window opens independent panes and tabs at Starting Directory.
Window commands and the live window list use AppKit's native Window menu, which
adds the layout and tiling actions supported by the running macOS version.
Menus and toolbar actions route to the active browser window; dialogs open only
in that window.

Settings > General sets Starting Directory and Restore windows and tabs on
startup (default off). Normal quit saves open windows, tabs, histories, pane
layouts, selected tabs, view settings and window frames. They restore when that
setting is on. Quit and Keep Windows requests restoration for the next launch
even when the setting is off. Missing saved folders fall back to Starting
Directory; an invalid Starting Directory falls back to Home.

Recent Folders stores the last 20 distinct successful local destinations, shared
between the Go menu and sidebar. View controls path-bar, title-bar, toolbar,
devices and device-info visibility; those choices persist. Pane status shows
visible item count, selected known bytes (unknown sizes are marked), and free
volume space without recursively scanning folders.

Swap Panes exchanges pane states, including their histories and selections, while
retaining the active visual position. Clone Pane navigates the opposite pane to
the active folder. Both require two idle panes.

Sync Browsing mirrors only directory entry and Enclosing Folder into the other
pane. Back/Forward, breadcrumbs and direct destinations stay independent. A
missing counterpart leaves the opposite pane unchanged and shows an explanation.
Switching to single-pane mode turns Sync Browsing off. It never changes files.

Devices refresh on mount, unmount and volume rename. File > Eject requires a
selected ejectable sidebar volume. Failures are reported; unmounted locations
return to Home. Ejection tests use a fake service and never eject a real drive.
Go > Connections remains a disabled placeholder until M08.

For isolated UI tests, `FILETERM_INITIAL_DIRECTORY` overrides Starting Directory
and `FILETERM_SETTINGS_SUITE` selects an independent preferences domain.

Edit > Select All, Deselect All and Invert Selection update the active pane's
selection without changing the current folder. Quick Select (Command-S) matches
name (substring or `*`/`?` wildcards), extension or tag in Replace, Add or Remove
mode and displays the resulting selection count before applying.

Quick Open (Escape, when no sheet or text field is active) fuzzy-searches commands
from the registry, folders in the current listing and recent folders, with
extension points ready for devices, favorites, applications and rename presets.

File > Find (Command-F) and the toolbar search field open a separate search
result scope with criteria (name, extension, tag, file contents, subfolders,
hidden items) and engine selection (Built-in scanning search for all providers,
or Spotlight for local folders). Closing the search returns to the underlying
folder and restores its prior selection.

The toolbar "Show hidden" checkbox and View > Show Hidden Items toggle hidden
entries (rendered dimmed), independent of future sync options. View > Refresh
(Command-R) reloads open panes while preserving existing selections, and
View > Auto-Refresh watches local folders via FSEvents.

Settings > Shortcuts provides a searchable command list, shortcut recorder,
conflict warnings with Reassign/Cancel, and Restore Defaults, seeded with the
4.6 defaults (Quick Select ⌘S, Quick Open Esc, New Folder ⇧⌘N, New Folder With
Selection ⌃⌘N, New File ⌥⇧⌘N, Open ⌘O, Quick Look ⌘Y).

## Roadmap

See [milestones](docs/README.md) and [M03 implementation status](tasks/todo.md).
This workspace initially had no Git repository or remote. The CI workflow needs
to be hosted before its passing status can be verified.
