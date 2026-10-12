import Foundation
import Testing
@testable import BarUICore

@Suite("Background import setting")
@MainActor
struct BackgroundImportSettingTests {
    @Test("On a first launch the login item gets registered, because the switch is on by default")
    func registersByDefault() {
        let service = FakeLoginItem()
        let setting = BackgroundImportSetting(service: service, store: FakeChoiceStore())

        setting.reconcile()

        #expect(service.status == .enabled)
        #expect(setting.isEnabled)
        #expect(setting.problem == nil)
    }

    @Test("Turning the switch off unregisters the login item and the choice survives a relaunch")
    func switchingOffUnregisters() {
        let service = FakeLoginItem()
        let store = FakeChoiceStore()
        let setting = BackgroundImportSetting(service: service, store: store)
        setting.reconcile()

        setting.setEnabled(false)

        #expect(service.status == .notRegistered)
        #expect(!setting.isEnabled)
        #expect(store.choice == false)

        let relaunched = BackgroundImportSetting(service: service, store: store)
        relaunched.reconcile()
        #expect(service.status == .notRegistered)
        #expect(!relaunched.isEnabled)
    }

    @Test("Turning the switch back on registers again")
    func switchingBackOn() {
        let service = FakeLoginItem()
        let setting = BackgroundImportSetting(service: service, store: FakeChoiceStore())
        setting.setEnabled(false)

        setting.setEnabled(true)

        #expect(service.status == .enabled)
        #expect(setting.isEnabled)
    }

    @Test("A login item left registered while the switch is off is unregistered at launch")
    func reconcileUnregistersWhenOff() {
        let service = FakeLoginItem()
        service.status = .enabled
        let store = FakeChoiceStore()
        store.choice = false
        let setting = BackgroundImportSetting(service: service, store: store)

        setting.reconcile()

        #expect(service.status == .notRegistered)
    }

    @Test("Reconciling twice registers once")
    func reconcileIsIdempotent() {
        let service = FakeLoginItem()
        let setting = BackgroundImportSetting(service: service, store: FakeChoiceStore())

        setting.reconcile()
        setting.reconcile()

        #expect(service.registerCalls == 1)
    }

    @Test("A registration that fails is reported and the switch shows what is really registered")
    func registrationFailure() {
        let service = FakeLoginItem()
        service.registerError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        let setting = BackgroundImportSetting(service: service, store: FakeChoiceStore())

        setting.reconcile()

        #expect(setting.problem == "Operation not permitted")
        #expect(setting.status == .notRegistered)
    }

    @Test("A failed unregister is reported")
    func unregisterFailure() {
        let service = FakeLoginItem()
        service.status = .enabled
        service.unregisterError = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Busy"])
        let setting = BackgroundImportSetting(service: service, store: FakeChoiceStore())

        setting.setEnabled(false)

        #expect(setting.problem == "Busy")
        #expect(setting.status == .enabled)
    }

    @Test("A login item waiting for approval in System Settings is not registered again")
    func requiresApprovalLeftAlone() {
        let service = FakeLoginItem()
        service.status = .requiresApproval
        let setting = BackgroundImportSetting(service: service, store: FakeChoiceStore())

        setting.reconcile()

        #expect(service.registerCalls == 0)
        #expect(setting.status == .requiresApproval)
    }

    @Test("A build without the helper inside reports it and does not try to register")
    func helperMissing() {
        let service = FakeLoginItem()
        service.status = .notFound
        let setting = BackgroundImportSetting(service: service, store: FakeChoiceStore())

        setting.reconcile()

        #expect(service.registerCalls == 0)
        #expect(setting.status == .notFound)
    }
}

final class FakeLoginItem: LoginItemRegistering, @unchecked Sendable {
    var status: LoginItemStatus = .notRegistered
    var registerError: (any Error)?
    var unregisterError: (any Error)?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}

final class FakeChoiceStore: BackgroundImportChoiceStoring, @unchecked Sendable {
    var choice: Bool?
}
