import BarUICore
import SwiftUI

struct SettingsView: View {
    let openAtLogin: LoginItemSetting
    let backgroundImport: LoginItemSetting

    var body: some View {
        Form {
            Section {
                Toggle("Open Bar UI at login", isOn: binding(for: openAtLogin))
                Text("Starts in the menu bar when you log in, without opening the window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LoginItemNotes(setting: openAtLogin, approvalText: "Allow Bar UI under Login Items in System Settings so it opens at login.")
            }
            Section {
                Toggle("Keep importing when Bar UI is closed", isOn: binding(for: backgroundImport))
                Text("A background helper copies new Telemetry into the Archive as it arrives, so the Bar Apps' retention can never delete files before they're imported. It starts when you log in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LoginItemNotes(setting: backgroundImport, approvalText: "Allow Bar UI under Login Items in System Settings to start the helper.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binding(for setting: LoginItemSetting) -> Binding<Bool> {
        Binding(
            get: { setting.isEnabled },
            set: { setting.setEnabled($0) }
        )
    }
}
