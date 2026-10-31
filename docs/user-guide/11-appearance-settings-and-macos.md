# 11 Appearance, settings and macOS

Open settings with FileTerm › Settings… (⌘,). The panes are General, Transfers, Shortcuts, Tags, Tools, Editing, Themes, Terminal and Integrations.

## Themes

Settings › Themes lists the built-in themes with color swatches. They include Default, which follows the system appearance, plus Dark, Light, Bluerange, Dracula, Commander, Sand and Polar Night. Click one to use it.

A theme sets the browser window's background, sidebar, text and accent colors. Its light or dark choice applies to the whole app. The terminal keeps its own settings from Settings › Terminal.

## Tag management

Settings › Tags lists the tags shown in the sidebar. The defaults are Gray, Green, Purple, Blue, Yellow, Red and Orange.

- To add one, type a name, choose a color and click Add.
- Remove takes a tag off this list only. It stays on your files.

Clicking a sidebar tag lists the files that have it, using Spotlight, as a closeable result list. Files on other volumes and in folders Spotlight doesn't index aren't listed. To tag a file, see [chapter 5](05-metadata-preview-and-utilities.md#tags-and-comments).

## Drag confirmations

Settings › General › Ask for confirmation for drag operations is off by default. With it on, dropping items on a pane asks whether to copy or move them. See [chapter 4](04-creating-copying-and-moving.md#drag-and-drop) for what a drop does otherwise.

## Remote pane preference

Settings › General › Open remote connections in chooses Left Pane, Right Pane (the default) or Active Pane. It only affects where a connection opens.

## Startup settings

- **Restore windows and tabs on startup:** off by default. See [chapter 2](02-views-windows-and-tabs.md#quit-and-restore).
- **Starting Directory:** an absolute folder path, Home by default. Click Set Starting Directory to save it. New windows use it, and so does startup with restoration off.

## Other General settings

- **Handle archives with FileTerm** and **Treat archives as folders:** see [chapter 9](09-archives-deletion-and-comparison.md#archive-handling-settings).
- **Detect application when deleting:** see [chapter 9](09-archives-deletion-and-comparison.md#app-deleter).
- **Compare tool:** see [chapter 9](09-archives-deletion-and-comparison.md#file-comparison).
- **Terminal application:** see [chapter 10](10-favorites-tools-editing-and-git.md#terminal-integration).
- **Sync Favorites to iCloud:** saved but not working yet. See [chapter 10](10-favorites-tools-editing-and-git.md#icloud-favorites-sync).

## Updates and version information

FileTerm › About FileTerm shows the version and build.

FileTerm › Check for Updates… looks up the latest release on GitHub. If a newer one exists, it offers to open the download page. It doesn't download or install anything itself.

Settings › General has Automatically check for updates, which is off by default, and Check for Updates Now. An automatic check stays quiet unless there's an update to offer.

## Services and sharing

- FileTerm › Services shows the macOS services for the current selection. The list depends on what's installed on your Mac.
- File › Share… opens the macOS share picker for selected local items.

## System text features

macOS adds its own entries to the Edit menu, such as Dictation and Emoji & Symbols. They work in text fields and aren't file commands.

## Help

The Help menu opens this guide in your web browser. FileTerm Help opens the start page. Below it, one submenu per app menu links each command to its row in the [command reference](commands.md). You need an internet connection to read the guide this way.

## Permissions and notifications

On first launch, a welcome window explains Full Disk Access and has a button that opens that System Settings page. You don't need it for ordinary folders. It's for folders macOS protects, such as Mail and other apps' data. Grant only what you intend to use.

The window also has Allow Notifications. FileTerm doesn't send notifications yet, and the window says so. Allowing them now means it won't ask later.

If a local folder can't be opened because of a permission, the pane names the permission and offers Open System Settings. Empty Trash separately asks for permission to control Finder.

## Language

FileTerm is in English. Translation is only partly prepared, and no other language ships today. See [chapter 13](13-limits-and-known-gaps.md).
