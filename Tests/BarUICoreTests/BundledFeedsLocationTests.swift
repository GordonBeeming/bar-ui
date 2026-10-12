import Foundation
import Testing
@testable import BarUICore

@Suite("Bundled feeds location")
struct BundledFeedsLocationTests {
    @Test("Finds the resource bundle in the first folder that holds it")
    func findsBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let holder = root.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: holder.appendingPathComponent(BundledFeeds.bundleName, isDirectory: true),
            withIntermediateDirectories: true
        )

        let found = BundledFeeds.locateBundle(in: [empty, holder])

        #expect(found?.bundleURL.standardizedFileURL == holder.appendingPathComponent(BundledFeeds.bundleName).standardizedFileURL)
    }

    @Test("A missing resource bundle is reported, not a crash")
    func missingBundleThrows() {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        #expect(BundledFeeds.locateBundle(in: [nowhere]) == nil)
        #expect(throws: BundledFeeds.Missing.self) {
            try BundledFeeds.data(named: "litellm-prices", in: nil)
        }
    }
}
