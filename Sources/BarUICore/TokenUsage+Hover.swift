import Foundation

extension TokenUsage {
    /// The bucket whose period contains `date`; nil before the first bucket or
    /// after the last one ends.
    public func bucket(containing date: Date, component: Calendar.Component, calendar: Calendar = .current) -> Bucket? {
        guard let bucket = buckets.last(where: { $0.start <= date }),
              let end = calendar.date(byAdding: component, value: 1, to: bucket.start),
              date < end else {
            return nil
        }
        return bucket
    }

    /// From the first bucket's start to the end of the last bucket. A chart
    /// left to find its own domain only sees the buckets it drew a mark for,
    /// so quiet buckets at either end would vanish and the activity would
    /// look like it filled the whole range. Nil when there are no buckets.
    public func timeDomain(component: Calendar.Component, calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let first = buckets.first?.start, let last = buckets.last?.start,
              let end = calendar.date(byAdding: component, value: 1, to: last) else {
            return nil
        }
        return first...end
    }
}

extension TokenUsage.Bucket {
    /// "8 PM–9 PM" for an hourly bucket, "Mon 12 Oct" for a daily one.
    public func rangeText(component: Calendar.Component, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale

        guard component == .hour else {
            // A fixed pattern: the localized template would reorder to "Mon, Oct 12" in en_US.
            formatter.dateFormat = "EEE d MMM"
            return formatter.string(from: start)
        }
        formatter.setLocalizedDateFormatFromTemplate("j")
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        return "\(Self.normalised(formatter.string(from: start)))–\(Self.normalised(formatter.string(from: end)))"
    }

    /// ICU separates the time and the AM/PM mark with a narrow no-break space.
    private static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
