import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator();
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        log("app: Souzaiosoficial EXTERNAL launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if licenseManager.isActive {
                    ContentView()
                        .environmentObject(licenseManager)
                } else {
                    LicenseActivationView(manager: licenseManager)
                }
            }
                .environmentObject(appState)
                .environmentObject(patchDraftCoordinator)
                .environmentObject(fileOperationCoordinator)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
            .fullScreenCover(item: $updateOffer) { offer in
                UpdateRequiredView(offer: offer)
            }
            .onAppear {
                licenseManager.beginLaunchSession()
                appState.detectSupport()
                checkForUpdate()
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { return }
                    checkForUpdate()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                licenseManager.beginLaunchSession()
                appState.detectSupport()
                checkForUpdate()
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct UpdateRequiredView: View {
    let offer: AppUpdateChecker.Offer

    var body: some View {
        ZStack {
            AnimatedHyperBackdrop()
                .ignoresSafeArea()
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 72, height: 72)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())

                VStack(spacing: 10) {
                    Text("ATUALIZAÇÃO DISPONÍVEL")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Olá! É de extrema importância que você instale esta nova versão disponível. Você só conseguirá utilizar o EXTERNAL caso atualize.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)

                    Text("Versão \(offer.version) • Build \(offer.build)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.top, 4)
                }

                Button {
                    UIApplication.shared.open(offer.url)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("ATUALIZAR EXTERNAL")
                    }
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 14, y: 7)
                }
                .buttonStyle(.plain)
            }
            .padding(26)
            .frame(maxWidth: 380)
            .background(.ultraThinMaterial.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
            .padding(.horizontal, 22)
        }
        .interactiveDismissDisabled(true)
        .preferredColorScheme(.dark)
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}
