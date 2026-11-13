import Foundation

enum ExploitSupportPolicy {
    static let verifiedIOS26Range = "26.0–26.7.2"
    static let verifiedIOS27Range = "27.0–27.2"

    // Only kept for early 27 beta build matching if needed
    static let verifiedIOS27Builds: [(beta: Int, publicBeta: Int?, build: String)] = [
        (1, nil, "24A5355q"),
        (2, nil, "24A5370h"),
        (3, 1, "24A5380h"),
        (4, 2, "24A5390f")
    ]

    static func iOS27BetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.beta
    }

    static func iOS27PublicBetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.publicBeta
    }

    // Kernel exploit (17/18) is DISABLED. Only worse_query path on 26/27.
    static func supportsKernelExploit(major: Int, minor: Int, patch: Int) -> Bool {
        return false
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        if major == 26 {
            guard minor >= 0, patch >= 0 else { return false }
            // worse_query: 26.0 – 26.7.2
            return minor < 7 || (minor == 7 && patch <= 2)
        }

        if major == 27 {
            // worse_query: 27.0 – 27.2
            if minor == 0 && patch == 0 {
                // Accept known early betas by build
                if iOS27BetaNumber(for: build) != nil { return true }
            }
            return minor < 2 || (minor == 2 && patch == 0)
        }

        return false
    }
}
