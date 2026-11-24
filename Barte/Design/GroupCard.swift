import SwiftUI

/// The signature element: every group is a colored card, like in Wallet.
/// The top row (name and my balance) stays readable when cards are stacked.
struct GroupCard: View {
    let group: SplitGroup
    let me: UUID?
    /// Off for previews of groups I'm not in yet (joining).
    var showsStatus = true
    /// The chat badge; off inside the group, where the toolbar shows it.
    var showsUnread = true

    var body: some View {
        let balance = group.balance(of: me)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                    if group.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    if showsUnread && group.unreadMessages > 0 {
                        UnreadBadge(count: group.unreadMessages, color: group.color.tint)
                    }
                }
                Spacer(minLength: 8)
                if showsStatus {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(group.expenses.isEmpty ? String(localized: "Noch keine Ausgaben") : Self.statusText(balance: balance, me: me))
                            .font(.caption.weight(.medium))
                            .opacity(0.85)
                        if balance != 0 {
                            Text(Money.format(abs(balance), currency: group.currency))
                                .font(.cardAmount)
                                .contentTransition(.numericText())
                        }
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
        if me == nil { return String(localized: "Wer bist du?", comment: "Card status when I haven't picked my name in a group") }
        return balance > 0 ? String(localized: "Du bekommst", comment: "Card status, followed by an amount")
            : balance < 0 ? String(localized: "Du schuldest", comment: "Card status, followed by an amount")
            : String(localized: "Du bist quitt")
    }

    static func accessibilityLabel(group: SplitGroup, balance: Int, me: UUID?) -> String {
        var parts = [group.name]
        if balance == 0 {
            parts.append(statusText(balance: balance, me: me))
        } else {
            parts.append("\(statusText(balance: balance, me: me)) \(Money.format(abs(balance), currency: group.currency))")
        }
        parts.append(String(localized: "\(group.members.count) Personen", comment: "Number of people in a group"))
        if group.isShared { parts.append(String(localized: "geteilt", comment: "VoiceOver: the group is shared with other app users")) }
        if group.unreadMessages > 0 { parts.append(UnreadBadge.label(group.unreadMessages)) }
        return parts.joined(separator: ", ")
    }
}

/// New chat messages on a card: a white pill with a bubble and the count.
struct UnreadBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bubble.left.fill")
                .font(.caption2.weight(.bold))
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.white, in: .capsule)
        .accessibilityLabel(Self.label(count))
    }

    static func label(_ count: Int) -> String {
        String(localized: "\(count) neue Nachrichten", comment: "Unread chat messages, with plural variants")
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
