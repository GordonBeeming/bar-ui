import CoreServices
import Foundation
import Testing
@testable import BarUICore

@Suite("How Bar UI was launched")
struct LaunchKindTests {
    private static func openEvent(propData: OSType?) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let propData {
            event.setParam(NSAppleEventDescriptor(enumCode: propData), forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }

    @Test("An open event marked launched-as-login-item is a login launch")
    func loginItemLaunch() {
        #expect(LaunchKind(launchEvent: Self.openEvent(propData: OSType(keyAELaunchedAsLogInItem))) == .atLogin)
    }

    @Test("A plain open, another marker, or no event at all is a launch by hand")
    func otherLaunches() {
        #expect(LaunchKind(launchEvent: Self.openEvent(propData: nil)) == .byHand)
        #expect(LaunchKind(launchEvent: Self.openEvent(propData: OSType(keyAELaunchedAsServiceItem))) == .byHand)
        #expect(LaunchKind(launchEvent: nil) == .byHand)
    }

    @Test("A login-item marker on an event that isn't open-application doesn't count")
    func onlyOpenApplication() {
        let reopen = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        reopen.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        #expect(LaunchKind(launchEvent: reopen) == .byHand)
    }
}

@Suite("Login item choices in UserDefaults")
struct UserDefaultsChoiceStoreTests {
    @Test("Each switch keeps its own choice, so turning one off leaves the other alone")
    func separateKeys() throws {
        let suite = "BarUICoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var openAtLogin = UserDefaultsChoiceStore(key: UserDefaultsChoiceStore.openAtLoginKey, defaults: defaults)
        let backgroundImport = UserDefaultsChoiceStore(key: UserDefaultsChoiceStore.backgroundImportKey, defaults: defaults)

        openAtLogin.choice = false

        #expect(openAtLogin.choice == false)
        #expect(backgroundImport.choice == nil)
    }

    @Test("The background-import switch keeps the key it always used, so an existing choice survives")
    func keepsExistingKey() {
        #expect(UserDefaultsChoiceStore.backgroundImportKey == "backgroundImport")
    }
}
