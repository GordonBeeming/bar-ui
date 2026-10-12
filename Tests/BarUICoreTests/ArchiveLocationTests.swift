import Foundation
import Testing
@testable import BarUICore

@Suite("Archive location")
struct ArchiveLocationTests {
    @Test("The Archive lives in Bar UI's own folder under Application Support, created on demand")
    func createsItsFolder() throws {
        let temp = try TemporaryFolder()

        let url = try ArchiveLocation.url(inApplicationSupport: temp.url)

        #expect(url.path == temp.url.appendingPathComponent("com.gordonbeeming.BarUI/Archive.sqlite").path)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
