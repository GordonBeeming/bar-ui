import BarUICore
import SwiftUI

/// What a Bar App's Perks are now, and what became of the ones that went.
struct PerksSectionView: View {
    let app: BarApp
    let available: [AvailablePerk]
    let gone: [GonePerk]

    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted)
    private static let dateTimeFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Perks")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if available.isEmpty && gone.isEmpty {
                Text("\(app.displayName) hasn't recorded any Perks.")
                    .foregroundStyle(.secondary)
            }

            if !available.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available now")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(available, id: \.self) { perk in
                        availableRow(perk)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Available Perks")
            }

            if !gone.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gone")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(gone, id: \.self) { perk in
                        goneRow(perk)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Gone Perks")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func availableRow(_ perk: AvailablePerk) -> some View {
        row {
            Text(PerkText.quantity(kind: perk.kind, quantity: perk.quantity, currency: perk.currency))
                .fontWeight(.semibold)
            Spacer(minLength: 12)
            Text(perk.expiresAt.map { "Expires \($0.formatted(Self.dateFormat))" } ?? "No expiry known")
                .foregroundStyle(.secondary)
        }
    }

    private func goneRow(_ perk: GonePerk) -> some View {
        row {
            Text(PerkText.quantity(kind: perk.kind, quantity: perk.quantity, currency: perk.currency))
            Text(PerkText.label(for: perk.reason))
                .font(.caption.weight(.semibold))
                .foregroundStyle(perk.reason.labelColor)
            Spacer(minLength: 12)
            Text(perk.goneAt.formatted(Self.dateTimeFormat))
                .foregroundStyle(.secondary)
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

extension PerkGoneReason {
    /// Text colours that pass contrast in both appearances; "unknown" stays
    /// neutral because it is an absence of information, not a warning.
    var labelColor: Color {
        switch self {
        case .used: Color(light: 0x1A7F37, dark: 0x56D364)
        case .expired: Color(light: 0x8A5300, dark: 0xF2B544)
        case .unknown: .secondary
        }
    }
}
