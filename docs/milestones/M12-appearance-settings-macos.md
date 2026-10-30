# M12 — Appearance, settings & macOS integration

**Goal:** Add themes, tag management, the remaining General settings, updates and OS integration.
**Ref:** Guide › Ch. 11 Appearance settings and macOS integration.

## Items

### M12.01 Theme engine
- [x] Built-in themes: Default (follows the system appearance), Dark, Light, ForkLift, Bluerange, Dracula, Commander, Sand, Polar Night.
- [x] Theme definitions are data files, so custom themes can be added later *(custom themes are vendor-documented)*.

### M12.02 Tag management
- [x] Settings › Tags: default Gray, Green, Purple, Blue, Yellow, Red, Orange, with Add and Remove.
- [x] The sidebar shows these tags. Clicking a tag lists the files that have it.

### M12.03 Drag confirmation
- [x] Settings › General › Ask for confirmation for drag operations (default off) shows a copy/move confirmation after a drop.

### M12.04 Startup settings
- [x] Starting Directory (default Home) and Restore windows and tabs are connected to M02.11.

### M12.05 About & updates
- [x] About window shows the version and build.
- [x] Check for Updates, an automatic-check toggle (default off) and Check for Updates Now.

### M12.06 Services & sharing
- [x] ForkLift › Services exposes the system Services menu for the current selection.
- [x] Share menu/integration *(vendor-documented)*.

### M12.07 System text features
- [x] Edit menu includes the standard Dictation, Emoji & Symbols and AutoFill entries (provided by the OS).

### M12.08 Permissions & notifications onboarding
- [x] On first run, a guide explains Full Disk Access and asks for notification permission.
- [x] When an access error happens, the app explains which permission is missing and links to System Settings.

### M12.09 Localization
- [ ] All UI strings are externalized. Ships in English, ready for more languages *(more languages are vendor-documented)*.

## Status

M12.01 to M12.08 are built. M12.09 is partly built, see below.

## Notes

- **Themes.** Each theme is a JSON file in `FileTerm/Resources/Themes`. Adding a file adds a theme, with no code change. Only Dracula and Polar Night (Nord) use published palettes. The guide lists the other names without colors, so ForkLift, Bluerange, Commander and Sand are our own choices.
- **Themes reach** the browser window: background, sidebar, text and accent. Light or dark applies to the whole app. The terminal keeps its own colors from Settings › Terminal.
- **Tags.** Clicking a tag searches the whole startup disk with Spotlight and shows a closeable result scope. Files on other volumes and folders Spotlight does not index are not listed. Removing a tag from the list leaves it on files.
- **Drops.** Panes had no drop targets before this milestone, so M12.03 adds them. The same volume moves, another volume copies, Option always copies, and a remote pane always copies. Search results are not a drop target.
- **Updates** read the latest GitHub release and open its download page. Nothing is downloaded or installed. There is no Sparkle dependency. Until a release is published, the check reports that none exists.
- **Notifications.** The first-run guide asks for permission, but the app does not send notifications yet, and the guide says so.
- **Access errors.** The explanation and System Settings button appear when a local folder cannot be opened in a pane. A copy or move that is denied still reports its error in Activities and Logs, without a button.

## Not done

- **M12.09:** SwiftUI text and the menus look up translations, and `Localizable.xcstrings` holds 380 English strings extracted from the build. Still hard-coded: `NSAlert` text, command titles as catalog entries, `String` values built in code, and messages from Core. There are about 1,300 lines with such literals, many in `AppDelegate` and `FileOperationCoordinator`, so do this sweep after parallel work in those files has merged.
- **Not driven by a test:** a Service or Share actually running. `FileTermUITests/AppearanceUITests` confirms that the menus list them and that they are enabled for a selection. Hosted tests cover the file data a Service receives.
