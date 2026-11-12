import SwiftUI
import UIKit

struct LicenseActivationView: View {
    @ObservedObject var manager: LicenseManager
    @State private var key = ""
    @FocusState private var keyFocused: Bool
    @State private var loadingProgress = 0.0
    @State private var pasteFeedback: String?

    var body: some View {
        ZStack {
            AnimatedHyperBackdrop()
                .ignoresSafeArea()

            Color.black.opacity(0.15)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 36)

                        if manager.isApproving {
                            // Header durante aprovação
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.bottom, 12)

                            Text("ACESSO APROVADO")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .tracking(1.0)
                                .foregroundStyle(.white)

                            Text("Sua chave foi validada com sucesso")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.top, 6)

                            approvalCard
                                .padding(.horizontal, 22)
                                .padding(.top, 28)
                        } else {
                            // Login header — layout mais limpo e profissional
                            VStack(spacing: 18) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [AppTheme.accent.opacity(0.28), .clear],
                                                center: .center,
                                                startRadius: 8,
                                                endRadius: 70
                                            )
                                        )
                                        .frame(width: 120, height: 120)

                                    Circle()
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        .frame(width: 78, height: 78)

                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }

                                VStack(spacing: 8) {
                                    Text("Souzaiosoficial")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .tracking(2.5)
                                        .foregroundStyle(.white.opacity(0.45))

                                    Text("EXTERNAL")
                                        .font(.system(size: 30, weight: .black, design: .rounded))
                                        .tracking(1.5)
                                        .foregroundStyle(.white)

                                    Text("Acesse com sua chave oficial para continuar")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.48))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 28)
                                }
                            }

                            loginCard(proxy: proxy)
                                .padding(.horizontal, 22)
                                .padding(.top, 32)
                        }

                        Spacer(minLength: 48)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: keyFocused) { focused in
                    guard focused else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("activation-card", anchor: .center)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var approvalCard: some View {
        VStack(spacing: 28) {
            // Circular progress ring with countdown
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.accent.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 90
                        )
                    )
                    .frame(width: 160, height: 160)

                // Track
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 112, height: 112)

                // Progress arc
                Circle()
                    .trim(from: 0, to: loadingProgress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                AppTheme.accent.opacity(0.35),
                                AppTheme.accent,
                                Color.white.opacity(0.9),
                                AppTheme.accent
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 112, height: 112)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.72), value: loadingProgress)

                VStack(spacing: 2) {
                    Text("\(manager.approvalCountdown)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("SEG")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.40))
                }
            }

            VStack(spacing: 10) {
                Text("PREPARANDO APLICATIVO")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white)

                Text(loadingMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .id(loadingMessage)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.35), value: loadingMessage)
            }

            // Slim progress bar
            loadingRail
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent.opacity(0.85))
                Text("Não feche o app durante a preparação")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color.white.opacity(0.04),
                in: Capsule(style: .continuous)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    AppTheme.accent.opacity(0.25),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        )
        .onAppear {
            loadingProgress = 0
        }
        .onChange(of: manager.approvalCountdown) { value in
            withAnimation(.easeInOut(duration: 0.72)) {
                loadingProgress = min(1, max(0, Double(8 - value) / 8.0))
            }
        }
    }

    private var loadingRail: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width)
            let lightWidth: CGFloat = min(74, width * 0.22)
            let travel = max(0, width - lightWidth)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .frame(height: 3)

                Capsule(style: .continuous)
                    .fill(AppTheme.accent.opacity(0.32))
                    .frame(width: max(3, width * loadingProgress), height: 3)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppTheme.accent.opacity(0.85),
                                Color.white.opacity(0.92),
                                AppTheme.accent.opacity(0.85),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: lightWidth, height: 7)
                    .blur(radius: 1.2)
                    .offset(x: travel * loadingProgress)
                    .shadow(color: AppTheme.accent.opacity(0.42), radius: 8)
            }
        }
        .frame(height: 10)
        .padding(.horizontal, 2)
    }

    private var loadingMessage: String {
        switch manager.approvalCountdown {
        case 8: return "Preparando o app…"
        case 7: return "Confirmando seus dados…"
        case 6: return "Sincronizando sua licença…"
        case 5: return "Carregando recursos…"
        case 4: return "Verificando integridade…"
        case 3: return "Preparando os patches…"
        case 2: return "Finalizando configuração…"
        case 1: return "Quase tudo pronto…"
        default: return "Acesso liberado"
        }
    }


    private func loginCard(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CHAVE DE ACESSO")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.42))

                    Spacer()

                    Button(action: pasteKeyFromClipboard) {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .bold))
                            Text("Colar KEY")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            AppTheme.accent.opacity(0.12),
                            in: Capsule(style: .continuous)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    TextField("Cole ou digite sua KEY", text: $key)
                        .focused($keyFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { activate() }
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            keyFocused
                                ? AppTheme.accent.opacity(0.75)
                                : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
                .id("activation-card")

                if let pasteFeedback {
                    Text(pasteFeedback)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                        .transition(.opacity)
                }
            }

            Toggle(isOn: $manager.rememberKey) {
                Text("Lembrar neste dispositivo")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
            }
            .tint(AppTheme.accent)

            Button(action: activate) {
                HStack(spacing: 10) {
                    if manager.isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text(manager.isBusy ? "VALIDANDO…" : "ENTRAR")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    LinearGradient(
                        colors: [
                            AppTheme.accent,
                            AppTheme.accent.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: AppTheme.accent.opacity(0.40), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
            .opacity(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

            if let message = manager.message {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(message)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Color.red.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Color.red.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }

            if let contactOwner = manager.contactOwner,
               let contactURL = ownerURL(from: contactOwner) {
                Button {
                    UIApplication.shared.open(contactURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Falar com o suporte")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.085).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    AppTheme.accent.opacity(0.20),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
        )
    }

    private func pasteKeyFromClipboard() {
        // No iOS 16+, o sistema pode pedir permissão de colar ao acessar o pasteboard.
        let raw = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !raw.isEmpty else {
            withAnimation(.easeOut(duration: 0.2)) {
                pasteFeedback = "Nada copiado no momento"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.2)) {
                    pasteFeedback = nil
                }
            }
            return
        }

        key = raw
        keyFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            pasteFeedback = "KEY colada com sucesso"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                pasteFeedback = nil
            }
        }
    }

    private func activate() {
        keyFocused = false
        manager.activate(key: key)
    }

    private func ownerURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("@") {
            return URL(string: "https://t.me/" + String(trimmed.dropFirst()))
        }
        return URL(string: "https://t.me/" + trimmed)
    }
}
