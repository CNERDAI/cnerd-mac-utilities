import CoreGraphics
import Foundation

/// How one display's taskbar gets its apps.
enum TaskbarDisplayAppMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The apps the Show Apps On setting gives this display.
    case followScope
    /// Only the apps chosen for this display, running or not.
    case chosenApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followScope: "Same as Show Apps On"
        case .chosenApps: "Only Apps I Choose"
        }
    }
}

/// What the person set up for one display's taskbar. A display without a rule follows Show Apps On.
struct TaskbarDisplayRule: Codable, Equatable, Identifiable, Sendable {
    /// The display's own identifier (its UUID as text). It stays the same after a restart and
    /// after the display is unplugged and plugged back in. The display number macOS hands out
    /// while the Mac is running does not.
    var displayKey: String
    /// The display's name when the rule was last changed.
    var displayName: String
    var mode: TaskbarDisplayAppMode = .followScope
    /// Bundle identifiers of the chosen apps, in the order the taskbar shows them. Kept while the
    /// mode is `followScope`, so switching back brings the same apps.
    var appIDs: [String] = []
    /// When on, a taskbar with chosen apps also shows the Applications, Hidden Apps, and Trash buttons.
    var showsButtons = false

    var id: String { displayKey }

    /// True when the rule says nothing, so it does not need to be stored.
    var isDefault: Bool {
        mode == .followScope && appIDs.isEmpty && !showsButtons
    }
}

/// One display that shows a taskbar, as the settings screen lists it.
struct TaskbarDisplay: Identifiable, Equatable, Sendable {
    /// The display number macOS uses while the Mac is running.
    let id: UInt32
    /// The display's stable identifier. See `TaskbarDisplayRule.displayKey`.
    let key: String
    let name: String
    /// Size in points.
    let size: CGSize
    /// True for the display with the menu bar.
    let isMain: Bool

    var sizeText: String {
        "\(Int(size.width)) × \(Int(size.height)) points"
    }
}

/// Pure rules for the per-display setup. Every function returns a new list and leaves a rule out
/// once it says nothing, so the stored list stays short.
enum TaskbarDisplayRules {
    static func rule(for key: String, in rules: [TaskbarDisplayRule]) -> TaskbarDisplayRule? {
        rules.first { $0.displayKey == key }
    }

    /// True when the display shows only its chosen apps.
    static func showsChosenApps(_ key: String, in rules: [TaskbarDisplayRule]) -> Bool {
        rule(for: key, in: rules)?.mode == .chosenApps
    }

    /// Changes one display's rule, creating it first if the display has none.
    static func updating(
        _ key: String, name: String, in rules: [TaskbarDisplayRule], _ change: (inout TaskbarDisplayRule) -> Void
    ) -> [TaskbarDisplayRule] {
        var result = rules
        var rule = rule(for: key, in: rules) ?? TaskbarDisplayRule(displayKey: key, displayName: name)
        if !name.isEmpty { rule.displayName = name }
        change(&rule)
        result.removeAll { $0.displayKey == key }
        if !rule.isDefault { result.append(rule) }
        return result
    }

    /// Adds apps to the end of a display's chosen apps. Apps already there keep their place.
    /// Apps without a bundle identifier ("pid:123") cannot be chosen, because the number changes.
    static func adding(_ appIDs: [String], to key: String, name: String, in rules: [TaskbarDisplayRule]) -> [TaskbarDisplayRule] {
        updating(key, name: name, in: rules) { rule in
            for id in appIDs where !id.hasPrefix("pid:") && !rule.appIDs.contains(id) {
                rule.appIDs.append(id)
            }
        }
    }

    static func removing(_ appID: String, from key: String, in rules: [TaskbarDisplayRule]) -> [TaskbarDisplayRule] {
        guard let existing = rule(for: key, in: rules), existing.appIDs.contains(appID) else { return rules }
        return updating(key, name: existing.displayName, in: rules) { rule in
            rule.appIDs.removeAll { $0 == appID }
        }
    }

    /// Puts an app directly before or after another chosen app. An app that was not chosen yet
    /// joins the list. Doing it twice gives the same result, so it is safe to call over and over
    /// while the pointer moves during a drag.
    static func placing(
        _ appID: String, before: Bool, target: String, on key: String, name: String, in rules: [TaskbarDisplayRule]
    ) -> [TaskbarDisplayRule] {
        guard !appID.hasPrefix("pid:"), appID != target,
              let existing = rule(for: key, in: rules), existing.appIDs.contains(target)
        else { return rules }
        return updating(key, name: name, in: rules) { rule in
            rule.appIDs.removeAll { $0 == appID }
            guard let index = rule.appIDs.firstIndex(of: target) else { return }
            rule.appIDs.insert(appID, at: before ? index : index + 1)
        }
    }

    /// The displays, by key, that show this app as one of their chosen apps.
    static func displays(showing appID: String, in rules: [TaskbarDisplayRule]) -> Set<String> {
        Set(rules.filter { $0.mode == .chosenApps && $0.appIDs.contains(appID) }.map(\.displayKey))
    }
}
