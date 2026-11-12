//
//  SouzaiosoficialDashboardSupport.swift
//  Componentes visuais do original.zip preservados junto aos serviços 3105.
//
import AudioToolbox
import SwiftUI
import UIKit

/// Fundo vermelho, branco e preto copiado do DesignSystem do original.zip.
struct AnimatedHyperBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.07),
                    Color(red: 0.04, green: 0.04, blue: 0.045),
                    Color(red: 0.02, green: 0.02, blue: 0.025)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

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

            RadialGradient(
                colors: [Color.white.opacity(0.04), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}

/// Ícone vetorial de pistola do DesignSystem do original.zip.
struct PistolIcon: View {
    var size: CGFloat = 18
    var color: Color = AppTheme.accent

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            func x(_ value: CGFloat) -> CGFloat { value / 24 * w }
            func y(_ value: CGFloat) -> CGFloat { value / 24 * h }

            var path = Path()
            path.move(to: CGPoint(x: x(2), y: y(8)))
            path.addLine(to: CGPoint(x: x(18), y: y(8)))
            path.addLine(to: CGPoint(x: x(18), y: y(7)))
            path.addLine(to: CGPoint(x: x(22), y: y(7)))
            path.addLine(to: CGPoint(x: x(22), y: y(11)))
            path.addLine(to: CGPoint(x: x(18), y: y(11)))
            path.addLine(to: CGPoint(x: x(18), y: y(12)))
            path.addLine(to: CGPoint(x: x(12), y: y(12)))
            path.addLine(to: CGPoint(x: x(11), y: y(13)))
            path.addLine(to: CGPoint(x: x(10), y: y(20)))
            path.addLine(to: CGPoint(x: x(6), y: y(20)))
            path.addLine(to: CGPoint(x: x(7), y: y(13)))
            path.addLine(to: CGPoint(x: x(6), y: y(12)))
            path.addLine(to: CGPoint(x: x(2), y: y(12)))
            path.closeSubpath()
            context.fill(path, with: .color(color))

            var sight = Path()
            sight.addRoundedRect(
                in: CGRect(x: x(20.2), y: y(5.5), width: x(1.4), height: y(1.8)),
                cornerSize: CGSize(width: x(0.3), height: y(0.3))
            )
            context.fill(sight, with: .color(color))

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

/// Mantém o feedback tátil e sonoro associado às ações de patch.
enum PatchAudioFeedback {
    static func bypassActivated() {
        play(soundID: 1306, kind: .success)
    }

    static func originalRestored() {
        play(soundID: 1307, kind: .warning)
    }

    private static func play(soundID: SystemSoundID, kind: UINotificationFeedbackGenerator.FeedbackType) {
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(kind)
            AudioServicesPlaySystemSound(soundID)
        }
    }
}

/// Controla se o aviso de licença já foi exibido nesta execução do aplicativo.
@MainActor
final class SouzaiosoficialNoticeState {
    static let shared = SouzaiosoficialNoticeState()
    var hasShownLicenseNotice = false
    private init() {}
}
