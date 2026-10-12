import Foundation
import Testing
@testable import BarUICore

@Suite("Token pace")
struct TokenPaceTests {
    private static let second: Int64 = 1_000_000_000
    private static let now = Date(timeIntervalSince1970: 1_799_971_200 + 12 * 3_600)
    private static var nowNano: Int64 { Int64(now.timeIntervalSince1970) * second }

    private static func sample(minutesAgo: Int64, count: Int64, app: BarApp = .claudeBar) -> TokenSample {
        TokenSample(app: app, model: "m", tokenType: .output, startTimeUnixNano: 1, timeUnixNano: nowNano - minutesAgo * 60 * second, count: count)
    }

    @Test("Now is what the last hour added; the average spreads the last 24 hours over 24")
    func nowAndAverage() {
        let samples = [
            Self.sample(minutesAgo: 600, count: 1_000),
            Self.sample(minutesAgo: 90, count: 4_000),
            Self.sample(minutesAgo: 30, count: 4_500),
            Self.sample(minutesAgo: 5, count: 5_000)
        ]

        let pace = TokenPace(samples: samples, now: Self.now)

        // 1,000 + 3,000 + 500 + 500 across 24h, and 1,000 of that in the last hour.
        #expect(pace.perHourNow == 1_000)
        #expect(pace.perHourAverage == 5_000.0 / 24)
    }

    @Test("With no usage both are zero")
    func quiet() {
        let pace = TokenPace(samples: [], now: Self.now)

        #expect(pace.perHourNow == 0)
        #expect(pace.perHourAverage == 0)
    }
}
