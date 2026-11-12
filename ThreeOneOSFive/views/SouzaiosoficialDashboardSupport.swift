//
//  SouzaiosoficialDashboardSupport.swift
//  Componentes visuais e de feedback usados pelo painel Souzaiosoficial EXTERNAL.
//  Estas declarações não existiam no repositório original, por isso o arquivo
//  antigo de tela nunca chegou a compilar dentro do target.
//
import AudioToolbox
import SwiftUI
import UIKit

/// Fundo escuro animado com brilhos na cor de destaque do app.
struct AnimatedHyperBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let glowRadius: CGFloat = 300

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [Color(white: 0.07), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            if reduceMotion {
                staticGlow
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    animatedGlow(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var glowGradient: RadialGradient {
        RadialGradient(
            colors: [AppTheme.accent.opacity(0.26), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: glowRadius
        )
    }

    private var staticGlow: some View {
        ZStack {
            glowGradient
                .frame(width: glowRadius * 2, height: glowRadius * 2)
                .offset(x: -40, y: -160)
            glowGradient
                .frame(width: glowRadius * 1.6, height: glowRadius * 1.6)
                .offset(x: 120, y: 220)
        }
    }

    private func animatedGlow(at time: TimeInterval) -> some View {
        let x1 = sin(time * 0.18) * 110
        let y1 = cos(time * 0.13) * 80
        let x2 = cos(time * 0.21) * -130
        let y2 = sin(time * 0.16) * 110
        return ZStack {
            glowGradient
                .frame(width: glowRadius * 2, height: glowRadius * 2)
                .offset(x: CGFloat(x1), y: CGFloat(y1 - 160))
            glowGradient
                .frame(width: glowRadius * 1.6, height: glowRadius * 1.6)
                .offset(x: CGFloat(x2 + 120), y: CGFloat(y2 + 220))
        }
    }
}

/// Glifo simples de pistola usado na linha "Em desenvolvimento".
struct PistolIcon: View {
    var size: CGFloat = 20
    var color: Color = AppTheme.accent

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Corpo e cano
            Path { path in
                path.move(to: point(0.04, 0.26))
                path.addLine(to: point(0.96, 0.26))
                path.addLine(to: point(0.96, 0.44))
                path.addLine(to: point(0.46, 0.44))
                path.addLine(to: point(0.46, 0.56))
                path.addLine(to: point(0.34, 0.56))
                path.addLine(to: point(0.34, 0.44))
                path.addLine(to: point(0.04, 0.44))
                path.closeSubpath()
            }
            .fill(color)

            // Empunhadura
            Path { path in
                path.move(to: point(0.30, 0.48))
                path.addLine(to: point(0.46, 0.48))
                path.addLine(to: point(0.38, 0.96))
                path.addLine(to: point(0.20, 0.96))
                path.closeSubpath()
            }
            .fill(color.opacity(0.85))

            // Guarda-mato / gatilho
            Path { path in
                path.move(to: point(0.46, 0.48))
                path.addLine(to: point(0.58, 0.48))
                path.addLine(to: point(0.54, 0.62))
                path.addLine(to: point(0.46, 0.56))
                path.closeSubpath()
            }
            .fill(color.opacity(0.60))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Converte uma coordenada relativa (0...1) para o tamanho do ícone.
    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * size, y: y * size)
    }
}

/// Feedback tátil e sonoro das ações de ativar e restaurar patch.
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
