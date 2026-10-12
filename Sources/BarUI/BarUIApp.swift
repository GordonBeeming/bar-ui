import SwiftUI

@main
struct BarUIApp: App {
    /// Opened once for the app: every window shares one connection, and the
    /// shared overview skips a refresh while another window's is running.
    @State private var archive = ArchiveOpening.open()

    var body: some Scene {
        // No preferredColorScheme anywhere: the window has to follow the Mac's
        // light/dark setting and switch live when the system does.
        WindowGroup("Bar UI") {
            ContentView(archive: archive)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
