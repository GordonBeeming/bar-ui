import Foundation
import Testing
@testable import BarUICore

@Suite("Tokens in the Archive")
struct TokenArchiveTests {
    private static let progress = ImportProgress(app: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0)

    @Test("Token samples come back oldest first, and recording them twice keeps one copy")
    func roundTrip() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let early = TokenSample(app: .claudeBar, model: "m", tokenType: .input, startTimeUnixNano: 1, timeUnixNano: 10, count: 5)
        let late = TokenSample(app: .claudeBar, model: "m", tokenType: .input, startTimeUnixNano: 1, timeUnixNano: 20, count: 9)

        try await archive.record(TelemetryRecords(tokenSamples: [late, early]), progress: Self.progress)
        try await archive.record(TelemetryRecords(tokenSamples: [early, late]), progress: Self.progress)

        #expect(try await archive.tokenSamples() == [early, late])
    }

    @Test("Token samples survive reopening the Archive")
    func persists() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("Archive.sqlite")
        let sample = TokenSample(app: .codexBar, model: "gpt-5-codex", tokenType: .cacheRead, startTimeUnixNano: 1, timeUnixNano: 10, count: 5)
        do {
            let archive = try Archive(url: url)
            try await archive.record(TelemetryRecords(tokenSamples: [sample]), progress: Self.progress)
        }

        let reopened = try Archive(url: url)

        #expect(try await reopened.tokenSamples() == [sample])
    }

    @Test("Importing a metrics file archives its tokens")
    func importerArchivesTokens() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)

        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        let tokens = try await fixture.archive.tokenSamples()
        #expect(tokens.map(\.count) == [59_896, 59_896])
        #expect(tokens.allSatisfy { $0.app == .codexBar && $0.model == "gpt-5-codex" && $0.tokenType == .input })
    }
}
