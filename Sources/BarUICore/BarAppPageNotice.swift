/// The banner at the top of a Bar App's page saying where its Tracking
/// stands. It never replaces the page: the Archive keeps everything a Bar App
/// recorded, so its Limits, tokens and Perks show below whatever this says.
public enum BarAppPageNotice: Sendable, Hashable {
    case notInstalled
    case trackingOff(hasHistory: Bool)

    /// Nil while the Bar App is Tracking, when there is nothing to say.
    public init?(state: TrackingState) {
        switch state {
        case .tracking: return nil
        case .off: self = .trackingOff(hasHistory: false)
        case .offWithHistory: self = .trackingOff(hasHistory: true)
        case .notInstalled: self = .notInstalled
        }
    }

    public func title(appName: String) -> String {
        switch self {
        case .notInstalled: "\(appName) isn't installed."
        case .trackingOff: "Tracking is off."
        }
    }

    public func message(appName: String) -> String {
        switch self {
        case .notInstalled: "Anything it recorded before stays in the Archive and is shown below."
        case .trackingOff(let hasHistory): hasHistory ? "You're looking at History." : "Nothing is being recorded."
        }
    }
}
