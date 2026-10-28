import Foundation

extension LimitHistoryRow {
    /// What the chart's readout shows for a pointer position.
    public struct Hover: Sendable, Hashable {
        public let point: Point
        /// The reset that happened at this sample, if one did.
        public let reset: ResetMarker?
    }

    /// The sample nearest `date` within the run the pointer is over. Over a
    /// Tracking gap there is nothing to show, because snapping across it would
    /// invent a reading for time nobody recorded. Past either end of the data
    /// the readout holds the first or last sample.
    public func hover(at date: Date) -> Hover? {
        guard let point = Self.nearestPoint(in: segments, to: date) else {
            return nil
        }
        let reset = resetMarkers.first { marker in
            Self.nearestPoint(in: segments, to: marker.date) == point
        }
        return Hover(point: point, reset: reset)
    }

    /// The reset closest to `date` within `reach`, whatever samples sit near
    /// it. A reset inside a Tracking gap has no sample to carry its figure,
    /// so hovering near its marker has to find it on its own.
    public func resetMarker(near date: Date, within reach: TimeInterval) -> ResetMarker? {
        resetMarkers
            .filter { abs($0.date.timeIntervalSince(date)) <= reach }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    static func nearestPoint(in segments: [[Point]], to date: Date) -> Point? {
        guard let firstDate = segments.first?.first?.date, let lastDate = segments.last?.last?.date else {
            return nil
        }
        if date <= firstDate {
            return segments.first?.first
        }
        if date >= lastDate {
            return segments.last?.last
        }
        for run in segments {
            guard let start = run.first?.date, let end = run.last?.date, date >= start, date <= end else {
                continue
            }
            // min(by:) keeps the first of equal distances, so a tie goes to the earlier sample.
            return run.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        return nil
    }
}
