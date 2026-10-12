import Foundation
import Testing
@testable import BarUICore

@Suite("Why a Perk is gone")
struct PerkGoneReasonTests {
    private let expiry = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The reason the Bar App wrote is used as it is")
    func reportedReasonWins() {
        let early = expiry.addingTimeInterval(-60)
        #expect(PerkGoneReason.resolve(reported: .expired, goneAt: early, expiresAt: expiry, redemptionOnRecord: false) == .expired)
        #expect(PerkGoneReason.resolve(reported: .used, goneAt: expiry.addingTimeInterval(60), expiresAt: expiry, redemptionOnRecord: false) == .used)
    }

    @Test("Going at or after its expiry means it expired")
    func atOrAfterExpiry() {
        #expect(PerkGoneReason.resolve(reported: nil, goneAt: expiry, expiresAt: expiry, redemptionOnRecord: false) == .expired)
        #expect(PerkGoneReason.resolve(reported: nil, goneAt: expiry.addingTimeInterval(1), expiresAt: expiry, redemptionOnRecord: false) == .expired)
    }

    @Test("Going before its expiry means it was used")
    func beforeExpiry() {
        #expect(PerkGoneReason.resolve(reported: nil, goneAt: expiry.addingTimeInterval(-1), expiresAt: expiry, redemptionOnRecord: false) == .used)
    }

    @Test("With no expiry known it was used only if a redemption is on record")
    func noExpiry() {
        #expect(PerkGoneReason.resolve(reported: nil, goneAt: expiry, expiresAt: nil, redemptionOnRecord: true) == .used)
        #expect(PerkGoneReason.resolve(reported: nil, goneAt: expiry, expiresAt: nil, redemptionOnRecord: false) == .unknown)
    }
}
