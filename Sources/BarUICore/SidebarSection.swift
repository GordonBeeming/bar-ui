public struct SidebarSection: Sendable, Hashable {
    /// Nil for the leading section, which sits above the first heading.
    public let title: String?
    public let items: [SidebarItem]

    public init(title: String?, items: [SidebarItem]) {
        self.title = title
        self.items = items
    }

    public static let all: [SidebarSection] = [
        SidebarSection(title: nil, items: [.overview]),
        SidebarSection(title: "Bar Apps", items: BarApp.allCases.map(SidebarItem.barApp)),
        SidebarSection(title: "Archive", items: ArchivePage.allCases.map(SidebarItem.archive))
    ]
}
