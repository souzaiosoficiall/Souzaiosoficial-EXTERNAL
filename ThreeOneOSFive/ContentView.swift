import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showCleaner = false
    @StateObject private var patchStore = PatchProjectStore()
    @State private var patchOperationBusy = false
    @State private var patchMessage = "PRONTO — SELECIONE UM PATCH"
    @State private var pescocoEnabled = false
    @State private var peitoEnabled = false
    @State private var selectedTab = 0

    // ============================================================
    //  BANNER - Coloque aqui o link do Imgur (ou qualquer imagem)
    //  Exemplo: "https://i.imgur.com/XXXXXXX.png"
    //  Deixe vazio "" para não mostrar o banner
    // ============================================================
    private let bannerURL = "https://i.imgur.com/Dy838X7.jpeg"

    var body: some View {
        ZStack {
            AnimatedHyperBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Conteúdo das abas
                Group {
                    if selectedTab == 0 {
                        homeTab
                    } else {
                        profileTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Barra de navegação inferior
                bottomTabBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showCleaner) {
            CleanerView()
        }
        .sheet(item: $patchStore.passwordRequest, onDismiss: patchStore.cancelUnlock) { _ in
            PatchUnlockPrompt(store: patchStore)
        }
        .onAppear { syncPatchStates() }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, !patchOperationBusy else { return }
            syncPatchStates()
            patchMessage = "PRONTO — SELECIONE UM PATCH"
        }
    }

    // MARK: - Home Tab (tela principal)
    private var homeTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                bannerView
                brandHeader
                patchOptions
                gameLaunchPanel
                footerStatus
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Profile Tab (status + comunidade)
    private var profileTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                bannerView
                brandHeader
                devicePanel
                developerCredits
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Banner (Imgur)
    private var bannerView: some View {
        Group {
            if !bannerURL.isEmpty, let url = URL(string: bannerURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .frame(height: 120)
                            .overlay(ProgressView().tint(AppTheme.accent))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
                            )
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - Bottom Tab Bar
    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "house.fill", title: "Início", index: 0)
            tabButton(icon: "person.fill", title: "Perfil", index: 1)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            Color.black.opacity(0.75)
                .overlay(
                    Rectangle()
                        .fill(AppTheme.accent.opacity(0.25))
                        .frame(height: 1),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(icon: String, title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selectedTab == index ? AppTheme.accent : .white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var brandHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Souzaiosoficial EXTERNAL")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text("CENTRO DE CONTROLE DE PATCH")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(AppTheme.accent)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.38), in: Circle())
                    .overlay(Circle().stroke(AppTheme.accent.opacity(0.42), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir configurações")
        }
    }

    private var devicePanel: some View {
        VStack(spacing: 0) {
            panelTitle("STATUS DO DISPOSITIVO", icon: "shield.lefthalf.filled")
            statusRow(icon: "apple.logo", title: "iOS", value: AppInfo.osVersion, color: AppTheme.secondaryAccent)
            statusRow(icon: "iphone", title: "Dispositivo", value: AppInfo.displayMachineName, color: AppTheme.secondaryAccent)
            statusRow(icon: "checkmark.seal.fill", title: "Suporte", value: appState.isSupported ? "SUPORTADO" : "NÃO SUPORTADO", color: appState.isSupported ? .green : .red)
        }
        .padding(16)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.accent.opacity(0.38), lineWidth: 1))
    }

    private var patchOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                panelTitle("OPÇÕES DE PATCH", icon: "bolt.fill")
                Spacer()
                Text("SELECIONE PARA ATIVAR")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                patchCard(name: "HS PESCOÇO", target: "FREE FIRE • NORMAL", package: "pescoco.3105", color: AppTheme.accent, state: $pescocoEnabled)
                patchCard(name: "HS PEITO", target: "FREE FIRE • NORMAL", package: "peito.3105", color: AppTheme.secondaryAccent, state: $peitoEnabled)
            }

            HStack(spacing: 8) {
                Circle().fill(patchMessage.localizedCaseInsensitiveContains("Bem-sucedida") ? .green : AppTheme.accent).frame(width: 7, height: 7)
                Text(patchOperationBusy ? "PROCESSANDO PATCH…" : patchMessage)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.34), in: Capsule())
        }
    }

    private func patchCard(name: String, target: String, package: String, color: Color, state: Binding<Bool>) -> some View {
        PatchOptionCard(name: name, target: target, color: color, isEnabled: state, isBusy: patchOperationBusy) {
            togglePatch(packageFilename: package, state: state)
        }
    }

    private var gameLaunchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelTitle("INICIAR JOGO", icon: "arrow.up.forward.app.fill")
            HStack(spacing: 12) {
                launchButton(title: "FF NORMAL", subtitle: "Free Fire Normal", color: AppTheme.accent, scheme: "freefireth")
                lockedLaunchButton(title: "FF MAX", subtitle: "Bloqueado • Em breve", color: AppTheme.secondaryAccent)
            }
            Button {
                showCleaner = true
            } label: {
                Label("Limpar Cache e Temp", systemImage: "trash.slash.fill")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.accent.opacity(0.52), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir limpador de cache e arquivos temporários")
        }
    }

    private func launchButton(title: String, subtitle: String, color: Color, scheme: String) -> some View {
        Button { openGame(scheme: scheme) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.38), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func lockedLaunchButton(title: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color.opacity(0.72))
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Text(subtitle)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.72))
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.24), lineWidth: 1))
        .opacity(0.72)
        .accessibilityLabel("FF MAX bloqueado, em breve")
    }

    private var footerStatus: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 9, height: 9).shadow(color: .green, radius: 6)
            Text("SISTEMA ATIVO")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text("Souzaiosoficial EXTERNAL")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(AppTheme.accent.opacity(0.2), lineWidth: 1))
    }

    private var developerCredits: some View {
        VStack(spacing: 14) {
            Text("Desenvolvido por Souzaiosoficial EXTERNAL")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Text("NOSSA COMUNIDADE")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)

            Button {
                guard let destination = URL(string: "https://slat.cc/souzaiosoficial") else { return }
                UIApplication.shared.open(destination)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Toda a minha comunidade")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.secondaryAccent],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: AppTheme.accent.opacity(0.45), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func panelTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(AppTheme.accent)
    }

    private func statusRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(color).frame(width: 24)
            Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text(value).font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(.white)
        }
        .padding(.top, 14)
    }

    private func syncPatchStates() {
        pescocoEnabled = isPatchActive("pescoco.3105")
        peitoEnabled = isPatchActive("peito.3105")
    }

    private func isPatchActive(_ packageFilename: String) -> Bool {
        patchStore.items.first(where: { $0.packageURL.lastPathComponent.caseInsensitiveCompare(packageFilename) == .orderedSame })
            .flatMap { DevicePatchService.latestReceipt(projectID: $0.id) } != nil
    }

    private enum PatchActionResult {
        case applied
        case restored
        case unavailable(String)
    }

    private func setPatchState(for packageFilename: String, enabled: Bool) {
        switch packageFilename {
        case "pescoco.3105": pescocoEnabled = enabled
        case "peito.3105": peitoEnabled = enabled
        default: break
        }
    }

    private func togglePatch(packageFilename: String, state: Binding<Bool>) {
        guard !patchOperationBusy else { return }
        guard let item = patchStore.items.first(where: { $0.packageURL.lastPathComponent.caseInsensitiveCompare(packageFilename) == .orderedSame }) else {
            patchMessage = "ERRO — PACOTE NÃO ENCONTRADO"
            log("patch: package not found: \(packageFilename)")
            return
        }

        let wasEnabled = state.wrappedValue
        patchOperationBusy = true
        patchMessage = "PROCESSANDO — \(packageFilename)"
        let project = item.project
        let projectID = item.id

        DispatchQueue.global(qos: .userInitiated).async {
            let result: PatchActionResult
            do {
                if wasEnabled {
                    guard let receipt = DevicePatchService.latestReceipt(projectID: projectID) else {
                        result = .unavailable("NO ACTIVE RECEIPT — NOTHING TO RESTORE")
                        DispatchQueue.main.async {
                            self.setPatchState(for: packageFilename, enabled: false)
                            self.patchMessage = "DESLIGADO — NENHUM PATCH ATIVO ENCONTRADO"
                            self.patchOperationBusy = false
                        }
                        return
                    }
                    try DevicePatchService.restore(receipt: receipt)
                    result = .restored
                } else {
                    guard let project else {
                        result = .unavailable("PASSWORD REQUIRED — UNLOCK PACKAGE")
                        DispatchQueue.main.async {
                            self.patchStore.requestUnlock(for: item)
                            self.patchMessage = "SENHA NECESSÁRIA — DIGITE A SENHA DO PACOTE"
                            self.patchOperationBusy = false
                        }
                        return
                    }
                    _ = try DevicePatchService.apply(project: project)
                    result = .applied
                }
            } catch {
                result = .unavailable("FALHOU — \(String(describing: error))")
            }

            DispatchQueue.main.async {
                switch result {
                case .applied:
                    self.setPatchState(for: packageFilename, enabled: true)
                    self.patchMessage = "Injeção Bem-sucedida — \(packageFilename)"
                    PatchAudioFeedback.bypassActivated()
                case .restored:
                    self.setPatchState(for: packageFilename, enabled: false)
                    self.patchMessage = "Restauração Bem-sucedida — \(packageFilename)"
                    PatchAudioFeedback.originalRestored()
                case .unavailable(let message):
                    self.patchMessage = message
                }
                self.patchOperationBusy = false
            }
        }
    }

    private func openGame(scheme: String) {
        guard let url = URL(string: "\(scheme)://") else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            log("launch: \(scheme) success=\(success)")
        }
    }
}

