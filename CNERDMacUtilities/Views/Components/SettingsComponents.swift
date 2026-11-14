import AppKit
import SwiftUI

/// Rounded, colored icon in the style of the System Settings sidebar.
struct TintedIcon: View {
    let symbolName: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.52, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A settings screen: a header followed by grouped sections, like a System Settings pane.
struct SettingsPage<Content: View>: View {
    private let item: SidebarItem
    private let content: Content

    init(_ item: SidebarItem, @ViewBuilder content: () -> Content) {
        self.item = item
        self.content = content()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    TintedIcon(symbolName: item.symbolName, tint: item.tint, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.title2.weight(.semibold))
                        Text(item.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            content
        }
        .formStyle(.grouped)
        .toggleStyle(ClearSwitchToggleStyle())
        .navigationTitle(item.title)
    }
}

/// Title with a short explanation underneath. Used as the label of every setting.
struct SettingLabel: View {
    let title: String
    var description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Color {
    /// The system accent color, the same in front and background windows.
    /// SwiftUI's `Color.accentColor` turns gray in any window that is not in front, and the taskbar
    /// is never the front window, so anything that has to stay readable there uses this instead.
    static var steadyAccent: Color { Color(nsColor: .controlAccentColor) }
}

/// A switch that shows on and off clearly even when the window is in the background.
///
/// macOS draws its own switches gray in every window that is not in front. This app's window is
/// often behind another app while its settings are being tried out, and then on and off looked
/// almost the same. This switch has the same shape and keeps its color.
struct ClearSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ClearSwitchRow(configuration: configuration)
    }
}

private struct ClearSwitchRow: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    private static let trackSize = CGSize(width: 38, height: 20)
    private static let knobSize = CGSize(width: 22, height: 16)

    var body: some View {
        LabeledContent {
            track
                .contentShape(Capsule())
                .onTapGesture { toggle() }
                // Reachable with the Tab key when keyboard navigation is on in macOS, like any switch.
                .focusable(interactions: .activate)
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    toggle()
                    return .handled
                }
        } label: {
            configuration.label
        }
        // VoiceOver and other assistive tools see one switch per row, named by its label.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { toggle() }
    }

    private func toggle() {
        guard isEnabled else { return }
        configuration.isOn.toggle()
    }

    private var track: some View {
        let isOn = configuration.isOn
        return Capsule()
            .fill(isOn ? Color.steadyAccent : Color.primary.opacity(0.2))
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: Self.knobSize.width, height: Self.knobSize.height)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
            }
            .overlay {
                if isFocused {
                    Capsule().strokeBorder(Color.steadyAccent.opacity(0.6), lineWidth: 3).padding(-4)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A switch with a name and a short explanation.
struct SettingToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingLabel(title: title, description: description)
        }
    }
}

/// A setting with any control on the trailing side.
struct SettingRow<Accessory: View>: View {
    private let title: String
    private let description: String?
    private let accessory: Accessory

    init(_ title: String, description: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.description = description
        self.accessory = accessory()
    }

    var body: some View {
        LabeledContent {
            accessory
        } label: {
            SettingLabel(title: title, description: description)
        }
    }
}

/// Small colored dot with a status word.
struct StatusBadge: View {
    enum Level {
        case good
        case off
        case attention
    }

    let text: String
    let level: Level

    init(_ text: String, level: Level) {
        self.text = text
        self.level = level
    }

    init(_ status: ModuleStatus) {
        text = status.text
        switch status {
        case .active: level = .good
        case .disabled: level = .off
        case .needsAttention: level = .attention
        }
    }

    private var color: Color {
        switch level {
        case .good: .green
        case .off: .secondary
        case .attention: .orange
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A one-line notice inside a section.
struct NoticeRow: View {
    enum Kind {
        case warning
        case info
        case success
    }

    let text: String
    var kind: Kind = .info

    private var symbolName: String {
        switch kind {
        case .warning: AppSymbol.warning
        case .info: AppSymbol.info
        case .success: AppSymbol.checkmark
        }
    }

    private var tint: Color {
        switch kind {
        case .warning: .orange
        case .info: .secondary
        case .success: .green
        }
    }

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
        }
    }
}

/// A small menu of donation amounts. Each choice opens the CNERD shop in the browser.
/// The app itself never handles payments.
struct DonateMenu: View {
    var body: some View {
        // The heart sits beside the menu, not inside its label. macOS draws a menu's own icon in
        // the text color, so a heart inside the label would not stay red.
        HStack(spacing: 4) {
            DonateHeart()
            Menu("Donate") {
                ForEach(AppInfo.donationAmounts, id: \.self) { amount in
                    Button("$\(amount)") {
                        NSWorkspace.shared.open(AppInfo.donateURL(amount: amount))
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .help("Support development. Opens the CNERD shop in your browser.")
    }
}

/// The red heart shown beside Donate and beside the thank-you line.
struct DonateHeart: View {
    var body: some View {
        Image(systemName: AppSymbol.donate)
            .foregroundStyle(.red)
            .accessibilityHidden(true)
    }
}

/// Takes the place of the Donate button once the person turns on "I Have Donated".
struct SupporterThanks: View {
    var body: some View {
        HStack(spacing: 4) {
            DonateHeart()
            Text("Thank you for your support")
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
