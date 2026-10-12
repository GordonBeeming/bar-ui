import Foundation

/// Reads the Limit, token and Perk samples out of a Bar App's OTLP/JSON metrics lines,
/// following Telemetry Spec v1. Anything that doesn't conform is dropped and
/// counted, never guessed at.
public enum MetricsParser {
    private static let tokensMetricName = "bar.tokens"

    public static func parse(_ data: Data, from app: BarApp) -> TelemetryParseResult {
        var records = TelemetryRecords()
        var perks = PerkAccumulator()
        var dropped = 0
        let lines = OTLPLines.forEachRequest(in: data, as: ExportMetricsServiceRequest.self) { request in
            for resourceMetrics in request.resourceMetrics ?? [] {
                read(resourceMetrics, from: app, into: &records.limitSamples, tokens: &records.tokenSamples, perks: &perks, dropped: &dropped)
            }
        }
        records.perkSamples = perks.samples
        return TelemetryParseResult(records: records, droppedRecords: dropped + lines.undecodableLines, consumedByteCount: lines.consumedByteCount)
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
        guard OTLPLines.isConforming(resource: resource, of: app) else {
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
        guard let sum = metric.sum, !sum.isMalformed, sum.aggregationTemporality == 2, sum.isMonotonic == true else {
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
        guard !point.isMalformed,
              let model = attributes.string("model"), !model.isEmpty,
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
        guard !point.isMalformed,
              let kind = attributes.string("perk.kind").flatMap(PerkKind.init(rawValue:)),
              let time = point.timeUnixNano, time > 0,
              let value = point.value, value.isFinite, value >= 0,
              let currency = PerkAttributes.currency(of: kind, in: attributes),
              let expiresAt = PerkAttributes.expiresAt(in: attributes) else {
            return nil
        }
        return PerkSample(app: app, kind: kind, currency: currency.value, timeUnixNano: time, value: value, expiresAt: expiresAt.value)
    }

    private static func sample(from point: NumberDataPoint, metric: LimitMetric, app: BarApp) -> LimitSample? {
        let attributes = point.attributes ?? []
        guard !point.isMalformed,
              let limit = OTLPLines.limitDescriptor(from: attributes),
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
    /// A field was present but of the wrong type.
    let isMalformed: Bool

    private enum CodingKeys: String, CodingKey {
        case aggregationTemporality, isMonotonic, dataPoints
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var malformed = false
        aggregationTemporality = container.decodeLeniently(Int.self, forKey: .aggregationTemporality, malformed: &malformed)
        isMonotonic = container.decodeLeniently(Bool.self, forKey: .isMonotonic, malformed: &malformed)
        dataPoints = container.decodeLeniently([NumberDataPoint].self, forKey: .dataPoints, malformed: &malformed)
        isMalformed = malformed
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
    /// Some field, or an attribute's value, was present but of the wrong type.
    let isMalformed: Bool

    private enum CodingKeys: String, CodingKey {
        case attributes, startTimeUnixNano, timeUnixNano, asDouble, asInt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var malformed = false
        attributes = container.decodeLeniently([KeyValue].self, forKey: .attributes, malformed: &malformed)
        startTimeUnixNano = container.decodeLeniently(OTLPInt.self, forKey: .startTimeUnixNano, malformed: &malformed)?.value
        timeUnixNano = container.decodeLeniently(OTLPInt.self, forKey: .timeUnixNano, malformed: &malformed)?.value
        let double = container.decodeLeniently(Double.self, forKey: .asDouble, malformed: &malformed)
        let int = container.decodeLeniently(OTLPInt.self, forKey: .asInt, malformed: &malformed)?.value
        value = double ?? int.map(Double.init)
        isMalformed = malformed || attributes?.isMalformed == true
    }
}
