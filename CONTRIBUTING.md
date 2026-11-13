# Contributing

Thanks for helping. A few rules keep the app small and trustworthy.

## Ground rules

1. **Public APIs only.** No private frameworks, no code injection, nothing that needs System Integrity Protection off.
2. **Write down the gray areas.** If a feature depends on an undocumented preference key, notification, or command-line argument, add it to `docs/FEASIBILITY.md` with the limit and the fallback.
3. **No dependencies.** Swift, SwiftUI, and AppKit cover everything so far.
4. **Every module can be switched off,** and does nothing while off.
5. **Ask for a permission only when a feature needs it,** and only after the person clicks something.
6. **No network connections, no telemetry.**
7. **No timers that poll.** React to notifications and events.

## Code style

- Swift 6 language mode with strict concurrency. Controllers are `@MainActor`.
- Views never call system APIs. They read state from a module controller and call its methods.
- Pure rules (geometry, layout, ordering) live in `Models/` or as static functions, with unit tests.
- Plain comments that explain why, not what.

## Before you open a pull request

```bash
./build.sh test
```

All tests must pass with no compiler warnings. Add tests for new pure logic. For anything that touches other apps' windows, the Dock, or Finder, say in the pull request what you tried by hand and on which macOS version.

## Adding a module

1. Add a case to `SidebarItem` (title, symbol, tint, summary) and include it in `SidebarItem.modules`.
2. Add its preferences to `AppSettings`.
3. Create a controller in `Modules/<Name>/` that conforms to `UtilityModule`.
4. Create it in `AppEnvironment` and add it to `modules`.
5. Add a screen in `Views/Settings/` and route to it in `MainWindowView.detail(for:)`.
6. Run `xcodegen generate`.

By contributing you agree that your work is released under the MIT license. The CNERD AI and CNERD Mac Utilities names and logos are not part of that license. See [TRADEMARKS.md](TRADEMARKS.md).
