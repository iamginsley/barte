import Foundation

/// Which member "I" am in each group, and my name for new groups. Kept on this device only:
/// members are plain names, so every friend picks themselves once per group.
@MainActor
enum Identity {
    private static var defaults: UserDefaults = .standard

    /// Demo mode uses its own, emptied defaults so screenshots never touch real data.
    static func useDemoDefaults() {
        let suite = "com.iamginsley.barte.demo"
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite) ?? .standard
    }

    static func me(in groupID: UUID) -> UUID? {
        defaults.string(forKey: key(groupID)).flatMap(UUID.init(uuidString:))
    }

    static func setMe(_ memberID: UUID?, in groupID: UUID) {
        defaults.set(memberID?.uuidString, forKey: key(groupID))
    }

    static var myName: String {
        get { defaults.string(forKey: "myName") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "myName") }
    }

    private static func key(_ groupID: UUID) -> String { "me." + groupID.uuidString }
}
