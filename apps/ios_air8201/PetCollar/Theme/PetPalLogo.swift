import SwiftUI

struct PetPalLogo: View {
    var size: CGFloat = 96
    var showShadow: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .fill(PetPalTheme.brandGradient)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.35), lineWidth: size * 0.025)
                        .blur(radius: 1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.35), .clear],
                        center: .init(x: 0.3, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.45
                    )
                )

            PawShape()
                .fill(.white)
                .frame(width: size * 0.58, height: size * 0.58)
                .offset(y: size * 0.02)

            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(PetPalTheme.primaryDeep)
                .offset(x: size * 0.22, y: size * 0.24)
                .shadow(color: .white.opacity(0.8), radius: 1, x: 0, y: 0)
        }
        .frame(width: size, height: size)
        .shadow(color: showShadow ? PetPalTheme.primary.opacity(0.4) : .clear,
                radius: 18, x: 0, y: 10)
    }
}

private struct PawShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Main pad (lower center, slightly flattened oval)
        let padRect = CGRect(
            x: w * 0.20, y: h * 0.45,
            width: w * 0.60, height: h * 0.45
        )
        path.addEllipse(in: padRect)

        // Four toe beans (top row + sides), sized and tilted naturally
        let toes: [(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat)] = [
            (0.20, 0.30, 0.11, 0.16),
            (0.42, 0.14, 0.11, 0.17),
            (0.62, 0.14, 0.11, 0.17),
            (0.82, 0.30, 0.11, 0.16),
        ]
        for t in toes {
            let r = CGRect(
                x: w * (t.cx - t.rx),
                y: h * (t.cy - t.ry),
                width: w * (t.rx * 2),
                height: h * (t.ry * 2)
            )
            path.addEllipse(in: r)
        }
        return path
    }
}

struct PetPalWordmark: View {
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text("PetPel")
                .font(.system(size: compact ? 28 : 36, weight: .heavy, design: .rounded))
                .foregroundStyle(PetPalTheme.brandGradient)
            Text("宠宝")
                .font(.system(size: compact ? 18 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkPrimary.opacity(0.7))
                .tracking(8)
        }
    }
}

#Preview("Logo") {
    VStack(spacing: 24) {
        PetPalLogo(size: 140)
        PetPalWordmark()
    }
    .padding(40)
    .background(PetPalTheme.backgroundGradient)
}
