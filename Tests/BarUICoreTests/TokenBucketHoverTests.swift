import Foundation
import Testing
@testable import BarUICore

@Suite("Token bucket hover")
struct TokenBucketHoverTests {
    struct RangeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let start: Date
        let component: Calendar.Component
        let expected: String

        var testDescription: String { name }
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static let locale = Locale(identifier: "en_US")

    static func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? .distantPast
    }

    static let rangeCases: [RangeCase] = [
        RangeCase(name: "evening hour", start: date(day: 12, hour: 20), component: .hour, expected: "8 PM–9 PM"),
        RangeCase(name: "morning hour", start: date(day: 12, hour: 9), component: .hour, expected: "9 AM–10 AM"),
        RangeCase(name: "hour that ends at midnight", start: date(day: 12, hour: 23), component: .hour, expected: "11 PM–12 AM"),
        RangeCase(name: "midday hour", start: date(day: 12, hour: 11), component: .hour, expected: "11 AM–12 PM"),
        RangeCase(name: "a day", start: date(day: 12, hour: 0), component: .day, expected: "Mon 12 Oct"),
        RangeCase(name: "a day at month end", start: date(day: 31, hour: 0), component: .day, expected: "Sat 31 Oct")
    ]

    @Test("Bucket range text", arguments: rangeCases)
    func rangeText(_ testCase: RangeCase) {
        let bucket = TokenUsage.Bucket(start: testCase.start, tokensByApp: [:])

        let text = bucket.rangeText(component: testCase.component, calendar: Self.calendar, locale: Self.locale)

        #expect(text == testCase.expected)
    }

    struct ContainingCase: Sendable, CustomTestStringConvertible {
        let name: String
        let at: Date
        let expectedStart: Date?

        var testDescription: String { name }
    }

    static let containingCases: [ContainingCase] = [
        ContainingCase(name: "start of a bucket", at: date(day: 12, hour: 21), expectedStart: date(day: 12, hour: 21)),
        ContainingCase(name: "inside a bucket", at: date(day: 12, hour: 21).addingTimeInterval(1_800), expectedStart: date(day: 12, hour: 21)),
        ContainingCase(name: "last bucket", at: date(day: 12, hour: 22).addingTimeInterval(3_599), expectedStart: date(day: 12, hour: 22)),
        ContainingCase(name: "before the first bucket", at: date(day: 12, hour: 19), expectedStart: nil),
        ContainingCase(name: "after the last bucket ends", at: date(day: 12, hour: 23), expectedStart: nil)
    ]

    @Test("The bucket containing a pointer position", arguments: containingCases)
    func containing(_ testCase: ContainingCase) {
        let usage = TokenUsage(
            samples: [],
            rangeStart: Self.date(day: 12, hour: 20),
            bucketComponent: .hour,
            now: Self.date(day: 12, hour: 22),
            calendar: Self.calendar
        )

        let bucket = usage.bucket(containing: testCase.at, component: .hour, calendar: Self.calendar)

        #expect(bucket?.start == testCase.expectedStart)
    }
}
