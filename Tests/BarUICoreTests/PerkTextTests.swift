import Foundation
import Testing
@testable import BarUICore

@Suite("How Perks read on the page")
struct PerkTextTests {
    private let locale = Locale(identifier: "en_US")

    @Test("Counted Perks say how many, singular or plural")
    func counts() {
        #expect(PerkText.quantity(kind: .resetCredit, quantity: 1, currency: nil, locale: locale) == "1 Reset Credit")
        #expect(PerkText.quantity(kind: .resetCredit, quantity: 3, currency: nil, locale: locale) == "3 Reset Credits")
        #expect(PerkText.quantity(kind: .guestPass, quantity: 2, currency: nil, locale: locale) == "2 Guest Passes")
        #expect(PerkText.quantity(kind: .guestPass, quantity: 1, currency: nil, locale: locale) == "1 Guest Pass")
    }

    @Test("A Credit Grant shows its amount in its own currency")
    func amounts() {
        #expect(PerkText.quantity(kind: .creditGrant, quantity: 12.5, currency: "USD", locale: locale) == "$12.50 Credit Grant")
        #expect(PerkText.quantity(kind: .creditGrant, quantity: 20, currency: "AUD", locale: locale) == "A$20.00 Credit Grant")
    }

    @Test("A currency with no minor units shows none")
    func zeroExponentCurrency() {
        #expect(PerkText.quantity(kind: .creditGrant, quantity: 1500, currency: "JPY", locale: locale) == "¥1,500 Credit Grant")
    }

    @Test("A Credit Grant that went without an amount says so")
    func unknownAmount() {
        #expect(PerkText.quantity(kind: .creditGrant, quantity: nil, currency: "USD", locale: locale) == "Credit Grant, amount unknown")
    }

    @Test("A code that isn't a currency is shown as it was written")
    func unrecognisedCurrency() {
        #expect(PerkText.quantity(kind: .creditGrant, quantity: 5, currency: "XYZ", locale: locale).contains("XYZ"))
    }

    @Test("Each reason has a label")
    func reasons() {
        #expect(PerkText.label(for: .used) == "Used")
        #expect(PerkText.label(for: .expired) == "Expired")
        #expect(PerkText.label(for: .unknown) == "Reason unknown")
    }

    struct ItemLineCase: Sendable {
        let kind: PerkKind
        let currency: String?
        let quantity: Double
        let expiresAt: Date?
        let expected: String
    }

    static let itemLineCases: [ItemLineCase] = [
        ItemLineCase(kind: .resetCredit, currency: nil, quantity: 1, expiresAt: Date(timeIntervalSince1970: 1_792_800_000), expected: "1 Reset Credit \u{00B7} Expires 24 Oct 2026"),
        ItemLineCase(kind: .guestPass, currency: nil, quantity: 2, expiresAt: nil, expected: "2 Guest Passes \u{00B7} No expiry known"),
        ItemLineCase(kind: .creditGrant, currency: "AUD", quantity: 12.5, expiresAt: Date(timeIntervalSince1970: 1_792_800_000), expected: "$12.50 Credit Grant \u{00B7} Expires 24 Oct 2026")
    ]

    @Test("An item line says what it is and when it expires", arguments: PerkTextTests.itemLineCases)
    func itemLine(_ testCase: ItemLineCase) {
        let line = PerkText.itemLine(
            kind: testCase.kind,
            currency: testCase.currency,
            item: AvailablePerkItem(quantity: testCase.quantity, perkID: "x", expiresAt: testCase.expiresAt),
            locale: Locale(identifier: "en_AU"),
            timeZone: TimeZone(identifier: "UTC") ?? .gmt
        )
        #expect(line == testCase.expected)
    }

    @Test("A group of one Perk with no id stays a single line; any other group lists its items")
    func singleLineRule() {
        let plain = AvailablePerkItem(quantity: 2, perkID: nil, expiresAt: nil)
        let identified = AvailablePerkItem(quantity: 1, perkID: "a", expiresAt: nil)
        func group(_ items: [AvailablePerkItem]) -> AvailablePerk {
            AvailablePerk(app: .codexBar, kind: .resetCredit, currency: nil, items: items, sampledAt: Date(timeIntervalSince1970: 0))
        }
        #expect(!group([plain]).listsItems)
        #expect(group([identified]).listsItems)
        #expect(group([identified, identified]).listsItems)
    }
}
