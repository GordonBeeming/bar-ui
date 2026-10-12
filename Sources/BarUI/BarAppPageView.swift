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
    /// Nil when the Archive couldn't be opened.
    let overview: LimitsOverview?

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

            if let notice = BarAppPageNotice(state: status.state) {
                NoticeBanner(notice: notice, appName: app.displayName, turnOn: status.settings.map { settings in
                    { editing = TrackingSettingsEditing(app: app, current: settings, startEnabled: true) }
                })
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

    /// The Archive-backed sections show whatever the Bar App's state, because
    /// the Archive keeps what it recorded even after it's uninstalled. Each
    /// section has its own empty state.
    @ViewBuilder
    private var content: some View {
        if let history {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LimitHistorySection(app: app, model: history)
                        .id(app)
                    if let overview {
                        ModelTokensSection(app: app, overview: overview)
                        PerksSectionView(
                            app: app,
                            available: overview.availablePerks(of: app),
                            gone: overview.gonePerks(of: app)
                        )
                    }
                }
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

private struct NoticeBanner: View {
    let notice: BarAppPageNotice
    let appName: String
    /// Nil when there are no Tracking settings to change, as when the Bar
    /// App isn't installed.
    let turnOn: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice == .notInstalled ? "app.dashed" : "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("\(Text(notice.title(appName: appName)).bold()) \(notice.message(appName: appName))")
                .frame(maxWidth: .infinity, alignment: .leading)
            if notice != .notInstalled, let turnOn {
                Button("Turn on Tracking…", action: turnOn)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
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
