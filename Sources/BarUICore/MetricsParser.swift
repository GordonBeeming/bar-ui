import Foundation

public struct MetricsParseResult: Sendable, Equatable {
    public let samples: [LimitSample]
    public let tokenSamples: [TokenSample]
    public let perkSamples: [PerkSample]
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
    private static let tokensMetricName = "bar.tokens"
    private static let newline = UInt8(ascii: "\n")

    public static func parse(_ data: Data, from app: BarApp) -> MetricsParseResult {
        guard let lastNewline = data.lastIndex(of: newline) else {
            return MetricsParseResult(samples: [], tokenSamples: [], perkSamples: [], droppedRecords: 0, consumedByteCount: 0)
        }
        let complete = data[data.startIndex..<lastNewline]
        let decoder = JSONDecoder()
        var samples: [LimitSample] = []
        var tokenSamples: [TokenSample] = []
        var perks = PerkAccumulator()
        var dropped = 0

        for line in complete.split(separator: newline, omittingEmptySubsequences: false) {
            guard let request = try? decoder.decode(ExportMetricsServiceRequest.self, from: Data(line)) else {
                dropped += 1
                continue
            }
            for resourceMetrics in request.resourceMetrics ?? [] {
                read(resourceMetrics, from: app, into: &samples, tokens: &tokenSamples, perks: &perks, dropped: &dropped)
            }
        }

        return MetricsParseResult(
            samples: samples,
            tokenSamples: tokenSamples,
            perkSamples: perks.samples,
            droppedRecords: dropped,
            consumedByteCount: lastNewline - data.startIndex + 1
        )
    }

    private static func read(
        _ resourceMetrics: ResourceMetrics,
        from app: BarApp,
        into samples: inout [LimitSample],
        tokens: inout [TokenSample],
        perks: inout PerkAccumulator,
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
                if metric.name == Self.tokensMetricName {
                    readTokens(metric, from: app, into: &tokens, dropped: &dropped)
                    continue
                }
                if metric.name == PerkSample.metricName {
                    guard let gauge = metric.gauge else {
                        dropped += 1
                        continue
                    }
                    for point in gauge.dataPoints ?? [] {
                        if let sample = perkSample(from: point, app: app) {
                            perks.add(sample)
                        } else {
                            dropped += 1
                        }
                    }
                    continue
                }
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

    private static func readTokens(
        _ metric: Metric,
        from app: BarApp,
        into tokens: inout [TokenSample],
        dropped: inout Int
    ) {
        // Reading a cumulative count as anything else would turn totals into
        // increments, so a Sum of another shape is dropped whole.
        guard let sum = metric.sum, sum.aggregationTemporality == 2, sum.isMonotonic == true else {
            dropped += 1
            return
        }
        for point in sum.dataPoints ?? [] {
            if let sample = tokenSample(from: point, app: app) {
                tokens.append(sample)
            } else {
                dropped += 1
            }
        }
    }

    private static func tokenSample(from point: NumberDataPoint, app: BarApp) -> TokenSample? {
        let attributes = point.attributes ?? []
        guard let model = attributes.string("model"), !model.isEmpty,
              let typeName = attributes.string("token.type"), let tokenType = TokenType(rawValue: typeName),
              let start = point.startTimeUnixNano, start > 0,
              let time = point.timeUnixNano, time > 0,
              let value = point.value, value >= 0, let count = Int64(exactly: value) else {
            return nil
        }
        return TokenSample(app: app, model: model, tokenType: tokenType, startTimeUnixNano: start, timeUnixNano: time, count: count)
    }

    private static func perkSample(from point: NumberDataPoint, app: BarApp) -> PerkSample? {
        let attributes = point.attributes ?? []
        guard let kind = attributes.string("perk.kind").flatMap(PerkKind.init(rawValue:)),
              let time = point.timeUnixNano, time > 0,
              let value = point.value, value.isFinite, value >= 0,
              let currency = PerkAttributes.currency(of: kind, in: attributes),
              let expiresAt = PerkAttributes.expiresAt(in: attributes) else {
            return nil
        }
        return PerkSample(app: app, kind: kind, currency: currency.value, timeUnixNano: time, value: value, expiresAt: expiresAt.value)
    }

    /// The Limit attributes every `bar.limit.*` metric point and event carries.
    /// Nil when one the spec requires is missing or broken.
    static func limitDescriptor(from attributes: [KeyValue]) -> LimitDescriptor? {
        guard let id = attributes.string("limit.id"), !id.isEmpty,
              let name = attributes.string("limit.name"), !name.isEmpty else {
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
        return LimitDescriptor(id: id, name: name, windowDurationMinutes: duration, modelID: attributes.string("model.id"))
    }

    private static func sample(from point: NumberDataPoint, metric: LimitMetric, app: BarApp) -> LimitSample? {
        let attributes = point.attributes ?? []
        guard let limit = limitDescriptor(from: attributes),
              let time = point.timeUnixNano, time > 0,
              let value = point.value, value.isFinite else {
            return nil
        }

        switch metric {
        case .utilization:
            guard (0...100).contains(value) else { return nil }
        case .resetsAt:
            guard value > 0 else { return nil }
        }

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
    let sum: Sum?
}

private struct Sum: Decodable {
    let aggregationTemporality: Int?
    let isMonotonic: Bool?
    let dataPoints: [NumberDataPoint]?

    private enum CodingKeys: String, CodingKey {
        case aggregationTemporality, isMonotonic, dataPoints
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aggregationTemporality = try? container.decodeIfPresent(Int.self, forKey: .aggregationTemporality)
        isMonotonic = try? container.decodeIfPresent(Bool.self, forKey: .isMonotonic)
        dataPoints = try? container.decodeIfPresent([NumberDataPoint].self, forKey: .dataPoints)
    }
}

private struct Gauge: Decodable {
    let dataPoints: [NumberDataPoint]?
}

private struct NumberDataPoint: Decodable {
    let attributes: [KeyValue]?
    let startTimeUnixNano: Int64?
    let timeUnixNano: Int64?
    let value: Double?

    private enum CodingKeys: String, CodingKey {
        case attributes, startTimeUnixNano, timeUnixNano, asDouble, asInt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attributes = try? container.decodeIfPresent([KeyValue].self, forKey: .attributes)
        startTimeUnixNano = (try? container.decodeIfPresent(OTLPInt.self, forKey: .startTimeUnixNano))?.value
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

struct KeyValue: Decodable {
    let key: String
    let value: AnyValue?
}

struct AnyValue: Decodable {
    let stringValue: String?
    let intValue: Int64?
    let doubleValue: Double?

    private enum CodingKeys: String, CodingKey {
        case stringValue, intValue, doubleValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stringValue = try? container.decodeIfPresent(String.self, forKey: .stringValue)
        intValue = (try? container.decodeIfPresent(OTLPInt.self, forKey: .intValue))?.value
        doubleValue = try? container.decodeIfPresent(Double.self, forKey: .doubleValue)
    }
}

/// OTLP/JSON writes 64-bit integers as strings, and receivers are expected to
/// take a plain JSON number too.
struct OTLPInt: Decodable {
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

extension [KeyValue] {
    func string(_ key: String) -> String? {
        first { $0.key == key }?.value?.stringValue
    }

    func attribute(_ key: String) -> AnyValue? {
        first { $0.key == key }?.value
    }
}
