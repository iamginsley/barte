import Foundation
import Testing
@testable import Barte

/// German is the source language; English must be complete. The other suites run in German
/// (scheme test language), so English is checked here against the catalogs and the en bundle.
@Suite("English")
struct LocalizationTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let catalogs = ["Barte/Resources/Localizable.xcstrings", "Barte/Resources/Demo.xcstrings", "BarteWidgets/Localizable.xcstrings"]

    /// The app's English strings, whatever language the test run uses.
    private var english: Bundle {
        get throws { try #require(Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))) }
    }

    @Test(arguments: catalogs)
    func everyStringHasEnglish(catalog: String) throws {
        let data = try Data(contentsOf: Self.root.appending(path: catalog))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty)
        let missing = strings.filter { _, entry in
            guard entry["extractionState"] as? String != "stale", entry["shouldTranslate"] as? Bool != false else { return false }
            let localizations = entry["localizations"] as? [String: Any]
            return localizations?["en"] == nil
        }
        #expect(missing.isEmpty, "No English for: \(missing.keys.sorted())")
    }

    @Test func englishWordingAndPlurals() throws {
        let en = try english
        func text(_ key: String, _ arguments: any CVarArg...) -> String {
            String(format: en.localizedString(forKey: key, value: nil, table: nil), locale: Locale(identifier: "en_US"), arguments: arguments)
        }
        #expect(text("Bar oder mit Karte? Egal, Barte rechnet.") == "Cash or card? Barte does the math.")
        #expect(text("%lld neue Nachrichten", 1) == "1 new message")
        #expect(text("%lld neue Nachrichten", 3) == "3 new messages")
        #expect(text("%lld Personen", 1) == "1 person")
        #expect(text("%lld Personen", 5) == "5 people")
        #expect(text("Mit %lld Überweisungen seid ihr quitt", 1) == "1 transfer and you're all square")
        #expect(text("%lld Anteile, %@", 2, "€10.00") == "2 shares, €10.00")
        #expect(text("%lld Anteile, %@", 1, "€5.00") == "1 share, €5.00")
        #expect(text("%@ hat %@ in %@ umbenannt", "Ben", "Clara", "Klara") == "Ben renamed Clara to Klara")
        #expect(text("Du hast %@ eingetragen", "“Pizza”") == "You added “Pizza”")
        #expect(text("Diesen Einladungscode gibt es nicht. Vielleicht wurde ein neuer Link erstellt?")
            == "This invite code doesn't exist. Maybe a new link was created?")
    }

    @Test func germanPluralsStillWork() {
        #expect(String(localized: "\(1) neue Nachrichten") == "1 neue Nachricht")
        #expect(String(localized: "\(4) neue Nachrichten") == "4 neue Nachrichten")
        #expect(UnreadBadge.label(1) == "1 neue Nachricht")
    }

    @Test(arguments: [
        ("Gas", "fuelpump.fill"), ("Groceries", "cart.fill"), ("Dinner at Luigi's", "fork.knife"), ("Train tickets", "tram.fill"),
        ("Rent", "house.fill"), ("Electricity", "bolt.fill"), ("Movie night", "film.fill"), ("Pub", "wineglass.fill"),
        ("Birthday gift", "gift.fill"), ("Car rental", "car.fill"), ("Oscar statue", "creditcard.fill"), ("Parent's gift", "gift.fill"),
        ("Tanken", "fuelpump.fill"), ("Dackel", "dog.fill"),
    ])
    func iconsMatchEnglishAndGermanTitles(title: String, symbol: String) {
        #expect(ExpenseIcon.symbol(for: title) == symbol)
    }

    @MainActor @Test func pushLanguageTag() {
        #expect(PushToken.tag(language: "en", region: "GB") == "en-GB")
        #expect(PushToken.tag(language: "de", region: "AT") == "de-AT")
        #expect(PushToken.tag(language: "en-US", region: "DE") == "en-DE")
        #expect(PushToken.tag(language: nil, region: nil) == "de")
    }
}
