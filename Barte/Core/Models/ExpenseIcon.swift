import Foundation

/// Picks an SF Symbol for an expense from words in its title ("Pizza" → fork and knife).
enum ExpenseIcon {
    private static let rules: [(symbol: String, words: [String])] = [
        ("dog.fill", ["dackel", "hund", "wuff"]),
        ("fork.knife", ["essen", "pizza", "restaurant", "burger", "sushi", "döner", "kebab", "dinner", "mittag", "frühstück", "brunch", "grill", "pasta"]),
        ("wineglass.fill", ["bier", "wein", "drinks", "bar", "cocktail", "spritzer", "prost", "party", "hütte"]),
        ("cup.and.saucer.fill", ["kaffee", "café", "cafe", "coffee", "kuchen"]),
        ("cart.fill", ["einkauf", "supermarkt", "spar", "billa", "hofer", "rewe", "lidl", "aldi", "edeka", "penny", "dm", "lebensmittel"]),
        ("car.fill", ["taxi", "uber", "bolt", "auto", "maut", "parken", "vignette", "mietwagen"]),
        ("figure.skiing.downhill", ["ski", "lift", "piste"]),
        ("fuelpump.fill",["tank", "sprit", "benzin", "diesel", "laden"]),
        ("tram.fill", ["zug", "bahn", "öbb", "db ", "u-bahn", "tube", "bus", "ticket öffi", "öffi"]),
        ("airplane", ["flug", "flight", "ryanair", "easyjet", "lufthansa", "austrian"]),
        ("bed.double.fill", ["hotel", "chalet", "airbnb", "unterkunft", "hostel", "apartment", "ferienwohnung"]),
        ("house.fill", ["miete", "wohnung"]),
        ("bolt.fill", ["strom", "energie"]),
        ("wifi", ["internet", "wlan", "wifi", "netflix", "spotify", "abo"]),
        ("film.fill", ["kino", "film"]),
        ("ticket.fill", ["ticket", "konzert", "festival", "eintritt", "museum"]),
        ("gift.fill", ["geschenk", "geburtstag", "present"]),
        ("bubbles.and.sparkles.fill", ["putz", "reinigung", "wasch"]),
        ("cross.case.fill", ["apotheke", "arzt"]),
    ]

    static func symbol(for title: String, isSettlement: Bool = false) -> String {
        if isSettlement { return "arrow.left.arrow.right" }
        let text = " " + title.lowercased() + " "
        return rules.first { rule in rule.words.contains { text.contains($0) } }?.symbol ?? "creditcard.fill"
    }
}
