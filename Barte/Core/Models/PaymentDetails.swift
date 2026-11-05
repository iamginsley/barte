import Foundation

/// How someone wants to get money: a PayPal.me name and/or a bank account.
/// Visible to everyone who shares a group with them, so paying back needs no "where to?".
struct PaymentDetails: Hashable, Sendable {
    /// The name behind paypal.me/, without the domain.
    var paypal: String?
    /// Upper case, without spaces.
    var iban: String?
    var accountHolder: String?

    var isEmpty: Bool { paypal == nil && iban == nil }

    /// paypal.me link with the amount filled in, e.g. https://paypal.me/annahuber/12.50EUR
    func paypalURL(amountCents: Int, currency: String) -> URL? {
        guard let paypal else { return nil }
        let amount = "\(amountCents / 100).\(String(format: "%02d", amountCents % 100))"
        return URL(string: "https://paypal.me/\(paypal)/\(amount)\(currency)")
    }
}

enum PayPalMe {
    /// Accepts "annahuber", "paypal.me/annahuber", "https://www.paypal.me/annahuber/" or "@annahuber".
    /// Returns nil for empty input, `.failure` for something that can't be a PayPal.me name.
    static func normalize(_ text: String) -> Result<String, Invalid>? {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        for prefix in ["https://", "http://", "www."] where name.lowercased().hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        if name.lowercased().hasPrefix("paypal.me/") { name.removeFirst("paypal.me/".count) }
        if name.hasPrefix("@") { name.removeFirst() }
        // A pasted link may carry an amount: paypal.me/annahuber/10EUR
        name = String(name.split(separator: "/").first ?? "")
        let valid = (1...20).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return valid ? .success(name) : .failure(Invalid())
    }

    struct Invalid: Error, Equatable {}
}

enum IBAN {
    /// Upper case without spaces, or nil for empty input. Does not check validity.
    static func compact(_ text: String) -> String? {
        let compact = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        return compact.isEmpty ? nil : compact
    }

    /// Country code, check digits and the mod-97 checksum (ISO 13616).
    static func isValid(_ iban: String) -> Bool {
        let chars = Array(iban)
        guard (15...34).contains(chars.count),
              chars[0...1].allSatisfy({ $0.isASCII && $0.isUppercase }),
              chars[2...3].allSatisfy({ $0.isASCII && $0.isNumber }),
              chars.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return false }
        var remainder = 0
        for char in chars[4...] + chars[0..<4] {
            if let digit = char.wholeNumberValue {
                remainder = (remainder * 10 + digit) % 97
            } else if let ascii = char.asciiValue {
                remainder = (remainder * 100 + Int(ascii) - 55) % 97
            }
        }
        return remainder == 1
    }

    /// Groups of four for reading: "DE89 3704 0044 0532 0130 00".
    static func formatted(_ iban: String) -> String {
        stride(from: 0, to: iban.count, by: 4).map { offset in
            let start = iban.index(iban.startIndex, offsetBy: offset)
            let end = iban.index(start, offsetBy: 4, limitedBy: iban.endIndex) ?? iban.endIndex
            return String(iban[start..<end])
        }.joined(separator: " ")
    }
}
