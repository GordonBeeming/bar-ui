import Foundation
import Testing
@testable import BarUICore

@Suite("Bar App page notice")
struct BarAppPageNoticeTests {
    @Test("A Tracking Bar App's page has no notice")
    func trackingHasNone() {
        #expect(BarAppPageNotice(state: .tracking) == nil)
    }

    @Test("Tracking off says whether there is History to look at")
    func trackingOff() {
        #expect(BarAppPageNotice(state: .off) == .trackingOff(hasHistory: false))
        #expect(BarAppPageNotice(state: .offWithHistory) == .trackingOff(hasHistory: true))
        #expect(BarAppPageNotice.trackingOff(hasHistory: false).message(appName: "ClaudeBar") == "Nothing is being recorded.")
        #expect(BarAppPageNotice.trackingOff(hasHistory: true).message(appName: "ClaudeBar") == "You're looking at History.")
    }

    @Test("An uninstalled Bar App's page says so and that what the Archive holds is still shown")
    func notInstalled() {
        let notice = BarAppPageNotice(state: .notInstalled)

        #expect(notice == .notInstalled)
        #expect(notice?.title(appName: "CodexBar") == "CodexBar isn't installed.")
        #expect(notice?.message(appName: "CodexBar") == "Anything it recorded before stays in the Archive and is shown below.")
    }
}
