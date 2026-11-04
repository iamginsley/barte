import SwiftUI
import UIKit

// Colors come from the asset catalog and point at iOS system colors, so light, dark and
// increased contrast come for free: .surface/.card (grouped backgrounds), .ink/.inkSecondary (labels),
// accent (system blue). .positive/.negative use Apple's increased-contrast green and red so balance
// text keeps ≥ 4.5:1 on white and on dark backgrounds.

extension Font {
    /// Rounded display face, used for large titles and hero amounts only.
    static let heroAmount = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    static let cardAmount = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let amount = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()
}

enum Theme {
    static let cardCornerRadius: CGFloat = 26
    static let minTapSize: CGFloat = 44
    /// Real payment cards are 85.6 × 54 mm.
    static let cardAspectRatio: CGFloat = 85.6 / 54
}

extension CardColor {
    var base: Color {
        switch self {
        case .blue: .cardBlue
        case .indigo: .cardIndigo
        case .purple: .cardPurple
        case .pink: .cardPink
        case .red: .cardRed
        case .orange: .cardOrange
        case .green: .cardGreen
        case .teal: .cardTeal
        case .graphite: .cardGraphite
        }
    }

    /// How much black is mixed in (sRGB) so white text reaches 4.5:1 on the lightest spot of the card,
    /// in light and dark mode (checked against the system colors of both).
    private var darkening: Double {
        switch self {
        case .indigo: 0.04
        case .blue, .pink: 0.14
        case .purple, .red: 0.16
        case .graphite: 0.18
        case .orange: 0.30
        case .green: 0.36
        case .teal: 0.38
        }
    }

    /// Orange leans toward red before darkening, so it stays warm instead of turning brown.
    private var hue: Color {
        self == .orange ? base.mix(with: .cardRed, by: 0.3, in: .device) : base
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [tint, hue.mix(with: .black, by: darkening + 0.18, in: .device)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Flat tint for small elements (icons, the color picker).
    var tint: Color { hue.mix(with: .black, by: darkening, in: .device) }
}

extension Int {
    /// Color for a balance: green when you get money, red when you owe, secondary when even.
    var balanceColor: Color {
        self > 0 ? .positive : self < 0 ? .negative : .inkSecondary
    }
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// Dismisses the keyboard when tapping outside a text field, without blocking other taps.
    func dismissesKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }
}
