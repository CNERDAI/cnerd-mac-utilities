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
        Menu {
            ForEach(AppInfo.donationAmounts, id: \.self) { amount in
                Button("$\(amount)") {
                    NSWorkspace.shared.open(AppInfo.donateURL(amount: amount))
                }
            }
        } label: {
            Label("Donate", systemImage: AppSymbol.donate)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Support development. Opens the CNERD shop in your browser.")
    }
}
