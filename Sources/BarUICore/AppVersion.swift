import Foundation

/// Which build of Bar UI this is, in words a person can read out and a bug
/// report can carry.
public struct AppVersion: Sendable, Equatable {
    /// The full text, such as `0.16 (42)` for a release or `0.16-dev (1a2b3c4)`
    /// for a local build.
    public let display: String
    /// The short form for tight spots: `v0.16`, or `v0.16-dev`.
    public let short: String

    public init(display: String) {
        self.display = display
        self.short = Self.short(from: display)
    }

    /// The running app's own Info.plist.
    public static var current: AppVersion {
        AppVersion(display: display(from: Bundle.main.infoDictionary ?? [:]))
    }

    /// `GBDisplayVersion` when the build stamped one. Otherwise the marketing
    /// version with its build number, then the marketing version alone, and
    /// `dev` when the app runs from somewhere with no Info.plist at all, such
    /// as `swift run`.
    public static func display(from info: [String: Any]) -> String {
        if let stamped = text(info["GBDisplayVersion"]) {
            return stamped
        }
        guard let version = text(info["CFBundleShortVersionString"]) else {
            return "dev"
        }
        guard let build = text(info["CFBundleVersion"]) else {
            return version
        }
        return "\(version) (\(build))"
    }

    /// The version before its parenthesised part, with a `v`. `dev` has no
    /// number to put one in front of.
    static func short(from display: String) -> String {
        guard display != "dev" else {
            return display
        }
        let version = display.split(separator: " ", maxSplits: 1).first.map(String.init) ?? display
        return "v\(version)"
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }
}
