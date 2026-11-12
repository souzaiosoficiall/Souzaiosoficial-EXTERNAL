import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pairingManager: LocalVPNPairingManager
    @ObservedObject private var dialerStore = DialerThemeStore.shared
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage(FeatureVisibility.cleanerStorageKey) private var cleanerEnabled = true
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @AppStorage(LocalVPNPairingManager.universalIOS27SupportKey)
    private var universalIOS27SupportEnabled = true
    @AppStorage("repository.ios_unlock") private var repoIOSUnlock = true
    @AppStorage("appearance.accent") private var accentChoiceRaw = AppAccentChoice.sunset.rawValue
    @AppStorage("appearance.theme") private var themeModeRaw = AppThemeMode.system.rawValue
    @AppStorage("appearance.haptics_enabled") private var hapticsEnabled = true

    @State private var statusBanner: String?
    @State private var showClearRecoveryConfirm = false

    private var currentRoute: AccessRouteKind {
        let v = AppInfo.versionTuple
        return ExploitSupportPolicy.activeAccessRoute(major: v.major, minor: v.minor, patch: v.patch)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("3105").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // v2.2 System Access & AirLift / worse_query Section
                Section {
                    LabeledContent(
                        language.text("public_settings.access_route"),
                        value: currentRoute.rawValue
                    )
                    LabeledContent(
                        language.text("public_settings.app_group"),
                        value: WorseQueryService.hasAppGroupEntitlement
                            ? language.text("public_settings.app_group_ready")
                            : language.text("public_settings.app_group_missing")
                    )
                    HStack {
                        Label("LocalDevVPN", systemImage: "checkmark.shield.fill")
                        Spacer()
                        Text(
                            pairingManager.isTunnelConnected
                                ? language.text("localvpn.connected")
                                : language.text("localvpn.disconnected")
                        )
                        .foregroundStyle(pairingManager.isTunnelConnected ? Color.green : Color.secondary)
                    }
                    LabeledContent(
                        language.text("airlift.pin"),
                        value: pairingManager.generatedPairingPIN
                    )
                    Toggle(isOn: $pairingManager.useAirLiftForEverything) {
                        Label(
                            language.text("public_settings.use_airlift_all"),
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    }
                    Toggle(isOn: $pairingManager.airLiftWalletAndPasscodeEnabled) {
                        Label(
                            language.text("public_settings.airlift_features"),
                            systemImage: "creditcard.and.123"
                        )
                    }
                    Button {
                        let ver = dialerStore.captureKeypadBaseline()
                        statusBanner = "\(language.text("dialer.capture_done")) (\(ver))"
                    } label: {
                        Label(
                            language.text("public_settings.capture_dialer_passcode"),
                            systemImage: "circle.grid.3x3.fill"
                        )
                    }
                    Button {
                        statusBanner = WorseQueryService.runProbe()
                    } label: {
                        Label(
                            language.text("public_settings.worse_query_probe"),
                            systemImage: "waveform.path.ecg"
                        )
                    }
                    if let statusBanner {
                        Text(statusBanner)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text(language.text("public_settings.access_section"))
                } footer: {
                    Text(language.text("public_settings.route_worse_query_footer"))
                }

                // v2.2 Options & Unlock iOS Repo
                Section {
                    Toggle(isOn: $repoIOSUnlock) {
                        Label(
                            language.text("public_settings.repo_ios_unlock"),
                            systemImage: "lock.open.fill"
                        )
                    }
                    Toggle(isOn: $cleanerEnabled) {
                        Label(language.text("tab.cleaner"), systemImage: "sparkles")
                    }
                    Toggle(isOn: $developerModeEnabled) {
                        Label(
                            language.text("settings.developer_mode"),
                            systemImage: "hammer.fill"
                        )
                    }
                    NavigationLink {
                        SystemFeaturesView()
                    } label: {
                        Label(
                            language.text("system_feature.source_name"),
                            systemImage: "lock.iphone"
                        )
                    }
                    Button(role: .destructive) {
                        showClearRecoveryConfirm = true
                    } label: {
                        Label(
                            language.text("public_settings.clear_patch_recovery"),
                            systemImage: "trash.slash"
                        )
                    }
                } header: {
                    Text(language.text("public_settings.options_section"))
                } footer: {
                    Text(
                        repoIOSUnlock
                            ? language.text("public_settings.repo_ios_unlock_footer_on")
                            : language.text("public_settings.repo_ios_unlock_footer")
                    )
                }

                // v2.2 Appearance & Customization
                Section {
                    Picker(language.text("settings.appearance.theme"), selection: $themeModeRaw) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(language.text(mode.localizationKey)).tag(mode.rawValue)
                        }
                    }
                    Picker(language.text("settings.appearance.accent"), selection: $accentChoiceRaw) {
                        ForEach(AppAccentChoice.allCases) { choice in
                            Text(language.text(choice.localizationKey)).tag(choice.rawValue)
                        }
                    }
                    Toggle(language.text("settings.appearance.haptics"), isOn: $hapticsEnabled)
                } header: {
                    Text(language.text("settings.appearance.section"))
                } footer: {
                    Text(language.text("settings.appearance.footer"))
                }

                if WallpaperFeatureSupportPolicy.isSupported(
                    major: AppInfo.versionTuple.major
                ) {
                    Section {
                        NavigationLink {
                            WallpaperResetSettingsView()
                        } label: {
                            Label(
                                language.text("wallpaper.reset"),
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                    } header: {
                        Text(language.text("tab.wallpapers"))
                    } footer: {
                        Text(language.text("wallpaper.reset_settings_footer"))
                    }
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                }

                Section {
                    HStack {
                        Text(language.text("settings.current_version"))
                        Spacer()
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                        .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                    }
                    LabeledContent("iOS 17", value: ExploitSupportPolicy.verifiedIOS17Range)
                    LabeledContent("iOS 18", value: ExploitSupportPolicy.verifiedIOS18Range)
                    LabeledContent("iOS 26", value: ExploitSupportPolicy.verifiedIOS26Range)
                    LabeledContent("iOS 27+", value: ExploitSupportPolicy.verifiedIOS27Range)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iOS 27.0 – 27.2+")
                            .font(.body)
                        Text(language.text("pairing.ios27_official_supported"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        ForEach(ExploitSupportPolicy.verifiedIOS27Builds, id: \.build) { version in
                            Text(versionLabel(version))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text(language.text("settings.verified_versions"))
                } footer: {
                    Text(language.text("settings.supported_versions_footer"))
                }

                Section(language.text("settings.social_media")) {
                    creditsRow(
                        name: "GitHub",
                        role: language.text("social.github_role"),
                        url: "https://github.com/YangJiiii/3105"
                    )
                    creditsRow(
                        name: "Cộng Đồng IOSVN",
                        role: language.text("social.iosvn_role"),
                        url: "https://t.me/ioscrackvn"
                    )
                }

                Section(language.text("settings.credits")) {
                    creditsRow(
                        name: "YangJiii",
                        role: language.text("credit.yangjiii"),
                        url: "https://x.com/duongduong0908"
                    )
                    creditsRow(
                        name: "0xjohnnydev",
                        role: language.text("credit.filzaslop"),
                        url: "https://github.com/0xjohnnydev/FilzaSlop"
                    )
                    creditsRow(
                        name: "LeminLimez",
                        role: language.text("credit.pocket_poster"),
                        url: "https://github.com/leminlimez/Pocket-Poster"
                    )
                    creditsRow(
                        name: "CrazyMind90",
                        role: language.text("credit.sandbox_escape"),
                        url: "https://github.com/CrazyMind90"
                    )
                    creditsRow(
                        name: "forcequitOS",
                        role: language.text("credit.forcequit"),
                        url: "https://github.com/forcequitOS"
                    )
                }
            }
            .environment(\.layoutDirection, language.layoutDirection)
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                language.text("public_settings.clear_patch_confirm_title"),
                isPresented: $showClearRecoveryConfirm,
                titleVisibility: .visible
            ) {
                Button(language.text("public_settings.clear_patch_action"), role: .destructive) {
                    if let backupRoot = try? PatchProjectLibrary.backupRootURL() {
                        try? FileManager.default.removeItem(at: backupRoot)
                        _ = try? PatchProjectLibrary.backupRootURL()
                    }
                    statusBanner = language.text("public_settings.clear_patch_done_title")
                }
                Button(language.text("common.cancel"), role: .cancel) {}
            } message: {
                Text(language.text("public_settings.clear_patch_confirm_message"))
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "2.2"
    }

    private func versionLabel(
        _ version: (beta: Int, publicBeta: Int?, build: String)
    ) -> String {
        if let publicBeta = version.publicBeta {
            return language.text(
                "settings.developer_public_beta_build",
                Int64(version.beta),
                Int64(publicBeta),
                version.build
            )
        }
        return language.text(
            "settings.developer_beta_build",
            Int64(version.beta),
            version.build
        )
    }

    @ViewBuilder
    private func creditsRow(name: String, role: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("accessibility.open_profile", name))
        }
    }
}
