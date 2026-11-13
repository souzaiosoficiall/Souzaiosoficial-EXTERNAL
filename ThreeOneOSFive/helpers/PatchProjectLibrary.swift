import Foundation

struct PatchLibraryItem: Identifiable {
    let summary: PatchPackageSummary
    var project: PatchProject?
    var contentKey: Data?
    var packageURL: URL
    let isAuthorCopy: Bool
    let origin: PatchPackageOrigin?

    var id: UUID { summary.packageID }
    var isLocked: Bool { project == nil }
    var canInspectContents: Bool {
        guard let project else { return false }
        return PatchProjectAccessPolicy.canInspectContents(
            project: project,
            isAuthorCopy: isAuthorCopy
        )
    }
    var workspaceURL: URL? {
        guard canInspectContents else { return nil }
        return PatchWorkspaceService.workspaceURL(projectID: id)
    }
}

struct PatchPasswordRequest: Identifiable {
    let summary: PatchPackageSummary
    let origin: PatchPackageOrigin?
    var id: UUID { summary.packageID }

    init(summary: PatchPackageSummary, origin: PatchPackageOrigin? = nil) {
        self.summary = summary
        self.origin = origin
    }
}

enum PatchProjectLibrary {
    private static let authorCopiesDirectoryName = ".AuthorCopies"
    private static let originsDirectoryName = ".Origins"
    private static let bundledResourcePassword = "3105"

    static func installBundledPackagesIfNeeded(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        guard let root = try? packageRootURL(fileManager: fileManager) else { return }

        let nested = bundle.urls(forResourcesWithExtension: "3105", subdirectory: "Patches") ?? []
        let flattened = bundle.urls(forResourcesWithExtension: "3105", subdirectory: nil) ?? []
        var seen = Set<String>()
        let resources = (nested + flattened).filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }

        for sourceURL in resources {
            let destinationURL = root.appendingPathComponent(sourceURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            do {
                let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                _ = try PatchPackageCodec.inspect(data)
                try data.write(to: destinationURL, options: [.atomic, .completeFileProtection])
                log("patch: installed bundled package \(sourceURL.lastPathComponent)")
            } catch {
                log("patch: skipped bundled package \(sourceURL.lastPathComponent): \(error)")
            }
        }
    }

