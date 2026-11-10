import Testing
@testable import BarUICore

@Suite("Menu Bar Preview grid")
struct MenuBarGridTests {
    @Test("One card gets one full-width column, more than one gets two")
    func columnCount() {
        #expect(MenuBarGrid.columnCount(forCards: 0) == 1)
        #expect(MenuBarGrid.columnCount(forCards: 1) == 1)
        #expect(MenuBarGrid.columnCount(forCards: 2) == 2)
        #expect(MenuBarGrid.columnCount(forCards: 5) == 2)
    }

    @Test("Cards fill across a row at a time, in their existing order")
    func rowMajor() {
        let five = [1, 2, 3, 4, 5]

        #expect(MenuBarGrid.rows(of: five, columns: 2) == [[1, 2], [3, 4], [5]])
        #expect(MenuBarGrid.rows(of: [1, 2, 3, 4], columns: 2) == [[1, 2], [3, 4]])
        #expect(MenuBarGrid.rows(of: [1], columns: MenuBarGrid.columnCount(forCards: 1)) == [[1]])
        #expect(MenuBarGrid.rows(of: [Int](), columns: 2).isEmpty)
        #expect(MenuBarGrid.rows(of: five, columns: 0).isEmpty)
    }

    @Test("The accounts' own order is kept")
    func accountOrder() {
        let accounts = [
            BarAppAccount(app: .claudeBar), BarAppAccount(app: .claudeBar, accountID: "work"),
            BarAppAccount(app: .codexBar), BarAppAccount(app: .grokBar)
        ]

        let rows = MenuBarGrid.rows(of: accounts, columns: 2)

        #expect(rows.flatMap { $0 } == accounts)
        #expect(rows.map(\.count) == [2, 2])
    }

    @Test("The card area gets what a screen has left after the summary, footer and spacing")
    func cardAreaLimit() {
        // A large screen: plenty left.
        #expect(MenuBarGrid.cardAreaLimit(visibleHeight: 1_400, summaryHeight: 300, footerHeight: 40, spacing: 90) == 970)
        // A laptop screen: less, so the cards scroll.
        #expect(MenuBarGrid.cardAreaLimit(visibleHeight: 900, summaryHeight: 300, footerHeight: 40, spacing: 90) == 470)
    }

    @Test("A screen with no room left gives 0, never a minimum that pushes the footer off")
    func cardAreaLimitClamps() {
        #expect(MenuBarGrid.cardAreaLimit(visibleHeight: 400, summaryHeight: 300, footerHeight: 40, spacing: 90) == 0)
        #expect(MenuBarGrid.cardAreaLimit(visibleHeight: 0, summaryHeight: 0, footerHeight: 0, spacing: 90) == 0)
    }
}
