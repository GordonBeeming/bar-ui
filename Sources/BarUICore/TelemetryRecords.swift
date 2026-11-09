import Foundation

/// An Account's `account.name`, kept for showing to people. It never decides
/// which series a record belongs to.
public struct AccountName: Sendable, Hashable {
    public let app: BarApp
    public let accountID: String
    public let name: String
    /// The newest time of any point or event in the resource that carried the
    /// name, in Unix nanoseconds. A rename is told from an older report of the
    /// old name by this, not by the order files happen to be read in.
    public let reportedAt: Int64

    public init(app: BarApp, accountID: String = BarAppAccount.defaultID, name: String, reportedAt: Int64 = 0) {
        self.app = app
        self.accountID = accountID
        self.name = name
        self.reportedAt = reportedAt
    }
}

/// Everything one read of a Telemetry file turned up, in the shape the Archive
/// stores it. A metrics file fills the samples and a logs file the events; the
/// Archive writes them, and the file's new read position, as one unit.
public struct TelemetryRecords: Sendable, Equatable {
    public var limitSamples: [LimitSample]
    public var tokenSamples: [TokenSample]
    public var perkSamples: [PerkSample]
    public var resets: [LimitReset]
    public var perkGoneEvents: [PerkGoneEvent]
    public var perkAvailableEvents: [PerkAvailableEvent]
    public var limitEvents: [LimitLifecycleEvent]
    public var trackingStarts: [TrackingStartedEvent]
    /// The labels Accounts gave themselves in the resources that were read.
    public var accountNames: [AccountName]

    public init(
        limitSamples: [LimitSample] = [],
        tokenSamples: [TokenSample] = [],
        perkSamples: [PerkSample] = [],
        resets: [LimitReset] = [],
        perkGoneEvents: [PerkGoneEvent] = [],
        perkAvailableEvents: [PerkAvailableEvent] = [],
        limitEvents: [LimitLifecycleEvent] = [],
        trackingStarts: [TrackingStartedEvent] = [],
        accountNames: [AccountName] = []
    ) {
        self.limitSamples = limitSamples
        self.tokenSamples = tokenSamples
        self.perkSamples = perkSamples
        self.resets = resets
        self.perkGoneEvents = perkGoneEvents
        self.perkAvailableEvents = perkAvailableEvents
        self.limitEvents = limitEvents
        self.trackingStarts = trackingStarts
        self.accountNames = accountNames
    }
}

/// What a parser made of a stretch of Telemetry lines. The records' own fields
/// read straight through, so `result.resets` is `result.records.resets`.
@dynamicMemberLookup
public struct TelemetryParseResult: Sendable, Equatable {
    public let records: TelemetryRecords
    /// Lines, resources, data points and events that broke the Telemetry Spec
    /// and were dropped. Metrics and events the spec doesn't define aren't
    /// counted.
    public let droppedRecords: Int
    /// How far into the data the complete, `\n`-terminated lines reach. A
    /// trailing partial line is left for the next read, once it's finished.
    public let consumedByteCount: Int

    public subscript<Value>(dynamicMember keyPath: KeyPath<TelemetryRecords, Value>) -> Value {
        records[keyPath: keyPath]
    }
}
