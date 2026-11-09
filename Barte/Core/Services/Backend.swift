import Foundation

/// The Nhost project (Frankfurt). Subdomain and region are public: every request names them anyway.
enum Backend {
    static let subdomain = "uenqaayyhyrekjhojdwn"
    static let region = "eu-central-1"

    /// `https://<subdomain>.<service>.<region>.nhost.run/v1/<path>`
    static func url(_ service: String, _ path: String = "") -> URL {
        let base = URL(string: "https://\(subdomain).\(service).\(region).nhost.run/v1")!
        return path.isEmpty ? base : base.appending(path: path)
    }

    static let session = NhostSession()
    static let api = NhostAPI(session: session)
}

/// Errors with a German message for the UI. Server errors carry the hint the SQL functions raise.
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
            case "member_linked": "Diese Person nutzt Barte selbst. Nur sie kann ihren Namen ändern oder die Gruppe verlassen."
            case "not_creator": "Nur wer die Gruppe erstellt hat, kann sie für alle löschen."
            case "not_member": "Du bist nicht mehr in dieser Gruppe."
            case "unknown_member", "member_not_found": "Jemand aus dieser Ausgabe ist nicht mehr in der Gruppe."
            case "empty_name": "Bitte gib einen Namen ein."
            case "invalid_split": "Die Beträge ergeben nicht die Summe der Ausgabe."
            case "invalid_paypal": "Das sieht nicht nach einem PayPal.me-Namen aus."
            case "invalid_iban": "Bitte prüfe die IBAN."
            case "not_signed_in": "Du bist nicht mehr angemeldet. Bitte melde dich erneut an."
            default: "Das hat nicht geklappt. Versuch es noch einmal."
            }
        }
    }

    /// Turns any thrown error into one the UI can show.
    static func from(_ error: Error) -> BarteError {
        if let error = error as? BarteError { return error }
        if error is URLError { return .offline }
        return .server(hint: nil)
    }
}
