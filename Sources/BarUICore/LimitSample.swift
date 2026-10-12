/// The two Limit metrics the Telemetry Spec defines. The raw values are the
/// spec's metric names, which the Archive also stores, so they must not change.
public enum LimitMetric: String, Sendable, Hashable, CaseIterable {
    case utilization = "bar.limit.utilization"
    case resetsAt = "bar.limit.resets_at"
}

/// What a Bar App says about a Limit alongside each sample. Only `id` is
/// identity; the rest is the latest description and may change over time.
public struct LimitDescriptor: Sendable, Hashable {
    public let id: String
    public let name: String
    /// Nil when the Bar App doesn't know the Window's length.
    public let windowDurationMinutes: Int?
    public let modelID: String?

    public init(id: String, name: String, windowDurationMinutes: Int?, modelID: String?) {
        self.id = id
        self.name = name
        self.windowDurationMinutes = windowDurationMinutes
        self.modelID = modelID
    }
}

/// One data point of a Limit metric, as read from a Bar App's metrics file.
public struct LimitSample: Sendable, Hashable {
    public let app: BarApp
    public let limit: LimitDescriptor
    public let metric: LimitMetric
    public let timeUnixNano: Int64
    /// Percent used (0 to 100) for utilisation; Unix seconds for a reset time.
    public let value: Double

    public init(app: BarApp, limit: LimitDescriptor, metric: LimitMetric, timeUnixNano: Int64, value: Double) {
        self.app = app
        self.limit = limit
        self.metric = metric
        self.timeUnixNano = timeUnixNano
        self.value = value
    }
}
