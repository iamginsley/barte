import SwiftUI

/// The logo drawn in SwiftUI: a card split diagonally into two offset halves.
/// `split` (0…1) controls how far the halves move apart, used for a small tap animation.
struct BarteLogo: View {
    var size: CGFloat = 96
    var split: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [.cardBlue, .cardIndigo], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, canvasSize in
                let scale = canvasSize.width / 1024
                let offset = CGSize(width: 16 * split * scale, height: 4 * split * scale)
                var left = context
                left.translateBy(x: -offset.width, y: -offset.height)
                left.fill(Self.leftHalf.applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(.white))
                var right = context
                right.translateBy(x: offset.width, y: offset.height)
                right.fill(Self.rightHalf.applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(.white.opacity(0.72)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Barte")
    }

    // Same geometry as the app icon (1024 × 1024 canvas): card 640 × 420, corner radius 56,
    // cut from (560, 302) to (464, 722).
    static let leftHalf = Path { path in
        path.move(to: CGPoint(x: 248, y: 302))
        path.addLine(to: CGPoint(x: 560, y: 302))
        path.addLine(to: CGPoint(x: 464, y: 722))
        path.addLine(to: CGPoint(x: 248, y: 722))
        path.addArc(tangent1End: CGPoint(x: 192, y: 722), tangent2End: CGPoint(x: 192, y: 666), radius: 56)
        path.addLine(to: CGPoint(x: 192, y: 358))
        path.addArc(tangent1End: CGPoint(x: 192, y: 302), tangent2End: CGPoint(x: 248, y: 302), radius: 56)
        path.closeSubpath()
    }

    static let rightHalf = Path { path in
        path.move(to: CGPoint(x: 560, y: 302))
        path.addLine(to: CGPoint(x: 776, y: 302))
        path.addArc(tangent1End: CGPoint(x: 832, y: 302), tangent2End: CGPoint(x: 832, y: 358), radius: 56)
        path.addLine(to: CGPoint(x: 832, y: 666))
        path.addArc(tangent1End: CGPoint(x: 832, y: 722), tangent2End: CGPoint(x: 776, y: 722), radius: 56)
        path.addLine(to: CGPoint(x: 464, y: 722))
        path.closeSubpath()
    }
}

#Preview {
    BarteLogo(size: 200)
}
