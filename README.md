# CNERD Mac Utilities

Free, open source utilities that make a Mac feel familiar to people who come from Windows.
Native Swift, no dependencies, no account, no data collection. Developed by [CNERD AI](https://cnerd.ai).

If it saves you time, you can [support development with a donation](https://cnerd.ai/shop/?app=mac-utilities).

## What it does

| Module | Features |
| --- | --- |
| **Window Manager** | Maximize that fills the screen without entering Full Screen, and restores on the second use. Left half, right half, center. Global keyboard shortcuts. Optional: make the green window button maximize instead of going Full Screen (beta). |
| **Taskbar & Dock** | A Windows-style taskbar on all displays, the main display, or the other displays. Put it on the bottom, top, left, or right. Square or rounded edges, glass or solid, icon size, app names and their size and position. Drag apps to reorder. Right-click for Keep in Taskbar, Show All Windows, Show in Finder, Hide, Quit. Trash button. Switches for the real Dock: auto-hide, position, size, and turn the Dock off. |
| **Finder Enhancements** | Show hidden files, copy the full path of the Finder selection, quick access to common folders. |
| **Desktop Manager** | Read-only list of Desktop files with sorting, and information about every connected display. |

Every module has its own on and off switch. When a module is off it does nothing.

## Requirements

- macOS 14 or later, Apple silicon or Intel
- To build: Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Install

**Download:** get [CNERD-Mac-Utilities-1.0.0.dmg](https://github.com/CNERDAI/cnerd-mac-utilities/releases/latest) from the latest release. It is signed and notarized by Apple. Open the `.dmg` and drag the app to Applications.

**Build it yourself:**

```bash
git clone https://github.com/CNERDAI/cnerd-mac-utilities.git
cd cnerd-mac-utilities
./build.sh
open "build/Build/Products/Debug/CNERD Mac Utilities.app"
```

## First run

1. Open the app, go to **Window Manager**, and click **Request Access**. Turn on CNERD Mac Utilities under System Settings, Privacy & Security, Accessibility. macOS requires this before any app can move another app's windows.
2. Try the shortcuts in any app:

| Action | Default shortcut |
| --- | --- |
| Maximize / Restore | Control-Option-Up |
| Move window left | Control-Option-Left |
| Move window right | Control-Option-Right |
| Center window | Control-Option-C |

3. Open **Taskbar & Dock** and turn on **Show Taskbar**.

Closing the window does not quit the app. Use the menu bar icon to reopen it or quit.

## Permissions

The app asks for a permission only when a feature needs it.

| Permission | Used for | When macOS asks |
| --- | --- | --- |
| Accessibility | Moving and resizing other apps' windows, the green button option | When you click Request Access |
| Automation: Finder | Reading which files are selected, to copy their paths | First use of Copy Path |
| Automation: System Events | Changing Dock auto-hide, position, and size | First use of a Dock switch |
| Desktop folder | Listing the files on your Desktop | First time you open Desktop Manager |

The app makes no network connections. The Donate buttons open a web page in your browser.

## How it works, and what macOS does not allow

macOS does not let apps change everything Windows users might expect. [docs/FEASIBILITY.md](docs/FEASIBILITY.md) lists, feature by feature, which public API is used, what the limits are, and where the app relies on behavior Apple does not document. A few to know up front:

- The app cannot be sandboxed, so it cannot be sold in the Mac App Store. Window control of other apps needs the Accessibility API.
- macOS shows the real Dock on one display at a time. The taskbar is this app's own bar, and only this app's maximize and snap know to stay clear of it.
- Turning the Dock off uses an undocumented Dock setting. The app asks before doing it, and one switch brings the Dock back.

## Building and testing

```bash
./build.sh          # generate the Xcode project and build a Debug app into ./build
./build.sh test     # run the unit tests
xcodegen generate   # regenerate the Xcode project, then open CNERDMacUtilities.xcodeproj
```

`project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after adding, moving, or deleting files.

**Signing.** By default the app is signed to run locally, which needs no Apple developer account. macOS forgets the Accessibility permission each time an ad-hoc signed app is rebuilt. To avoid that, create `Config/Signing.local.xcconfig` with your own certificate. See the comments in `Config/Signing.xcconfig`.

**Releases.** `./release.sh` builds a universal Release app, signs it with a Developer ID certificate, makes the `.dmg`, and can notarize it. See the comments at the top of the script.

## Project layout

```
project.yml                     XcodeGen project definition
Config/                         Signing settings, generated Info.plist and entitlements
CNERDMacUtilities/
  App/                          App entry point and app delegate
  Core/                         Settings store, environment, shared types
  Models/                       Plain data types and pure layout and ordering rules
  Services/                     Permissions, login item, global hot keys, Dock facts
  Modules/
    WindowManager/              Accessibility window control, geometry, green button tap
    Taskbar/                    Taskbar panels, running apps, Dock settings
    FinderEnhancements/         Finder preferences, selection path, folders
    DesktopManager/             Desktop file list, displays
  Views/                        SwiftUI screens, one per module, plus shared components
  Resources/                    Asset catalog, including the app icon
CNERDMacUtilitiesTests/         Unit tests
docs/                           FEASIBILITY.md and ARCHITECTURE.md
Artwork/                        Icon source artwork
```

More detail is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. The short version: public APIs only, no dependencies, every module can be switched off, and anything that leans on undocumented behavior is written down in `docs/FEASIBILITY.md`.

## Support development

CNERD Mac Utilities is free. If you want to help pay for the time that goes into it, the **Donate** button at the bottom of the app's sidebar offers $5, $10, $20, $50, and $100, or use the [CNERD shop](https://cnerd.ai/shop/?app=mac-utilities). Thank you.

After you donate, you can turn on **I Have Donated** in General Settings. It swaps the Donate button for a thank-you. It is on the honor system: nothing is checked, and nothing is locked either way.

## License

[MIT](LICENSE). Copyright (c) 2026 CNERD AI.

## Names, logos, and trademarks

The MIT license covers the source code. The CNERD AI and CNERD Mac Utilities names, logos, and app icon are trademarks of CNERD AI and are not part of that license. If you share a changed version, please give it your own name and icon.

CNERD Mac Utilities is not affiliated with, endorsed by, or sponsored by Apple Inc. or Microsoft Corporation. Mac, macOS, Finder, and Dock are trademarks of Apple Inc. Windows is a trademark of Microsoft Corporation. All other names, logos, and app icons belong to their owners, and are mentioned with respect, only to describe what this app works with.

The full note is in [TRADEMARKS.md](TRADEMARKS.md).
