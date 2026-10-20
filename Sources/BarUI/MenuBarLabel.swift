import AppKit
import BarUICore
import os
import SwiftUI

/// The menu bar icon, and the work that has to happen on every launch. The
/// label is the one view that exists from launch to quit whether or not the
/// window is open, so it owns registering the login items, keeping prices
/// current, and opening the window when Bar UI was opened by hand.
struct MenuBarLabel: View {
    let appDelegate: AppDelegate
    let openAtLogin: LoginItemSetting
    let backgroundImport: LoginItemSetting
    let pricing: PricingCatalog

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .accessibilityLabel("Bar UI")
            .task {
                // Registers both login items the first time Bar UI runs, and
                // repairs them if they were removed or a choice changed since.
                openAtLogin.reconcile()
                backgroundImport.reconcile()
            }
            // The label can appear before launching finishes, so wait for the
            // launch kind rather than reading it once.
            .onChange(of: appDelegate.launchKind, initial: true) { _, kind in
                if kind == .byHand {
                    showWindow()
                }
            }
            .task {
                while !Task.isCancelled {
                    await pricing.refresh()
                    do {
                        try await Task.sleep(for: BarUIApp.pricingCheckInterval)
                    } catch {
                        // Cancelled as the app quits; stop checking.
                        return
                    }
                }
            }
            .onChange(of: appDelegate.reopenRequests) {
                showWindow()
            }
    }

    private func showWindow() {
        openWindow(id: MainWindow.id)
        // A menu bar app isn't brought forward by opening a window on its own.
        NSApp.activate()
    }
}
