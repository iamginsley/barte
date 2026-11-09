import Foundation

/// Public pages on GitHub Pages, in the language the app shows.
enum Legal {
    static var privacyPolicy: URL {
        Bundle.main.preferredLocalizations.first == "en"
            ? URL(string: "https://iamginsley.github.io/barte/privacy")!
            : URL(string: "https://iamginsley.github.io/barte/datenschutz")!
    }
}
