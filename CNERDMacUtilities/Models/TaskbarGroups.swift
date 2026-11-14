import Foundation

/// A named set of apps that sit side by side on the taskbar.
struct TaskbarGroup: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// Bundle identifiers in the order they show.
    var appIDs: [String]

    init(id: String = UUID().uuidString, name: String, appIDs: [String] = []) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

/// The topics apps are sorted into automatically.
enum AppTopic: String, CaseIterable, Identifiable, Sendable {
    case aiTools
    case browsers
    case communication
    case productivity
    case developer
    case creative
    case games
    case utilities
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiTools: "AI Tools"
        case .browsers: "Browsers"
        case .communication: "Communication"
        case .productivity: "Productivity"
        case .developer: "Developer Tools"
        case .creative: "Design & Media"
        case .games: "Games"
        case .utilities: "System & Utilities"
        case .other: "Other"
        }
    }

    /// The identifier of the group made for this topic. It stays the same when the group is
    /// renamed, so new apps keep finding their group.
    var groupID: String { "topic.\(rawValue)" }
}

/// Decides which topic an app belongs to. Pure rules, no system calls.
///
/// Apple's app categories have no entry for browsers or AI tools, so well-known apps are matched
/// by bundle identifier first. Everything else falls back to the category the app declares
/// (`LSApplicationCategoryType`). An app that matches nothing lands in Other, where it can be moved by hand.
enum AppTopicClassifier {
    /// Checked in this order. The first topic with a matching piece of the bundle identifier wins.
    private static let keywords: [(topic: AppTopic, words: [String])] = [
        (.aiTools, [
            "openai", "anthropic", "claude", "chatgpt", "copilot", "perplexity", "ollama", "lmstudio",
            "superwhisper", "gemini", "mistral",
        ]),
        (.browsers, [
            "com.apple.safari", "com.google.chrome", "org.mozilla.firefox", "com.microsoft.edgemac",
            "com.brave.browser", "company.thebrowser", "com.operasoftware", "com.vivaldi", "com.duckduckgo",
            "com.kagi.kagimacos", "org.chromium", "zen-browser",
        ]),
        (.communication, [
            "com.microsoft.outlook", "com.microsoft.teams", "slack", "zoom.us", "discord", "whatsapp", "telegram",
            "signal-desktop", "ringcentral", "skype", "webex", "com.apple.mail", "com.apple.mobilesms",
            "com.apple.facetime", "mimestream", "readdle.smartemail",
        ]),
        (.developer, [
            "com.apple.dt.", "com.apple.terminal", "com.microsoft.vscode", "com.jetbrains", "iterm2",
            "com.github.githubclient", "com.docker", "com.sublimetext", "dev.warp", "com.postmanlabs",
        ]),
        (.creative, [
            "com.adobe", "autodesk", "com.figma", "com.blackmagic", "com.bohemiancoding", "com.seriflabs",
            "com.apple.finalcut", "com.apple.logic", "com.apple.garageband", "com.apple.imovie", "com.apple.photos",
            "com.apple.music", "com.apple.tv", "com.apple.podcasts", "com.spotify", "org.videolan", "blender",
        ]),
        (.productivity, [
            "com.microsoft.word", "com.microsoft.excel", "com.microsoft.powerpoint", "com.microsoft.onenote",
            "com.apple.iwork", "com.apple.ical", "com.apple.notes", "com.apple.reminders", "com.apple.addressbook",
            "com.apple.preview", "notion", "md.obsidian", "com.todoist", "com.culturedcode", "com.flexibits", "evernote",
        ]),
        (.games, ["com.valvesoftware", "com.epicgames", "net.battle", "com.blizzard"]),
        (.utilities, [
            "com.apple.finder", "com.apple.systempreferences", "ai.cnerd.macutilities", "com.elgato", "remotepc",
            "teamviewer", "anydesk", "1password", "bitwarden", "com.ugreen",
        ]),
    ]

    /// - Parameters:
    ///   - bundleID: The app's bundle identifier.
    ///   - category: The app's `LSApplicationCategoryType`, if it declares one.
    static func topic(bundleID: String, category: String?) -> AppTopic {
        let id = bundleID.lowercased()
        for entry in keywords where entry.words.contains(where: id.contains) {
            return entry.topic
        }
        return category.flatMap(topic(forCategory:)) ?? .other
    }

    /// Maps Apple's app categories, for example "public.app-category.developer-tools".
    static func topic(forCategory category: String) -> AppTopic? {
        let name = category.lowercased().replacingOccurrences(of: "public.app-category.", with: "")
        if name.hasSuffix("games") { return .games }
        switch name {
        case "developer-tools": return .developer
        case "productivity", "business", "finance", "education", "reference": return .productivity
        case "social-networking": return .communication
        case "graphics-design", "photography", "video", "music", "entertainment": return .creative
        case "utilities": return .utilities
        default: return nil
        }
    }
}

/// Pure rules for arranging apps into groups.
enum TaskbarGrouping {
    /// Every grouped app, in the order the taskbar shows them.
    static func order(of groups: [TaskbarGroup]) -> [String] {
        groups.flatMap(\.appIDs)
    }

