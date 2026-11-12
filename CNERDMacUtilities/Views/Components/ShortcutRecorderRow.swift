import AppKit
import SwiftUI

/// Shows one keyboard shortcut and lets the user record a new one.
/// Click the button, then press the new key combination. Escape cancels.
struct ShortcutRecorderRow: View {
    let action: ShortcutAction

    @Environment(AppEnvironment.self) private var environment
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    private var combo: KeyCombo? {
        environment.settings.shortcuts[action]
    }

    private var displayedMessage: String? {
        if let message { return message }
        if environment.windowManager.unavailableShortcuts.contains(action) {
            return "macOS would not register this shortcut. Another app may be using it."
        }
        return nil
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    Text(isRecording ? "Press keys…" : (combo?.displayString ?? "None"))
                        .frame(minWidth: 92)
                }
                .help(isRecording ? "Press the new shortcut, or Escape to cancel" : "Click to record a new shortcut")

                Button(action: clear) {
                    Image(systemName: AppSymbol.remove)
                }
                .buttonStyle(.borderless)
                .disabled(combo == nil || isRecording)
                .help("Remove this shortcut")
                .accessibilityLabel("Remove shortcut for \(action.title)")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let displayedMessage {
                    Text(displayedMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        message = nil
        isRecording = true
        // Existing shortcuts are paused so pressing one can be recorded instead of triggering it.
        environment.windowManager.setShortcutsSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        environment.windowManager.setShortcutsSuspended(false)
    }

    private func clear() {
        message = nil
        environment.settings.shortcuts[action] = nil
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty, event.keyCode == 53 { // Escape
            stopRecording()
            return
        }
        guard let newCombo = KeyCombo(event: event) else {
            message = "Include Control, Option, or Command."
            return
        }
        // Never take over a shortcut macOS itself is using.
        if SystemShortcuts.isUsedByMacOS(newCombo) {
            message = "\(newCombo.displayString) is used by macOS. Choose another."
            return
        }
        let duplicate = environment.settings.shortcuts.first { other, otherCombo in
            other != action
                && otherCombo.keyCode == newCombo.keyCode
                && otherCombo.carbonModifiers == newCombo.carbonModifiers
        }
        if let duplicate {
            message = "\(newCombo.displayString) is already used for \(duplicate.key.title)."
            return
        }
        environment.settings.shortcuts[action] = newCombo
        stopRecording()
    }
}
