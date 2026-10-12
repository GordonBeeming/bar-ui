import BarUICore
import SwiftUI

/// UserDefaults key shared by the Settings picker and the Overview.
enum CurrencySetting {
    static let key = "currency"
}

struct SettingsView: View {
    @Environment(PricingCatalog.self) private var pricing
    @AppStorage(CurrencySetting.key) private var currencyCode = Currency.default.rawValue

    var body: some View {
        Form {
            Picker("Currency", selection: currency) {
                ForEach(Currency.allCases) { currency in
                    Text("\(currency.rawValue) · \(currency.name)").tag(currency)
                }
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

    private var currency: Binding<Currency> {
        Binding(
            get: { Currency(storedCode: currencyCode) },
            set: { currencyCode = $0.rawValue }
        )
    }
}
