import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PairingVPNView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var pairingManager: LocalVPNPairingManager
    @EnvironmentObject private var appState: AppState
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false

    @State private var selectedSegment: HubSegment = .localVPN
    @State private var showImportPairingPicker = false
    @State private var showSharePairingSheet = false
    @State private var showNetworkConfigSheet = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    enum HubSegment: String, CaseIterable, Identifiable {
        case localVPN
        case pairing

        var id: String { rawValue }
    }

    init(
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    segmentSelector

                    if selectedSegment == .localVPN {
                        localDevVPNSection
                    } else {
                        developerModePairingSection
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle(
                selectedSegment == .localVPN
                    ? "LocalDevVPN"
                    : language.text("pairing.developer_mode_title")
            )
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNetworkConfigSheet = true
                    } label: {
                        Image(systemName: "network")
                    }
                    .accessibilityLabel(language.text("localvpn.network_config"))
                }
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
            .sheet(isPresented: $showImportPairingPicker) {
                FileDocumentPicker(
                    allowedContentTypes: [.item, .data, .propertyList, .xml],
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showImportPairingPicker = false
                        if case .success(let urls) = result, let url = urls.first {
                            do {
                                _ = try pairingManager.importPairingFile(from: url)
                                appState.detectSupport()
                                alertMessage = language.text("pairing.import_success")
                                showAlert = true
                            } catch {
                                alertMessage = language.text("pairing.import_failed")
                                showAlert = true
                            }
                        }
                    },
                    onCancel: {
                        showImportPairingPicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showSharePairingSheet) {
                PairingFileShareSheet(items: [pairingManager.exportPairingFileURL()])
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showNetworkConfigSheet) {
                LocalVPNConfigSheet(pairingManager: pairingManager)
            }
            .alert(language.text("pairing.title"), isPresented: $showAlert) {
                Button(language.text("common.ok"), role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var segmentSelector: some View {
        Picker("", selection: $selectedSegment) {
            Text("LocalDevVPN").tag(HubSegment.localVPN)
            Text(language.text("pairing.developer_mode_title")).tag(HubSegment.pairing)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - LocalDevVPN Screen

    private var localDevVPNSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Card 1: Current status
            VStack(alignment: .leading, spacing: 18) {
                Text(language.text("localvpn.current_status"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                HStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                pairingManager.isTunnelConnected
                                    ? Color.green.opacity(0.18)
                                    : Color.orange.opacity(0.16)
                            )
                            .frame(width: 92, height: 92)
                        Circle()
                            .strokeBorder(
                                pairingManager.isTunnelConnected
                                    ? Color.green.opacity(0.42)
                                    : Color.orange.opacity(0.38),
                                lineWidth: 2
                            )
                            .frame(width: 92, height: 92)
                        Image(
                            systemName: pairingManager.isTunnelConnected
                                ? "checkmark.shield.fill"
                                : "shield.slash.fill"
                        )
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(
                            pairingManager.isTunnelConnected ? Color.green : Color.orange
                        )
                    }

                    Spacer()

                    Text(
                        pairingManager.isTunnelConnected
                            ? language.text("localvpn.connected")
                            : language.text("localvpn.disconnected")
                    )
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.vertical, 4)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        pairingManager.isTunnelConnected
                            ? language.text(
                                "localvpn.connected_to",
                                pairingManager.networkConfig.tunnelIPWithPrefix
                            )
                            : language.text("localvpn.ready_to_connect")
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            )

            // Card 2: Connection
            VStack(alignment: .leading, spacing: 14) {
                Text(language.text("localvpn.connection"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(language.text("localvpn.connection_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pairingManager.toggleLocalTunnel()
                        appState.detectSupport()
                    }
                } label: {
                    Text(
                        pairingManager.isTunnelConnected
                            ? language.text("localvpn.disconnect")
                            : language.text("localvpn.connect")
                    )
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule()
                            .fill(
                                pairingManager.isTunnelConnected
                                    ? Color(red: 0.92, green: 0.26, blue: 0.24)
                                    : Color.green
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            )

            // Card 3: Session details
            VStack(alignment: .leading, spacing: 14) {
                Text(language.text("localvpn.session_details"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(language.text("localvpn.session_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                Text(language.text("localvpn.network_config"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text("localvpn.tunnel_ip"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pairingManager.networkConfig.tunnelIPWithPrefix)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)

                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text("localvpn.device_ip"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pairingManager.networkConfig.deviceIPWithPrefix)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)

                HStack(spacing: 14) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text("pairing.paired_devices"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            pairingManager.pairedDevices.first?.name ?? "3105"
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("iOS \(AppInfo.osVersion)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                .padding(.vertical, 2)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            )
        }
    }

    // MARK: - Developer Mode & Paired Devices ("3105") Screen

    private var developerModePairingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Developer Mode Toggle Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(language.text("pairing.developer_mode_title"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $developerModeEnabled)
                        .labelsHidden()
                        .tint(.green)
                        .onChange(of: developerModeEnabled) { enabled in
                            pairingManager.developerModeEnabled = enabled
                        }
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                )

                Text(language.text("pairing.developer_mode_description"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }

            // Paired Devices ("3105") Section
            VStack(alignment: .leading, spacing: 10) {
                Text(language.text("pairing.paired_devices"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                if pairingManager.pairedDevices.isEmpty {
                    HStack {
                        Text(language.text("pairing.no_paired_devices"))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                    )
                } else {
                    ForEach(pairingManager.pairedDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("HostID: \(device.hostID.prefix(12))… · iOS \(AppInfo.osVersion)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                        )
                    }
                }
            }

            // Other Devices scanning row
            HStack(spacing: 10) {
                Text(language.text("pairing.other_devices"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView()
                    .tint(.secondary)
                    .scaleEffect(0.85)
                Spacer()
                if !pairingManager.discoveredServices.isEmpty {
                    Text(pairingManager.discoveredServices.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)

            // 6-Digit Pairing Code & Notification Card
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    language.isRTL ? "كود الاقتران وإشعار نمط المطور" : "Pairing Code & Developer Mode Notification",
                    systemImage: "bell.badge.fill"
                )
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

                Text(
                    language.isRTL
                        ? "اضغط على (بدء بث الاقتران وإرسال الإشعار) ثم انتقل إلى إعدادات الآيفون ← الخصوصية والأمن ← نمط المطور؛ سيصلك إشعار تفاعلي أعلى الشاشة لإدخال كود الاقتران المكون من 6 أرقام، أو يمكنك إدخاله هنا مباشرة:"
                        : "Tap 'Start Pairing Broadcast & Send Notification', then open iOS Settings → Privacy & Security → Developer Mode. A notification banner will appear to enter the 6-digit pairing code, or enter it below:"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("000000 (كود الاقتران)", text: $pairingManager.pairingCodeInput)
                        .keyboardType(.numberPad)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )

                    Button {
                        pairingManager.completePairingWithCode(pairingManager.pairingCodeInput)
                        appState.detectSupport()
                        alertMessage = language.text("pairing.pair_success_3105")
                        showAlert = true
                    } label: {
                        Text(language.isRTL ? "تأكيد الكود" : "Confirm Code")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.green)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if !pairingManager.lastPairingNotificationStatus.isEmpty {
                    Text(pairingManager.lastPairingNotificationStatus)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button {
                    pairingManager.startDeveloperModeBonjourPairingSession()
                } label: {
                    HStack {
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                        Text(
                            language.isRTL
                                ? "بدء بث الاقتران (3105) وإرسال إشعار الكود"
                                : "Start 3105 Pairing Broadcast & Send Notification"
                        )
                        .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.accent)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    pairingManager.openDeveloperModeOrSettings()
                } label: {
                    HStack {
                        Image(systemName: "gearshape.2.fill")
                        Text(
                            language.isRTL
                                ? "فتح إعدادات نمط المطور ( مع استمرار البث بالخلفية )"
                                : "Open iOS Developer Mode Settings (Keep Broadcasting)"
                        )
                        .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.blue.opacity(0.35))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            )

            // Actions Card for Direct Pairing & .mobiledevicepairing File Import/Export
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("pairing.actions_title"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(language.text("pairing.actions_subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    pairingManager.pairCurrentDeviceAs3105()
                    appState.detectSupport()
                    alertMessage = language.text("pairing.pair_success_3105")
                    showAlert = true
                } label: {
                    HStack {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                        Text(language.text("pairing.pair_now_button"))
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.green.opacity(0.85))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showImportPairingPicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.gearshape")
                        Text(language.text("pairing.import_file_button"))
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    _ = pairingManager.exportPairingFileURL()
                    showSharePairingSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(
                            language.isRTL
                                ? "تثبيت / حفظ ملف الاقتران (3105.mobiledevicepairing)"
                                : "Install / Save Pairing File (3105.mobiledevicepairing)"
                        )
                        .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            )
        }
    }
}

private struct PairingFileShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct LocalVPNConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @ObservedObject var pairingManager: LocalVPNPairingManager
    @State private var tunnelIP: String = "10.7.1.1"
    @State private var deviceIP: String = "10.7.0.1"
    @State private var lockdownPort: String = "62078"

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("localvpn.network_config")) {
                    LabeledContent(language.text("localvpn.tunnel_ip")) {
                        TextField("10.7.1.1", text: $tunnelIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .font(.body.monospaced())
                    }
                    LabeledContent(language.text("localvpn.device_ip")) {
                        TextField("10.7.0.1", text: $deviceIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .font(.body.monospaced())
                    }
                    LabeledContent("Lockdownd Port") {
                        TextField("62078", text: $lockdownPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .font(.body.monospaced())
                    }
                }
            }
            .navigationTitle(language.text("localvpn.network_config"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done")) {
                        let port = UInt16(lockdownPort) ?? 62078
                        pairingManager.updateNetworkConfiguration(
                            tunnelIP: tunnelIP,
                            deviceIP: deviceIP,
                            port: port
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tunnelIP = pairingManager.networkConfig.tunnelIP
                deviceIP = pairingManager.networkConfig.deviceIP
                lockdownPort = String(pairingManager.networkConfig.lockdownPort)
            }
        }
    }
}
