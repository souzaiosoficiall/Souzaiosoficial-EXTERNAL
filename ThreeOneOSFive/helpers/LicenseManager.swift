import Combine
import Foundation
import Security
import UIKit

@MainActor
final class LicenseManager: ObservableObject {
    private static let apiBase = URL(string: "https://souzakeys.duckdns.org")!
    private static let service = "com.Souzaiosoficial.external-ios.license"
    private static let keyAccount = "license-key"
    private static let expirationAccount = "license-expiration"
    private static let deviceAccount = "license-device"

    @Published private(set) var expirationDate: Date?
    @Published private(set) var isActive = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var contactOwner: String? = "https://wa.me/5527997306436"
    @Published private(set) var approvalCountdown = 0
    @Published private(set) var isApproving = false
    @Published var rememberKey = true

    private var monitorTask: Task<Void, Never>?
    private var approvalTask: Task<Void, Never>?
    private var lastAttemptAt: Date?
    private var sessionKey: String?

    init() {
        loadCachedLicense()
    }

    deinit {
        monitorTask?.cancel()
        approvalTask?.cancel()
    }

    var licenseKey: String? { sessionKey ?? rememberedKey() }

    var formattedExpiration: String {
        guard let expirationDate else { return "Indeterminada" }
        return expirationDate.formatted(date: .abbreviated, time: .shortened)
    }

    func beginLaunchSession() {
        loadCachedLicense()
        startMonitoring()
        guard let key = rememberedKey(), !key.isEmpty else {
            isActive = false
            message = "Chave necessária — insira sua chave de acesso"
            return
        }

        if isExpired {
            invalidateLocalLicense(message: "Sua licença expirou")
        } else {
            sessionKey = key
            isActive = true
            message = "Acesso liberado"
            checkWithServer(key: key, showBusy: false)
        }
    }

