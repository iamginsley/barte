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

/// Errors with a message for the UI, in the device language. Server errors carry the hint the SQL functions raise.
enum BarteError: LocalizedError, Equatable {
    case notSignedIn
    case offline
    case server(hint: String?)
    case appleRevocationFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            String(localized: "Du bist nicht mehr angemeldet. Bitte melde dich erneut an.")
        case .offline:
            String(localized: "Keine Verbindung. Prüf dein Internet und versuch es noch einmal.")
        case .appleRevocationFailed:
            String(localized: "Die Verbindung zu deiner Apple-ID konnte nicht getrennt werden. Dein Konto ist noch da. Versuch es gleich noch einmal.")
        case .server(let hint):
            switch hint {
            case "invalid_code": String(localized: "Diesen Einladungscode gibt es nicht. Vielleicht wurde ein neuer Link erstellt?")
            case "member_taken": String(localized: "Diesen Namen hat schon jemand anderes gewählt.")
            case "member_involved": String(localized: "Diese Person kommt in Ausgaben vor und kann nicht entfernt werden.")
            case "member_linked": String(localized: "Diese Person nutzt Barte selbst. Nur sie kann ihren Namen ändern oder die Gruppe verlassen.")
            case "open_balance": String(localized: "Du kannst die Gruppe erst verlassen, wenn du quitt bist. Sonst bliebe offen, wer wem etwas schuldet.")
            case "open_balances": String(localized: "Abschließen geht erst, wenn alle quitt sind.")
            case "reminded_recently": String(localized: "Du hast heute schon erinnert. Morgen geht es wieder.")
            case "nothing_owed", "invalid_amount": String(localized: "Hier ist nichts mehr offen. Vielleicht hat schon jemand gezahlt?")
            case "no_app": String(localized: "Diese Person nutzt Barte nicht. Schick ihr die Erinnerung lieber als Nachricht.")
            case "not_member": String(localized: "Du bist nicht mehr in dieser Gruppe.")
            case "unknown_member", "member_not_found": String(localized: "Jemand aus dieser Ausgabe ist nicht mehr in der Gruppe.")
            case "empty_name": String(localized: "Bitte gib einen Namen ein.")
            case "invalid_split": String(localized: "Die Beträge ergeben nicht die Summe der Ausgabe.")
            case "invalid_paypal": String(localized: "Das sieht nicht nach einem PayPal.me-Namen aus.")
            case "invalid_iban": String(localized: "Bitte prüfe die IBAN.")
            case "not_signed_in": String(localized: "Du bist nicht mehr angemeldet. Bitte melde dich erneut an.")
            default: String(localized: "Das hat nicht geklappt. Versuch es noch einmal.")
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
