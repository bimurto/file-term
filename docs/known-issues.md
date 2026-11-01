# Known issues

Problems in the app as it stands on 2026-11-01. Missing features and untested protocols are in the [user guide's limits chapter](user-guide/13-limits-and-known-gaps.md), and unfinished work is in the [milestones](milestones/).

**Seen** means someone watched it happen in the running app. **From the code** means it comes from reading the code and hasn't been run. **Not confirmed** means it may not be a real bug.

## App behavior

| Issue | Status | Detail |
|---|---|---|
| A scrollbar sometimes appears under the toolbar | Seen | It moves the toolbar up about 8 points and comes and goes between launches. A build from before M15 does it too, so M15 didn't cause it. The cause isn't known. The toolbar asks for hidden scroll indicators in `BrowserView`. |
| Copy Dropbox Link shows on every local item without Dropbox | Seen | With no Dropbox set up, the right-click menu shows the item dimmed instead of hiding it. The earlier short menu used the same logic. |
| Share opens in the window's corner | From the code | `file.share` shows the picker at `.zero` of the window's content view, not at the clicked item. |
| Tags… doesn't open a tag editor of its own | From the code | `file.tags` calls the same `showInfo` as Get Info. |
| Only the first seven tags get a color dot | From the code | The rest are in File › Tags. |
| A row in an earlier column offers only Open | Seen | In column view, that row isn't in the current folder, so the commands can't act on it. |

## Security

These came from the review on 2026-11-01. The threat is a malicious server, file or archive, not the person using the app.

| Issue | Status | Detail |
|---|---|---|
| Tool placeholders inside quotes can run code from a file name | From the code | `UserTool` substitutes values already wrapped in single quotes, so in `"$SOURCE_PATH"` or `'$SOURCE_PATH'` that quoting stops protecting the value, and `$(...)` in a file name runs through `/bin/sh -c`. Until this is fixed, write placeholders bare: `$SOURCE_PATH`. Tracking quotes won't cover nested `$(...)`, so the fix needs a design that passes values as variables, and lists like `$SOURCE_SELECTION_PATHS` need several words. |
| Downloaded and extracted files have no quarantine mark | From the code | Nothing sets `com.apple.quarantine`, and `bsdtar` drops it when extracting (probed). Gatekeeper's first-launch check doesn't run on an app taken from an extracted archive or opened from a server. Fixing it means marking files at each place that writes them: extraction, `download()` and `ProviderTransfer`. |
| Release builds are ad-hoc signed and not notarized | From the code | `dev/Signing.xcconfig` sets `CODE_SIGN_IDENTITY = -`, and `scripts/create-dmg.sh` has no signing or notarization step. Users must bypass Gatekeeper and can't verify the DMG. The app also has no sandbox. This needs a Developer ID account. |
| Server listings have no size limit | From the code | An endless listing or folder tree can use up memory or hang a job (`SFTPProvider`, `FTPProvider`, `WebDAVProvider`). The caps on entries, bytes and depth haven't been chosen. |
| Dependencies are pinned to tags, not commits | From the code | `scripts/fetch-dependencies.sh` clones by tag and `.github/workflows/ci.yml` uses `actions/checkout@v4`. A moved tag would change what gets built. |
| A crash can leave a login secret in a temp file | From the code | `SSHCommand` and `FTPProvider` write 0600 files to the per-user temp folder and remove them after use. A crash skips that, and nothing removes stale files at launch. |
| A key-type mismatch might look like a new server | Not confirmed | `SFTPProvider.startupError` treats ssh's "No … host key is known" as an unknown host, which offers Trust. In a loopback test with OpenSSH 10.2, RSA known with ed25519 offered, and the reverse, both reported a changed key, which is refused. Other OpenSSH versions weren't tried. |

## Right-click menus not fully tested

Details are in [M15](milestones/M15-context-menus.md).

| Issue | Status | Detail |
|---|---|---|
| Remote menu behavior hasn't run against a server | From the code | Covers remote Open, Delete…, disabled Copy and disabled Open With. Docker wasn't running. |
| Eject from the sidebar menu hasn't been run | From the code | No volume was ejected to test it. |
| Running a service from the Services submenu hasn't been tried | Not confirmed | The submenu appears and lists copies of the app menu's items. |
| Turning a tag off with a color dot hasn't been tried | Not confirmed | Turning one on works. |
| The Contents limit of 1000 items hasn't been tried | Not confirmed | No folder that large was opened. |

## Development

| Issue | Status | Detail |
|---|---|---|
| The right-click UI tests have never run | Seen | `FileTermUITests/ContextMenuUITests.swift` stopped with "Timed out while enabling automation mode". It may need approval on screen. It also doesn't cover the sidebar yet. |
