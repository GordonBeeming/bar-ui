import SwiftUI

@main
struct BarUIApp: App {
    var body: some Scene {
        // No preferredColorScheme anywhere: the window has to follow the Mac's
        // light/dark setting and switch live when the system does.
        WindowGroup("Bar UI") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
