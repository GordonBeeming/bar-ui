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
    /// Lines, resources and `bar.limit.reset` events that broke the Telemetry
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

    public static func parse(_ data: Data, from app: BarApp) -> LogParseResult {
        guard let lastNewline = data.lastIndex(of: newline) else {
            return LogParseResult(resets: [], droppedRecords: 0, consumedByteCount: 0)
        }
        let complete = data[data.startIndex..<lastNewline]
        let decoder = JSONDecoder()
        var resets: [LimitReset] = []
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
                    for record in scope.logRecords ?? [] where record.eventName == resetEventName {
                        if let reset = reset(from: record, app: app) {
                            resets.append(reset)
                        } else {
                            dropped += 1
                        }
                    }
                }
            }
        }

        return LogParseResult(
            resets: resets,
            droppedRecords: dropped,
            consumedByteCount: lastNewline - data.startIndex + 1
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
