import BarUICore
import SwiftUI

enum MainWindow {
    static let id = "main"
}

@main
struct BarUIApp: App {
    /// Opened once for the app: every window shares one connection, and the
    /// shared overview skips a refresh while another window's is running.
    @State private var archive = ArchiveOpening.open()
    @State private var monitor = BarAppMonitor(detector: BarAppDetector(
        locator: WorkspaceApplicationLocator(),
        preferences: SystemPreferences(),
        homeDirectory: ContentView.home
    ))
    @State private var openAtLogin = LoginItemSetting(
        service: LoginItemService.app,
        store: UserDefaultsChoiceStore(key: UserDefaultsChoiceStore.openAtLoginKey)
    )
    @State private var backgroundImport = LoginItemSetting(
        service: LoginItemService.helper,
        store: UserDefaultsChoiceStore(key: UserDefaultsChoiceStore.backgroundImportKey)
    )
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // No preferredColorScheme anywhere: the window has to follow the Mac's
        // light/dark setting and switch live when the system does.
        //
        // A single Window rather than a WindowGroup, so Open Bar UI in the
        // Menu Bar Preview brings this one forward instead of making another.
        Window("Bar UI", id: MainWindow.id) {
            ContentView(monitor: monitor, archive: archive)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1440, height: 900)
        // Never opened by a launch on its own: at login Bar UI stays in the
        // menu bar, and a launch by hand opens it from the menu bar label.
        // Restoration is off too, or a window left open at logout would come
        // back at the next login despite the suppressed launch.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarPreviewView(preview: archive.preview, monitor: monitor, archiveFailure: archive.failure)
        } label: {
            MenuBarLabel(
                appDelegate: appDelegate,
                openAtLogin: openAtLogin,
                backgroundImport: backgroundImport
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(openAtLogin: openAtLogin, backgroundImport: backgroundImport)
        }
    }
}
