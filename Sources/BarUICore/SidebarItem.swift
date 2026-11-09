public enum SidebarItem: Sendable, Hashable, Identifiable {
    case overview
    /// A Bar App with one Account, or none archived yet.
    case barApp(BarApp)
    /// One Account of a Bar App that has several.
    case account(BarAppAccount)
    case archive(ArchivePage)

    public static let initial: SidebarItem = .overview

    /// Built from raw values rather than titles so a renamed label never
    /// changes an id that selection or restoration has stored.
    public var id: String {
        switch self {
        case .overview: "overview"
        case .barApp(let app): "barApp.\(app.rawValue)"
        case .account(let account): "barApp.\(account.key)"
        case .archive(let page): "archive.\(page.rawValue)"
        }
    }

    public var title: String {
        title(names: [:])
    }

    /// `names` is what each Account called itself; an Account without one is
    /// shown by its id.
    public func title(names: [BarAppAccount: String]) -> String {
        switch self {
        case .overview: "Overview"
        case .barApp(let app): app.displayName
        case .account(let account): names[account] ?? (account.isDefault ? "Default" : account.accountID)
        case .archive(let page): page.title
        }
    }

    /// The Bar App the item belongs to, for the items that belong to one.
    public var app: BarApp? {
        switch self {
        case .barApp(let app): app
        case .account(let account): account.app
        case .overview, .archive: nil
        }
    }
}