    static func packageRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("PatchProjects", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func backupRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func load(fileManager: FileManager = .default) -> [PatchLibraryItem] {
        guard let root = try? packageRootURL(fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else { return [] }

        var byID: [UUID: PatchLibraryItem] = [:]
        for url in urls where url.pathExtension.lowercased() == "3105" {
            do {
                let data = try readPackage(at: url)
                let summary = try PatchPackageCodec.inspect(data)
                let decoded: DecodedPatchPackage?
                let storedContentKey = (try? PatchKeyStore.load(for: summary)) ?? nil
                if let storedContentKey,
                   let storedDecode = try? PatchPackageCodec.decode(data, contentKey: storedContentKey) {
                    decoded = storedDecode
                } else if summary.isPasswordProtected {
                    let filename = url.deletingPathExtension().lastPathComponent.lowercased()
                    let bundledNames: Set<String> = [
                        "pescoco", "peito", "pscant", "ptatn", "holograma"
                    ]
                    let isBundledPackage = bundledNames.contains(filename)
                        || filename.hasPrefix("souzaiosoficial")
                    if isBundledPackage {
                        do {
                            let bundled = try PatchPackageCodec.decode(
                                data,
                                password: bundledResourcePassword
                            )
                            try PatchKeyStore.store(bundled.contentKey, for: summary)
                            decoded = bundled
                        } catch {
                            decoded = nil
                            log("patch: bundled package unlock failed for \(url.lastPathComponent): \(error)")
                        }
                    } else {
                        decoded = nil
                    }
                } else {
                    decoded = try PatchPackageCodec.decode(data, password: nil)
                }
                let isAuthorCopy = isAuthorCopy(
                    packageID: summary.packageID,
                    fileManager: fileManager
                )
                let item = PatchLibraryItem(
                    summary: summary,
                    project: decoded?.project,
                    contentKey: decoded?.contentKey,
                    packageURL: url,
                    isAuthorCopy: isAuthorCopy,
                    origin: loadOrigin(
                        packageID: summary.packageID,
                        fileManager: fileManager
                    )
                )
                if summary.schemaVersion >= 2, let project = decoded?.project {
                    if PatchProjectAccessPolicy.shouldMaterializeWorkspace(
                        project: project,
                        isAuthorCopy: isAuthorCopy
                    ) {
                        do {
                            _ = try PatchWorkspaceService.ensureWorkspace(for: project)
                        } catch {
                            log("patch: workspace unavailable for \(project.id.uuidString): \(error)")
                        }
                    } else {
                        try? PatchWorkspaceService.deleteWorkspace(
                            projectID: project.id,
                            fileManager: fileManager
                        )
                    }
                }
                byID[summary.packageID] = item
            } catch {
                log("patch: skipped invalid local package \(url.lastPathComponent): \(error)")
            }
        }
        return byID.values.sorted {
            ($0.project?.updatedAt ?? .distantPast) > ($1.project?.updatedAt ?? .distantPast)
        }
    }

    static func readPackage(at url: URL) throws -> Data {
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty {
            return data
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isDirectory != true,
              values.isSymbolicLink != true else {
            throw PatchPackageError.invalidProject
        }
        return try Data(contentsOf: url)
    }

    static func save(
        data: Data,
        projectName: String,
        existingURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination: URL
        if let existingURL {
            destination = existingURL
        } else {
            let root = try packageRootURL(fileManager: fileManager)
            let baseName = sanitizedFilename(projectName)
            var candidate = root.appendingPathComponent(baseName).appendingPathExtension("3105")
            var suffix = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = root.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension("3105")
                suffix += 1
            }
            destination = candidate
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func markAsAuthorCopy(
        packageID: UUID,
        fileManager: FileManager = .default
    ) throws {
        let root = try authorCopiesRootURL(fileManager: fileManager)
        try Data().write(
            to: root.appendingPathComponent(packageID.uuidString),
            options: .atomic
        )
    }

    static func isAuthorCopy(
        packageID: UUID,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let root = try? authorCopiesRootURL(fileManager: fileManager) else {
            return false
        }
        return fileManager.fileExists(
            atPath: root.appendingPathComponent(packageID.uuidString).path
        )
    }

    static func overlappingTargetPath(
        in project: PatchProject,
        excludingPackageID: UUID,
        fileManager: FileManager = .default
    ) -> String? {
        var occupied = Set<String>()
        for item in load(fileManager: fileManager) where item.id != excludingPackageID {
            guard let other = item.project else { continue }
            for rule in other.rules {
                occupied.insert(rule.bundleID + "\0" + rule.relativePath)
            }
        }
        for rule in project.rules {
            let key = rule.bundleID + "\0" + rule.relativePath
            if occupied.contains(key) {
                return rule.bundleID + "/" + rule.relativePath
            }
        }
        return nil
    }

    static func installImportedPackage(
        data: Data,
        decoded: DecodedPatchPackage,
        summary: PatchPackageSummary,
        existingURL: URL?,
        origin: PatchPackageOrigin? = nil,
        fileManager: FileManager = .default
    ) throws {
        let authorCopy = isAuthorCopy(
            packageID: summary.packageID,
            fileManager: fileManager
        )
        let previousData = try existingURL.map { try readPackage(at: $0) }
        let originURL = try originFileURL(
            packageID: summary.packageID,
            fileManager: fileManager
        )
        let previousOriginData = try? Data(contentsOf: originURL)
        var savedURL: URL?
        do {
            if let origin {
                try saveOrigin(origin, to: originURL)
            }
            try? PatchKeyStore.store(decoded.contentKey, for: summary)
            savedURL = try save(
                data: data,
                projectName: decoded.project.name,
                existingURL: existingURL,
                fileManager: fileManager
            )
            if summary.schemaVersion >= 2 {
                if PatchProjectAccessPolicy.shouldMaterializeWorkspace(
                    project: decoded.project,
                    isAuthorCopy: authorCopy
                ) {
                    _ = try PatchWorkspaceService.replaceWorkspace(
                        with: decoded.project,
                        fileManager: fileManager
                    )
                } else {
                    try PatchWorkspaceService.deleteWorkspace(
                        projectID: decoded.project.id,
                        fileManager: fileManager
                    )
                }
            } else {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            }
        } catch {
            if let previousData, let existingURL {
                try? previousData.write(
                    to: existingURL,
                    options: .atomic
                )
            } else if let savedURL, fileManager.fileExists(atPath: savedURL.path) {
                try? fileManager.removeItem(at: savedURL)
            }
            if let previousOriginData {
                try? previousOriginData.write(
                    to: originURL,
                    options: .atomic
                )
            } else if origin != nil, fileManager.fileExists(atPath: originURL.path) {
                try? fileManager.removeItem(at: originURL)
            }
            throw error
        }
    }

    static func delete(_ item: PatchLibraryItem, fileManager: FileManager = .default) throws {
        let backupRoot = try backupRootURL(fileManager: fileManager)
        guard PatchTransaction.latestReceipt(
            projectID: item.id,
            backupRoot: backupRoot,
            fileManager: fileManager
        ) == nil else {
            throw PatchPackageError.activePatchCannotBeDeleted
        }
        if fileManager.fileExists(atPath: item.packageURL.path) {
            try fileManager.removeItem(at: item.packageURL)
        }
        try? PatchWorkspaceService.deleteWorkspace(projectID: item.id, fileManager: fileManager)
        try? PatchKeyStore.delete(for: item.summary)
        if let originURL = try? originFileURL(
            packageID: item.id,
            fileManager: fileManager
        ), fileManager.fileExists(atPath: originURL.path) {
            try? fileManager.removeItem(at: originURL)
        }
        if let marker = try? authorCopyMarkerURL(
            packageID: item.id,
            fileManager: fileManager
        ), fileManager.fileExists(atPath: marker.path) {
            try? fileManager.removeItem(at: marker)
        }
    }

    static func synchronizeWorkspace(
        item: PatchLibraryItem,
        fileManager: FileManager = .default
    ) throws -> PatchProject {
        guard item.summary.schemaVersion >= 2,
              item.canInspectContents,
              let baseProject = item.project,
              let contentKey = item.contentKey else {
            throw PatchPackageError.invalidProject
        }
        let workspace = try PatchWorkspaceService.ensureWorkspace(
            for: baseProject,
            fileManager: fileManager
        )
        let project = try PatchWorkspaceService.snapshot(
            baseProject: baseProject,
            workspaceURL: workspace,
            fileManager: fileManager
        )
        let original = try readPackage(at: item.packageURL)
        let updated = try PatchPackageCodec.update(
            original,
            project: project,
            contentKey: contentKey,
            schemaVersion: PatchPackageCodec.latestSchemaVersion
        )
        _ = try save(
            data: updated,
            projectName: project.name,
            existingURL: item.packageURL,
            fileManager: fileManager
        )
        return project
    }

    private static func sanitizedFilename(_ rawName: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let scalars = rawName.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }
        let result = scalars.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return result.isEmpty ? "Patch-\(UUID().uuidString.prefix(6))" : String(result)
    }

    private static func authorCopiesRootURL(
        fileManager: FileManager
    ) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent(authorCopiesDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func authorCopyMarkerURL(
        packageID: UUID,
        fileManager: FileManager
    ) throws -> URL {
        try authorCopiesRootURL(fileManager: fileManager)
            .appendingPathComponent(packageID.uuidString)
    }

    private static func originsRootURL(fileManager: FileManager) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent(originsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func originFileURL(
        packageID: UUID,
        fileManager: FileManager
    ) throws -> URL {
        try originsRootURL(fileManager: fileManager)
            .appendingPathComponent(packageID.uuidString)
            .appendingPathExtension("plist")
    }

    private static func loadOrigin(
        packageID: UUID,
        fileManager: FileManager
    ) -> PatchPackageOrigin? {
        guard let url = try? originFileURL(
            packageID: packageID,
            fileManager: fileManager
        ), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListDecoder().decode(PatchPackageOrigin.self, from: data)
    }

    private static func saveOrigin(
        _ origin: PatchPackageOrigin,
        to url: URL
    ) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(origin).write(
            to: url,
            options: .atomic
        )
    }
}
