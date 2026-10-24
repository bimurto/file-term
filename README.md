# FileTerm

Native macOS file browser. M00 provides one pane, a path bar, item count,
registry-driven commands, persistent settings and placeholder panels.

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

The dependency-free Swift package tests filesystem operations, navigation races
and command availability. Xcode runs the settings tests and UI smoke test. UI
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

Browsing starts at Home, hides hidden items and sorts folders first by name.
Only directories open on double-click. Failed navigation preserves the current
folder, listing and selection; obsolete requests cannot replace newer results.
Permission errors do not request broad access automatically.

For isolated UI tests, `FILETERM_INITIAL_DIRECTORY` overrides the startup folder
and `FILETERM_SETTINGS_SUITE` selects an independent preferences domain.

## Roadmap

See [milestones](docs/README.md) and [M00 implementation status](tasks/todo.md).
This workspace initially had no Git repository or remote. The CI workflow needs
to be hosted before its passing status can be verified.
