import BarUICore
import SwiftUI

struct PlaceholderPageView: View {
    let item: SidebarItem

    var body: some View {
        ContentUnavailableView(item.title, systemImage: "hammer")
            .navigationTitle(item.title)
    }
}
