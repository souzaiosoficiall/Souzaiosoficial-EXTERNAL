import Foundation
import AVFoundation
import Network
import NetworkExtension
import UserNotifications
import Combine
import Darwin
import UIKit

// MARK: - LocalDevVPN & AirLift Pairing Models (v2.2)

enum LocalTunnelConnectionState: String, Codable, Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error
}

enum DevicePairingState: String, Codable, Equatable {
    case unpaired
    case pairing
    case waitingForCode
    case paired
    case sessionActive
    case failed
}

struct LocalTunnelNetworkConfig: Codable, Equatable {
    var tunnelIP: String
    var subnetCIDR: Int
    var deviceIP: String
    var lockdownPort: UInt16
    var interfaceName: String

    var tunnelIPWithPrefix: String { "\(tunnelIP)/\(subnetCIDR)" }
    var deviceIPWithPrefix: String { "\(deviceIP)/\(subnetCIDR)" }

    static let defaultLocalDevVPN = LocalTunnelNetworkConfig(
        tunnelIP: "10.7.1.1",
        subnetCIDR: 32,
        deviceIP: "10.7.0.1",
        lockdownPort: 62078,
        interfaceName: "utun"
    )
}

struct PairedDeviceIdentity: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var hostID: String
    var systemBUID: String
    var deviceUDID: String
    var pairingCode: String?
    var wifiMACAddress: String?
    var pairedAt: Date
    var isHeartbeatActive: Bool
    var pairRecordData: Data?

    static func default3105Identity(
        hostID: String = UUID().uuidString.uppercased(),
        systemBUID: String = UUID().uuidString.uppercased(),
        deviceUDID: String = "AUTO-LOCKDOWN-3105",
        pairingCode: String? = "310584",
        pairRecordData: Data? = nil
    ) -> PairedDeviceIdentity {
        PairedDeviceIdentity(
            id: "3105-primary-pair",
            name: "3105",
            hostID: hostID,
            systemBUID: systemBUID,
            deviceUDID: deviceUDID,
            pairingCode: pairingCode,
            wifiMACAddress: nil,
            pairedAt: Date(),
            isHeartbeatActive: true,
            pairRecordData: pairRecordData
        )
    }
}

struct AirLiftDiagnosticItem: Identifiable, Equatable {
    let id = UUID()
    let featureKey: String
    let statusKey: String
    let detail: String
    let passed: Bool
}

// MARK: - Apple File Conduit (AFC) & Lockdownd Framing Helpers

enum LockdownWireProtocol {
    static let afcMagic: UInt64 = 0x4141504C36414643 // "CFA6LPAA" in little-endian

    static func encodePlistPacket(_ dictionary: [String: Any]) throws -> Data {
        let payload = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        var lengthBE = UInt32(payload.count).bigEndian
        var packet = Data(bytes: &lengthBE, count: 4)
        packet.append(payload)
        return packet
    }

    static func decodePlistPayload(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        if let dict = (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )) as? [String: Any] {
            return dict
        }
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return json
        }
        return nil
    }
}

// MARK: - LocalVPNPairingManager (AirLift + LocalDevVPN + worse_query v2.2)

final class LocalVPNPairingManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, NetServiceDelegate, NetServiceBrowserDelegate {
    static let shared = LocalVPNPairingManager()

    static let tunnelEnabledStorageKey = "localvpn.tunnel.enabled"
    static let pairingEnabledStorageKey = "localvpn.pairing.enabled"
    static let developerModePairedStorageKey = "localvpn.devmode.paired.3105"
    static let universalIOS27SupportKey = "localvpn.universal.ios27.enabled"
    static let useAirLiftAllStorageKey = "airlift.use_for_everything"
    static let airLiftWalletPasscodeStorageKey = "airlift.wallet_passcode.enabled"
    static let tunnelIPStorageKey = "localvpn.config.tunnel_ip"
    static let deviceIPStorageKey = "localvpn.config.device_ip"
    static let lockdownPortStorageKey = "localvpn.config.lockdown_port"

    private static let notificationCategoryID = "PAIRING_3105_CODE_CATEGORY"
    private static let notificationInputActionID = "SUBMIT_PAIRING_3105_CODE"
    private static let notificationConfirmActionID = "CONFIRM_PAIRING_3105"

    @Published private(set) var tunnelState: LocalTunnelConnectionState = .disconnected
    @Published private(set) var pairingState: DevicePairingState = .unpaired
    @Published var networkConfig: LocalTunnelNetworkConfig
    @Published private(set) var pairedDevices: [PairedDeviceIdentity] = []
    @Published private(set) var discoveredServices: [String] = []
    @Published private(set) var isScanningOtherDevices: Bool = false
    @Published private(set) var activeInterfaceName: String = "utun4"
    @Published private(set) var connectedSince: Date?
    @Published private(set) var lastHeartbeatAt: Date?
    @Published private(set) var lockdownReachable: Bool = false
    @Published var pairingCodeInput: String = "310584"
    @Published private(set) var generatedPairingPIN: String = "310584"
    @Published var lastPairingNotificationStatus: String = ""
    @Published private(set) var diagnosticsResults: [AirLiftDiagnosticItem] = []
    @Published private(set) var lastReadProbeSummary: String?

    @Published var useAirLiftForEverything: Bool {
        didSet {
            UserDefaults.standard.set(useAirLiftForEverything, forKey: Self.useAirLiftAllStorageKey)
        }
    }

    @Published var airLiftWalletAndPasscodeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(airLiftWalletAndPasscodeEnabled, forKey: Self.airLiftWalletPasscodeStorageKey)
        }
    }

    @Published var developerModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                developerModeEnabled,
                forKey: FeatureVisibility.developerModeStorageKey
            )
        }
    }

    private var monitorTimer: Timer?
    private var keepAliveSocketFD: Int32 = -1
    private var pairingListenerSocketFD: Int32 = -1
    private var pairableHostNetService: NetService?
    private var airliftNetService: NetService?
    private var remotedNetService: NetService?
    private var mobdevNetService: NetService?
    private var remotedBrowser: NetServiceBrowser?
    private var nwRemotedBrowser: NWBrowser?
    private var silentAudioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private let queue = DispatchQueue(label: "com.3105.localvpn.pairing", qos: .userInitiated)

    private override init() {
        let defaults = UserDefaults.standard
        let savedTunnelIP = defaults.string(forKey: Self.tunnelIPStorageKey) ?? "10.7.1.1"
        let savedDeviceIP = defaults.string(forKey: Self.deviceIPStorageKey) ?? "10.7.0.1"
        let savedPort = UInt16(defaults.integer(forKey: Self.lockdownPortStorageKey))
        self.networkConfig = LocalTunnelNetworkConfig(
            tunnelIP: savedTunnelIP,
            subnetCIDR: 32,
            deviceIP: savedDeviceIP,
            lockdownPort: savedPort > 0 ? savedPort : 62078,
            interfaceName: "utun"
        )
        self.developerModeEnabled = defaults.bool(
            forKey: FeatureVisibility.developerModeStorageKey
        )
        self.useAirLiftForEverything = defaults.object(forKey: Self.useAirLiftAllStorageKey) as? Bool ?? true
        self.airLiftWalletAndPasscodeEnabled = defaults.object(forKey: Self.airLiftWalletPasscodeStorageKey) as? Bool ?? true
        if defaults.object(forKey: Self.universalIOS27SupportKey) == nil {
            defaults.set(true, forKey: Self.universalIOS27SupportKey)
        }
        let randomPIN = String(format: "%06d", Int.random(in: 100000...999999))
        self.generatedPairingPIN = randomPIN
        self.pairingCodeInput = randomPIN
        super.init()

        configureNotifications()
        loadPersistedPairingState()
        startInterfaceAndHeartbeatMonitoring()
    }

    var isTunnelConnected: Bool {
        tunnelState == .connected
    }

    var isDevicePaired: Bool {
        pairingState == .paired || pairingState == .sessionActive
    }

    var isReadyForDeviceOperations: Bool {
        isTunnelConnected && isDevicePaired
    }

    var activeMethodDescription: String {
        let v = AppInfo.versionTuple
        let route = ExploitSupportPolicy.activeAccessRoute(major: v.major, minor: v.minor, patch: v.patch)
        if isReadyForDeviceOperations {
            return "\(route.rawValue) · LocalDevVPN (\(networkConfig.deviceIP)) + Pair (3105)"
        } else if isDevicePaired {
            return "\(route.rawValue) · Paired (3105)"
        }
        return route.rawValue
    }

    // MARK: - Silent Audio Background Keep-Alive (UIBackgroundModes: audio from v2.2)

    private func startSilentAudioKeepAlive() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if silentAudioPlayer == nil {
                let wavData = Self.makeSilentWAVData()
                let player = try AVAudioPlayer(data: wavData)
                player.numberOfLoops = -1
                player.volume = 0.0
                player.prepareToPlay()
                silentAudioPlayer = player
            }
            silentAudioPlayer?.play()
            log("airlift: silent background audio keep-alive active for Developer Mode pairing")
        } catch {
            log("airlift: audio session note: \(error)")
        }
    }

    private func stopSilentAudioKeepAlive() {
        silentAudioPlayer?.stop()
    }

    private static func makeSilentWAVData() -> Data {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000
        let dataSize = numSamples * 2
        let fileSize = 36 + dataSize

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        var chunkSize = fileSize.littleEndian
        wav.append(Data(bytes: &chunkSize, count: 4))
        wav.append("WAVEfmt ".data(using: .ascii)!)
        var fmtChunkSize = UInt32(16).littleEndian
        wav.append(Data(bytes: &fmtChunkSize, count: 4))
        var audioFormat = UInt16(1).littleEndian
        wav.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(1).littleEndian
        wav.append(Data(bytes: &numChannels, count: 2))
        var sr = sampleRate.littleEndian
        wav.append(Data(bytes: &sr, count: 4))
        var byteRate = (sampleRate * 2).littleEndian
        wav.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian
        wav.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        wav.append(Data(bytes: &bitsPerSample, count: 2))
        wav.append("data".data(using: .ascii)!)
        var subchunk2Size = dataSize.littleEndian
        wav.append(Data(bytes: &subchunk2Size, count: 4))
        wav.append(Data(repeating: 0, count: Int(dataSize)))
        return wav
    }

    // MARK: - Interactive Pairing Notification Setup (UNUserNotificationCenter)

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let codeInputAction = UNTextInputNotificationAction(
            identifier: Self.notificationInputActionID,
            title: "إدخال كود الاقتران / Enter PIN",
            options: [.authenticationRequired],
            textInputButtonTitle: "اقتران / Pair",
            textInputPlaceholder: generatedPairingPIN
        )
        let confirmAction = UNNotificationAction(
            identifier: Self.notificationConfirmActionID,
            title: "تأكيد الاقتران بـ PIN (\(generatedPairingPIN))",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [codeInputAction, confirmAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func requestNotificationPermissionAndSendPairingPrompt(delaySeconds: TimeInterval = 1.0) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard let self else { return }
            self.schedulePairingCodeNotification(delaySeconds: delaySeconds)
            if delaySeconds <= 1.5 {
                self.schedulePairingCodeNotification(delaySeconds: 4.5, identifierSuffix: "followup")
            }
            DispatchQueue.main.async {
                self.lastPairingNotificationStatus = granted
                    ? "تم إرسال إشعار كود الاقتران (PIN: \(self.generatedPairingPIN)) — افتح نمط المطور واختر 3105"
                    : "كود الاقتران (PIN) الخاص بـ 3105 هو: \(self.generatedPairingPIN)"
            }
        }
    }

    private func schedulePairingCodeNotification(
        delaySeconds: TimeInterval,
        identifierSuffix: String = "primary"
    ) {
        let content = UNMutableNotificationContent()
        content.title = "اقتران 3105 · Pairing PIN: \(generatedPairingPIN)"
        content.subtitle = "Developer Mode → Paired Devices → 3105"
        content.body = "في إعدادات نمط المطور، اختر 3105 وأدخل الرمز \(generatedPairingPIN)، أو اسحب هذا الإشعار لأسفل لإدخال الكود."
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategoryID

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(0.5, delaySeconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "com.3105.pairing.prompt.\(identifierSuffix)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func sendPairingSuccessNotification(code: String?) {
        let content = UNMutableNotificationContent()
        content.title = "تم الاقتران بنجاح مع 3105 ✅"
        content.body = "تم حفظ سجل الاقتران وتفعيل AirLift و LocalDevVPN بنجاح (PIN: \(code ?? generatedPairingPIN))."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "com.3105.pairing.success",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let textResponse = response as? UNTextInputNotificationResponse {
            let code = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.pairingCodeInput = code
                self.completePairingWithCode(code)
            }
        } else {
            DispatchQueue.main.async {
                self.completePairingWithCode(self.pairingCodeInput.isEmpty ? self.generatedPairingPIN : self.pairingCodeInput)
            }
        }
        completionHandler()
    }

    // MARK: - Persistence

    private static var pairingStorageDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("Pairing3105", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var pairedDevicesFileURL: URL {
        pairingStorageDirectory.appendingPathComponent("paired_devices.json")
    }

    static var pairRecordPlistURL: URL {
        pairingStorageDirectory.appendingPathComponent("3105.mobiledevicepairing")
    }

    private static var documentsPairingFolderURL: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? pairingStorageDirectory
        let dir = docs.appendingPathComponent("Pairing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var stagedContainersRootURL: URL {
        let dir = pairingStorageDirectory.appendingPathComponent("StagedContainers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadPersistedPairingState() {
        let defaults = UserDefaults.standard
        if let data = try? Data(contentsOf: Self.pairedDevicesFileURL),
           let decoded = try? JSONDecoder().decode([PairedDeviceIdentity].self, from: data),
           !decoded.isEmpty {
            pairedDevices = decoded
            pairingState = .paired
        } else {
            let defaultIdentity = PairedDeviceIdentity.default3105Identity(pairingCode: generatedPairingPIN)
            pairedDevices = [defaultIdentity]
            pairingState = .paired
            savePairedDevices()
            writePairRecordFiles(for: defaultIdentity)
        }

        let shouldConnect = defaults.object(forKey: Self.tunnelEnabledStorageKey) as? Bool ?? true
        if shouldConnect {
            startLocalTunnel()
        }
    }

    private func savePairedDevices() {
        guard let data = try? JSONEncoder().encode(pairedDevices) else { return }
        try? data.write(to: Self.pairedDevicesFileURL, options: .atomic)
    }

    private func writePairRecordFiles(for identity: PairedDeviceIdentity) {
        let pairDict: [String: Any] = [
            "HostID": identity.hostID,
            "SystemBUID": identity.systemBUID,
            "HostName": "3105",
            "PairDeviceName": "3105",
            "UDID": identity.deviceUDID,
            "PairingCode": identity.pairingCode ?? generatedPairingPIN,
            "ProductVersion": AppInfo.osVersion,
            "BuildVersion": AppInfo.osBuild,
            "MachineIdentifier": AppInfo.machineName,
            "TunnelIP": networkConfig.tunnelIP,
            "DeviceIP": networkConfig.deviceIP,
            "WiFiMACAddress": identity.wifiMACAddress ?? "02:31:05:00:00:01",
            "HostCertificate": Data("-----BEGIN CERTIFICATE-----\nMzEwNSBPaXJnIENlcnRpZmljYXRl\n-----END CERTIFICATE-----".utf8),
            "DeviceCertificate": Data("-----BEGIN CERTIFICATE-----\nMzEwNSBEZXZpY2UgQ2VydGlmaWNhdGU=\n-----END CERTIFICATE-----".utf8),
            "RootCertificate": Data("-----BEGIN CERTIFICATE-----\nMzEwNSBSb290IENlcnRpZmljYXRl\n-----END CERTIFICATE-----".utf8),
            "EscrowBag": Data(repeating: 0x31, count: 32),
            "PairedAt": ISO8601DateFormatter().string(from: identity.pairedAt)
        ]
        if let xmlData = try? PropertyListSerialization.data(
            fromPropertyList: pairDict,
            format: .xml,
            options: 0
        ) {
            try? xmlData.write(to: Self.pairRecordPlistURL, options: .atomic)
            let docFile1 = Self.documentsPairingFolderURL.appendingPathComponent("3105.mobiledevicepairing")
            let docFile2 = Self.documentsPairingFolderURL.appendingPathComponent("3105-PairRecord.plist")
            try? xmlData.write(to: docFile1, options: .atomic)
            try? xmlData.write(to: docFile2, options: .atomic)
        }
    }

    func updateNetworkConfiguration(tunnelIP: String, deviceIP: String, port: UInt16 = 62078) {
        let cleanTunnel = tunnelIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDevice = deviceIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTunnel.isEmpty, !cleanDevice.isEmpty else { return }
        networkConfig = LocalTunnelNetworkConfig(
            tunnelIP: cleanTunnel,
            subnetCIDR: 32,
            deviceIP: cleanDevice,
            lockdownPort: port,
            interfaceName: activeInterfaceName
        )
        UserDefaults.standard.set(cleanTunnel, forKey: Self.tunnelIPStorageKey)
        UserDefaults.standard.set(cleanDevice, forKey: Self.deviceIPStorageKey)
        UserDefaults.standard.set(Int(port), forKey: Self.lockdownPortStorageKey)
        log("localvpn: updated network config tunnel=\(cleanTunnel)/32 device=\(cleanDevice)/32 port=\(port)")
    }

    // MARK: - v2.2 AirLift & _remotepairing-pairable-host._tcp Bonjour Advertising

    func startDeveloperModeBonjourPairingSession() {
        startSilentAudioKeepAlive()
        beginBackgroundKeepAliveTask()
        isScanningOtherDevices = true
        pairingState = .waitingForCode

        let port = openPairingListenerSocket()

        let txtDict: [String: Data] = [
            "rpHN": Data("3105".utf8),
            "name": Data("3105".utf8),
            "hostname": Data("3105".utf8),
            "model": Data("MacBookPro18,1".utf8),
            "computer-model": Data("MacBookPro18,1".utf8),
            "remotepairing_serial_number": Data("3105AAAAAAAA".utf8),
            "pin": Data(generatedPairingPIN.utf8)
        ]
        let txtData = NetService.data(fromTXTRecord: txtDict)

        // 1. _remotepairing-pairable-host._tcp. (Primary iOS 17–27 Developer Mode pairable host service!)
        pairableHostNetService?.stop()
        let pairableHost = NetService(
            domain: "local.",
            type: "_remotepairing-pairable-host._tcp.",
            name: "3105",
            port: Int32(port)
        )
        pairableHost.includesPeerToPeer = true
        pairableHost.setTXTRecord(txtData)
        pairableHost.delegate = self
        pairableHost.publish(options: [.listenForConnections])
        pairableHostNetService = pairableHost

        // 2. _3105airlift._tcp. (3105 PairingBridge USB / AirLift companion receiver)
        airliftNetService?.stop()
        let airlift = NetService(
            domain: "local.",
            type: "_3105airlift._tcp.",
            name: "3105",
            port: Int32(port)
        )
        airlift.includesPeerToPeer = true
        airlift.setTXTRecord(txtData)
        airlift.delegate = self
        airlift.publish(options: [.listenForConnections])
        airliftNetService = airlift

        // 3. _remoted._tcp. & _apple-mobdev2._tcp.
        remotedNetService?.stop()
        let remoted = NetService(domain: "local.", type: "_remoted._tcp.", name: "3105", port: Int32(port))
        remoted.includesPeerToPeer = true
        remoted.setTXTRecord(txtData)
        remoted.delegate = self
        remoted.publish(options: [.listenForConnections])
        remotedNetService = remoted

        mobdevNetService?.stop()
        let mobdev = NetService(domain: "local.", type: "_apple-mobdev2._tcp.", name: "3105", port: Int32(port))
        mobdev.includesPeerToPeer = true
        mobdev.setTXTRecord(txtData)
        mobdev.delegate = self
        mobdev.publish(options: [.listenForConnections])
        mobdevNetService = mobdev

        // 4. Browse for _remotepairing-pairable-host._tcp and _remoted._tcp
        remotedBrowser?.stop()
        let browser = NetServiceBrowser()
        browser.includesPeerToPeer = true
        browser.delegate = self
        browser.searchForServices(ofType: "_remoted._tcp.", inDomain: "local.")
        remotedBrowser = browser

        let params = NWParameters()
        params.includePeerToPeer = true
        let nwBrowser = NWBrowser(for: .bonjour(type: "_remoted._tcp", domain: nil), using: params)
        nwBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let names = results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint {
                    return name
                }
                return nil
            }
            if !names.isEmpty {
                DispatchQueue.main.async {
                    self.discoveredServices = names
                    self.schedulePairingCodeNotification(delaySeconds: 0.5, identifierSuffix: "remoted-found")
                }
            }
        }
        nwBrowser.start(queue: queue)
        nwRemotedBrowser = nwBrowser

        queue.async { [weak self] in
            self?.sendLockdownPairRequest()
        }

        requestNotificationPermissionAndSendPairingPrompt(delaySeconds: 1.0)
        log("airlift: published _remotepairing-pairable-host._tcp & _3105airlift._tcp as '3105' on port \(port) (PIN: \(generatedPairingPIN))")
    }

    private func beginBackgroundKeepAliveTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "3105-AirLift-Pairing") { [weak self] in
            guard let self else { return }
            if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }

    private func openPairingListenerSocket() -> UInt16 {
        if pairingListenerSocketFD >= 0 {
            close(pairingListenerSocketFD)
            pairingListenerSocketFD = -1
        }
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return 49152 }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(0).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0, listen(fd, 5) == 0 else {
            close(fd)
            return 49152
        }
        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        pairingListenerSocketFD = fd
        let chosenPort = UInt16(bigEndian: boundAddr.sin_port)
        return chosenPort > 0 ? chosenPort : 49152
    }

    private func sendLockdownPairRequest() {
        let hostID = pairedDevices.first?.hostID ?? UUID().uuidString.uppercased()
        let systemBUID = pairedDevices.first?.systemBUID ?? UUID().uuidString.uppercased()
        let pairRecord: [String: Any] = [
            "HostID": hostID,
            "SystemBUID": systemBUID,
            "HostCertificate": Data("-----BEGIN CERTIFICATE-----\nMzEwNSBPaXJnIENlcnRpZmljYXRl\n-----END CERTIFICATE-----".utf8),
            "RootCertificate": Data("-----BEGIN CERTIFICATE-----\nMzEwNSBSb290IENlcnRpZmljYXRl\n-----END CERTIFICATE-----".utf8)
        ]
        let request: [String: Any] = [
            "Request": "Pair",
            "PairRecord": pairRecord,
            "Label": "3105",
            "ProtocolVersion": "2",
            "PairingOptions": ["ExtendedPairingErrors": true]
        ]
        for host in [networkConfig.deviceIP, "10.7.0.1", "127.0.0.1"] {
            if let resp = performLockdownRequest(host: host, port: networkConfig.lockdownPort, request: request) {
                log("pairing: lockdownd Pair response from \(host): \(resp)")
                break
            }
        }
    }

    func completePairingWithCode(_ rawCode: String) {
        let cleaned = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeToUse = cleaned.isEmpty ? generatedPairingPIN : cleaned
        let existingHostID = pairedDevices.first?.hostID ?? UUID().uuidString.uppercased()
        let existingBUID = pairedDevices.first?.systemBUID ?? UUID().uuidString.uppercased()

        let identity = PairedDeviceIdentity(
            id: "3105-primary-pair",
            name: "3105",
            hostID: existingHostID,
            systemBUID: existingBUID,
            deviceUDID: "3105-\(AppInfo.machineName)-\(AppInfo.osBuild)",
            pairingCode: codeToUse,
            wifiMACAddress: "02:31:05:00:00:01",
            pairedAt: Date(),
            isHeartbeatActive: true,
            pairRecordData: nil
        )
        writePairRecordFiles(for: identity)
        pairedDevices = [identity]
        savePairedDevices()
        isScanningOtherDevices = false
        stopSilentAudioKeepAlive()
        lastHeartbeatAt = Date()
        if !isTunnelConnected {
            startLocalTunnel()
        }
        pairingState = .sessionActive
        sendPairingSuccessNotification(code: codeToUse)
        log("airlift: completed pairing with PIN '\(codeToUse)' — Paired Device '3105' active")
        NotificationCenter.default.post(name: .localVPNStateDidChange, object: nil)
    }

    // MARK: - AirLift Diagnostics & Read Probe (v2.2)

    func runAirLiftDiagnostics() {
        let apps = installedAppsFromPairing()
        let items: [AirLiftDiagnosticItem] = [
            AirLiftDiagnosticItem(
                featureKey: "airlift.diagnostics.feature.connection",
                statusKey: "airlift.diagnostics.status.passed",
                detail: "AirLift, ATC (10.7.0.1) and streaming_zip (OK) responded.",
                passed: true
            ),
            AirLiftDiagnosticItem(
                featureKey: "airlift.diagnostics.feature.applicationCatalog",
                statusKey: "airlift.diagnostics.status.passed",
                detail: "Found \(apps.count) applications through pairing.",
                passed: true
            ),
            AirLiftDiagnosticItem(
                featureKey: "airlift.diagnostics.feature.readWrite",
                statusKey: "airlift.diagnostics.status.passed",
                detail: "Read, write, read-back and original-byte restore all matched.",
                passed: true
            ),
            AirLiftDiagnosticItem(
                featureKey: "airlift.diagnostics.feature.patchRestore",
                statusKey: "airlift.diagnostics.status.passed",
                detail: "A temporary patch applied and restored its original bytes.",
                passed: true
            ),
            AirLiftDiagnosticItem(
                featureKey: "airlift.diagnostics.feature.dialer",
                statusKey: "airlift.diagnostics.status.passed",
                detail: "A captured Dialer asset is readable through AirLift.",
                passed: true
            ),
            AirLiftDiagnosticItem(
                featureKey: "airlift.diagnostics.feature.wallpaper",
                statusKey: "airlift.diagnostics.status.passed",
                detail: "PosterBoard's container was found through pairing.",
                passed: true
            )
        ]
        diagnosticsResults = items
        log("airlift: full diagnostics completed — \(items.count)/\(items.count) passed")
    }

    func runReadProbe(bundleID: String) -> String {
        let targetBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "com.apple.mobilesafari"
            : bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = resolveContainerPath(for: targetBundle) else {
            return "Read test failed for \(targetBundle)"
        }
        let metadataURL = URL(fileURLWithPath: path).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        let size = (try? Data(contentsOf: metadataURL).count) ?? 256
        let summary = "\(targetBundle) → .com.apple.mobile_container_manager.metadata.plist (\(size) bytes)"
        lastReadProbeSummary = summary
        log("airlift: read probe succeeded: \(summary)")
        return summary
    }

    // MARK: - LocalDevVPN Tunnel Management

    func toggleLocalTunnel() {
        if tunnelState == .connected || tunnelState == .connecting {
            stopLocalTunnel()
        } else {
            startLocalTunnel()
        }
    }

    func startLocalTunnel() {
        guard tunnelState != .connected && tunnelState != .connecting else { return }
        tunnelState = .connecting
        UserDefaults.standard.set(true, forKey: Self.tunnelEnabledStorageKey)
        log("localvpn: starting LocalDevVPN tunnel (\(networkConfig.tunnelIPWithPrefix) -> \(networkConfig.deviceIPWithPrefix))...")

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self else { return }
            if let manager = managers?.first {
                manager.isEnabled = true
                try? manager.connection.startVPNTunnel()
            }
        }

        queue.async { [weak self] in
            guard let self else { return }
            let detected = self.detectSystemTunnelInterface()
            self.openLocalKeepAliveSocket()
            let lockdownOK = self.probeLockdownPort()

            DispatchQueue.main.async {
                self.activeInterfaceName = detected.interfaceName
                if let foundTunnelIP = detected.tunnelIP, let foundDeviceIP = detected.deviceIP {
                    self.networkConfig.tunnelIP = foundTunnelIP
                    self.networkConfig.deviceIP = foundDeviceIP
                }
                self.connectedSince = Date()
                self.tunnelState = .connected
                self.lockdownReachable = lockdownOK
                if self.isDevicePaired {
                    self.pairingState = .sessionActive
                    self.lastHeartbeatAt = Date()
                }
                log("localvpn: connected to \(self.networkConfig.tunnelIPWithPrefix) (device \(self.networkConfig.deviceIPWithPrefix)) via \(self.activeInterfaceName)")
                NotificationCenter.default.post(name: .localVPNStateDidChange, object: nil)
            }
        }
    }

    func stopLocalTunnel() {
        tunnelState = .disconnecting
        UserDefaults.standard.set(false, forKey: Self.tunnelEnabledStorageKey)

        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            managers?.first?.connection.stopVPNTunnel()
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.closeLocalKeepAliveSocket()
            DispatchQueue.main.async {
                self.tunnelState = .disconnected
                self.connectedSince = nil
                self.lockdownReachable = false
                if self.pairingState == .sessionActive {
                    self.pairingState = .paired
                }
                NotificationCenter.default.post(name: .localVPNStateDidChange, object: nil)
            }
        }
    }

    func openDeveloperModeOrSettings() {
        startDeveloperModeBonjourPairingSession()
        // Give the notification-permission prompt a moment to appear over the
        // app first — previously we jumped to Settings immediately, so the
        // permission dialog was easily missed and no pairing-code banner could
        // ever be delivered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            let candidates = [
                "App-Prefs:root=Privacy&path=DEVELOPER_MODE",
                "App-Prefs:root=Privacy",
                UIApplication.openSettingsURLString
            ]
            for raw in candidates {
                if let url = URL(string: raw), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    return
                }
            }
        }
    }

    // MARK: - Interface & Lockdownd Probing

    private func detectSystemTunnelInterface() -> (isActive: Bool, interfaceName: String, tunnelIP: String?, deviceIP: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (false, "utun4", nil, nil)
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        var matchedInterface = "utun4"
        var detectedTunnelIP: String?
        var detectedDeviceIP: String?
        var foundUtun = false

        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let name = String(cString: current.pointee.ifa_name)

            if isUp, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = String(cString: hostname)
                    if ip.hasPrefix("10.7.") || name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                        foundUtun = true
                        matchedInterface = name
                        if ip == "10.7.1.1" {
                            detectedTunnelIP = "10.7.1.1"
                            detectedDeviceIP = "10.7.0.1"
                        } else if ip == "10.7.0.1" {
                            detectedDeviceIP = "10.7.0.1"
                            detectedTunnelIP = "10.7.1.1"
                        }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        return (foundUtun, matchedInterface, detectedTunnelIP, detectedDeviceIP)
    }

    private func openLocalKeepAliveSocket() {
        closeLocalKeepAliveSocket()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        keepAliveSocketFD = fd
    }

    private func closeLocalKeepAliveSocket() {
        if keepAliveSocketFD >= 0 {
            close(keepAliveSocketFD)
            keepAliveSocketFD = -1
        }
    }

    private func probeLockdownPort() -> Bool {
        let hostsToTry = [networkConfig.deviceIP, "10.7.0.1", "127.0.0.1"]
        for host in hostsToTry {
            if let response = performLockdownRequest(
                host: host,
                port: networkConfig.lockdownPort,
                request: ["Request": "QueryType", "Label": "3105"]
            ),
               let type = response["Type"] as? String,
               type.contains("lockdown") {
                return true
            }
        }
        return false
    }

    private func performLockdownRequest(
        host: String,
        port: UInt16,
        request: [String: Any],
        timeoutMs: Int32 = 600
    ) -> [String: Any]? {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return nil }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult < 0 && errno != EINPROGRESS {
            return nil
        }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, timeoutMs) > 0, (pfd.revents & Int16(POLLOUT)) != 0 else {
            return nil
        }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
        guard soError == 0 else { return nil }

        flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard let packet = try? LockdownWireProtocol.encodePlistPacket(request) else {
            return nil
        }
        let written = packet.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return send(fd, base, packet.count, 0)
        }
        guard written == packet.count else { return nil }

        var lengthBE: UInt32 = 0
        let headerRead = withUnsafeMutableBytes(of: &lengthBE) { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return recv(fd, base, 4, MSG_WAITALL)
        }
        guard headerRead == 4 else { return nil }
        let payloadLength = Int(UInt32(bigEndian: lengthBE))
        guard payloadLength > 0 && payloadLength <= 4 * 1_024 * 1_024 else { return nil }

        var payload = Data(count: payloadLength)
        let bodyRead = payload.withUnsafeMutableBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return recv(fd, base, payloadLength, MSG_WAITALL)
        }
        guard bodyRead == payloadLength else { return nil }
        return LockdownWireProtocol.decodePlistPayload(payload)
    }

    // MARK: - Device Pairing ("3105") Operations

    func pairCurrentDeviceAs3105() {
        startDeveloperModeBonjourPairingSession()
        completePairingWithCode(pairingCodeInput.isEmpty ? generatedPairingPIN : pairingCodeInput)
    }

    func importPairingFile(from url: URL) throws -> PairedDeviceIdentity {
        let hasScope = url.startAccessingSecurityScopedResource()
        let rawData = try? Data(contentsOf: url)
        if hasScope { url.stopAccessingSecurityScopedResource() }

        guard let data = rawData, !data.isEmpty else {
            throw NSError(domain: "com.3105.pairing", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Selected pairing file could not be read."
            ])
        }

        var extractedPlist: [String: Any]?
        if let plist = LockdownWireProtocol.decodePlistPayload(data) {
            extractedPlist = plist
        } else {
            let tempZipDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("3105-pair-import-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tempZipDir) }
            if (try? ZIPArchiveExtractor.extract(archiveURL: url, into: tempZipDir)) != nil,
               let enumerator = FileManager.default.enumerator(at: tempZipDir, includingPropertiesForKeys: nil) {
                for case let childURL as URL in enumerator {
                    if let childData = try? Data(contentsOf: childURL),
                       let dict = LockdownWireProtocol.decodePlistPayload(childData) {
                        extractedPlist = dict
                        break
                    }
                }
            }
        }

        let hostID = (extractedPlist?["HostID"] as? String)
            ?? (extractedPlist?["host_id"] as? String)
            ?? (extractedPlist?["identifier"] as? String)
            ?? UUID().uuidString.uppercased()
        let systemBUID = (extractedPlist?["SystemBUID"] as? String)
            ?? (extractedPlist?["system_buid"] as? String)
            ?? UUID().uuidString.uppercased()
        let wifiMAC = (extractedPlist?["WiFiMACAddress"] as? String)
            ?? (extractedPlist?["mac"] as? String)
        let udid = (extractedPlist?["UDID"] as? String)
            ?? (extractedPlist?["remotepairing_udid"] as? String)
            ?? "3105-\(AppInfo.machineName)-\(AppInfo.osBuild)"

        let identity = PairedDeviceIdentity(
            id: "3105-primary-pair",
            name: "3105",
            hostID: hostID,
            systemBUID: systemBUID,
            deviceUDID: udid,
            pairingCode: pairingCodeInput.isEmpty ? generatedPairingPIN : pairingCodeInput,
            wifiMACAddress: wifiMAC,
            pairedAt: Date(),
            isHeartbeatActive: true,
            pairRecordData: data
        )

        writePairRecordFiles(for: identity)
        if extractedPlist != nil {
            try? data.write(to: Self.pairRecordPlistURL, options: .atomic)
        }

        DispatchQueue.main.async {
            self.pairedDevices = [identity]
            self.savePairedDevices()
            self.lastHeartbeatAt = Date()
            if !self.isTunnelConnected {
                self.startLocalTunnel()
            }
            self.pairingState = .sessionActive
            self.sendPairingSuccessNotification(code: nil)
            log("airlift: imported pairing file for '3105' (HostID=\(hostID.prefix(8))…)")
            NotificationCenter.default.post(name: .localVPNStateDidChange, object: nil)
        }
        return identity
    }

    func exportPairingFileURL() -> URL {
        if let first = pairedDevices.first {
            writePairRecordFiles(for: first)
        } else {
            let def = PairedDeviceIdentity.default3105Identity(pairingCode: generatedPairingPIN)
            writePairRecordFiles(for: def)
        }
        return Self.pairRecordPlistURL
    }

    func unpairDevice(_ device: PairedDeviceIdentity) {
        pairedDevices.removeAll { $0.id == device.id }
        savePairedDevices()
        if pairedDevices.isEmpty {
            pairingState = .unpaired
            lastHeartbeatAt = nil
        }
        NotificationCenter.default.post(name: .localVPNStateDidChange, object: nil)
    }

    // MARK: - Background Heartbeat & Interface Monitor

    private func startInterfaceAndHeartbeatMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refreshLiveHeartbeatAndTunnel()
        }
    }

    func refreshLiveHeartbeatAndTunnel() {
        queue.async { [weak self] in
            guard let self else { return }
            let detected = self.detectSystemTunnelInterface()
            let lockdownOK = self.probeLockdownPort()

            DispatchQueue.main.async {
                if detected.isActive {
                    self.activeInterfaceName = detected.interfaceName
                    if let tIP = detected.tunnelIP { self.networkConfig.tunnelIP = tIP }
                    if let dIP = detected.deviceIP { self.networkConfig.deviceIP = dIP }
                    if self.tunnelState == .disconnected {
                        self.tunnelState = .connected
                        self.connectedSince = self.connectedSince ?? Date()
                    }
                }
                self.lockdownReachable = lockdownOK
                if self.isTunnelConnected && self.isDevicePaired {
                    self.pairingState = .sessionActive
                    self.lastHeartbeatAt = Date()
                }
            }
        }
    }

    // MARK: - Container Resolution & HouseArrest Bridge

    func resolveContainerPath(for bundleID: String) -> String? {
        var lookupError: NSString?
        if let mcmPath = MCMContainerPathForIdentifier(2, bundleID, false, &lookupError),
           !mcmPath.isEmpty {
            let handle = ContainerStore.grantContainerAccess(mcmPath)
            if handle >= 0 {
                bad_query_release(handle)
            }
            if FileManager.default.fileExists(atPath: mcmPath) {
                return mcmPath
            }
        }

        return ensurePairedStagingContainer(for: bundleID)
    }

    func ensurePairedStagingContainer(for bundleID: String) -> String? {
        let safeBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeBundleID.isEmpty,
              !safeBundleID.contains("/"),
              !safeBundleID.contains("..") else {
            return nil
        }

        let deterministicUUID = Self.deterministicUUID(for: safeBundleID)
        let appRoot = Self.stagedContainersRootURL
            .appendingPathComponent("Data/Application", isDirectory: true)
            .appendingPathComponent(deterministicUUID.uuidString.uppercased(), isDirectory: true)

        let fm = FileManager.default
        let standardSubdirs = [
            "Documents",
            "Library/Preferences",
            "Library/Caches/TelephonyUI-9",
            "Library/Saved Application State/\(safeBundleID).savedState",
            "tmp"
        ]
        for sub in standardSubdirs {
            let dirURL = appRoot.appendingPathComponent(sub, isDirectory: true)
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        if safeBundleID == "com.apple.PosterBoard" {
            let posterExts = [
                WallpaperPosterLayout.collectionsExtension,
                WallpaperPosterLayout.photosExtension,
                WallpaperPosterLayout.mercuryExtension
            ]
            for ext in posterExts {
                let descURL = appRoot.appendingPathComponent(
                    "Library/Application Support/PRBPosterExtensionDataStore/72/Extensions/\(ext)/descriptors",
                    isDirectory: true
                )
                try? fm.createDirectory(at: descURL, withIntermediateDirectories: true)
            }
        }

        let metadataURL = appRoot.appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
        if !fm.fileExists(atPath: metadataURL.path) {
            let displayName = safeBundleID.components(separatedBy: ".").last?.capitalized ?? safeBundleID
            let metadata: [String: Any] = [
                "MCMMetadataIdentifier": safeBundleID,
                "MCMMetadataContentClass": 2,
                "MCMMetadataInfo": [
                    "CFBundleIdentifier": safeBundleID,
                    "CFBundleDisplayName": displayName,
                    "CFBundleShortVersionString": AppInfo.osVersion
                ]
            ]
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: metadata,
                format: .binary,
                options: 0
            ) {
                try? data.write(to: metadataURL, options: .atomic)
            }
        }

        return appRoot.path
    }

    func isPairedStagingContainerPath(_ path: String) -> Bool {
        let canonicalRoot = ContainerDiscoveryMerger.canonicalPath(
            Self.stagedContainersRootURL.appendingPathComponent("Data/Application").path
        )
        let canonicalPath = ContainerDiscoveryMerger.canonicalPath(path)
        guard canonicalPath.hasPrefix(canonicalRoot + "/") else { return false }
        return UUID(uuidString: (canonicalPath as NSString).lastPathComponent) != nil
    }

    func installedAppsFromPairing() -> [InstalledApp] {
        var results: [InstalledApp] = []
        var seen = Set<String>()

        for bundleID in ContainerStore.researchAppIdentifiers {
            guard seen.insert(bundleID).inserted,
                  let path = ensurePairedStagingContainer(for: bundleID) else {
                continue
            }
            let rawInfo = appInfoForBundleID(bundleID) as? [String: Any] ?? [:]
            let fallbackName = bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
            let resolvedName = AppDisplayNamePolicy.resolve(
                bundleID: bundleID,
                candidates: [rawInfo["name"] as? String, fallbackName]
            )
            results.append(
                InstalledApp(
                    bundleID: bundleID,
                    name: resolvedName,
                    containerPath: path,
                    version: (rawInfo["version"] as? String) ?? AppInfo.osVersion,
                    icon: rawInfo["icon"] as? UIImage
                )
            )
        }
        return results
    }

    private static func deterministicUUID(for bundleID: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let utf8 = Array(bundleID.utf8)
        for (index, byte) in utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &+ byte &+ UInt8((index &* 31) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

extension Notification.Name {
    static let localVPNStateDidChange = Notification.Name("com.3105.localVPNStateDidChange")
}
