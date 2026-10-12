import SwiftUI

struct OverviewView: View {
    var body: some View {
        ContentUnavailableView(
            "No Telemetry yet",
            systemImage: "chart.bar.xaxis",
            description: Text("Usage from your Bar Apps shows up here once they record Telemetry.")
        )
        .navigationTitle("Overview")
    }
}
