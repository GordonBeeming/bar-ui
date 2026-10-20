import BarUICore
import SwiftUI

/// UserDefaults key shared by the Settings picker and the Overview.
enum CurrencySetting {
    static let key = "currency"
}

struct SettingsView: View {
    @Environment(PricingCatalog.self) private var pricing
    let openAtLogin: LoginItemSetting
    let backgroundImport: LoginItemSetting
    @AppStorage(CurrencySetting.key) private var currencyCode = Currency.default.rawValue

    var body: some View {
        Form {
            Picker("Currency", selection: currency) {
                ForEach(Currency.allCases) { currency in
                    Text("\(currency.rawValue) · \(currency.name)").tag(currency)
                }
            }
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
            Section {
                Text("API Cost is what your tokens would have cost at the vendors' public API prices, converted from US dollars. It is not what you were charged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(pricing.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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

    private var currency: Binding<Currency> {
        Binding(
            get: { Currency(storedCode: currencyCode) },
            set: { currencyCode = $0.rawValue }
        )
    }
}
