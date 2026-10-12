import Foundation
import Testing
@testable import BarUICore

@Suite("Token usage per Bar App and model")
struct TokenUsageByAppAndModelTests {
    @Test("One Bar App's models keep reasoning, which the cost breakdown leaves out")
    func perApp() {
        let usage = ModelTokensFixture.usage([
            ModelTokensFixture.sample(.output, app: .codexBar, model: "a", count: 5),
            ModelTokensFixture.sample(.reasoning, app: .codexBar, model: "a", count: 3),
            ModelTokensFixture.sample(.input, app: .claudeBar, model: "a", count: 10)
        ])

        #expect(usage.tokens(of: .codexBar) == ["a": [.output: 5, .reasoning: 3]])
        #expect(usage.tokens(of: .claudeBar) == ["a": [.input: 10]])
    }

    @Test("A Bar App with no usage has no models")
    func none() {
        let usage = ModelTokensFixture.usage([
            ModelTokensFixture.sample(.input, app: .claudeBar, model: "a", count: 10)
        ])

        #expect(usage.tokens(of: .codexBar).isEmpty)
    }
}

enum ModelTokensFixture {
    static let now = Date(timeIntervalSince1970: 1_799_971_200 + 12 * 3_600)

    static func sample(_ type: TokenType, app: BarApp, model: String, count: Int64) -> TokenSample {
        TokenSample(
            app: app, model: model, tokenType: type, startTimeUnixNano: 1,
            timeUnixNano: (Int64(now.timeIntervalSince1970) - 3_600) * 1_000_000_000, count: count
        )
    }

    static func usage(_ samples: [TokenSample]) -> TokenUsage {
        TokenUsage(samples: samples, range: .day, now: now)
    }
}
