/// How the Overview lays itself out. The whole-page empty state is only for an
/// Archive with nothing in it; otherwise every section shows, each with its
/// own empty state, so archived tokens and Events aren't hidden just because
/// no Limit is being Tracked right now.
public enum OverviewLayout: Sendable, Hashable {
    case nothingArchived
    case sections

    /// `holdsTelemetry` is nil when the Archive couldn't say, and then the
    /// sections show alongside the problem rather than claiming it's empty.
    public init(holdsTelemetry: Bool?) {
        self = holdsTelemetry == false ? .nothingArchived : .sections
    }
}
