import AppKit
import Observation
import SystemConfiguration
import UniformTypeIdentifiers

/// Saves the whole setup to a file and reads it back, so it can move to another Mac.
///
/// Nothing here touches the network. The file is plain JSON that the person saves and sends
/// wherever they like. Before an import changes anything, the settings in use are saved to
/// Application Support, so the import can be undone.
@MainActor
@Observable
final class SettingsTransferService {
    /// What the last export or import did, shown under the buttons.
    struct Notice: Equatable {
        var text: String
        var isProblem = false
    }

    private(set) var notice: Notice?
    /// True when the settings from before the last import are still on file.
    private(set) var canUndoImport = false

    private let settings: AppSettings
    private let undoFile: URL?
    /// The displays connected right now, the main display first. Set by `AppEnvironment`.
    @ObservationIgnored var connectedDisplays: () -> [BackupDisplay] = { [] }
    /// Turns the taskbar on or off the safe way, bringing the macOS Dock back when the taskbar
    /// goes away. Set by `AppEnvironment`. Without it the setting is changed directly.
    @ObservationIgnored var showTaskbar: ((Bool) -> Void)?

    /// - Parameter undoFolder: Where the settings from before an import are kept. Tests pass
    ///   their own folder. The app uses its folder in Application Support.
    init(settings: AppSettings, undoFolder: URL? = nil) {
        self.settings = settings
        let folder = undoFolder ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(AppInfo.name, isDirectory: true)
        undoFile = folder?.appendingPathComponent("Before Last Import.\(SettingsBackup.fileExtension)")
        canUndoImport = undoFile.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    // MARK: - The file

    /// The settings in use right now, as a file.
    func makeBackup() -> SettingsBackup {
        SettingsBackup(
            appVersion: AppInfo.versionDisplay,
            exportedAt: Date(),
            computerName: SCDynamicStoreCopyComputerName(nil, nil) as String?,
            displays: connectedDisplays(),
            settings: settings.snapshot()
        )
    }

    /// Applies a file's settings and says what happened. The settings in use are saved first.
    @discardableResult
    func apply(_ backup: SettingsBackup, savingUndo: Bool = true) -> Notice {
        if savingUndo { saveUndoCopy() }

        var snapshot = backup.settings
        var unmatched: [String] = []
        if let rules = snapshot.taskbarDisplayRules {
            let placed = SettingsBackup.placing(rules, from: backup.displays ?? [], on: connectedDisplays())
            snapshot.taskbarDisplayRules = placed.rules
            unmatched = placed.unmatched
        }
        // The taskbar switch goes last and through the taskbar itself, so the Dock comes back
        // when an import turns the taskbar off on a Mac where the Dock was turned off.
        let wantsTaskbar = snapshot.taskbarEnabled
        snapshot.taskbarEnabled = nil
        settings.apply(snapshot)
        if let wantsTaskbar, wantsTaskbar != settings.taskbarEnabled {
            if let showTaskbar {
                showTaskbar(wantsTaskbar)
            } else {
                settings.taskbarEnabled = wantsTaskbar
            }
        }

        var parts = ["Settings imported."]
        let missing = backup.settings.namedApps.filter { !isInstalled($0) }.count
        if missing == 1 {
            parts.append("1 app in the file is not installed on this Mac. It shows on the taskbar once it is installed.")
        } else if missing > 1 {
            parts.append("\(missing) apps in the file are not installed on this Mac. They show on the taskbar once they are installed.")
        }
        if !unmatched.isEmpty {
            let names = unmatched.map { $0.isEmpty ? "a display" : $0 }.joined(separator: ", ")
            parts.append("The setup for \(names) found no matching display here. It is kept, and you can set up this Mac's displays in App Icon Controls.")
        }
        return Notice(text: parts.joined(separator: " "))
    }

    // MARK: - Buttons

    /// Asks where to save, then writes the settings file.
    func exportWithPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "\(AppInfo.name) Settings.\(SettingsBackup.fileExtension)"
        panel.allowedContentTypes = [Self.fileType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try makeBackup().encoded().write(to: url, options: .atomic)
            notice = Notice(text: "Settings exported to \(url.lastPathComponent). Copy that file to another Mac and choose Import there.")
        } catch {
            notice = Notice(text: "The settings could not be saved: \(error.localizedDescription)", isProblem: true)
        }
    }

    /// Asks for a settings file, shows what is in it, and applies it after a yes.
    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Settings"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [Self.fileType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let backup: SettingsBackup
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= SettingsBackup.largestFileSize else { throw SettingsBackupError.notASettingsFile }
            backup = try SettingsBackup.decoded(from: Data(contentsOf: url))
        } catch let error as SettingsBackupError {
            notice = Notice(text: error.message, isProblem: true)
            return
        } catch {
            notice = Notice(text: "The file could not be read: \(error.localizedDescription)", isProblem: true)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import these settings?"
        alert.informativeText = Self.summary(of: backup)
            + "\n\nThey replace the settings on this Mac. Your current settings are saved first, so you can undo this."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        notice = apply(backup)
    }

    /// Puts back the settings from before the last import.
    func undoLastImport() {
        guard let undoFile, let data = try? Data(contentsOf: undoFile),
              let backup = try? SettingsBackup.decoded(from: data)
        else {
            canUndoImport = false
            notice = Notice(text: "The settings from before the import could not be found.", isProblem: true)
            return
        }
        apply(backup, savingUndo: false)
        try? FileManager.default.removeItem(at: undoFile)
        canUndoImport = false
        notice = Notice(text: "The settings from before the import are back.")
    }

    // MARK: - Pieces

    /// A few plain lines about a file, for the question before an import.
    static func summary(of backup: SettingsBackup) -> String {
        var lines: [String] = []
        if let name = backup.computerName, !name.isEmpty { lines.append("From: \(name)") }
        lines.append("Saved: \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Made with version \(backup.appVersion)")
        let kept = backup.settings.taskbarPinnedApps?.count ?? 0
        let groups = backup.settings.taskbarGroups?.count ?? 0
        let setups = backup.settings.taskbarDisplayRules?.count ?? 0
        lines.append("Taskbar: \(kept) kept \(kept == 1 ? "app" : "apps"), \(groups) \(groups == 1 ? "group" : "groups"), \(setups) display \(setups == 1 ? "setup" : "setups")")
        return lines.joined(separator: "\n")
    }

    private static var fileType: UTType {
        UTType(filenameExtension: SettingsBackup.fileExtension, conformingTo: .json) ?? .json
    }

    private func saveUndoCopy() {
        guard let undoFile else { return }
        do {
            try FileManager.default.createDirectory(at: undoFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try makeBackup().encoded().write(to: undoFile, options: .atomic)
            canUndoImport = true
        } catch {
            canUndoImport = false
        }
    }

    private func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
