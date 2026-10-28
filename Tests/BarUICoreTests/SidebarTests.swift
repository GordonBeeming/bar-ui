import Testing
@testable import BarUICore

@Suite("Sidebar")
struct SidebarTests {
    @Test("Sections follow the design order")
    func sectionsFollowDesignOrder() {
        let sections = SidebarSection.all

        #expect(sections.map(\.title) == [nil, "Bar Apps", "Archive"])
        #expect(sections.map(\.items) == [
            [.overview],
            [.barApp(.claudeBar), .barApp(.codexBar)],
            [.archive(.events), .archive(.imports)]
        ])
    }

    @Test("Bar Apps are the closed set, named as in the glossary")
    func barAppsAreClosedSet() {
        #expect(BarApp.allCases.map(\.displayName) == ["ClaudeBar", "CodexBar"])
    }

    @Test("Every item has its sidebar title")
    func itemTitles() {
        let titles = SidebarSection.all.flatMap(\.items).map(\.title)

        #expect(titles == ["Overview", "ClaudeBar", "CodexBar", "Resets & Perks", "Imports"])
    }

    @Test("Item ids are unique and stable")
    func itemIds() {
        let ids = SidebarSection.all.flatMap(\.items).map(\.id)

        #expect(ids == ["overview", "barApp.claudeBar", "barApp.codexBar", "archive.events", "archive.imports"])
    }

    @Test("The window opens on the Overview")
    func defaultSelection() {
        #expect(SidebarItem.initial == .overview)
    }
}
