import Foundation

/// A Limit's Window rolling over, as the Bar App logged it.
public struct LimitReset: Sendable, Hashable {
    public let app: BarApp
    public let limit: LimitDescriptor
    public let timeUnixNano: Int64
    /// The last utilisation sampled before the reset, 0 to 100.
    public let utilizationLast: Double
    public let nextResetsAt: Date?

    public init(app: BarApp, limit: LimitDescriptor, timeUnixNano: Int64, utilizationLast: Double, nextResetsAt: Date?) {
        self.app = app
        self.limit = limit
        self.timeUnixNano = timeUnixNano
        self.utilizationLast = utilizationLast
        self.nextResetsAt = nextResetsAt
    }
}

/// Reads the events the Dashboard stores out of a Bar App's OTLP/JSON logs
/// lines, following Telemetry Spec v1: Limit resets, Limits appearing and
/// disappearing, Tracking starting, and Perks becoming available or going.
/// One of those that breaks the spec is dropped and counted; any other event
/// is skipped without being counted.
public enum LogEventParser {
    private static let resetEventName = "bar.limit.reset"
    private static let perkAvailableEventName = "bar.perk.available"
    private static let perkGoneEventName = "bar.perk.gone"
    private static let limitAppearedEventName = "bar.limit.appeared"
    private static let limitDisappearedEventName = "bar.limit.disappeared"
    private static let trackingStartedEventName = "bar.tracking.started"

    public static func parse(_ data: Data, from app: BarApp) -> TelemetryParseResult {
        var records = TelemetryRecords()
        var dropped = 0
        let lines = OTLPLines.forEachRequest(in: data, as: ExportLogsServiceRequest.self) { request in
            for resourceLogs in request.resourceLogs ?? [] {
                let resource = resourceLogs.resource?.attributes ?? []
                guard OTLPLines.isConforming(resource: resource, of: app) else {
                    dropped += 1
                    continue
                }
                let scopes = resourceLogs.scopeLogs ?? []
                guard OTLPLines.hasSpecAttributes(resource: resource) else {
                    if scopes.contains(where: holdsBarEvents) {
                        dropped += 1
                    }
                    continue
                }
                for scope in scopes {
                    guard OTLPLines.isConforming(scope: scope.scope, of: app) else {
                        if holdsBarEvents(scope) {
                            dropped += 1
                        }
                        continue
                    }
                    for record in scope.logRecords ?? [] {
                        read(record, from: app, into: &records, dropped: &dropped)
                    }
                }
            }
        }
        return TelemetryParseResult(records: records, droppedRecords: dropped + lines.undecodableLines, consumedByteCount: lines.consumedByteCount)
    }

    private static let readEventNames: Set = [
        resetEventName, perkAvailableEventName, perkGoneEventName,
        limitAppearedEventName, limitDisappearedEventName, trackingStartedEventName
    ]

    /// Whether the scope holds an event read here, or one whose name is broken
    /// so it might be, making dropping it for a broken resource or scope
    /// worth counting.
    private static func holdsBarEvents(_ scope: ScopeLogs) -> Bool {
        (scope.logRecords ?? []).contains { record in
            record.isEventNameMalformed || record.eventName.map(readEventNames.contains) == true
        }
    }

    private static func read(_ record: LogRecord, from app: BarApp, into records: inout TelemetryRecords, dropped: inout Int) {
        if record.isEventNameMalformed {
            // It may be one of the events read here; it breaks the spec either way.
            dropped += 1
            return
        }
        guard let name = record.eventName, readEventNames.contains(name) else {
            return
        }
        guard !record.isMalformed, record.isInfoWithObservedTime else {
            dropped += 1
            return
        }
        switch name {
        case resetEventName:
            if let reset = reset(from: record, app: app) {
                records.resets.append(reset)
            } else {
                dropped += 1
            }
        case perkAvailableEventName, perkGoneEventName:
            if let event = perkEvent(from: record, app: app) {
                if record.eventName == perkGoneEventName {
                    records.perkGoneEvents.append(event)
                } else {
                    records.perkAvailableEvents.append(PerkAvailableEvent(gone: event))
                }
            } else {
                dropped += 1
            }
        case limitAppearedEventName, limitDisappearedEventName:
            if let event = limitEvent(from: record, app: app) {
                records.limitEvents.append(event)
            } else {
                dropped += 1
            }
        case trackingStartedEventName:
            if let event = trackingStarted(from: record, app: app) {
                records.trackingStarts.append(event)
            } else {
                dropped += 1
            }
        default:
            break
        }
    }

    private static func limitEvent(from record: LogRecord, app: BarApp) -> LimitLifecycleEvent? {
        guard let limit = OTLPLines.limitDescriptor(from: record.attributes ?? []),
              let time = record.timeUnixNano, time > 0 else {
            return nil
        }
        let kind: LimitLifecycleEvent.Kind = record.eventName == limitAppearedEventName ? .appeared : .disappeared
        return LimitLifecycleEvent(app: app, limit: limit, kind: kind, timeUnixNano: time)
    }

