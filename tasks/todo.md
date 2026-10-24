# M00 implementation

- [x] 1. Project skeleton, pinned tooling and CI workflow
- [x] 2. Provider contracts and local filesystem tests
- [x] 3. Single-pane browsing and native presentation
- [x] 4. Command registry, menus and placeholder panels
- [x] 5. Persistent settings and seven categories
- [x] 6. Formatting, build, tests and runtime verification

The repository initially contains documentation only and has no Git metadata or remote.
Hosted CI cannot be claimed as passing until the workflow runs on a connected repository.

Verification: seven core tests, the settings unit test and the native UI smoke
test pass. Swift formatting and shell syntax checks pass. Xcode builds the native
app. Downloads browsing, panel visibility persistence and settings-category
persistence were checked in the running app, including a full restart.

Review: removing the command dispatcher's availability guard makes its focused
test fail. The guard was restored and all seven core tests passed again.

Environment: restricted-shell Xcode package resolution fails, so native build
and UI-test verification ran through Xcode. The Defaults dependency emits one
upstream warning about inherited unchecked Sendable conformance; app code builds.
