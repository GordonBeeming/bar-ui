import Foundation
import Testing
@testable import BarUICore

@Suite("Tokens by kind")
struct TokenKindTests {
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: "UTC") {
            calendar.timeZone = zone
        }
        return calendar
    }

    @Test("Kinds read as cache reads, input and output, with short forms for the headline")
    func labels() {
        #expect(TokenKind.allCases.map(\.label) == ["Cache reads", "Input", "Output"])
        #expect(TokenKind.allCases.map(\.shortLabel) == ["cached", "in", "out"])
    }

    /// A counter that starts at zero an hour ago and reads `count` now.
    private static func sample(_ type: TokenType, _ count: Int64, app: BarApp = .claudeBar) -> [TokenSample] {
        let start = Int64((now.timeIntervalSince1970 - 3_600) * 1_000_000_000)
        let end = Int64(now.timeIntervalSince1970 * 1_000_000_000)
        return [
            TokenSample(app: app, model: "m", tokenType: type, startTimeUnixNano: start, timeUnixNano: start, count: 0),
            TokenSample(app: app, model: "m", tokenType: type, startTimeUnixNano: start, timeUnixNano: end, count: count)
        ]
    }

    // Typed up front so the @Test macro doesn't have to infer the tuples.
    private static let kinds: [(TokenType, TokenKind?)] = [
        (.cacheRead, .cacheRead),
        (.input, .newInput),
        (.cacheWrite5m, .newInput),
        (.cacheWrite1h, .newInput),
        (.cacheWrite, .newInput),
        (.output, .output),
        (.reasoning, nil)
    ]

    @Test("Each Token Type falls in one kind; reasoning is inside output already, so it has none", arguments: kinds)
    func kind(type: TokenType, expected: TokenKind?) {
        #expect(TokenKind(type) == expected)
    }

    @Test("Totals and buckets split into cache reads, new input and output, adding up to the total")
    func split() throws {
        let samples = Self.sample(.cacheRead, 1_000) + Self.sample(.input, 30) + Self.sample(.cacheWrite5m, 20)
            + Self.sample(.output, 7) + Self.sample(.reasoning, 3) + Self.sample(.output, 5, app: .codexBar)

        let usage = TokenUsage(samples: samples, range: .day, now: Self.now, calendar: Self.utc)

        #expect(usage.totalByKind == [.cacheRead: 1_000, .newInput: 50, .output: 12])
        #expect(usage.totalByKind.values.reduce(0, +) == usage.total)
        let bucket = try #require(usage.buckets.first { !$0.tokensByKind.isEmpty })
        #expect(bucket.tokensByKind == [.cacheRead: 1_000, .newInput: 50, .output: 12])
    }
}
