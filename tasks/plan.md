# M00 — Foundation implementation

## Decisions

- Native macOS 14+ app, Swift 6, direct distribution, App Sandbox disabled.
- AppKit owns windows and menus; SwiftUI presents the browser and settings.
- XcodeGen generates the project. Defaults stores typed preferences; Settings
  owns the seven-category settings window. Tool and package versions are pinned.
- A dependency-free local Swift package exposes provider contracts, local I/O,
  navigation and command dispatch so core behavior is testable independently.

## Verification

Follow `tasks/todo.md` in order. Run `swift test` for core changes, Xcode unit
tests for preferences, and the UI smoke test for browsing and settings. Inspect
the running native app, Downloads navigation, panel toggles and persistence.
Formatting and a clean app build are required before completion.

## Boundaries

Only one browser pane. No user-facing mutation commands, history, interactive
breadcrumbs, remote connections, real preview or transfer processing. Signing
and release packaging are deferred. Hosted CI remains unverified until a remote
repository runs the supplied workflow.
