import Foundation
import Testing
@testable import BarUICore

@Suite("Burn Rate text")
struct BurnRateTextTests {
    // Typed up front so the @Test macro doesn't have to infer the tuples.
    private static let cases: [(Double, String)] = [
        (24, "+24%/h"),
        (3.24, "+3.2%/h"),
        (0.04, "Steady"),
        (0, "Steady")
    ]

    @Test("A rising Window reads as points gained per hour; one that isn't moving reads as steady", arguments: cases)
    func text(percentPerHour: Double, expected: String) {
        #expect(MenuBarLimitRow.burnRateText(percentPerHour: percentPerHour) == expected)
    }
}
