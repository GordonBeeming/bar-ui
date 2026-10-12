import Foundation

/// A calendar day as a Bar App names its Telemetry files, with no time zone
/// attached: the day in the file name is the day the Bar App wrote it.
public struct TelemetryDay: Sendable, Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day in a spec file name like `claudebar-metrics-2026-10-12.jsonl`,
    /// or nil for a name that doesn't carry a real calendar day.
    init?(fileName: String) {
        guard let match = fileName.firstMatch(of: /-(\d{4})-(\d{2})-(\d{2})\.jsonl$/),
              let year = Int(match.output.1),
              let month = Int(match.output.2),
              let day = Int(match.output.3),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public static func < (lhs: TelemetryDay, rhs: TelemetryDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// How many records of one Bar App's Telemetry for one day were dropped for
/// not following the Telemetry Spec.
public struct SkippedRecords: Sendable, Hashable {
    public let day: TelemetryDay
    public let count: Int

    public init(day: TelemetryDay, count: Int) {
        self.day = day
        self.count = count
    }
}

/// What a Bar App's page says about records that were dropped.
public struct SkippedRecordsNotice: Sendable, Hashable {
    public static let specName = "Telemetry Spec v1"
    // The page on main, not a commit, so the link follows the spec as it is
    // clarified within v1.
    public static let specURL: URL = {
        guard let url = URL(string: "https://github.com/GordonBeeming/bar-ui/blob/main/docs/telemetry-spec.md") else {
            preconditionFailure("The Telemetry Spec URL is a literal and must parse")
        }
        return url
    }()

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public let count: Int
    public let first: TelemetryDay
    public let last: TelemetryDay

    /// Nil when nothing was skipped, so there is no notice to show.
    public init?(days: [SkippedRecords]) {
        let skipped = days.filter { $0.count > 0 }
        guard let first = skipped.map(\.day).min(), let last = skipped.map(\.day).max() else {
            return nil
        }
        self.count = skipped.reduce(0) { $0 + $1.count }
        self.first = first
        self.last = last
    }

    /// The sentence up to where the spec's name goes, which the page makes a link.
    public func message(now: Date) -> String {
        let noun = count == 1 ? "record" : "records"
        let verb = count == 1 ? "was skipped because it doesn't match" : "were skipped because they don't match"
        return "\(count) \(noun) from \(dateRange(now: now)) \(verb)"
    }

    private func dateRange(now: Date) -> String {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: now)
        func name(_ day: TelemetryDay) -> String {
            "\(day.day) \(Self.monthNames[day.month - 1])"
        }

        if first.year != last.year {
            return "\(name(first)) \(first.year) – \(name(last)) \(last.year)"
        }
        let suffix = first.year == currentYear ? "" : " \(first.year)"
        if first == last {
            return name(first) + suffix
        }
        if first.month == last.month {
            return "\(first.day)–\(name(last))\(suffix)"
        }
        return "\(name(first)) – \(name(last))\(suffix)"
    }
}
