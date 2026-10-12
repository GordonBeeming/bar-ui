import Foundation

/// How many tokens per hour are being used right now against the last day's
/// average, for the Menu Bar Preview.
public struct TokenPace: Sendable, Equatable {
    /// What the last 60 minutes added.
    public let perHourNow: Int64
    /// The last 24 hours spread evenly over 24, so a quiet night pulls it down
    /// the way it would for anyone reading "average".
    public let perHourAverage: Double

    public init(samples: [TokenSample], now: Date, calendar: Calendar = .current) {
        let lastHour = TokenUsage(samples: samples, rangeStart: now.addingTimeInterval(-3_600), bucketComponent: .hour, now: now, calendar: calendar)
        let lastDay = TokenUsage(samples: samples, range: .day, now: now, calendar: calendar)
        perHourNow = lastHour.total
        perHourAverage = Double(lastDay.total) / 24
    }
}
