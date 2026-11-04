import SwiftUI

/// A round initial badge for a person.
struct MemberAvatar: View {
    let name: String
    var isMe = false
    var size: CGFloat = 32
    /// Draw on a colored card (white ring) instead of a list background.
    var onCard = false

    private var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }

    var body: some View {
        Text(initial.isEmpty ? "?" : initial)
            .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
            .foregroundStyle(onCard ? Color.black.opacity(0.75) : (isMe ? Color.white : Color.accentColor))
            .frame(width: size, height: size)
            .background {
                Circle().fill(onCard ? AnyShapeStyle(.white.opacity(0.92)) : isMe ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.14)))
            }
            .accessibilityHidden(true)
    }
}

/// Overlapping avatars, like the people on a shared card.
struct AvatarStack: View {
    let names: [String]
    var limit = 4
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { _, name in
                MemberAvatar(name: name, size: size, onCard: true)
                    .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1))
            }
            if names.count > limit {
                Text("+\(names.count - limit)")
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.white.opacity(0.25)))
            }
        }
        .accessibilityHidden(true)
    }
}
