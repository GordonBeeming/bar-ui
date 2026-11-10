import Testing
@testable import BarUICore

@Suite("App version")
struct AppVersionTests {
    @Test("A stamped GBDisplayVersion wins over the bundle's own numbers")
    func stampedWins() {
        let info: [String: Any] = [
            "GBDisplayVersion": "0.16-dev (1a2b3c4)",
            "CFBundleShortVersionString": "0.16",
            "CFBundleVersion": "0.16.1"
        ]

        #expect(AppVersion.display(from: info) == "0.16-dev (1a2b3c4)")
    }

    @Test("Without a stamp it reads as the marketing version and build")
    func versionAndBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.15", "CFBundleVersion": "42"]

        #expect(AppVersion.display(from: info) == "0.15 (42)")
    }

    @Test("A missing build leaves the marketing version alone, and nothing at all reads dev")
    func fallbacks() {
        #expect(AppVersion.display(from: ["CFBundleShortVersionString": "0.15"]) == "0.15")
        #expect(AppVersion.display(from: [:]) == "dev")
    }

    @Test("Blank and non-string values count as missing")
    func unusableValues() {
        let blank: [String: Any] = ["GBDisplayVersion": "  ", "CFBundleShortVersionString": "0.15", "CFBundleVersion": ""]
        let wrongTypes: [String: Any] = ["GBDisplayVersion": 7, "CFBundleShortVersionString": 0.15]

        #expect(AppVersion.display(from: blank) == "0.15")
        #expect(AppVersion.display(from: wrongTypes) == "dev")
    }

    @Test("The short form is v and the version, without the build or commit")
    func shortForm() {
        #expect(AppVersion(display: "0.16 (42)").short == "v0.16")
        #expect(AppVersion(display: "0.16-dev (1a2b3c4)").short == "v0.16-dev")
        #expect(AppVersion(display: "0.16").short == "v0.16")
        #expect(AppVersion(display: "dev").short == "dev")
    }
}
