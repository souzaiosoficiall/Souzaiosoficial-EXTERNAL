import CryptoKit
import Foundation
import Security

enum PatchKeyStore {
    private static let service = "com.apple.mobile.MobileHouseArrest.patch-keys"

    private static var fallbackDirectoryURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base
            .appendingPathComponent("PatchProjects", isDirectory: true)
            .appendingPathComponent(".KeyStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fallbackFileURL(for account: String) -> URL {
        fallbackDirectoryURL.appendingPathComponent(account + ".key", isDirectory: false)
    }

    static func account(for summary: PatchPackageSummary) -> String {
        let fingerprint = summary.keyFingerprint.map { String(format: "%02x", $0) }.joined()
        return "\(summary.packageID.uuidString).\(fingerprint)"
    }

    static func store(_ contentKey: Data, for summary: PatchPackageSummary) throws {
        guard contentKey.count == 32,
              Data(SHA256.hash(data: contentKey)) == summary.keyFingerprint else {
            throw PatchPackageError.keychainFailed
        }
        let account = account(for: summary)

        // 1. Always persist to fallback local keystore so sideloaded / unsigned-then-signed IPAs
        //    without keychain-access-groups entitlements never fail with errSecMissingEntitlement (-34018).
        let fileURL = fallbackFileURL(for: account)
        try? contentKey.write(to: fileURL, options: .atomic)

        // 2. Also attempt Keychain storage when entitlements permit it.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: contentKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var newItem = query
            attributes.forEach { newItem[$0.key] = $0.value }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            if addStatus == errSecSuccess { return }
        }

        // Verify fallback file succeeded if Keychain was unavailable
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PatchPackageError.keychainFailed
        }
    }

    static func load(for summary: PatchPackageSummary) throws -> Data? {
        let account = account(for: summary)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           data.count == 32,
           Data(SHA256.hash(data: data)) == summary.keyFingerprint {
            return data
        }

        // Fallback to local keystore file (handles errSecMissingEntitlement -34018 on sideloaded IPAs)
        let fileURL = fallbackFileURL(for: account)
        if let data = try? Data(contentsOf: fileURL),
           data.count == 32,
           Data(SHA256.hash(data: data)) == summary.keyFingerprint {
            return data
        }

        return nil
    }

    static func delete(for summary: PatchPackageSummary) throws {
        let account = account(for: summary)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
        let fileURL = fallbackFileURL(for: account)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
