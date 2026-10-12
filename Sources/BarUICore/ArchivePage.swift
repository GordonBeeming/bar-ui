public enum ArchivePage: String, CaseIterable, Sendable, Hashable {
    case events
    case imports

    public var title: String {
        switch self {
        case .events: "Events"
        case .imports: "Imports"
        }
    }
}
