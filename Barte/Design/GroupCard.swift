import SwiftUI

/// The signature element: every group is a colored card, like in Wallet.
/// The top row (name and my balance) stays readable when cards are stacked.
struct GroupCard: View {
    let group: SplitGroup
    let me: UUID?

    var body: some View {
        let balance = group.balance(of: me)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                    if group.sharing != .personal {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(group.expenses.isEmpty ? "Noch keine Ausgaben" : Self.statusText(balance: balance, me: me))
                        .font(.caption.weight(.medium))
                        .opacity(0.85)
                    if balance != 0 {
                        Text(Money.format(abs(balance), currency: group.currency))
                            .font(.cardAmount)
                            .contentTransition(.numericText())
                    }
                }
            }
            Spacer(minLength: 16)
            HStack(alignment: .bottom) {
                AvatarStack(names: group.members.map(\.name))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Gesamt")
                        .font(.caption2.weight(.medium))
                        .opacity(0.8)
                    Text(Money.format(group.totalSpent, currency: group.currency))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(Theme.cardAspectRatio, contentMode: .fit)
        .background { CardBackground(color: group.color) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(group: group, balance: balance, me: me))
    }

    static func statusText(balance: Int, me: UUID?) -> String {
        if me == nil { return "Wer bist du?" }
        return balance > 0 ? "Du bekommst" : balance < 0 ? "Du schuldest" : "Du bist quitt"
    }

    static func accessibilityLabel(group: SplitGroup, balance: Int, me: UUID?) -> String {
        var parts = [group.name]
        if balance == 0 {
            parts.append(statusText(balance: balance, me: me))
        } else {
            parts.append("\(statusText(balance: balance, me: me)) \(Money.format(abs(balance), currency: group.currency))")
        }
        parts.append("\(group.members.count) Personen")
        if group.sharing != .personal { parts.append("geteilt") }
        return parts.joined(separator: ", ")
    }
}

/// Gradient card with the diagonal split from the app icon as a soft sheen.
struct CardBackground: View {
    let color: CardColor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
        shape
            .fill(color.gradient)
            .overlay {
                SplitSheen()
                    .fill(.white.opacity(0.08))
                    .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}

/// The right part of the card behind a slanted cut, like the halves of the logo.
struct SplitSheen: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
