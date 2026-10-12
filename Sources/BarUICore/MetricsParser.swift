import Foundation

public struct MetricsParseResult: Sendable, Equatable {
    public let samples: [LimitSample]
    /// Lines, resources and `bar.limit.*` data points that broke the Telemetry
    /// Spec and were dropped. Metrics the spec doesn't define aren't counted.
    public let droppedRecords: Int
    /// How far into the data the complete, `\n`-terminated lines reach. A
    /// trailing partial line is left for the next read, once it's finished.
    public let consumedByteCount: Int
}

/// Reads the Limit samples out of a Bar App's OTLP/JSON metrics lines,
/// following Telemetry Spec v1. Anything that doesn't conform is dropped and
/// counted, never guessed at.
public enum MetricsParser {
    private static let newline = UInt8(ascii: "\n")

    public static func parse(_ data: Data, from app: BarApp) -> MetricsParseResult {
        guard let lastNewline = data.lastIndex(of: newline) else {
            return MetricsParseResult(samples: [], droppedRecords: 0, consumedByteCount: 0)
        }
        let complete = data[data.startIndex..<lastNewline]
        let decoder = JSONDecoder()
        var samples: [LimitSample] = []
        var dropped = 0

        for line in complete.split(separator: newline, omittingEmptySubsequences: false) {
            guard let request = try? decoder.decode(ExportMetricsServiceRequest.self, from: Data(line)) else {
                dropped += 1
                continue
            }
            for resourceMetrics in request.resourceMetrics ?? [] {
                read(resourceMetrics, from: app, into: &samples, dropped: &dropped)
            }
        }

        return MetricsParseResult(
            samples: samples,
            droppedRecords: dropped,
            consumedByteCount: lastNewline - data.startIndex + 1
        )
    }

    private static func read(
        _ resourceMetrics: ResourceMetrics,
        from app: BarApp,
        into samples: inout [LimitSample],
        dropped: inout Int
    ) {
        let resource = resourceMetrics.resource?.attributes ?? []
        // A record from another spec version or another Bar App can't be read
        // as this one's, so the whole resource goes rather than part of it.
        guard resource.string("bar.spec.version") == "1",
              resource.string("service.name") == app.serviceName else {
            dropped += 1
            return
        }
        for scope in resourceMetrics.scopeMetrics ?? [] {
            for metric in scope.metrics ?? [] {
                guard let name = metric.name, let limitMetric = LimitMetric(rawValue: name) else {
                    continue
                }
                guard let gauge = metric.gauge else {
                    dropped += 1
                    continue
                }
                for point in gauge.dataPoints ?? [] {
                    if let sample = sample(from: point, metric: limitMetric, app: app) {
                        samples.append(sample)
                    } else {
                        dropped += 1
                    }
                }
            }
        }
    }

    private static func sample(from point: NumberDataPoint, metric: LimitMetric, app: BarApp) -> LimitSample? {
        let attributes = point.attributes ?? []
        guard let id = attributes.string("limit.id"), !id.isEmpty,
              let name = attributes.string("limit.name"), !name.isEmpty,
              let time = point.timeUnixNano, time > 0,
              let value = point.value, value.isFinite else {
            return nil
        }

        var duration: Int?
        if let attribute = attributes.first(where: { $0.key == "limit.window.duration_minutes" }) {
            // The spec says to leave the attribute out when unknown, so one
            // that is present but zero or not an int is a broken record.
            guard let minutes = attribute.value?.intValue, minutes > 0, let exact = Int(exactly: minutes) else {
                return nil
            }
            duration = exact
        }

        switch metric {
        case .utilization:
            guard (0...100).contains(value) else { return nil }
        case .resetsAt:
            guard value > 0 else { return nil }
        }

        let limit = LimitDescriptor(
            id: id,
            name: name,
            windowDurationMinutes: duration,
            modelID: attributes.string("model.id")
        )
        return LimitSample(app: app, limit: limit, metric: metric, timeUnixNano: time, value: value)
    }
}

// MARK: - OTLP/JSON shapes

// Only the fields Bar UI reads. Every field is optional so a record missing
// one is judged against the spec by the parser, not rejected wholesale by
// the decoder along with the valid points on the same line.

private struct ExportMetricsServiceRequest: Decodable {
    let resourceMetrics: [ResourceMetrics]?
}

private struct ResourceMetrics: Decodable {
    let resource: Resource?
    let scopeMetrics: [ScopeMetrics]?
}

private struct Resource: Decodable {
    let attributes: [KeyValue]?
}

private struct ScopeMetrics: Decodable {
    let metrics: [Metric]?
}

private struct Metric: Decodable {
    let name: String?
    let gauge: Gauge?
}

private struct Gauge: Decodable {
    let dataPoints: [NumberDataPoint]?
}

private struct NumberDataPoint: Decodable {
    let attributes: [KeyValue]?
    let timeUnixNano: Int64?
    let value: Double?

    private enum CodingKeys: String, CodingKey {
        case attributes, timeUnixNano, asDouble, asInt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attributes = try? container.decodeIfPresent([KeyValue].self, forKey: .attributes)
        timeUnixNano = (try? container.decodeIfPresent(OTLPInt.self, forKey: .timeUnixNano))?.value
        if let double = try? container.decodeIfPresent(Double.self, forKey: .asDouble) {
            value = double
        } else if let int = (try? container.decodeIfPresent(OTLPInt.self, forKey: .asInt))?.value {
            value = Double(int)
        } else {
            value = nil
        }
    }
}

private struct KeyValue: Decodable {
    let key: String
    let value: AnyValue?
}

private struct AnyValue: Decodable {
    let stringValue: String?
    let intValue: Int64?

    private enum CodingKeys: String, CodingKey {
        case stringValue, intValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stringValue = try? container.decodeIfPresent(String.self, forKey: .stringValue)
        intValue = (try? container.decodeIfPresent(OTLPInt.self, forKey: .intValue))?.value
    }
}

/// OTLP/JSON writes 64-bit integers as strings, and receivers are expected to
/// take a plain JSON number too.
private struct OTLPInt: Decodable {
    let value: Int64

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let parsed = Int64(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a 64-bit integer: \(string)")
            }
            value = parsed
        } else {
            value = try container.decode(Int64.self)
        }
    }
}

private extension [KeyValue] {
    func string(_ key: String) -> String? {
        first { $0.key == key }?.value?.stringValue
    }
}
