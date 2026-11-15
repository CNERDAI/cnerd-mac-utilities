import AppKit
import Observation

/// Knows whether the Trash has anything in it, so the taskbar can show a full or an empty Trash.
///
/// There are two sources, and neither one ever shows a permission prompt:
///
/// - **The Dock's own note.** The Dock keeps the state of the Trash in its preferences
///   ("trash-full"). Reading it needs no permission, and it covers the Trash of every disk.
/// - **Finder.** Finder can say how many items the Trash holds. That is the exact answer, but it
///   needs the Automation permission for Finder. Finder is only asked when that permission was
///   already given, which happens the first time Empty Trash or Copy Path is used.
///
/// The folder itself (~/.Trash) cannot be read without Full Disk Access, so it is not used.
///
/// Event driven, with no timer. The Dock's note is watched for changes, and the taskbar asks
/// again when apps come and go, when the pointer reaches the Trash, and after Empty Trash.
/// See docs/FEASIBILITY.md.
@MainActor
@Observable
final class TrashMonitor {
    /// True when the Trash holds at least one item.
    private(set) var hasItems: Bool

    /// On while a taskbar shows the Trash. Finder is not asked while this is off.
    @ObservationIgnored var isWatching = false {
        didSet { if isWatching, !oldValue { refresh() } }
    }

    @ObservationIgnored private var dockObserver: DefaultsBoolObserver?
    /// True while a question to Finder is on its way.
    @ObservationIgnored private var isAsking = false
    /// Something changed while Finder was being asked, so it is asked once more afterward.
    @ObservationIgnored private var shouldAskAgain = false

    init() {
        hasItems = DockInfo.trashIsFull
        guard let dockDefaults = UserDefaults(suiteName: DockInfo.domain) else { return }
        dockObserver = DefaultsBoolObserver(defaults: dockDefaults, key: DockInfo.trashFullKey) { [weak self] isFull in
            self?.dockNoteChanged(isFull)
        }
    }

    /// Works out the state again. Cheap, and safe to call often: calls made while Finder is
    /// still answering are folded into one more question.
    func refresh() {
        guard isWatching else { return }
        guard !isAsking else {
            shouldAskAgain = true
            return
        }
        isAsking = true
        Task { [weak self] in
            let count = await FinderTrash.itemCount()
            self?.finish(finderCount: count)
        }
    }

    /// Finder knows exactly. Without an answer from Finder, the Dock's note decides.
    nonisolated static func hasItems(finderCount: Int?, dockSaysFull: Bool) -> Bool {
        if let finderCount { return finderCount > 0 }
        return dockSaysFull
    }

    private func finish(finderCount: Int?) {
        isAsking = false
        show(Self.hasItems(finderCount: finderCount, dockSaysFull: DockInfo.trashIsFull))
        if shouldAskAgain {
            shouldAskAgain = false
            refresh()
        }
    }

    /// The Dock has just changed its note, so the note is fresh. It is shown at once, and Finder
    /// confirms it when Finder may be asked.
    private func dockNoteChanged(_ isFull: Bool) {
        show(isFull)
        refresh()
    }

    private func show(_ value: Bool) {
        if hasItems != value { hasItems = value }
    }
}

/// Asks Finder about the Trash through Apple Events, away from the main thread, so a busy
/// Finder never holds up the taskbar.
enum FinderTrash {
    private static let queue = DispatchQueue(label: "ai.cnerd.MacUtilities.finder-trash", qos: .utility)
    private static let finderID = "com.apple.finder"

    /// How many items the Trash holds, counting every disk. Nil when Finder cannot be asked:
    /// Finder is not running, this app is not allowed to control it, or it did not answer in time.
    /// Never shows the macOS permission prompt.
    static func itemCount() async -> Int? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: itemCountNow()) }
        }
    }

    /// True when this app was already allowed to control Finder and Finder is running.
    /// Checks without showing the macOS prompt.
    static func canAsk() -> Bool {
        let finder = NSAppleEventDescriptor(bundleIdentifier: finderID)
        let status = AEDeterminePermissionToAutomateTarget(
            finder.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false
        )
        return status == noErr
    }

    /// The same question AppleScript sends for `count items of trash`, built by hand so it can
    /// be sent from a background thread.
    private static func itemCountNow() -> Int? {
        // Asking without permission would show the macOS prompt, so stop unless it was already given.
        guard canAsk() else { return nil }

        // "trash" is a property of the Finder application.
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("trsh")), forKeyword: code("seld"))
        record.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: code("from"))
        guard let trash = record.coerce(toDescriptorType: code("obj ")) else { return nil }

        // Count (core/cnte) the items (cobj) of the Trash.
        let event = NSAppleEventDescriptor(
            eventClass: code("core"), eventID: code("cnte"),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: finderID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(trash, forKeyword: code("----"))
        event.setParam(NSAppleEventDescriptor(typeCode: code("cobj")), forKeyword: code("kocl"))

        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 3) else { return nil }
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 { return nil }
        guard let number = reply.paramDescriptor(forKeyword: code("----"))?.coerce(toDescriptorType: code("long")) else { return nil }
        return Int(number.int32Value)
    }

    /// A four-letter Apple Event code as a number.
    private static func code(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}

/// Watches one on or off value in another app's preferences. macOS reports the change as soon
/// as that app saves it.
private final class DefaultsBoolObserver: NSObject {
    private let defaults: UserDefaults
    private let key: String
    private let onChange: @MainActor @Sendable (Bool) -> Void

    init(defaults: UserDefaults, key: String, onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.defaults = defaults
        self.key = key
        self.onChange = onChange
        super.init()
        defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
    }

    deinit {
        defaults.removeObserver(self, forKeyPath: key)
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        // The key has a hyphen in it, so it cannot be watched with a Swift key path.
        let isOn = defaults.bool(forKey: key)
        let onChange = onChange
        Task { @MainActor in onChange(isOn) }
    }
}
