public enum SidebarItem: Sendable, Hashable, Identifiable {
    case overview
    case barApp(BarApp)
    case archive(ArchivePage)

    public static let initial: SidebarItem = .overview

    /// Built from raw values rather than titles so a renamed label never
    /// changes an id that selection or restoration has stored.
    public var id: String {
        switch self {
        case .overview: "overview"
        case .barApp(let app): "barApp.\(app.rawValue)"
        case .archive(let page): "archive.\(page.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .barApp(let app): app.displayName
        case .archive(let page): page.title
        }
    }
}
