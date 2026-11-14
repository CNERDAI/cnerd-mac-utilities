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
- Anything that can be a pure function is one: `ScreenGeometry`, `TaskbarLayout`, `TaskbarOrdering`, `TaskbarGrouping`, `TaskbarFitting`, `TaskbarAppScope`, `TaskbarDisplayRules`, `AppTopicClassifier`. These have unit tests and no system calls.
- Event driven. The app reacts to workspace, screen, and Dock notifications, and to the release of the mouse button while taskbars show apps per display. The only timer is a short, bounded one that waits for the Accessibility permission after the person asks for it.

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
- **Groups.** `TaskbarGroup` is a name plus a list of bundle identifiers. `TaskbarGrouping` holds the rules for moving apps and groups, and `AppTopicClassifier` decides an app's topic from its bundle identifier and declared category. The controller turns the groups into `TaskbarSection` values, which both the taskbar and the App Icon Controls screen draw. While grouping is on, the flat app order is kept equal to the groups laid end to end.
- **App Icon Controls** (`AppIconsSettingsView`) is a second screen for this module: icon size, group switches, and drag and drop arrangement. It has no controller of its own. It calls `TaskbarController`.
- **Trash menu.** Empty Trash goes to Finder through Apple Events after the app's own confirmation. The list of disks to eject comes from `FileManager` and is refreshed by mount and unmount notifications.
- **Opening settings from the taskbar.** The taskbar panel never becomes the front window, so `AppNavigation.show` brings the main window forward on the right screen.
- **Hidden apps.** A list of bundle identifiers in the settings. The controller leaves those apps out of the taskbar's sections and shows them in a second `TaskbarPanel` that holds `TaskbarPopupView`, using the same app cells as the bar. `TaskbarLayout` works out the pop-up's size and place. While the pop-up is open, two `NSEvent` monitors watch for clicks elsewhere and close it.
- **Auto-fit.** `TaskbarFitting.fit` takes a bar's length and what has to go on it, and returns the icon size, whether names show, and how many apps stay on the bar. The steps are: hide names, shrink icons down to 16 points, then keep what fits beside a More button. `TaskbarController.content(for:)` runs it for each display and gives `TaskbarView` a `TaskbarBarContent`: the sections that fit, and the apps that did not. The bar's thickness never changes, only what is drawn on it.
- **More pop-up.** The apps that did not fit sit behind the More button. Its pop-up is `TaskbarPopup.moreApps(display:)`, which shares the panel, the view, and the click-elsewhere monitors with Hidden Apps.
- **Apps per display.** `WindowLocator` (in `Services`) reads the public window list and works out which displays each process has windows on. `TaskbarController.refreshWindowLocations` keeps that in `appDisplays`, remembering the last place of an app with no window showing. `TaskbarAppScope.bars(forAppOn:bars:)` decides which taskbars show an app. macOS sends no notice when another app's window moves, so the controller looks again after the mouse button is released (two `NSEvent` monitors, installed only while apps are shown per display) and after an app starts or comes forward. There is no polling, so a window moved without the mouse is picked up at the next click.
- **Right-click menus.** The taskbar does not use SwiftUI's `contextMenu`, because macOS moves such a menu off the screen on a display above the main one (see `docs/FEASIBILITY.md`). A view marks its area with `.taskbarMenu(edge:items:)`. That measures the view's frame with a `GeometryReader`, in the window's own coordinate space, and reports it to the window's `TaskbarMenuRegistry` together with the menu as a list of `TaskbarMenuItem`. `TaskbarPanel.sendEvent` catches right-clicks and Control-clicks, takes the smallest region under the pointer that has a menu, turns the items into an `NSMenu` (`TaskbarMenuBuilder`), and opens it with `popUp(positioning:at:in:)`. On a bar the menu opens beside the bar (`TaskbarLayout.menuTopLeft`). In a pop-up it opens at the pointer.
- **Apps chosen per display.** `TaskbarDisplayRule` (in `Models/TaskbarDisplays.swift`) holds one display's setup: its mode, its chosen apps, and whether the bar keeps its buttons. `TaskbarDisplayRules` has the pure rules for changing the list. Rules are keyed by the display's UUID, because the display number changes between restarts. `TaskbarController.sections(includingEmpty:display:)` returns the chosen apps for such a display and skips groups, hidden apps, and Show Apps On. `content(for:)` tells the view whether to draw the buttons. The Displays section of App Icon Controls (`DisplayAppsSection`) and the Show on Display menu both call the controller.
- **This app's own icon.** macOS serves the small sizes of this app's icon on a light plate. `TaskbarController.makeOwnIcon` draws the `AppLogo` artwork inside `TaskbarLayout.iconBodyRect`, so it matches the size of the icons macOS supplies for other apps.
- **Apple Dock or taskbar.** `TaskbarController.switchBar` is the one place that changes between the two. The menu bar menu, the Dock icon's menu (`AppDelegate.applicationDockMenu`), the settings screen, and the Applications button's menu all call it.
- **Free screen area.** The taskbar sits inside `NSScreen.usableFrame(dockIsHidden:)`. That is `visibleFrame`, except that when the Dock is hidden only the menu bar is subtracted. See `Services/DockInfo.swift` for why.
- **Dock switches** go through System Events (`dock preferences`). Turning the Dock off writes the Dock's `autohide-delay` preference and restarts the Dock. Both are described in `docs/FEASIBILITY.md`.
- **Window Manager tie-in.** `AppEnvironment` gives the Window Manager a closure that returns the space each taskbar takes, so maximize and snap stop at its edge.

## Finder Enhancements and Desktop Manager

- **`FinderController`** reads and writes Finder's hidden files preference, asks Finder for its selection through Apple Events, and opens folders with `NSWorkspace`.
- **`DesktopController`** lists the Desktop folder off the main thread and reads display facts from `NSScreen`. It never changes a file.

## Tests

`CNERDMacUtilitiesTests` covers geometry, taskbar layout and ordering, auto-fit, apps per display, apps chosen per display, right-click menu placement and building, window locating, groups and topic sorting, shortcuts, sorting, settings storage, and that every SF Symbol name used exists. Things that need other apps or permissions are on the manual checklist in `docs/FEASIBILITY.md`.
