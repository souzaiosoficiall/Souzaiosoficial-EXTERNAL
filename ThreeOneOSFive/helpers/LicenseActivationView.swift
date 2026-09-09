import SwiftUI

struct LicenseActivationView: View {
    @ObservedObject var manager: LicenseManager
    @State private var key = ""
    @FocusState private var keyFocused: Bool

    var body: some View {
        ZStack {
            AnimatedHyperBackdrop()
                .ignoresSafeArea()

            Color.black.opacity(0.25)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 44)

                        Image(systemName: manager.isApproving ? "checkmark.shield.fill" : "lock.shield.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(manager.isApproving ? .green : AppTheme.accent)
                            .padding(.bottom, 12)

                        Text(manager.isApproving ? "ACESSO APROVADO" : "ACESSO RESTRITO")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.white)

                        Text(manager.isApproving ? "Sua chave foi validada com sucesso" : "Entre com sua chave para continuar")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(.top, 7)

                        if manager.isApproving {
                            approvalCard
                                .padding(.horizontal, 22)
                                .padding(.top, 28)
                        } else {
                            loginCard(proxy: proxy)
                                .padding(.horizontal, 22)
                                .padding(.top, 28)
                        }

                        Text("Souzaiosoficial EXTERNAL")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 28)

                        Spacer(minLength: 42)
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
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(7 - manager.approvalCountdown) / 7.0)
                    .stroke(.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.8), value: manager.approvalCountdown)
                VStack(spacing: 2) {
                    Text("\(manager.approvalCountdown)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("seg")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 112, height: 112)

            VStack(spacing: 8) {
                Label("Chave validada com sucesso", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.green)
                Text("Preparando seu acesso com segurança…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                Text("Válida até: \(manager.formattedExpiration)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial.opacity(0.74), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.green.opacity(0.45), lineWidth: 1))
        .shadow(color: .green.opacity(0.18), radius: 22, y: 8)
        .transition(.opacity.combined(with: .scale))
    }

    private func loginCard(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 16, weight: .bold))
                Text("Chave de acesso")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }

            Text("Insira a chave fornecida pelo suporte oficial para liberar o aplicativo.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Digite sua KEY", text: $key)
                .focused($keyFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { activate() }
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(AppTheme.accent.opacity(0.48), lineWidth: 1))
                .id("activation-card")

            Toggle("Lembrar chave neste dispositivo", isOn: $manager.rememberKey)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .tint(AppTheme.accent)

            Button(action: activate) {
                HStack(spacing: 9) {
                    Image(systemName: manager.isBusy ? "hourglass" : "checkmark.shield.fill")
                    Text(manager.isBusy ? "VERIFICANDO…" : "VALIDAR E CONTINUAR")
                }
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: AppTheme.accent.opacity(0.30), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
            .opacity(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.48 : 1)

            if let message = manager.message {
                Text(message)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let contactOwner = manager.contactOwner,
               let contactURL = ownerURL(from: contactOwner) {
                Button("Falar com o suporte") {
                    UIApplication.shared.open(contactURL)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryAccent)
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
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
