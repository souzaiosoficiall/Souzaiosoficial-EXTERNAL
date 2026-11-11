import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager

    @State private var showSettings = false
    @State private var showCleaner = false
    @State private var showLicenseNotice = true
    @StateObject private var patchStore = PatchProjectStore()

    @State private var patchOperationBusy = false
    @State private var patchMessage = "PRONTO — ESCOLHA UMA OPÇÃO"
    @State private var pescocoEnabled = false
    @State private var peitoEnabled = false
    @State private var pescocoAntEnabled = false
    @State private var peitoAntEnabled = false
    @State private var holoEnabled = false
    @State private var selectedTab = 0
    @State private var showSuccessToast = false
    @State private var successToastText = "Ativado com sucesso"

    // Banner atual — mantenha este link se quiser usar o mesmo banner.
    private let bannerURL = "https://i.imgur.com/Dy838X7.jpeg"

    var body: some View {
        ZStack {
            AnimatedHyperBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if selectedTab == 0 {
                        homeTab
                    } else if selectedTab == 1 {
                        visualTab
                    } else {
                        profileTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomTabBar
            }

            if showLicenseNotice {
                licenseNoticeOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(20)
            }

            if showSuccessToast {
                VStack {
                    Spacer()
                    successToast
                        .padding(.horizontal, 22)
                        .padding(.bottom, 92)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(30)
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
        .onAppear {
            syncPatchStates()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, !patchOperationBusy else { return }
            syncPatchStates()
            patchMessage = "PRONTO — ESCOLHA UMA OPÇÃO"
        }
    }

    // MARK: - Principal

    private var homeTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                bannerView

                Text("Escolha sua opção de patch")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 2)

                Text("Ative uma opção para aplicar o arquivo configurado.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))

                patchSection

                if hasActivePatch {
                    restoreOriginalButton
                }

                operationStatus
                usageWarning
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Visual

    private var visualTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                bannerView

                Text("Opções visuais")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 2)

                Text("Ative uma opção visual para aplicar o arquivo configurado.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))

                visualSection

                if hasActiveVisualPatch {
                    restoreOriginalButton
                }

                operationStatus
                usageWarning
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Perfil

    private var profileTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                bannerView

                Text("Minha conta")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 2)

                profileInfoCard
                developerSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    private var profileInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileRow(
                title: "KEY DO USUARIO",
                value: maskedLicenseKey(licenseManager.licenseKey),
                icon: "key.fill",
                monospaced: true
            )

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 13)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                profileRow(
                    title: "TEMPO RESTANTE",
                    value: remainingTime(until: licenseManager.expirationDate, now: context.date),
                    icon: "timer",
                    monospaced: false
                )
            }

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 13)

            profileRow(
                title: "USUARIO",
                value: licenseManager.isActive ? "ATIVO" : "INATIVO",
                icon: "person.fill",
                valueColor: licenseManager.isActive ? .green : .red
            )
        }
        .padding(18)
        .background(Color.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.34), lineWidth: 1)
        )
    }

    private func profileRow(
        title: String,
        value: String,
        icon: String,
        monospaced: Bool = false,
        valueColor: Color = .white
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.42))

                Text(value)
                    .font(.system(
                        size: 13,
                        weight: .bold,
                        design: monospaced ? .monospaced : .rounded
                    ))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)
        }
    }

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(AppTheme.accent)
                    .frame(width: 3, height: 18)

                Text("INFORMAÇÕES DESENVOLVEDOR")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 3)

            developerLink(
                title: "CANAL DO YOUTUBE",
                subtitle: "youtube.com/@souzaiosoficial",
                icon: "play.rectangle.fill",
                url: "https://www.youtube.com/@souzaiosoficial"
            )

            developerLink(
                title: "TODA MINHA COMUNIDADE",
                subtitle: "slat.cc/souzaiosoficial",
                icon: "arrow.up.right",
                url: "https://slat.cc/souzaiosoficial"
            )

            developerLink(
                title: "MINHA LOJA OFICIAL",
                subtitle: "souzaiosoficial.lovable.app",
                icon: "cart.fill",
                url: "https://souzaiosoficial.lovable.app/"
            )
        }
    }

    private func developerLink(title: String, subtitle: String, icon: String, url: String) -> some View {
        Button {
            guard let destination = URL(string: url) else { return }
            UIApplication.shared.open(destination)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.30))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Patch

    private var patchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("OPÇÕES DE PATCH", icon: "gamecontroller.fill")

            patchToggleRow(
                title: "PESCOÇO SEGURO",
                subtitle: "Arquivo pescoco.3105",
                icon: "scope",
                isOn: $pescocoEnabled,
                package: "pescoco.3105"
            )

            patchToggleRow(
                title: "PEITO SEGURO",
                subtitle: "Arquivo peito.3105",
                icon: "target",
                isOn: $peitoEnabled,
                package: "peito.3105"
            )
        }
    }

    private var visualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("VISUAL", icon: "eye.fill")

            patchToggleRow(
                title: "PESCOÇO + ANT",
                subtitle: "Arquivo pscant.3105",
                icon: "antenna.radiowaves.left.and.right",
                isOn: $pescocoAntEnabled,
                package: "pscant.3105"
            )

            patchToggleRow(
                title: "PEITO + ANT",
                subtitle: "Arquivo ptatn.3105",
                icon: "antenna.radiowaves.left.and.right",
                isOn: $peitoAntEnabled,
                package: "ptatn.3105"
            )

            disabledPatchToggleRow(
                title: "HOLO NAS ARMAS",
                subtitle: "Arquivo holograma.3105",
                icon: "pistol"
            )
        }
    }

    private func disabledPatchToggleRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 13) {
            Group {
                if icon == "pistol" {
                    PistolIcon(size: 20, color: .gray)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: 40, height: 40)
            .background(
                Color.gray.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))

                Text("Em desenvolvimento.")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow.opacity(0.82))
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .opacity(0.82)
    }

    private func patchToggleRow(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>,
        package: String
    ) -> some View {
        HStack(spacing: 13) {
            Group {
                if icon == "pistol" {
                    PistolIcon(
                        size: 20,
                        color: isOn.wrappedValue ? .green : AppTheme.accent
                    )
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isOn.wrappedValue ? .green : AppTheme.accent)
                }
            }
            .frame(width: 40, height: 40)
            .background(
                (isOn.wrappedValue ? Color.green : AppTheme.accent).opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            Text(title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { isOn.wrappedValue },
                    set: { _ in
                        togglePatch(packageFilename: package, state: isOn)
                    }
                )
            )
            .labelsHidden()
            .tint(.green)
            .disabled(patchOperationBusy)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isOn.wrappedValue ? Color.green.opacity(0.30) : Color.white.opacity(0.07),
                    lineWidth: 1
                )
        )
    }

    private func lockedOption(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.30))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            Text("BLOQUEADO")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        )
    }

    private var usageWarning: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.yellow)
                .frame(width: 24, height: 24)

            Text("Ative apenas a opção caso voce abriu ja o Free Fire e deixou carregando ate os 40%. Logo apos, retorne ao jogo e deixe abrir ate o lobby, retorne aqui e clique para RESTAURAR ORIGINAL.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.yellow.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
    }

    private var restoreOriginalButton: some View {
        Button {
            restoreOriginal()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.counterclockwise")
                Text("RESTAURAR ORIGINAL")
            }
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.48), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(patchOperationBusy)
    }

    private var operationStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(patchOperationBusy ? AppTheme.accent : (hasActivePatch ? .green : Color.white.opacity(0.20)))
                .frame(width: 7, height: 7)

            Text(patchOperationBusy ? "PROCESSANDO…" : patchMessage)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.30), in: Capsule())
    }

    private var hasActivePatch: Bool {
        pescocoEnabled || peitoEnabled
    }

    private var hasActiveVisualPatch: Bool {
        pescocoAntEnabled || peitoAntEnabled || holoEnabled
    }

    // MARK: - Banner / Navigation

    private var bannerView: some View {
        Group {
            if let url = URL(string: bannerURL), !bannerURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.accent.opacity(0.32), lineWidth: 1)
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

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "house.fill", title: "Principal", index: 0)
            tabButton(icon: "eye.fill", title: "Visual", index: 1)
            tabButton(icon: "person.fill", title: "Perfil", index: 2)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
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
            .foregroundStyle(selectedTab == index ? AppTheme.accent : .white.opacity(0.40))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - License notice

    private var licenseNoticeOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACESSO LIBERADO")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Sua KEY está ativa neste dispositivo")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.44))
                    }

                    Spacer()
                }

                noticeRow(
                    title: "KEY",
                    value: licenseManager.licenseKey ?? "Não disponível",
                    icon: "key.fill",
                    monospaced: true
                )

                noticeRow(
                    title: "VENCE EM",
                    value: licenseManager.formattedExpiration,
                    icon: "calendar.badge.clock"
                )

                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showLicenseNotice = false
                    }
                } label: {
                    Text("FECHAR")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                Color(red: 0.045, green: 0.006, blue: 0.008)
                    .opacity(0.98),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: AppTheme.accent.opacity(0.16), radius: 28, y: 12)
        }
    }

    private func noticeRow(
        title: String,
        value: String,
        icon: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32, height: 32)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.38))

                Text(value)
                    .font(.system(
                        size: 12,
                        weight: .bold,
                        design: monospaced ? .monospaced : .rounded
                    ))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(11)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var successToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.green)

            Text(successToastText)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Color.black.opacity(0.90), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.green.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(AppTheme.accent)
            .padding(.top, 2)
    }

    private func maskedLicenseKey(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "Não disponível" }
        let visibleCount = min(4, key.count)
        let visible = String(key.prefix(visibleCount))
        let hidden = String(repeating: "x", count: max(0, key.count - visibleCount))
        return visible + hidden
    }

    private func remainingTime(until expiration: Date?, now: Date) -> String {
        guard let expiration else { return "—" }
        let seconds = max(0, Int(expiration.timeIntervalSince(now)))
        if seconds <= 0 { return "EXPIRADA" }

        let days = seconds / 86_400
        let hours = seconds / 3_600
        let minutes = seconds / 60

        // Mostra só a unidade principal (ex.: key de 1 dia → "23h", key de 7 dias → "6d")
        if days >= 2 {
            return "\(days)d"
        }
        if hours >= 1 {
            return "\(hours)h"
        }
        if minutes >= 1 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }

    // MARK: - Patch logic (mantida)

    private func syncPatchStates() {
        pescocoEnabled = isPatchActive("pescoco.3105")
        peitoEnabled = isPatchActive("peito.3105")
        pescocoAntEnabled = isPatchActive("pscant.3105")
        peitoAntEnabled = isPatchActive("ptatn.3105")
        holoEnabled = isPatchActive("holograma.3105")
    }

    private func isPatchActive(_ packageFilename: String) -> Bool {
        patchStore.items.first {
            $0.packageURL.lastPathComponent.caseInsensitiveCompare(packageFilename) == .orderedSame
        }
        .flatMap { DevicePatchService.latestReceipt(projectID: $0.id) } != nil
    }

    private enum PatchActionResult {
        case applied
        case restored
        case unavailable(String)
    }

    private func setPatchState(for packageFilename: String, enabled: Bool) {
        switch packageFilename {
        case "pescoco.3105":
            pescocoEnabled = enabled
        case "peito.3105":
            peitoEnabled = enabled
        case "pscant.3105":
            pescocoAntEnabled = enabled
        case "ptatn.3105":
            peitoAntEnabled = enabled
        case "holograma.3105":
            holoEnabled = enabled
        default:
            break
        }
    }

    private func togglePatch(packageFilename: String, state: Binding<Bool>) {
        guard !patchOperationBusy else { return }

        guard let item = patchStore.items.first(where: {
            $0.packageURL.lastPathComponent.caseInsensitiveCompare(packageFilename) == .orderedSame
        }) else {
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
                        result = .unavailable("NENHUM PATCH ATIVO ENCONTRADO")

                        DispatchQueue.main.async {
                            self.setPatchState(for: packageFilename, enabled: false)
                            self.patchMessage = "NENHUM PATCH ATIVO ENCONTRADO"
                            self.patchOperationBusy = false
                        }
                        return
                    }

                    try DevicePatchService.restore(receipt: receipt)
                    result = .restored
                } else {
                    guard let project else {
                        result = .unavailable("SENHA NECESSÁRIA — DESBLOQUEIE O PACOTE")

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
                if let patchError = error as? PatchPackageError,
                   case .targetAppUnavailable(let bundleID) = patchError {
                    result = .unavailable("APP ALVO NAO ENCONTRADO — \(bundleID). Verifique se o jogo esta instalado e se o acesso ao sandbox esta ativo.")
                } else {
                    result = .unavailable("FALHOU — \(String(describing: error))")
                }
            }

            // If Free Fire was opened only to materialize the container, bring EXTERNAL back.
            let ownID = Bundle.main.bundleIdentifier ?? "com.apple.mobile.MobileHouseArrest"
            _ = openApplicationForBundleID(ownID)

            DispatchQueue.main.async {
                switch result {
                case .applied:
                    self.setPatchState(for: packageFilename, enabled: true)
                    self.patchMessage = "ATIVADO COM SUCESSO — \(packageFilename)"
                    self.showSuccessToast(message: "Ativado com sucesso")
                    PatchAudioFeedback.bypassActivated()

                case .restored:
                    self.setPatchState(for: packageFilename, enabled: false)
                    self.patchMessage = "RESTAURAÇÃO BEM-SUCEDIDA — \(packageFilename)"
                    PatchAudioFeedback.originalRestored()

                case .unavailable(let message):
                    self.patchMessage = message
                }

                self.patchOperationBusy = false
            }
        }
    }

    private func restoreOriginal() {
        guard !patchOperationBusy else { return }

        let packageNames = [
            "pescoco.3105",
            "peito.3105",
            "pscant.3105",
            "ptatn.3105",
            "holograma.3105"
        ]
        let activePackages: [(String, UUID)] = packageNames.map { name in
            (name, patchStore.items.first(where: {
                $0.packageURL.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
            }).map(\.id))
        }
        .compactMap { name, id in
            guard let id else { return nil }
            guard DevicePatchService.latestReceipt(projectID: id) != nil else { return nil }
            return (name, id)
        }

        guard !activePackages.isEmpty else {
            syncPatchStates()
            patchMessage = "NENHUM PATCH ATIVO"
            return
        }

        patchOperationBusy = true
        patchMessage = "RESTAURANDO ARQUIVO ORIGINAL…"

        DispatchQueue.global(qos: .userInitiated).async {
            var success = true

            for (_, projectID) in activePackages {
                guard let receipt = DevicePatchService.latestReceipt(projectID: projectID) else { continue }

                do {
                    try DevicePatchService.restore(receipt: receipt)
                } catch {
                    success = false
                    log("restore original failed: \(String(describing: error))")
                }
            }

            DispatchQueue.main.async {
                self.syncPatchStates()
                self.patchOperationBusy = false

                if success {
                    self.patchMessage = "ARQUIVO ORIGINAL RESTAURADO"
                    self.successToastText = "Original restaurado"
                    self.showSuccessToast = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.showSuccessToast = false
                        }
                    }

                    PatchAudioFeedback.originalRestored()
                } else {
                    self.patchMessage = "RESTAURAÇÃO PARCIAL — VERIFIQUE O STATUS"
                }
            }
        }
    }

    private func showSuccessToast(message: String) {
        successToastText = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showSuccessToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                self.showSuccessToast = false
            }
        }
    }
}
