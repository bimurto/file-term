# M01 implementation

- [x] 1. Pane coordination and successful-navigation history
- [x] 2. Active-pane views, layouts and command routing
- [x] 3. Destinations, interactive path bar, Go to Folder and nested menus
- [x] 4. Persistent MRU, visibility and pane status
- [x] 5. Devices, volume notifications and injectable ejection
- [x] 6. Sync Browsing, regression tests, native verification and documentation

Verification on 24 October 2026:

- `swift test --disable-sandbox --scratch-path .build/core`: 16 passed.
- `swift format lint --strict --recursive FileTerm FileTermCoreTests FileTermTests FileTermUITests Package.swift`: passed.
- Generated project from `project.yml`; native Xcode build passed.
- Full `xcodebuild test`: 7 native unit tests and 5 native UI tests passed; no skips.
- Inspected the built app: ancestor breadcrumbs navigate correctly, internal
  volumes appear, and both layouts fit a 680 by 420 content area.
- Sync Browsing mutation check: inverting its guard causes the focused test to
  fail. Restored the implementation and reran the complete core suite successfully.
- All ejection tests use fake services. No real device was ejected.

M00 remains complete locally; hosted CI still requires a connected remote run.
