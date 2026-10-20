import BarUICore
import SwiftUI

/// What Settings says under a login-item switch when macOS is waiting for
/// approval or the last change failed.
struct LoginItemNotes: View {
    let setting: LoginItemSetting
    let approvalText: String

    var body: some View {
        if setting.status == .requiresApproval {
            Label(approvalText, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let problem = setting.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
