# FileTerm

Native macOS file browser with single, side-by-side and stacked panes,
independent navigation histories, interactive breadcrumbs, standard Go destinations,
recent folders, mounted devices and Sync Browsing.

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
histories, navigation races, Sync Browsing and command availability. Xcode runs
settings/navigation/device tests and native UI tests, including minimum-size layouts. UI
tests require an interactive desktop and Xcode's normal automation permission.
CI runs core tests, the native build and settings tests; run the UI test locally.

If an agent environment prevents SwiftPM's nested sandbox from starting, use
`swift test --disable-sandbox` inside that environment. Xcode builds may still
need to run in the native Xcode app when package-resolution services are blocked.

## Structure

- `FileTerm/Core`: provider-neutral locations, async provider protocol, local
  Foundation provider, observable pane model and command registry.
- `FileTerm/App`, `Commands`, `Views`: AppKit lifecycle and menus with SwiftUI
  presentation, native path control and system file icons.
- `FileTerm/Settings`: Defaults-backed settings and seven SwiftUI panes hosted
  by the Settings package.

Filesystem work runs in a dedicated actor. Reads are pull-based 64 KiB chunks;
writes consume chunks and refuse existing destinations. Moves also refuse an
existing destination. Delete is permanent at the provider layer. These mutation
methods have no user-facing commands in M00; later commands must confirm
destructive operations before calling them.

Browsing starts in single-pane mode at Home, hides hidden items and sorts folders
first by name. Both pane models start at the same location. Click a pane to make
it the command source; the other visible pane is the target. Single-pane mode
keeps the active pane visible and retains the hidden pane's state. Session
restoration is deferred to M02.

Double-click directories to enter them. Enclosing Folder moves up; Back and
Forward follow each pane's own history. Breadcrumb ancestors and Go destinations
navigate the active pane. Go to Folder accepts absolute paths, resolves symlinks,
and reports invalid paths without changing the current folder. Standard text
editing shortcuts work in its path field. Failed navigation preserves the folder,
listing, selection and history; obsolete requests cannot replace newer results.
Permission errors do not request broad access automatically.

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

For isolated UI tests, `FILETERM_INITIAL_DIRECTORY` overrides the startup folder
and `FILETERM_SETTINGS_SUITE` selects an independent preferences domain.

## Roadmap

See [milestones](docs/README.md) and [M01 implementation status](tasks/todo.md).
This workspace initially had no Git repository or remote. The CI workflow needs
to be hosted before its passing status can be verified.
