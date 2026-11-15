import Foundation

/// The settings that can be saved to a file and taken to another Mac.
///
/// Every value is optional, so a file from an older or a newer version still reads: a setting
/// the file does not have is left alone. Choices are stored as plain text ("bottom", "rounded"),
/// so a choice this version does not know is skipped and the rest still applies.
struct SettingsSnapshot: Codable, Equatable, Sendable {
    // Window Manager
    var windowManagerEnabled: Bool?
    var maximizeEnabled: Bool?
    var greenButtonEnabled: Bool?
    var snappingEnabled: Bool?
    var windowShortcutsEnabled: Bool?
    /// Keyboard shortcuts by action name. An action that is missing has no shortcut.
    var shortcuts: [String: KeyCombo]?

    // Finder Enhancements
    var finderEnabled: Bool?

    // Desktop Manager
    var desktopEnabled: Bool?
    var desktopSortOrder: String?

    // Taskbar
    var taskbarEnabled: Bool?
    var taskbarDisplayMode: String?
    var taskbarAppScope: String?
    var taskbarShowAppNames: Bool?
    var taskbarReserveSpace: Bool?
    var taskbarPosition: String?
    var taskbarIconPoints: Double?
    var taskbarNamePosition: String?
    var taskbarGlassBackground: Bool?
    var taskbarCornerStyle: String?
    var taskbarNameSize: String?
    var taskbarShowTrash: Bool?
    var taskbarPinnedApps: [String]?
    var taskbarAppOrder: [String]?
    var taskbarGroupingEnabled: Bool?
    var taskbarAutoGroupNewApps: Bool?
    var taskbarGroups: [TaskbarGroup]?
    var taskbarHiddenApps: [String]?
    var taskbarHiddenIcon: String?
    var taskbarDisplayRules: [TaskbarDisplayRule]?

    // General
    var showMenuBarIcon: Bool?
    var hasDonated: Bool?

    /// Every app the settings name, each one once: kept, hidden, and chosen for a display.
    var namedApps: Set<String> {
        var ids = Set(taskbarPinnedApps ?? [])
        ids.formUnion(taskbarHiddenApps ?? [])
        for rule in taskbarDisplayRules ?? [] { ids.formUnion(rule.appIDs) }
        return ids
    }
}

/// A display as a settings file remembers it, so the per-display setup can find its display
/// again on another Mac.
struct BackupDisplay: Codable, Equatable, Sendable {
    /// The display's own identifier. See `TaskbarDisplayRule.displayKey`.
    var key: String
    var name: String
    var isMain: Bool
}

/// Why a file could not be imported.
enum SettingsBackupError: Error, Equatable {
    case notASettingsFile
    /// The file's format is newer than this version reads. Carries the version that wrote it.
    case madeByNewerVersion(String)

    var message: String {
        switch self {
        case .notASettingsFile:
            "That file is not a CNERD Mac Utilities settings file, or it is damaged."
        case .madeByNewerVersion(let version):
            "That file was made by a newer version (\(version)). Update CNERD Mac Utilities on this Mac, then import it again."
        }
    }
}

/// A settings file: the settings, plus a few facts about where they came from.
/// Saved as plain, readable JSON with the extension "cnerdsettings".
struct SettingsBackup: Codable, Equatable, Sendable {
    /// Marks the file as ours. This is the app's bundle identifier.
    static let appID = "ai.cnerd.MacUtilities"
    /// Raised only when a newer file can no longer be read by older versions.
    static let currentFormat = 1
    static let fileExtension = "cnerdsettings"
    /// Larger files are not ours. A full setup is a few thousand bytes.
    static let largestFileSize = 2_000_000

    var app = SettingsBackup.appID
    var format = SettingsBackup.currentFormat
    /// The version that wrote the file, such as "1.3.0 (12)".
    var appVersion: String
    var exportedAt: Date
    /// The name of the Mac the file was made on. Only shown when the file is imported.
    var computerName: String?
    /// The displays connected when the file was made, the main display first.
    var displays: [BackupDisplay]?
    var settings: SettingsSnapshot

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> SettingsBackup {
        guard data.count <= largestFileSize else { throw SettingsBackupError.notASettingsFile }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Read the two marks first, so a newer file is named as newer even if the rest changed.
        guard let marks = try? decoder.decode(Marks.self, from: data), marks.app == appID else {
            throw SettingsBackupError.notASettingsFile
        }
        guard marks.format <= currentFormat else {
            throw SettingsBackupError.madeByNewerVersion(marks.appVersion ?? "unknown")
        }
        guard marks.format >= 1, let backup = try? decoder.decode(SettingsBackup.self, from: data) else {
            throw SettingsBackupError.notASettingsFile
        }
        return backup
    }

    private struct Marks: Decodable {
        let app: String
        let format: Int
        let appVersion: String?
    }

    /// Finds, for each per-display setup in a file, the display it belongs to on this Mac.
    ///
    /// A display keeps its identifier on its own Mac, so a setup whose display is connected stays
    /// as it is. Another Mac has other identifiers. There, a setup moves to the display with the
    /// same name, or else to the display in the same place in the list (the main display is
    /// first), but only to a display the file's Mac did not know, so restoring on the same Mac
    /// never moves a setup to the wrong display. A setup that finds no display is kept as it is,
    /// so it works again when its display comes back. Its display name is returned in `unmatched`.
    static func placing(
        _ rules: [TaskbarDisplayRule], from exported: [BackupDisplay], on current: [BackupDisplay]
    ) -> (rules: [TaskbarDisplayRule], unmatched: [String]) {
        let currentKeys = Set(current.map(\.key))
        let exportedKeys = Set(exported.map(\.key))
        // Displays that already have their setup, by identifier.
        var taken = Set(rules.map(\.displayKey).filter { currentKeys.contains($0) })
        /// Displays of this Mac that a setup from another Mac may move to.
        func isFree(_ display: BackupDisplay) -> Bool {
            !taken.contains(display.key) && !exportedKeys.contains(display.key)
        }

        var result: [TaskbarDisplayRule] = []
        var unmatched: [String] = []
        for rule in rules {
            guard !currentKeys.contains(rule.displayKey) else {
                result.append(rule)
                continue
            }
            let sameName = current.filter { $0.name == rule.displayName && isFree($0) }
            var target = sameName.count == 1 ? sameName.first : nil
            if target == nil, let index = exported.firstIndex(where: { $0.key == rule.displayKey }),
               current.indices.contains(index), isFree(current[index]) {
                target = current[index]
            }
            if let target {
                var moved = rule
                moved.displayKey = target.key
                moved.displayName = target.name
                taken.insert(target.key)
                result.append(moved)
            } else {
                result.append(rule)
                unmatched.append(rule.displayName)
            }
        }
        return (result, unmatched)
    }
}
