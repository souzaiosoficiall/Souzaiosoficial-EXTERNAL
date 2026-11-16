import Foundation

enum AccessRouteKind: String, CaseIterable {
    case airLift = "AirLift"
    case worseQuery = "worse_query"
    case badQuery = "bad_query"
    case kernel = "Kernel"
}

enum ExploitSupportPolicy {
    static let verifiedIOS17Range = "17.0–17.7.x (Kernel / AirLift)"
    static let verifiedIOS18Range = "18.0–18.7.10 (Kernel / AirLift)"
    static let verifiedIOS26Range = "26.0–26.7.2 (bad_query / worse_query / AirLift)"
    static let verifiedIOS27Range = "27.0–27.2+ Official & Beta (worse_query / AirLift)"

    static let verifiedIOS27Builds: [(beta: Int, publicBeta: Int?, build: String)] = [
        (1, nil, "24A5355q"),
        (2, nil, "24A5370h"),
        (3, 1, "24A5380h"),
        (4, 2, "24A5390f"),
        (5, 3, "24B119")
    ]

    static var isPairingAndLocalVPNEnabled: Bool {
        if UserDefaults.standard.object(forKey: LocalVPNPairingManager.universalIOS27SupportKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: LocalVPNPairingManager.universalIOS27SupportKey)
    }

    static var isRepoIOSUnlockEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "repository.ios_unlock") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "repository.ios_unlock")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "repository.ios_unlock")
            log("repository.ios_unlock enabled=\(newValue)")
        }
    }

    static func activeAccessRoute(major: Int, minor: Int, patch: Int) -> AccessRouteKind {
        if LocalVPNPairingManager.shared.useAirLiftForEverything && LocalVPNPairingManager.shared.isDevicePaired {
            return .airLift
        }
        if supportsKernelExploit(major: major, minor: minor, patch: patch) {
            return .kernel
        }
        if major == 26 && (minor > 6 || (minor == 6 && patch >= 2)) {
            return WorseQueryService.hasAppGroupEntitlement ? .worseQuery : .airLift
        }
        if major >= 27 {
            return WorseQueryService.hasAppGroupEntitlement ? .worseQuery : .airLift
        }
        if major == 26 {
            return .badQuery
        }
        return .airLift
    }

    static func iOS27BetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.beta
    }

    static func iOS27PublicBetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.publicBeta
    }

    static func supportsKernelExploit(major: Int, minor: Int, patch: Int) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }

        if major == 17 {
            return minor <= 7
        }

        if major == 18 {
            return minor < 7 || (minor == 7 && patch <= 1)
        }

        return false
    }

    static func supportsLocalVPNPairing(major: Int, minor: Int, patch: Int) -> Bool {
        guard major >= 16, minor >= 0, patch >= 0 else { return false }
        return isPairingAndLocalVPNEnabled
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        if supportsLocalVPNPairing(major: major, minor: minor, patch: patch) {
            return true
        }
        if supportsKernelExploit(major: major, minor: minor, patch: patch) {
            return true
        }
        if major >= 26 {
            return true
        }
        return false
    }
}