    func activate(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        guard lastAttemptAt.map({ Date().timeIntervalSince($0) >= 1 }) ?? true else {
            message = "Aguarde um instante antes de tentar novamente"
            return
        }

        lastAttemptAt = Date()
        isBusy = true
        message = "Verificando sua chave…"
        request(path: "/validar", key: trimmed) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let payload) where payload.status == "sucesso":
                let expiration = payload.expirationTimestamp > 0
                    ? Date(timeIntervalSince1970: payload.expirationTimestamp)
                    : nil
                self.sessionKey = trimmed
                self.saveLicense(key: trimmed, expiration: expiration)
                self.expirationDate = expiration
                self.message = "Chave validada com sucesso"
                self.startApprovalAnimation()
            case .success(let payload):
                self.isBusy = false
                self.invalidateLocalLicense(message: payload.message ?? "Chave inválida")
            case .failure(let error):
                self.isBusy = false
                self.isActive = false
                self.message = error.localizedDescription
            }
        }
    }

    func rememberedKey() -> String? {
        string(for: Self.keyAccount)
    }

    func refresh() {
        beginLaunchSession()
    }

    func deactivate() {
        approvalTask?.cancel()
        sessionKey = nil
        approvalCountdown = 0
        isApproving = false
        delete(Self.keyAccount)
        delete(Self.expirationAccount)
        delete(Self.deviceAccount)
        expirationDate = nil
        isActive = false
        isBusy = false
        message = "Ativação removida deste dispositivo"
    }

    private var isExpired: Bool {
        guard let expirationDate else { return false }
        return Date() >= expirationDate
    }

    private func startApprovalAnimation() {
        approvalTask?.cancel()
        isApproving = true
        isActive = false
        approvalCountdown = 7
        approvalTask = Task { [weak self] in
            for remaining in stride(from: 7, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.approvalCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.approvalCountdown = 0
            self.isApproving = false
            self.isBusy = false
            self.isActive = true
            self.message = "Acesso liberado"
            self.startMonitoring()
        }
    }

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self?.performBackgroundCheck()
            }
        }
    }

    private func performBackgroundCheck() {
        guard let key = sessionKey ?? rememberedKey(), !key.isEmpty else {
            invalidateLocalLicense(message: "Chave necessária — insira sua chave de acesso")
            return
        }
        if isExpired {
            invalidateLocalLicense(message: "Sua licença expirou")
            return
        }
        checkWithServer(key: key, showBusy: false)
    }

    private func checkWithServer(key: String, showBusy: Bool) {
        if showBusy { isBusy = true }
        request(path: "/checar", key: key) { [weak self] result in
            guard let self else { return }
            if showBusy { self.isBusy = false }
            switch result {
            case .success(let payload) where payload.status == "valido":
                if payload.expirationTimestamp > 0 {
                    let expiration = Date(timeIntervalSince1970: payload.expirationTimestamp)
                    self.saveExpiration(expiration)
                    self.expirationDate = expiration
                    if Date() >= expiration {
                        self.invalidateLocalLicense(message: "Sua licença expirou")
                    } else {
                        self.isActive = true
                    }
                }
            case .success(let payload) where payload.status == "invalido":
                self.invalidateLocalLicense(message: payload.message ?? "Licença inválida ou revogada")
            case .failure:
                // Mantém o acesso em cache até a expiração para evitar bloqueios por falhas transitórias.
                if self.isExpired { self.invalidateLocalLicense(message: "Sua licença expirou") }
            default:
                break
            }
        }
    }

    private func request(path: String, key: String, completion: @escaping (Result<LicensePayload, Error>) -> Void) {
        guard var components = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            completion(.failure(LicenseError.invalidURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "udid", value: deviceIdentifier)
        ]
        guard let url = components.url else {
            completion(.failure(LicenseError.invalidURL))
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Souzaiosoficial-EXTERNAL/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Task { @MainActor in completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                Task { @MainActor in completion(.failure(LicenseError.serverUnavailable)) }
                return
            }
            do {
                let payload = try JSONDecoder().decode(LicensePayload.self, from: data)
                Task { @MainActor in completion(.success(payload)) }
            } catch {
                Task { @MainActor in completion(.failure(error)) }
            }
        }.resume()
    }

    private var deviceIdentifier: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }

    private func loadCachedLicense() {
        expirationDate = double(for: Self.expirationAccount).map(Date.init(timeIntervalSince1970:))
        let hasKey = rememberedKey()?.isEmpty == false
        isActive = hasKey && !isExpired
    }

    private func saveLicense(key: String, expiration: Date?) {
        guard rememberKey else {
            delete(Self.keyAccount)
            delete(Self.expirationAccount)
            return
        }
        save(key, for: Self.keyAccount)
        save(deviceIdentifier, for: Self.deviceAccount)
        if let expiration { save(expiration.timeIntervalSince1970, for: Self.expirationAccount) }
    }

    private func saveExpiration(_ expiration: Date) {
        save(expiration.timeIntervalSince1970, for: Self.expirationAccount)
    }

    private func invalidateLocalLicense(message: String) {
        approvalTask?.cancel()
        sessionKey = nil
        isApproving = false
        approvalCountdown = 0
        isActive = false
        expirationDate = nil
        delete(Self.keyAccount)
        delete(Self.expirationAccount)
        self.message = message
    }

    private func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func double(for account: String) -> Double? {
        guard let value = string(for: account) else { return nil }
        return Double(value)
    }

    private func save(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func save(_ value: Double, for account: String) {
        save(String(value), for: account)
    }

    private func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private struct LicensePayload: Decodable {
        let status: String?
        let message: String?
        let expirationTimestamp: Double

        enum CodingKeys: String, CodingKey {
            case status
            case message = "mensagem"
            case expirationTimestamp = "expira_timestamp"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            if let number = try? container.decode(Double.self, forKey: .expirationTimestamp) {
                expirationTimestamp = number
            } else if let string = try? container.decode(String.self, forKey: .expirationTimestamp), let number = Double(string) {
                expirationTimestamp = number
            } else {
                expirationTimestamp = 0
            }
        }
    }

    private enum LicenseError: LocalizedError {
        case invalidURL
        case serverUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Não foi possível preparar a validação"
            case .serverUnavailable: return "Servidor de licença indisponível"
            }
        }
    }
}