    /// Sorts apps into one group per topic. Apps keep their order inside each group.
    /// Topics with no apps get no group.
    static func byTopic(_ ids: [String], topic: (String) -> AppTopic) -> [TaskbarGroup] {
        var members: [AppTopic: [String]] = [:]
        var seen = Set<String>()
        for id in ids where !id.hasPrefix("pid:") && seen.insert(id).inserted {
            members[topic(id), default: []].append(id)
        }
        return AppTopic.allCases.compactMap { topic in
            members[topic].map { TaskbarGroup(id: topic.groupID, name: topic.title, appIDs: $0) }
        }
    }

    /// Adds apps that are in no group yet. Each goes to the end of its topic's group.
    /// A missing topic group is created, ahead of Other so that Other stays last.
    static func adding(_ ids: [String], to groups: [TaskbarGroup], topic: (String) -> AppTopic) -> [TaskbarGroup] {
        var result = groups
        var placed = Set(order(of: groups))
        for id in ids where !id.hasPrefix("pid:") && placed.insert(id).inserted {
            let topic = topic(id)
            if let index = result.firstIndex(where: { $0.id == topic.groupID }) {
                result[index].appIDs.append(id)
                continue
            }
            let group = TaskbarGroup(id: topic.groupID, name: topic.title, appIDs: [id])
            if topic != .other, result.last?.id == AppTopic.other.groupID {
                result.insert(group, at: result.count - 1)
            } else {
                result.append(group)
            }
        }
        return result
    }

    /// Puts one app directly before or after another, in that app's group. Doing it twice gives
    /// the same result, so it is safe to call over and over while the pointer moves during a drag.
    static func placing(_ id: String, before: Bool, target: String, in groups: [TaskbarGroup]) -> [TaskbarGroup] {
        guard id != target,
              groups.contains(where: { $0.appIDs.contains(id) }),
              let groupIndex = groups.firstIndex(where: { $0.appIDs.contains(target) })
        else { return groups }
        var result = removing(id, from: groups)
        guard let targetIndex = result[groupIndex].appIDs.firstIndex(of: target) else { return groups }
        result[groupIndex].appIDs.insert(id, at: before ? targetIndex : targetIndex + 1)
        return result
    }

    /// Moves an app to the end of a group. An app that is already in the group keeps its spot.
    static func moving(_ id: String, toGroup groupID: String, in groups: [TaskbarGroup]) -> [TaskbarGroup] {
        guard !id.hasPrefix("pid:"),
              let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              !groups[groupIndex].appIDs.contains(id)
        else { return groups }
        var result = removing(id, from: groups)
        result[groupIndex].appIDs.append(id)
        return result
    }

    /// Moves a group into the spot another group holds. The other groups close the gap.
    static func placingGroup(_ id: String, at target: String, in groups: [TaskbarGroup]) -> [TaskbarGroup] {
        guard id != target,
              let from = groups.firstIndex(where: { $0.id == id }),
              let to = groups.firstIndex(where: { $0.id == target })
        else { return groups }
        var result = groups
        result.insert(result.remove(at: from), at: to)
        return result
    }

    /// Moves a group up (negative) or down (positive) by a number of places.
    static func shiftingGroup(_ id: String, by offset: Int, in groups: [TaskbarGroup]) -> [TaskbarGroup] {
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return groups }
        let to = min(max(from + offset, 0), groups.count - 1)
        guard to != from else { return groups }
        var result = groups
        result.insert(result.remove(at: from), at: to)
        return result
    }

    /// True when a group can be removed. Other cannot be removed while it holds apps,
    /// because it is where the apps of a removed group go.
    static func canRemoveGroup(_ id: String, from groups: [TaskbarGroup]) -> Bool {
        guard let group = groups.first(where: { $0.id == id }) else { return false }
        return group.id != AppTopic.other.groupID || group.appIDs.isEmpty
    }

    /// Removes a group. Its apps move to Other, which is created when needed.
    static func removingGroup(_ id: String, from groups: [TaskbarGroup]) -> [TaskbarGroup] {
        guard canRemoveGroup(id, from: groups), let index = groups.firstIndex(where: { $0.id == id }) else { return groups }
        var result = groups
        let removed = result.remove(at: index)
        guard !removed.appIDs.isEmpty else { return result }
        let other = AppTopic.other
        if let otherIndex = result.firstIndex(where: { $0.id == other.groupID }) {
            result[otherIndex].appIDs += removed.appIDs
        } else {
            result.append(TaskbarGroup(id: other.groupID, name: other.title, appIDs: removed.appIDs))
        }
        return result
    }

    /// A name no other group uses: "New Group", then "New Group 2", and so on.
    static func uniqueName(_ base: String, in groups: [TaskbarGroup]) -> String {
        let taken = Set(groups.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private static func removing(_ id: String, from groups: [TaskbarGroup]) -> [TaskbarGroup] {
        var result = groups
        for index in result.indices {
            result[index].appIDs.removeAll { $0 == id }
        }
        return result
    }
}
