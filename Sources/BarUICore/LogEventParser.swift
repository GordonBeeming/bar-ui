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

public struct LogParseResult: Sendable, Equatable {
    public let resets: [LimitReset]
    public let perkGoneEvents: [PerkGoneEvent]
    public let limitEvents: [LimitLifecycleEvent]
    public let trackingStarts: [TrackingStartedEvent]
    public let perkAvailableEvents: [PerkAvailableEvent]
    /// Lines, resources and `bar.limit.reset` and `bar.perk.*` events that broke the Telemetry
    /// Spec and were dropped. Events the Dashboard doesn't read aren't counted.
    public let droppedRecords: Int
    /// How far into the data the complete, `\n`-terminated lines reach.
    public let consumedByteCount: Int
}

/// Reads `bar.limit.reset` events out of a Bar App's OTLP/JSON logs lines,
/// following Telemetry Spec v1.
public enum LogEventParser {
    private static let newline = UInt8(ascii: "\n")
    private static let resetEventName = "bar.limit.reset"
    private static let perkAvailableEventName = "bar.perk.available"
    private static let perkGoneEventName = "bar.perk.gone"
    private static let limitAppearedEventName = "bar.limit.appeared"
    private static let limitDisappearedEventName = "bar.limit.disappeared"
    private static let trackingStartedEventName = "bar.tracking.started"

    public static func parse(_ data: Data, from app: BarApp) -> LogParseResult {
        guard let lastNewline = data.lastIndex(of: newline) else {
            return LogParseResult(resets: [], perkGoneEvents: [], limitEvents: [], trackingStarts: [], perkAvailableEvents: [], droppedRecords: 0, consumedByteCount: 0)
        }
        let complete = data[data.startIndex..<lastNewline]
        let decoder = JSONDecoder()
        var resets: [LimitReset] = []
        var perkGone: [PerkGoneEvent] = []
        var perkAvailable: [PerkAvailableEvent] = []
        var limitEvents: [LimitLifecycleEvent] = []
        var trackingStarts: [TrackingStartedEvent] = []
        var dropped = 0

        for line in complete.split(separator: newline, omittingEmptySubsequences: false) {
            guard let request = try? decoder.decode(ExportLogsServiceRequest.self, from: Data(line)) else {
                dropped += 1
                continue
            }
            for resourceLogs in request.resourceLogs ?? [] {
                let resource = resourceLogs.resource?.attributes ?? []
                guard resource.string("bar.spec.version") == "1",
                      resource.string("service.name") == app.serviceName else {
                    dropped += 1
                    continue
                }
                for scope in resourceLogs.scopeLogs ?? [] {
                    for record in scope.logRecords ?? [] {
                        switch record.eventName {
                        case resetEventName:
                            if let reset = reset(from: record, app: app) {
                                resets.append(reset)
                            } else {
                                dropped += 1
                            }
                        case perkAvailableEventName, perkGoneEventName:
                            if let event = perkEvent(from: record, app: app) {
                                if record.eventName == perkGoneEventName {
                                    perkGone.append(event)
                                } else {
                                    perkAvailable.append(PerkAvailableEvent(gone: event))
                                }
                            } else {
                                dropped += 1
                            }
                        case limitAppearedEventName, limitDisappearedEventName:
                            if let event = limitEvent(from: record, app: app) {
                                limitEvents.append(event)
                            } else {
                                dropped += 1
                            }
                        case trackingStartedEventName:
                            if let event = trackingStarted(from: record, app: app) {
                                trackingStarts.append(event)
                            } else {
                                dropped += 1
                            }
                        default:
                            break
                        }
                    }
                }
            }
        }

        return LogParseResult(
            resets: resets,
            perkGoneEvents: perkGone,
            limitEvents: limitEvents,
            trackingStarts: trackingStarts,
            perkAvailableEvents: perkAvailable,
            droppedRecords: dropped,
            consumedByteCount: lastNewline - data.startIndex + 1
        )
    }

    private static func limitEvent(from record: LogRecord, app: BarApp) -> LimitLifecycleEvent? {
        guard let limit = MetricsParser.limitDescriptor(from: record.attributes ?? []),
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
        guard let limit = MetricsParser.limitDescriptor(from: attributes),
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
    let logRecords: [LogRecord]?
}

private struct LogRecord: Decodable {
    let eventName: String?
    let timeUnixNano: Int64?
    let attributes: [KeyValue]?

    private enum CodingKeys: String, CodingKey {
        case eventName, timeUnixNano, attributes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventName = try? container.decodeIfPresent(String.self, forKey: .eventName)
        timeUnixNano = (try? container.decodeIfPresent(OTLPInt.self, forKey: .timeUnixNano))?.value
        attributes = try? container.decodeIfPresent([KeyValue].self, forKey: .attributes)
    }
}
