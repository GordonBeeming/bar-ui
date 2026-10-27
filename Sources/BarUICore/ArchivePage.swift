public enum ArchivePage: String, CaseIterable, Sendable, Hashable {
    case events
    case imports

    public var title: String {
        switch self {
        case .events: "Resets & Perks"
        case .imports: "Imports"
        }
    }
}
