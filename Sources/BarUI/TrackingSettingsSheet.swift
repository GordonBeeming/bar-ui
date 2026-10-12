import BarUICore
import SwiftUI
import UniformTypeIdentifiers

/// What the sheet starts from. `current` is the Bar App's saved settings at
/// the moment the sheet opened, which is what the request is diffed against.
struct TrackingSettingsEditing: Identifiable {
    let id = UUID()
    let app: BarApp
    let current: TrackingSettings
    var startEnabled: Bool
}

struct TrackingSettingsSheet: View {
    let editing: TrackingSettingsEditing
    let home: URL
    let remote: BarAppRemote

    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var intervalMinutes: Int?
    @State private var retentionDays: Int?
    @State private var folderText: String
    @State private var isChoosingFolder = false
    @State private var isSending = false
    @State private var failure: String?

    init(editing: TrackingSettingsEditing, home: URL, remote: BarAppRemote) {
        self.editing = editing
        self.home = home
        self.remote = remote
        _enabled = State(initialValue: editing.startEnabled)
        _intervalMinutes = State(initialValue: editing.current.intervalMinutes)
        _retentionDays = State(initialValue: editing.current.retentionDays)
        _folderText = State(initialValue: TrackingSettingsChoices.displayPath(of: editing.current.folder, home: home))
    }

    private var appName: String {
        editing.app.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appName) Tracking")
                    .font(.title3.bold())
                Text("\(appName) opens and asks you to confirm before it changes anything.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Toggle("Tracking", isOn: $enabled)
                    .help("Record Telemetry")

                Picker("Interval", selection: $intervalMinutes) {
                    if editing.current.intervalMinutes == nil {
                        Text("Not set").tag(Int?.none)
                    }
                    ForEach(TrackingSettingsChoices.intervals(current: editing.current.intervalMinutes), id: \.self) { minutes in
                        Text(TrackingSettingsChoices.intervalTitle(minutes)).tag(Int?.some(minutes))
                    }
                }

                Picker("Keep files for", selection: $retentionDays) {
                    if editing.current.retentionDays == nil {
                        Text("Not set").tag(Int?.none)
                    }
                    ForEach(TrackingSettingsChoices.retentions(current: editing.current.retentionDays), id: \.self) { days in
                        Text(TrackingSettingsChoices.retentionTitle(days)).tag(Int?.some(days))
                    }
                }

                LabeledContent("Telemetry Folder") {
                    HStack {
                        TextField("Telemetry Folder", text: $folderText)
                            .labelsHidden()
                        Button("Choose…") {
                            isChoosingFolder = true
                        }
                    }
                }
            }
            .formStyle(.columns)

            Text("Bar UI keeps everything it has imported in its Archive, whatever \(appName)'s retention is.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Button("\(appName) settings…") {
                    openBarAppSettings()
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Send to \(appName)") {
                    send()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSending)
            }
        }
        .padding(24)
        .frame(width: 520)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                folderText = TrackingSettingsChoices.displayPath(of: url, home: home)
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
    }

    private func edited() throws -> TrackingSettings {
        TrackingSettings(
            enabled: enabled,
            intervalMinutes: intervalMinutes,
            retentionDays: retentionDays,
            folder: try TrackingSettingsChoices.folder(fromDisplayPath: folderText, home: home)
        )
    }

    private func send() {
        failure = nil
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await remote.requestTrackingChange(of: editing.app, from: editing.current, to: edited())
                // The Bar App now shows its own confirmation; the page updates
                // from its defaults once it applies, so nothing is held here.
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func openBarAppSettings() {
        failure = nil
        Task {
            do {
                try await remote.openSettings(of: editing.app)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
