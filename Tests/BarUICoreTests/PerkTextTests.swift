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
}
