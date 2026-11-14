# Changelog

Every release is listed here, newest first. The version comes from `Config/Version.xcconfig`
and is changed with `./version.sh`. See "Versions and releases" in the README.

## 1.1.0 (2026-11-14)

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
