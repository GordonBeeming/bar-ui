import SwiftUI

/// The sidebar's last line: when Telemetry was last imported into the
/// Archive, so a quiet Overview can be told apart from a stalled import.
struct ImportStatusFooter: View {
    /// The relative time only needs to move on as fast as its wording does.
    private static let tick: TimeInterval = 15

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()

    let lastImportedAt: Date?
    let archiveFailure: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
            label(now: context.date)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func label(now: Date) -> some View {
        if archiveFailure != nil {
            Label("Archive unavailable", systemImage: "exclamationmark.triangle")
        } else if let lastImportedAt {
            // Worked out against the timeline's date, not the clock at render,
            // so "now" ages into "1 minute ago" between imports.
            Label("Last import \(Self.relative.localizedString(for: min(lastImportedAt, now), relativeTo: now))", systemImage: "arrow.down.circle")
                .help(lastImportedAt.formatted(date: .abbreviated, time: .standard))
        } else {
            Label("No imports yet", systemImage: "clock")
        }
    }
}
