import BarUICore
import Foundation

struct UserDefaultsChoiceStore: BackgroundImportChoiceStoring {
    static let key = "backgroundImport"

    // Apple documents UserDefaults as safe to use from any thread; it just
    // isn't annotated Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Nil until the person has flipped the switch, which reads as on.
    var choice: Bool? {
        get { defaults.object(forKey: Self.key) as? Bool }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
