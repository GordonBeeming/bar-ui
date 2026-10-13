import BarUICore
import SwiftUI

/// "● 1.37B cached  ● 28M new in  ● 2.8M out", in the same colours as the
/// token charts, so a big total shows how much of it was fresh work.
struct TokenKindSplit: View {
    let totals: [TokenKind: Int64]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TokenKind.allCases, id: \.self) { kind in
                HStack(spacing: 4) {
                    Circle()
                        .fill(kind.color)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text("\(DisplayFormat.tokens(totals[kind] ?? 0)) \(kind.shortLabel)")
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(kind.label): \(DisplayFormat.tokens(totals[kind] ?? 0))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
