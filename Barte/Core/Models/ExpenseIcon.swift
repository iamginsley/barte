import Foundation

/// Picks an SF Symbol for an expense from words in its title ("Pizza" → fork and knife).
enum ExpenseIcon {
    /// German and English words; matched as substrings of the padded, lower-cased title,
    /// so short English words carry a leading space (" car" must not match "Oscar").
    private static let rules: [(symbol: String, words: [String])] = [
        ("dog.fill", ["dackel", "hund", "wuff", "dachshund", " dog", "woof"]),
        ("fork.knife", ["essen", "pizza", "restaurant", "burger", "sushi", "döner", "kebab", "dinner", "mittag", "frühstück", "brunch", "grill", "pasta",
                        "food", "lunch", "breakfast", " meal", "takeaway", "takeout", "fish & chips", "bbq"]),
        ("wineglass.fill", ["bier", "wein", "drinks", "bar", "cocktail", "spritzer", "prost", "party", "hütte", "beer", "wine", " pub", "cheers"]),
        ("cup.and.saucer.fill", ["kaffee", "café", "cafe", "coffee", "kuchen", "cake"]),
        ("cart.fill", ["einkauf", "supermarkt", "spar", "billa", "hofer", "rewe", "lidl", "aldi", "edeka", "penny", "dm", "lebensmittel",
                       "grocer", "supermarket", "shopping", "tesco", "sainsbury", "walmart", "whole foods", "trader joe"]),
        ("car.fill", ["taxi", "uber", "bolt", "auto", "maut", "parken", "vignette", "mietwagen", " car ", " car", "cab ", " toll", "parking", "rental car"]),
        ("figure.skiing.downhill", ["ski", "lift", "piste", "slope"]),
        ("fuelpump.fill", ["tank", "sprit", "benzin", "diesel", "laden", "fuel", "petrol", " gas ", "gasoline", "charging"]),
        ("tram.fill", ["zug", "bahn", "öbb", "db ", "u-bahn", "tube", "bus", "ticket öffi", "öffi", "train", "metro", "subway", "tram", "rail"]),
        ("airplane", ["flug", "flight", "ryanair", "easyjet", "lufthansa", "austrian", "plane", "airline"]),
        ("bed.double.fill", ["hotel", "chalet", "airbnb", "unterkunft", "hostel", "apartment", "ferienwohnung", "accommodation", "lodging", "cabin"]),
        ("house.fill", ["miete", "wohnung", " rent", " flat "]),
        ("bolt.fill", ["strom", "energie", "electricity", "energy", "power bill", "utilities"]),
        ("wifi", ["internet", "wlan", "wifi", "netflix", "spotify", "abo", "subscription", "broadband"]),
        ("film.fill", ["kino", "film", "cinema", "movie"]),
        ("ticket.fill", ["ticket", "konzert", "festival", "eintritt", "museum", "concert", "admission", "entry"]),
        ("gift.fill", ["geschenk", "geburtstag", "present", "gift", "birthday"]),
        ("bubbles.and.sparkles.fill", ["putz", "reinigung", "wasch", "cleaning", "laundry", "detergent"]),
        ("cross.case.fill", ["apotheke", "arzt", "pharmacy", "doctor", "medicine"]),
    ]

    static func symbol(for title: String, isSettlement: Bool = false) -> String {
        if isSettlement { return "arrow.left.arrow.right" }
        let text = " " + title.lowercased() + " "
        return rules.first { rule in rule.words.contains { text.contains($0) } }?.symbol ?? "creditcard.fill"
    }
}
