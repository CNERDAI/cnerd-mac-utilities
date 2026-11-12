# Architecture

CNERD Mac Utilities is one native macOS app made of independent modules. This page explains how the pieces fit.

## The shape of the app

```
CNERDMacUtilitiesApp (SwiftUI App)
 ├─ Window "main"        MainWindowView: sidebar + one settings screen per module
 ├─ MenuBarExtra         quick actions, works while the main window is closed
 └─ AppEnvironment       creates and owns everything below
     ├─ AppSettings          all preferences, stored in UserDefaults
     ├─ PermissionsService   Accessibility and Automation status
     ├─ LoginItemService     launch at login (SMAppService)
     ├─ WindowManagerController
     ├─ TaskbarController
     ├─ FinderController
     └─ DesktopController
```

- **`AppEnvironment`** is the single place where services and modules are created and wired together. Views receive it through the SwiftUI environment.
- **`AppSettings`** is an `@Observable` class. Each property writes itself to UserDefaults and posts `appSettingsDidChange`. Views bind to it directly. Controllers listen for the notification and call their own `refresh()`.
- **Module controllers** own all system work for their module and conform to `UtilityModule`, which gives the Dashboard a status line. Views only read controller state and call controller methods.

## Rules the code follows

- Controllers and services are `@MainActor`. C callbacks (hot keys, the event tap) hop to the main actor with `MainActor.assumeIsolated`, because those callbacks are delivered on the main thread.
- Anything that can be a pure function is one: `ScreenGeometry`, `TaskbarLayout`, `TaskbarOrdering`. These have unit tests and no system calls.
- Event driven. The app reacts to workspace, screen, and Dock notifications. The only timer is a short, bounded one that waits for the Accessibility permission after the person asks for it.

## Window Manager

- **`AccessibilityWindowService`** wraps the Accessibility API (`AXUIElement`): find the focused window, read its frame, set its frame.
- **`ScreenGeometry`** works out target frames. Everything is in Accessibility coordinates (origin at the top left of the main display).
- **`WindowManagerController`** remembers, per window, where it was before the app moved it. Maximize on a window that is still where the app put it restores the earlier frame.
- **`HotKeyService`** registers global shortcuts with the system hot key API. No extra permission, no idle cost.
- **`GreenButtonInterceptor`** (beta, off by default) is a `CGEventTap` on left clicks. If the Accessibility API says the click is on a standard zoom or full screen button, the click is held back and the window is maximized instead. If anything is uncertain the click passes through untouched.

## Taskbar & Dock

- **`TaskbarPanel`** is a borderless, non-activating `NSPanel`. There is one per display that should show a taskbar. Its content is the SwiftUI `TaskbarView`.
- **`TaskbarController`** places the panels, keeps the app list current from workspace notifications, saves the order and the kept apps, and handles clicks and the right-click menu.
- **`TaskbarLayout`** turns the settings (edge, icon size, names, name size, rounded or square) into the bar's thickness and frame. The view uses the same numbers, so content always fits.
- **Free screen area.** The taskbar sits inside `NSScreen.usableFrame(dockIsHidden:)`. That is `visibleFrame`, except that when the Dock is hidden only the menu bar is subtracted. See `Services/DockInfo.swift` for why.
- **Dock switches** go through System Events (`dock preferences`). Turning the Dock off writes the Dock's `autohide-delay` preference and restarts the Dock. Both are described in `docs/FEASIBILITY.md`.
- **Window Manager tie-in.** `AppEnvironment` gives the Window Manager a closure that returns the space each taskbar takes, so maximize and snap stop at its edge.

## Finder Enhancements and Desktop Manager

- **`FinderController`** reads and writes Finder's hidden files preference, asks Finder for its selection through Apple Events, and opens folders with `NSWorkspace`.
- **`DesktopController`** lists the Desktop folder off the main thread and reads display facts from `NSScreen`. It never changes a file.

## Tests

`CNERDMacUtilitiesTests` covers geometry, taskbar layout and ordering, shortcuts, sorting, settings storage, and that every SF Symbol name used exists. Things that need other apps or permissions are on the manual checklist in `docs/FEASIBILITY.md`.
