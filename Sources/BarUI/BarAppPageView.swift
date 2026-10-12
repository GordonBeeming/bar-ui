import BarUICore
import SwiftUI

/// A Bar App's own page: its Limit history, plus the Tracking banner and
/// the way into the Tracking settings.
struct BarAppPageView: View {
    let app: BarApp
    let status: BarAppStatus
    let home: URL
    let remote: BarAppRemote
    /// Nil when nothing from this Bar App was skipped.
    let skipped: SkippedRecordsNotice?
    /// Nil when the Archive couldn't be opened; the Overview says why.
    let history: LimitHistoryModel?

    @State private var editing: TrackingSettingsEditing?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let settings = status.settings {
                Text(TrackingSettingsChoices.summary(of: settings, home: home))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if status.state == .off || status.state == .offWithHistory, let settings = status.settings {
                TrackingOffBanner(hasHistory: status.state == .offWithHistory) {
                    editing = TrackingSettingsEditing(app: app, current: settings, startEnabled: true)
                }
            }

            if let skipped {
                SkippedRecordsBanner(notice: skipped)
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .navigationTitle(app.displayName)
        .toolbar {
            if let settings = status.settings {
                ToolbarItemGroup {
                    Button("\(app.displayName) settings…") {
                        openBarAppSettings()
                    }
                    Button("Tracking settings…") {
                        editing = TrackingSettingsEditing(app: app, current: settings, startEnabled: settings.enabled)
                    }
                }
            }
        }
        .sheet(item: $editing) { editing in
            TrackingSettingsSheet(editing: editing, home: home, remote: remote)
        }
    }

    @ViewBuilder
    private var content: some View {
        if status.state == .notInstalled {
            ContentUnavailableView(
                "\(app.displayName) isn't installed",
                systemImage: "app.dashed",
                description: Text("Install \(app.displayName) to record Telemetry for Bar UI to show.")
            )
        } else if let history {
            ScrollView {
                LimitHistorySection(app: app, model: history)
                    .id(app)
            }
        } else {
            ContentUnavailableView(
                "The Archive couldn't be opened",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("Limit history is read from the Archive. The Overview says why it couldn't be opened.")
            )
        }
    }

    private func openBarAppSettings() {
        failure = nil
        Task {
            do {
                try await remote.openSettings(of: app)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

private struct TrackingOffBanner: View {
    let hasHistory: Bool
    let turnOn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("\(Text("Tracking is off.").bold()) \(hasHistory ? "You're looking at History." : "Nothing is being recorded.")")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Turn on Tracking…", action: turnOn)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct SkippedRecordsBanner: View {
    let notice: SkippedRecordsNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            TimelineView(.everyMinute) { context in
                Text(message(now: context.date))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func message(now: Date) -> AttributedString {
        var link = AttributedString(SkippedRecordsNotice.specName)
        link.link = SkippedRecordsNotice.specURL
        return AttributedString("\(notice.message(now: now)) ") + link + AttributedString(".")
    }
}