private struct PatchOptionCard: View {
    let name: String
    let target: String
    let color: Color
    @Binding var isEnabled: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: "bolt.fill").font(.system(size: 16, weight: .black)).foregroundStyle(color)
                    Spacer()
                    Text(isEnabled ? "ON" : "OFF")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(isEnabled ? .green : .white.opacity(0.58))
                }
                Text(name)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(target)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(color)
                HStack(spacing: 7) {
                    Circle().fill(isEnabled ? Color.green : Color.white.opacity(0.25)).frame(width: 8, height: 8)
                    Text(isEnabled ? "PATCH ACTIVE" : "ACTIVATE PATCH")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
            .padding(14)
            .background(Color.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isEnabled ? color.opacity(0.85) : color.opacity(0.28), lineWidth: isEnabled ? 1.5 : 1))
            .shadow(color: isEnabled ? color.opacity(0.20) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .accessibilityLabel("\(name), \(target), \(isEnabled ? "On" : "Off")")
    }
}

private enum PatchAudioFeedback {
    private static let synthesizer = AVSpeechSynthesizer()
    static func bypassActivated() { speak("Bypass ativado") }
    static func originalRestored() { speak("Bypass desativado") }
    private static func speak(_ message: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: message)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        utterance.voice = voices.first(where: {
            ($0.language.hasPrefix("pt-BR") || $0.language.hasPrefix("pt-PT") || $0.language.hasPrefix("pt")) && $0.gender == .female && $0.quality == .enhanced
        }) ?? voices.first(where: {
            $0.language.hasPrefix("pt-BR") || $0.language.hasPrefix("pt-PT") || $0.language.hasPrefix("pt")
        }) ?? AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = 0.43
        utterance.pitchMultiplier = 1.10
        utterance.volume = 0.90
        synthesizer.speak(utterance)
    }
}

private struct PatchUnlockPrompt: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Package password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in store.clearUnlockError() }
                    if let errorKey = store.unlockErrorKey {
                        Text(AppLanguage.english.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Enter the password once to unlock this Souzaiosoficial EXTERNAL package on this device.")
                }
            }
            .navigationTitle("Unlock package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock", action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

struct AnimatedHyperBackdrop: View {
    @State private var animate = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.pageBackground
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: animate ? 120 : -120, y: -proxy.size.height * 0.23)
                Circle()
                    .fill(AppTheme.secondaryAccent.opacity(0.08))
                    .frame(width: 260, height: 260)
                    .blur(radius: 80)
                    .offset(x: animate ? -100 : 100, y: proxy.size.height * 0.22)
                GridOverlay()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { animate = true }
            }
        }
    }
}

private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 44
            stride(from: CGFloat(0), through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat(0), through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(AppTheme.accent.opacity(0.055)), lineWidth: 1)
        }
    }
}
