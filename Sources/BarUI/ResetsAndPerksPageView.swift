import BarUICore
import SwiftUI

/// Every reset, Perk change and Tracking change in the Archive. The Overview
/// shows the same section for its range; this page opens on All time so
/// nothing older is out of reach.
struct ResetsAndPerksPageView: View {
    /// Nil when the Archive couldn't be opened; `archiveFailure` says why.
    let overview: LimitsOverview?
    let archiveFailure: String?

    @State private var range: TimeRange = .all
    /// Who this view is to the overview, which reads as far back as the
    /// longest range any view shows.
    @State private var viewer = UUID()

    var body: some View {
        Group {
            if let overview {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView {
                        ResetsAndPerksSection(
                            events: overview.events(range: range, now: context.date),
                            range: range,
                            now: context.date,
                            tokensDomain: nil,
                            rangeSelection: $range
                        )
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                    }
                }
                .task(id: range) {
                    await overview.show(range, by: viewer)
                }
                .onDisappear {
                    overview.stopShowing(by: viewer)
                }
            } else {
                ContentUnavailableView(
                    "The Archive couldn't be opened",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(archiveFailure ?? "")
                )
            }
        }
        .navigationTitle(ArchivePage.events.title)
    }
}
