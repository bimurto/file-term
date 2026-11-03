Download **FileTerm.dmg** below, open it and drag FileTerm to Applications. It runs on macOS 14 or later, on Apple silicon and Intel.

**First launch.** FileTerm isn't notarized by Apple yet, so macOS asks once:

- macOS 15 and later: open FileTerm, click **Done**, then go to System Settings › Privacy & Security and click **Open Anyway**.
- macOS 14: Control-click FileTerm in Applications and choose **Open**.
- Or run `xattr -dr com.apple.quarantine /Applications/FileTerm.app`.

Check the download with `shasum -a 256 -c FileTerm.dmg.sha256` in the folder that holds both files.

User guide: https://fileterm.bimurto.io/docs/