    private static func trackingStarted(from record: LogRecord, app: BarApp) -> TrackingStartedEvent? {
        guard let minutes = record.attributes?.attribute("tracking.interval_minutes")?.intValue,
              TrackingSettings.intervalRange.contains(Int(clamping: minutes)),
              let time = record.timeUnixNano, time > 0 else {
            return nil
        }
        return TrackingStartedEvent(app: app, intervalMinutes: Int(clamping: minutes), timeUnixNano: time)
    }

    private static func perkEvent(from record: LogRecord, app: BarApp) -> PerkGoneEvent? {
        let attributes = record.attributes ?? []
        guard let kind = attributes.string("perk.kind").flatMap(PerkKind.init(rawValue:)),
              let time = record.timeUnixNano, time > 0,
              let currency = PerkAttributes.currency(of: kind, in: attributes),
              let expiresAt = PerkAttributes.expiresAt(in: attributes) else {
            return nil
        }

        var quantity: Double?
        if let attribute = attributes.attribute("perk.quantity") {
            guard let value = attribute.doubleValue ?? attribute.intValue.map(Double.init),
                  value.isFinite, value > 0 else {
                return nil
            }
            quantity = value
        } else if kind != .creditGrant {
            quantity = 1
        }

        var reason: PerkGoneReason?
        if let attribute = attributes.attribute("perk.gone.reason") {
            guard let written = attribute.stringValue, let parsed = PerkGoneReason(rawValue: written), parsed != .unknown else {
                return nil
            }
            reason = parsed
        }

        return PerkGoneEvent(
            app: app,
            kind: kind,
            currency: currency.value,
            quantity: quantity,
            perkID: attributes.string("perk.id"),
            expiresAt: expiresAt.value,
            reportedReason: reason,
            timeUnixNano: time
        )
    }

    private static func reset(from record: LogRecord, app: BarApp) -> LimitReset? {
        let attributes = record.attributes ?? []
        guard let limit = OTLPLines.limitDescriptor(from: attributes),
              let time = record.timeUnixNano, time > 0,
              let last = attributes.attribute("limit.utilization.last")?.doubleValue,
              (0...100).contains(last) else {
            return nil
        }

        var next: Date?
        if let attribute = attributes.attribute("limit.resets_at.next") {
            // Present but unusable is a broken record, the same rule the
            // Window length follows.
            guard let seconds = attribute.intValue, seconds > 0 else {
                return nil
            }
            next = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return LimitReset(app: app, limit: limit, timeUnixNano: time, utilizationLast: last, nextResetsAt: next)
    }
}

// MARK: - OTLP/JSON shapes

private struct ExportLogsServiceRequest: Decodable {
    let resourceLogs: [ResourceLogs]?
}

private struct ResourceLogs: Decodable {
    let resource: LogResource?
    let scopeLogs: [ScopeLogs]?
}

private struct LogResource: Decodable {
    let attributes: [KeyValue]?
}

private struct ScopeLogs: Decodable {
    /// Nil when absent or not a scope object; either way it doesn't conform.
    let scope: InstrumentationScope?
    let logRecords: [LogRecord]?

    private enum CodingKeys: String, CodingKey {
        case scope, logRecords
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A scope that isn't an object reads as missing, which drops its
        // bar.* events, rather than throwing away the whole line.
        scope = try? container.decodeIfPresent(InstrumentationScope.self, forKey: .scope)
        logRecords = try container.decodeIfPresent([LogRecord].self, forKey: .logRecords)
    }
}

private struct LogRecord: Decodable {
    let eventName: String?
    let severityNumber: Int?
    let timeUnixNano: Int64?
    let observedTimeUnixNano: Int64?
    let attributes: [KeyValue]?
    /// The event name was present but not a string, so which event this is
    /// can't be told.
    let isEventNameMalformed: Bool
    /// Some field, or an attribute's value, was present but of the wrong type.
    let isMalformed: Bool

    private enum CodingKeys: String, CodingKey {
        case eventName, severityNumber, timeUnixNano, observedTimeUnixNano, attributes
    }

    /// Spec §5: every `bar.*` event is INFO (severity 9) and carries the time
    /// it was observed as well as the time it happened.
    var isInfoWithObservedTime: Bool {
        severityNumber == 9 && (observedTimeUnixNano ?? 0) > 0
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var nameMalformed = false
        var malformed = false
        eventName = container.decodeLeniently(String.self, forKey: .eventName, malformed: &nameMalformed)
        severityNumber = container.decodeLeniently(Int.self, forKey: .severityNumber, malformed: &malformed)
        timeUnixNano = container.decodeLeniently(OTLPInt.self, forKey: .timeUnixNano, malformed: &malformed)?.value
        observedTimeUnixNano = container.decodeLeniently(OTLPInt.self, forKey: .observedTimeUnixNano, malformed: &malformed)?.value
        attributes = container.decodeLeniently([KeyValue].self, forKey: .attributes, malformed: &malformed)
        isEventNameMalformed = nameMalformed
        isMalformed = nameMalformed || malformed || attributes?.isMalformed == true
    }
}
