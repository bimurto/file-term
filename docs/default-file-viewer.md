# Default file viewer

**Settings › Integrations › Use FileTerm for Reveal and Show in Finder** makes FileTerm handle these requests from other apps. It is off by default.

## What it changes

It sets one per-user system value. This is the same as running:

```sh
defaults write -g NSFileViewer -string com.fileterm.app
```

Apps read the value when they start, so restart an app for it to take effect there.

## What it does not change

- The system Open and Save dialogs. They stay the same.
- Finder itself, the desktop and double-clicking a folder in Finder.
- Apps that always call Finder directly rather than asking for the default viewer.

## How to revert

Turn the setting off. FileTerm restores the viewer that was set before, or clears the value so Finder is the viewer again. If FileTerm can't start, run:

```sh
defaults delete -g NSFileViewer
```

Then restart the affected apps.
