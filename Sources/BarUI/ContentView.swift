import BarUICore
import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .initial

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.all, id: \.self) { section in
                    if let title = section.title {
                        Section(title) {
                            rows(for: section)
                        }
                    } else {
                        rows(for: section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        } detail: {
            detail(for: selection ?? .initial)
        }
    }

    private func rows(for section: SidebarSection) -> some View {
        ForEach(section.items) { item in
            SidebarRow(item: item)
                .tag(item)
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .overview:
            OverviewView()
        case .barApp, .archive:
            PlaceholderPageView(item: item)
        }
    }
}
