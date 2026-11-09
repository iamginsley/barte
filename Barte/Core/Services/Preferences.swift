import Foundation

/// Small per-device settings. `myName` caches the account name, which lives on the server
/// (profiles) and is the same in every group.
@MainActor
enum Preferences {
    private static var defaults: UserDefaults = .standard

    /// Demo mode uses its own, emptied defaults so screenshots never touch real data.
    static func useDemoDefaults() {
        let suite = "com.iamginsley.barte.demo"
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite) ?? .standard
    }

    static var myName: String {
        get { defaults.string(forKey: "myName") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "myName") }
    }
}
