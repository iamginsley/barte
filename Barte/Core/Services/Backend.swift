import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// The Firebase project, from GoogleService-Info.plist (git-ignored, downloaded from the Firebase console).
enum Backend {
    /// Region of the Cloud Functions and the Firestore database: Frankfurt.
    static let region = "europe-west3"

    /// Configures Firebase once. False when the plist is missing, so the app shows how to set it up.
    @MainActor
    static let isConfigured: Bool = {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else { return false }
        FirebaseApp.configure(options: options)
        // Only this person's groups, and only while the app runs: nothing stays behind after signing out.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        return true
    }()

    static var functions: Functions { Functions.functions(region: region) }

    static var currentUserID: String {
        get throws {
            guard let id = Auth.auth().currentUser?.uid else { throw BarteError.notSignedIn }
            return id
        }
    }
}

/// Errors with a German message for the UI. Server errors carry a `hint` set by the Cloud Functions.
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
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain {
            if nsError.code == FunctionsErrorCode.unavailable.rawValue || nsError.code == FunctionsErrorCode.deadlineExceeded.rawValue {
                return .offline
            }
            let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            return .server(hint: details?["hint"] as? String)
        }
        if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.unavailable.rawValue {
            return .offline
        }
        if nsError.domain == NSURLErrorDomain || nsError.code == AuthErrorCode.networkError.rawValue && nsError.domain == AuthErrorDomain {
            return .offline
        }
        return .server(hint: nil)
    }
}
