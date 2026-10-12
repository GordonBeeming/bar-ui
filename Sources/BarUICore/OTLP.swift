import Foundation

/// The OTLP/JSON line handling the metrics and logs parsers share. Each file
/// holds one export request per `\n`-terminated line.
enum OTLPLines {
    private static let newline = UInt8(ascii: "\n")

    /// Decodes every complete line as a `Request` and hands it to `body`. A
    /// line that isn't a request at all is skipped and counted in
    /// `undecodableLines`, for the caller to report as dropped.
    /// `consumedByteCount` is how far into `data` the complete lines reach; a
    /// trailing partial line is left for the next read, once it's finished.
    static func forEachRequest<Request: Decodable>(
        in data: Data,
        as type: Request.Type,
        _ body: (Request) -> Void
    ) -> (consumedByteCount: Int, undecodableLines: Int) {
        guard let lastNewline = data.lastIndex(of: newline) else {
            return (0, 0)
        }
        var undecodable = 0
        let decoder = JSONDecoder()
        for line in data[data.startIndex..<lastNewline].split(separator: newline, omittingEmptySubsequences: false) {
            do {
                body(try decoder.decode(Request.self, from: Data(line)))
            } catch {
                undecodable += 1
            }
        }
        return (lastNewline - data.startIndex + 1, undecodable)
    }

    /// Whether a resource's records can be read as this Bar App's under
    /// Telemetry Spec v1. One that isn't is dropped whole rather than in part.
    static func isConforming(resource attributes: [KeyValue], of app: BarApp) -> Bool {
        attributes.string("bar.spec.version") == "1" && attributes.string("service.name") == app.serviceName
    }

    /// The rest of the resource attributes spec §3 requires. Only the `bar.*`
    /// records under a resource missing them are non-conforming; app-prefixed
    /// ones follow their own app's rules.
    static func hasSpecAttributes(resource attributes: [KeyValue]) -> Bool {
        attributes.string("service.version")?.isEmpty == false
            && attributes.string("host.name")?.isEmpty == false
            && attributes.string("os.type") == "darwin"
    }

    /// Whether the instrumentation scope is the one spec §3 names for this
    /// Bar App, with the app version set.
    static func isConforming(scope: InstrumentationScope?, of app: BarApp) -> Bool {
        guard let scope, !scope.isMalformed else {
            return false
        }
        return scope.name == app.telemetryScopeName && scope.version?.isEmpty == false
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
}

extension BarApp {
    /// Spec §3's `com.gordonbeeming.<AppName>.telemetry`, which is the bundle
    /// identifier with `.telemetry` on the end.
    var telemetryScopeName: String {
        "\(bundleIdentifier).telemetry"
    }
}

// MARK: - OTLP/JSON shapes both parsers read

struct InstrumentationScope: Decodable {
    let name: String?
    let version: String?
    /// A field was present but not a string.
    let isMalformed: Bool

    private enum CodingKeys: String, CodingKey {
        case name, version
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var malformed = false
        name = container.decodeLeniently(String.self, forKey: .name, malformed: &malformed)
        version = container.decodeLeniently(String.self, forKey: .version, malformed: &malformed)
        isMalformed = malformed
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
    /// A value field was present but not of its type.
    let isMalformed: Bool

    private enum CodingKeys: String, CodingKey {
        case stringValue, intValue, doubleValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var malformed = false
        stringValue = container.decodeLeniently(String.self, forKey: .stringValue, malformed: &malformed)
        intValue = container.decodeLeniently(OTLPInt.self, forKey: .intValue, malformed: &malformed)?.value
        doubleValue = container.decodeLeniently(Double.self, forKey: .doubleValue, malformed: &malformed)
        isMalformed = malformed
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

extension KeyedDecodingContainer {
    /// Nil when the field is absent or null. A field that is present but not
    /// a `T` is nil too, and sets `malformed`, so the record carrying it is
    /// dropped and counted rather than read as if the field were missing.
    /// Throwing instead would drop the whole line, valid records on it
    /// included.
    func decodeLeniently<T: Decodable>(_ type: T.Type, forKey key: Key, malformed: inout Bool) -> T? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            malformed = true
            return nil
        }
    }
}

extension [KeyValue] {
    /// Whether any attribute's value is present but of the wrong type.
    var isMalformed: Bool {
        contains { $0.value?.isMalformed == true }
    }

    func string(_ key: String) -> String? {
        first { $0.key == key }?.value?.stringValue
    }

    func attribute(_ key: String) -> AnyValue? {
        first { $0.key == key }?.value
    }
}
