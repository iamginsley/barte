import Foundation
import Supabase

/// Values injected at build time from Config.xcconfig via Info.plist.
enum AppConfig {
    static var supabaseURL: URL? {
        guard let host = infoValue("SupabaseHost") else { return nil }
        return URL(string: "https://\(host)")
    }

    static var supabaseAnonKey: String? { infoValue("SupabaseAnonKey") }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unresolved build settings or placeholders from the example file count as missing.
        if trimmed.isEmpty || trimmed.contains("$(") || trimmed.hasPrefix("your-") { return nil }
        return trimmed
    }
}

/// The single Supabase client for the app. `nil` when Config.xcconfig is missing.
enum Backend {
    static let client: SupabaseClient? = {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }()
}

/// Errors with a German message for the UI. Server errors carry a `hint` set by the SQL functions.
enum BarteError: LocalizedError, Equatable {
    case notSignedIn
    case offline
    case server(hint: String?)
    case appleRevocationFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Du bist nicht mehr angemeldet. Bitte melde dich erneut an."
        case .offline:
            "Keine Verbindung. Prüf dein Internet und versuch es noch einmal."
        case .appleRevocationFailed:
            "Die Verbindung zu deiner Apple-ID konnte nicht getrennt werden. Dein Konto ist noch da. Versuch es gleich noch einmal."
        case .server(let hint):
            switch hint {
            case "invalid_code": "Diesen Einladungscode gibt es nicht. Vielleicht wurde ein neuer Link erstellt?"
            case "member_taken": "Diesen Namen hat schon jemand anderes gewählt."
            case "member_involved": "Diese Person kommt in Ausgaben vor und kann nicht entfernt werden."
            case "member_linked": "Diese Person nutzt Barte selbst und kann nur selbst austreten."
            case "not_creator": "Nur wer die Gruppe erstellt hat, kann sie für alle löschen."
            case "not_member": "Du bist nicht mehr in dieser Gruppe."
            case "unknown_member": "Jemand aus dieser Ausgabe ist nicht mehr in der Gruppe."
            case "empty_name": "Bitte gib einen Namen ein."
            default: "Das hat nicht geklappt. Versuch es noch einmal."
            }
        }
    }

    /// Turns any thrown error into one the UI can show.
    static func from(_ error: Error) -> BarteError {
        if let error = error as? BarteError { return error }
        if let error = error as? PostgrestError { return .server(hint: error.hint) }
        if error is URLError { return .offline }
        return .server(hint: nil)
    }
}

extension SupabaseClient {
    var currentUserID: UUID {
        get throws {
            guard let id = auth.currentUser?.id else { throw BarteError.notSignedIn }
            return id
        }
    }
}
