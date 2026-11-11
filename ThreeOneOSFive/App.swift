import SwiftUI
import UIKit
import Combine

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var pairingManager = LocalVPNPairingManager.shared
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            ZStack {
                Group {
                    if licenseManager.isActive {
                        ContentView()
                            .environmentObject(appState)
                            .environmentObject(pairingManager)
                            .environmentObject(patchDraftCoordinator)
                            .environmentObject(fileOperationCoordinator)
                            .environmentObject(patchStore)
                            .environmentObject(repositoryStore)
                            .environmentObject(licenseManager)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                            .environment(\.layoutDirection, language.layoutDirection)
                    } else {
                        LicenseActivationView(manager: licenseManager)
                            .environmentObject(appState)
                    }
                }
                .opacity(showOnboarding ? 0 : 1)
                .allowsHitTesting(!showOnboarding)

                if showOnboarding {
                    OnboardingView {
                        OnboardingStore.markCompleted()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            showOnboarding = false
                        }
                        appState.detectSupport()
                        checkForUpdate()
                    }
                    .environmentObject(pairingManager)
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.layoutDirection)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98))
                    )
                    .zIndex(1)
                }
            }
            .environment(\.layoutDirection, language.layoutDirection)
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.layoutDirection)
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onAppear {
                licenseManager.beginLaunchSession()
                if !showOnboarding {
                    appState.detectSupport()
                    checkForUpdate()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showOnboarding else { return }
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
