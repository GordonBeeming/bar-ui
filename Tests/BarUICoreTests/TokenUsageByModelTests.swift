import Foundation
import Testing
@testable import BarUICore

@Suite("Token usage per model")
struct TokenUsageByModelTests {
    private static let second: Int64 = 1_000_000_000
    private static let now = Date(timeIntervalSince1970: 1_799_971_200 + 12 * 3_600)

    private static func sample(_ type: TokenType, app: BarApp, model: String, agoHours: Int64, count: Int64) -> TokenSample {
        TokenSample(
            app: app, model: model, tokenType: type, startTimeUnixNano: 1,
            timeUnixNano: Int64(now.timeIntervalSince1970) * second - agoHours * 3_600 * second, count: count
        )
    }

    @Test("Usage is split by model and Token Type across Bar Apps, leaving reasoning inside output")
    func splitByModel() {
        let samples = [
            Self.sample(.input, app: .claudeBar, model: "a", agoHours: 1, count: 10),
            Self.sample(.output, app: .claudeBar, model: "a", agoHours: 1, count: 20),
            Self.sample(.output, app: .codexBar, model: "a", agoHours: 1, count: 5),
            Self.sample(.reasoning, app: .codexBar, model: "a", agoHours: 1, count: 3),
            Self.sample(.cacheWrite1h, app: .codexBar, model: "b", agoHours: 1, count: 7)
        ]

        let usage = TokenUsage(samples: samples, range: .day, now: Self.now)

        #expect(usage.tokensByModel == [
            "a": [.input: 10, .output: 25],
            "b": [.cacheWrite1h: 7]
        ])
    }
}
