import SwiftUI

enum AppTheme {
    // Dark red, white and black palette shared by every primary screen.
    static let accent = Color(red: 0.42, green: 0.008, blue: 0.016)
    static let secondaryAccent = Color.white
    static let pageBackground = Color(red: 0.05, green: 0.05, blue: 0.055)
    static let consoleBackground = Color(red: 0.025, green: 0.004, blue: 0.006)
    static let referenceCard = Color(red: 0.10, green: 0.006, blue: 0.010).opacity(0.78)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Missing UI components (stubs for CI build)

struct AnimatedHyperBackdrop: View {
    var body: some View {
        ZStack {
            // Charcoal / near-black base (no purple)
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.07),
                    Color(red: 0.04, green: 0.04, blue: 0.045),
                    Color(red: 0.02, green: 0.02, blue: 0.025)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle red accent glow (top-right)
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(0.18),
                    AppTheme.accent.opacity(0.05),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 320
            )

            // Soft cool gray wash (bottom-left)
            RadialGradient(
                colors: [
                    Color.white.opacity(0.04),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}

struct PatchUnlockPrompt: View {
    @ObservedObject var store: PatchProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Unlock Patch")
                    .font(.title2.bold())
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                if let key = store.unlockErrorKey {
                    Text(key)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Button("Unlock") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.cancelUnlock()
                        dismiss()
                    }
                }
            }
        }
    }
}


/// Ícone vetorial de pistola (SF Symbols nao oferece arma de fogo).
struct PistolIcon: View {
    var size: CGFloat = 18
    var color: Color = AppTheme.accent

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Escala relativa a um grid 24x24
            func x(_ v: CGFloat) -> CGFloat { v / 24 * w }
            func y(_ v: CGFloat) -> CGFloat { v / 24 * h }

            var path = Path()

            // Cano + slide (parte superior alongada)
            path.move(to: CGPoint(x: x(2), y: y(8)))
            path.addLine(to: CGPoint(x: x(18), y: y(8)))
            path.addLine(to: CGPoint(x: x(18), y: y(7)))
            path.addLine(to: CGPoint(x: x(22), y: y(7)))
            path.addLine(to: CGPoint(x: x(22), y: y(11)))
            path.addLine(to: CGPoint(x: x(18), y: y(11)))
            path.addLine(to: CGPoint(x: x(18), y: y(12)))
            path.addLine(to: CGPoint(x: x(12), y: y(12)))
            // Transicao para o cabo
            path.addLine(to: CGPoint(x: x(11), y: y(13)))
            path.addLine(to: CGPoint(x: x(10), y: y(20)))
            path.addLine(to: CGPoint(x: x(6), y: y(20)))
            path.addLine(to: CGPoint(x: x(7), y: y(13)))
            path.addLine(to: CGPoint(x: x(6), y: y(12)))
            path.addLine(to: CGPoint(x: x(2), y: y(12)))
            path.closeSubpath()

            context.fill(path, with: .color(color))

            // Mira frontal (pequeno retangulo no cano)
            var sight = Path()
            sight.addRoundedRect(
                in: CGRect(x: x(20.2), y: y(5.5), width: x(1.4), height: y(1.8)),
                cornerSize: CGSize(width: x(0.3), height: y(0.3))
            )
            context.fill(sight, with: .color(color))

            // Gatilho (arco)
            var trigger = Path()
            trigger.addArc(
                center: CGPoint(x: x(9.5), y: y(13.5)),
                radius: x(2.2),
                startAngle: .degrees(-10),
                endAngle: .degrees(110),
                clockwise: false
            )
            context.stroke(
                trigger,
                with: .color(color),
                style: StrokeStyle(lineWidth: max(1.2, w * 0.06), lineCap: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

