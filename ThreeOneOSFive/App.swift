import SwiftUI
import UIKit
import Combine

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var pairingManager = LocalVPNPairingManager.shared
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        log("app: Souzaiosoficial EXTERNAL launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
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
            .environmentObject(pairingManager)
            .environmentObject(patchDraftCoordinator)
            .environmentObject(fileOperationCoordinator)
            .environmentObject(patchStore)
            .environmentObject(repositoryStore)
            .environment(\.appLanguage, language)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            .onAppear {
                licenseManager.beginLaunchSession()
                pairingManager.refreshLiveHeartbeatAndTunnel()
                appState.detectSupport()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                licenseManager.beginLaunchSession()
                pairingManager.refreshLiveHeartbeatAndTunnel()
                appState.detectSupport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .localVPNStateDidChange)) { _ in
                appState.detectSupport()
            }
            .onOpenURL { url in
                let ext = url.pathExtension.lowercased()
                let isPairingFile = ext == "mobiledevicepairing"
                    || (ext == "plist" && url.lastPathComponent.lowercased().contains("pair"))
                if isPairingFile {
                    _ = try? pairingManager.importPairingFile(from: url)
                    appState.detectSupport()
                } else {
                    patchDraftCoordinator.presentImport(url)
                }
            }
            .preferredColorScheme(.dark)
        }
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

        let pairing = LocalVPNPairingManager.shared
        if pairing.isReadyForDeviceOperations || pairing.isDevicePaired {
            exploitStatus = .success(method: pairing.activeMethodDescription)
            log("app: access ready via \(pairing.activeMethodDescription) on iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))")
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

        if LocalVPNPairingManager.shared.isDevicePaired {
            exploitStatus = .success(method: LocalVPNPairingManager.shared.activeMethodDescription)
            return
        }

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
                } else if LocalVPNPairingManager.shared.isDevicePaired {
                    self.exploitStatus = .success(
                        method: LocalVPNPairingManager.shared.activeMethodDescription
                    )
                    log("app: fallback to LocalDevVPN + Pairing (3105) active")
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app or enable LocalDevVPN + Pairing")
                }
            }
        }
    }
}
