import Foundation

/// A reminder for someone without the app: a message I send them myself, in my words.
/// (People with Barte get a push from the server instead, see `GroupRepository.remind`.)
enum Reminder {
    static func message(to name: String, group: String, amount: String, paypal: URL?) -> String {
        let text = String(localized: "Hallo \(name), kleine Erinnerung: Für „\(group)“ sind noch \(amount) an mich offen.",
                          comment: "Reminder message for someone without the app")
        guard let paypal else { return text }
        return text + "\n" + String(localized: "Per PayPal: \(paypal.absoluteString)", comment: "Reminder message: PayPal link with the amount")
    }
}
