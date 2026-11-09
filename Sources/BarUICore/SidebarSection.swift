public struct SidebarSection: Sendable, Hashable {
    /// Nil for the leading section, which sits above the first heading.
    public let title: String?
    public let items: [SidebarItem]

    public init(title: String?, items: [SidebarItem]) {
        self.title = title
        self.items = items
    }

    public static let all: [SidebarSection] = sections(accounts: [])

    /// A Bar App with only its default Account keeps its single row. One with
    /// several, or with a single one that isn't the default, is listed as its
    /// Accounts, so each has a page of its own.
    public static func sections(accounts: [BarAppAccount]) -> [SidebarSection] {
        let barApps = BarApp.allCases.flatMap { app -> [SidebarItem] in
            let own = Set(accounts.filter { $0.app == app }).sorted()
            // One Account that isn't the default still has to be that Account:
            // the app's own row would open the default's page, which is empty.
            if own.count == 1, let only = own.first, !only.isDefault {
                return [.account(only)]
            }
            return own.count > 1 ? own.map(SidebarItem.account) : [.barApp(app)]
        }
        return [
            SidebarSection(title: nil, items: [.overview]),
            SidebarSection(title: "Bar Apps", items: barApps),
            SidebarSection(title: "Archive", items: ArchivePage.allCases.map(SidebarItem.archive))
        ]
    }
}
