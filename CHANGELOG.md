# Changelog

Every release is listed here, newest first. The version comes from `Config/Version.xcconfig`
and is changed with `./version.sh`. See "Versions and releases" in the README.

## 1.2.1 (2026-11-15)

### Taskbar

- **The Trash shows full or empty.** With something in the Trash, the taskbar shows a full Trash, the same as the Dock. Empty it and the picture goes back to an empty Trash. The app reads the Dock's own note of the Trash, which needs no permission. Once the app is allowed to control Finder (the first time you use Empty Trash or Copy Path), it also asks Finder for the exact count. It never asks for a new permission for this.

## 1.2.0 (2026-11-14)

### Taskbar

- **Drag the taskbar to another edge.** Press and hold an empty part of the taskbar and drag toward the left, right, top, or bottom of the screen. An outline shows where it will land.
- **Right-click an empty part of the taskbar** for its menu: Add Icons, Add from Apple Dock, Position on Screen, Taskbar & Dock Settings, App Icon Controls, and Switch to Apple Dock. The Applications button has the same menu.
- **Add Icons.** Pick apps in a file chooser to keep them on the taskbar.
- **Add from Apple Dock.** Brings over the apps kept in the Apple Dock, one at a time or all at once.
- **Drop apps from Finder** onto the taskbar to keep them there. Dropped between two apps, they land in that spot.

### Safer

- If this app turned the macOS Dock off, the Dock now comes back when the app quits, and goes off again at the next launch. Quitting can no longer leave a Mac with no Dock and no taskbar.
- The README says how to remove the app and how to bring the Dock back by hand.

## 1.1.0 (2026-11-14)

Not published on its own. Everything in it is part of 1.2.0.

### Taskbar

- **Apps chosen per display.** In App Icon Controls, each display's taskbar can follow Show Apps On or show only the apps you choose for it. Chosen apps show whether they are running or not. Add them with Add App, by dragging, or with Show on Display in the right-click menu. A switch brings back the Applications, Hidden Apps, and Trash buttons on that bar.
- **Show Apps On.** With a taskbar on more than one display, each taskbar can show every app, or only the apps that have a window on its display.
- **Auto-fit.** When the apps do not fit, the taskbar hides the names, then shrinks the icons, then puts the rest behind a "+N" button with a pop-up.
- **App groups.** Apps can sit in groups with a line between them. They are sorted by topic the first time, and you can rename, add, delete, and reorder groups.
- **App Icon Controls.** A new screen to set the icon size, arrange apps and groups by dragging, and add apps.
- **Hidden apps.** Tuck running apps behind a Hidden Apps button that shows how many are running.
- **Apple Dock or taskbar.** One switch goes between this app's taskbar and the Apple Dock, and back.
- **Icon size slider** from 16 to 72 points, in place of small, medium, and large.
- **Right-click menus** on the Applications button (settings, switch to the Apple Dock) and on the Trash (open, empty, eject disks).

### Fixed

- Right-click menus on a display above the main display flashed and closed. macOS was moving the menu off the screen. The taskbar now shows its own menus, just beside the bar, on every display.
- This app's icon no longer shows a light border on the taskbar.
- Switches in the settings keep their color while the window is in the background.

### Other

- App logo above the CNERD AI link in the sidebar, an I Have Donated switch, and a trademark notice.
- The sidebar shows the version with its build number.
- Versioning: one version file, `./version.sh`, a build number that goes up on every build, and a release script that will not reuse a version.

## 1.0.0 (2026-11-12)

First public release. Free and open source under the MIT license.

- **Window Manager:** Windows-style maximize and restore, left half, right half, center, global keyboard shortcuts, and an optional green button maximize (beta).
- **Taskbar & Dock:** a taskbar on all displays, the main display, or the other displays, on any edge. Reorder apps, keep apps, Trash, Dock-style right-click menu, and switches for the real Dock.
- **Finder Enhancements:** show hidden files, copy the path of the Finder selection, quick folders.
- **Desktop Manager:** read-only Desktop file list and display information.
