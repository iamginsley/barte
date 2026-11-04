import Foundation

/// Amounts are integer minor units (cents) everywhere; only the UI converts to text.
/// All supported currencies have two decimal places, so 1 unit = 100 cents.
enum Money {
    static let locale = Locale(identifier: "de_DE")

    /// Currencies a group can use. Kept short on purpose; all have two decimals.
    static let currencies = ["EUR", "CHF", "USD", "GBP", "DKK", "SEK", "NOK", "PLN", "CZK"]

    static func format(_ cents: Int, currency: String, showsSign: Bool = false) -> String {
        let value = Decimal(cents) / 100
        var style = Decimal.FormatStyle.Currency(code: currency, locale: locale)
        if showsSign { style = style.sign(strategy: .always()) }
        return value.formatted(style)
    }

    /// Currency symbol for input fields, e.g. "€" or "CHF".
    static func symbol(for currency: String) -> String {
        var components = Locale.Components(locale: locale)
        components.currency = Locale.Currency(currency)
        return Locale(components: components).currencySymbol ?? currency
    }

    /// Localized currency name, e.g. "Euro".
    static func name(for currency: String) -> String {
        locale.localizedString(forCurrencyCode: currency) ?? currency
    }

    /// Plain editable text for a text field, e.g. "25,00".
    static func editString(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.number.locale(locale).precision(.fractionLength(2)).grouping(.never))
    }

    /// Parses user input like "12", "12,5", "12,50", "1.234,56", "12.50" or "12,50 €" into cents.
    static func parse(_ text: String) -> Int? {
        var cleaned = text.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        guard !cleaned.isEmpty, !cleaned.contains("-") else { return nil }

        let lastComma = cleaned.lastIndex(of: ",")
        let lastDot = cleaned.lastIndex(of: ".")
        // The right-most separator followed by 1–2 digits is the decimal separator; the other is grouping.
        let decimalSeparator: Character? = {
            switch (lastComma, lastDot) {
            case let (c?, d?): return c > d ? "," : "."
            case (_?, nil): return ","
            case (nil, let d?):
                let digitsAfter = cleaned.distance(from: d, to: cleaned.endIndex) - 1
                return digitsAfter <= 2 ? "." : nil
            default: return nil
            }
        }()
        if let decimalSeparator {
            let grouping: Character = decimalSeparator == "," ? "." : ","
            cleaned.removeAll { $0 == grouping }
            cleaned = cleaned.replacingOccurrences(of: String(decimalSeparator), with: ".")
        } else {
            cleaned.removeAll { $0 == "." || $0 == "," }
        }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let whole = Int(parts[0].isEmpty ? "0" : parts[0]) else { return nil }
        var cents = 0
        if parts.count == 2 {
            let fraction = parts[1]
            guard fraction.count <= 2 else { return nil }
            cents = Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        }
        let (total, overflow) = whole.multipliedReportingOverflow(by: 100)
        guard !overflow, total <= 100_000_000_00 else { return nil }
        return total + cents
    }
}
