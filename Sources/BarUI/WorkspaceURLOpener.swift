import AppKit
import BarUICore

/// Opens a Bar App's URL through Launch Services, which launches the Bar App
/// if needed and brings it forward so its confirmation is seen.
struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(url, configuration: configuration)
    }
}
