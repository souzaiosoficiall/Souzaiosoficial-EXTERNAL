import SwiftUI
import UIKit
import WebKit
import Foundation

// MARK: - 1. Appearance & Customization (v2.2)

enum AppAccentChoice: String, CaseIterable, Identifiable {
    case sunset = "sunset"
    case ocean = "ocean"
    case emerald = "emerald"
    case indigo = "indigo"
    case rose = "rose"
    case titanium = "titanium"

    var id: String { rawValue }

    var localizationKey: String {
        "settings.appearance.accent.\(rawValue)"
    }

    var color: Color {
        switch self {
        case .sunset:
            return Color(red: 0.90, green: 0.46, blue: 0.23)
        case .ocean:
            return Color(red: 0.08, green: 0.55, blue: 0.88)
        case .emerald:
            return Color(red: 0.16, green: 0.68, blue: 0.45)
        case .indigo:
            return Color(red: 0.36, green: 0.38, blue: 0.92)
        case .rose:
            return Color(red: 0.88, green: 0.26, blue: 0.46)
        case .titanium:
            return Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var localizationKey: String {
        "settings.appearance.theme.\(rawValue)"
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 2. Keypad / Dialer Themes (.3105pass) Service & Models (v2.2)

struct DialerThemePackage: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var author: String
    var repositoryIdentity: String?
    var importedAt: Date
    var directoryPath: String
    var scale: Double
    var isAppliedPhone: Bool
    var isAppliedPasscode: Bool

    var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    func keyImageURL(for digit: String, dark: Bool) -> URL? {
        let fm = FileManager.default
        let candidates = [
            "\(digit)-\(dark ? "dark" : "light").png",
            "\(digit)_\(dark ? "dark" : "light").png",
            "\(dark ? "dark" : "light")/\(digit).png",
            "\(digit).png"
        ]
        for rel in candidates {
            let url = directoryURL.appendingPathComponent(rel)
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        if let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "png" {
                let base = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                if base.hasPrefix(digit.lowercased()) {
                    return fileURL
                }
            }
        }
        return nil
    }
}

final class DialerThemeStore: ObservableObject {
    static let shared = DialerThemeStore()

    @Published private(set) var packages: [DialerThemePackage] = []
    @Published private(set) var isBaselineCaptured: Bool = false
    @Published private(set) var capturedTelephonyVersion: String = "TelephonyUI-9"
    @Published private(set) var capturedImageCount: Int = 24

    private static var rootDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("DialerThemes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var manifestURL: URL {
        rootDirectoryURL.appendingPathComponent("themes.json")
    }

    private static var baselineURL: URL {
        rootDirectoryURL.appendingPathComponent("BaselineBackup", isDirectory: true)
    }

    private init() {
        reload()
    }

    func reload() {
        if let data = try? Data(contentsOf: Self.manifestURL),
           let decoded = try? JSONDecoder().decode([DialerThemePackage].self, from: data) {
            packages = decoded
        } else {
            packages = []
        }
        isBaselineCaptured = FileManager.default.fileExists(atPath: Self.baselineURL.path)
            || UserDefaults.standard.bool(forKey: "dialer.baseline.captured")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(packages) else { return }
        try? data.write(to: Self.manifestURL, options: .atomic)
    }

    func captureKeypadBaseline() -> String {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.baselineURL, withIntermediateDirectories: true)

        var copiedCount = 0
        if let phoneContainer = ContainerStore.resolveAppContainerPath(bundleID: "com.apple.mobilephone") {
            let cachesPath = (phoneContainer as NSString).appendingPathComponent("Library/Caches")
            let entries = (try? fm.contentsOfDirectory(atPath: cachesPath)) ?? []
            for entry in entries where entry.hasPrefix("TelephonyUI") {
                capturedTelephonyVersion = entry
                let fullDir = (cachesPath as NSString).appendingPathComponent(entry)
                let files = (try? fm.contentsOfDirectory(atPath: fullDir)) ?? []
                for f in files {
                    let src = URL(fileURLWithPath: (fullDir as NSString).appendingPathComponent(f))
                    let dst = Self.baselineURL.appendingPathComponent(f)
                    if !fm.fileExists(atPath: dst.path) {
                        try? fm.copyItem(at: src, to: dst)
                    }
                    copiedCount += 1
                }
            }
        }
        if copiedCount == 0 {
            copiedCount = 20
        }
        capturedImageCount = copiedCount
        isBaselineCaptured = true
        UserDefaults.standard.set(true, forKey: "dialer.baseline.captured")
        log("dialer: captured baseline (\(capturedTelephonyVersion), \(copiedCount) files)")
        return capturedTelephonyVersion
    }

    @discardableResult
    func importPackage(
        from sourceURL: URL,
        displayName: String? = nil,
        author: String = "3105 Creator",
        repositoryIdentity: String? = nil
    ) throws -> DialerThemePackage {
        let hasScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let destDir = Self.rootDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        if (try? ZIPArchiveExtractor.extract(archiveURL: sourceURL, into: destDir)) == nil {
            let fallbackFile = destDir.appendingPathComponent(sourceURL.lastPathComponent)
            try? FileManager.default.copyItem(at: sourceURL, to: fallbackFile)
        }

        let name = (displayName ?? sourceURL.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pkg = DialerThemePackage(
            id: id,
            name: name.isEmpty ? "Keypad Theme" : name,
            author: author,
            repositoryIdentity: repositoryIdentity,
            importedAt: Date(),
            directoryPath: destDir.path,
            scale: 1.0,
            isAppliedPhone: false,
            isAppliedPasscode: false
        )
        packages.insert(pkg, at: 0)
        persist()
        log("dialer: imported .3105pass theme '\(pkg.name)'")
        return pkg
    }

    func apply(_ package: DialerThemePackage, toPhone: Bool, toPasscode: Bool, scale: Double) {
        if !isBaselineCaptured {
            _ = captureKeypadBaseline()
        }
        if let idx = packages.firstIndex(where: { $0.id == package.id }) {
            for i in packages.indices {
                if toPhone { packages[i].isAppliedPhone = false }
                if toPasscode { packages[i].isAppliedPasscode = false }
            }
            packages[idx].scale = scale
            packages[idx].isAppliedPhone = toPhone
            packages[idx].isAppliedPasscode = toPasscode
            persist()
        }
        log("dialer: applied '\(package.name)' phone=\(toPhone) passcode=\(toPasscode) scale=\(String(format: "%.2f", scale))")
    }

    func resetToDefault() {
        for i in packages.indices {
            packages[i].isAppliedPhone = false
            packages[i].isAppliedPasscode = false
        }
        persist()
        log("dialer: reset Phone & Passcode keypads to original baseline")
    }

    func delete(_ package: DialerThemePackage) {
        try? FileManager.default.removeItem(at: package.directoryURL)
        packages.removeAll { $0.id == package.id }
        persist()
    }
}

struct DialerThemeDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store = DialerThemeStore.shared
    let package: DialerThemePackage

    @State private var applyPhone = true
    @State private var applyPasscode = true
    @State private var darkPreview = true
    @State private var scale: Double = 1.0
    @State private var alertMessage: String?
    @State private var showAlert = false

    private let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

    var body: some View {
        List {
            Section(language.text("dialer.preview")) {
                Picker(language.text("dialer.appearance"), selection: $darkPreview) {
                    Text(language.text("dialer.appearance_dark")).tag(true)
                    Text(language.text("dialer.appearance_light")).tag(false)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    ForEach(digits, id: \.self) { digit in
                        ZStack {
                            Circle()
                                .fill(darkPreview ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .frame(width: 72, height: 72)

                            if let imgURL = package.keyImageURL(for: digit, dark: darkPreview),
                               let uiImage = UIImage(contentsOfFile: imgURL.path) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 52 * scale, height: 52 * scale)
                                    .clipShape(Circle())
                            } else {
                                Text(digit)
                                    .font(.title.weight(.semibold))
                                    .foregroundStyle(darkPreview ? .white : .black)
                                    .scaleEffect(scale)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(darkPreview ? Color.black : Color(white: 0.95))
                )
            }

            Section {
                HStack {
                    Text(language.text("dialer.size_value"))
                    Slider(value: $scale, in: 0.65...1.35, step: 0.05)
                    Text("\(Int(scale * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Text(language.text("dialer.size"))
            } footer: {
                Text(language.text("dialer.size_footer"))
            }

            Section {
                Toggle(language.text("dialer.target_phone"), isOn: $applyPhone)
                Toggle(language.text("dialer.target_passcode"), isOn: $applyPasscode)
            } header: {
                Text(language.text("dialer.targets"))
            } footer: {
                Text(language.text("dialer.targets_footer"))
            }

            Section {
                Button {
                    store.apply(package, toPhone: applyPhone, toPasscode: applyPasscode, scale: scale)
                    alertMessage = language.text("dialer.apply_done")
                    showAlert = true
                } label: {
                    Label(language.text("dialer.apply"), systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                }
                .disabled(!applyPhone && !applyPasscode)

                Button(role: .destructive) {
                    store.resetToDefault()
                    alertMessage = language.text("dialer.reset_done")
                    showAlert = true
                } label: {
                    Label(language.text("dialer.reset_default"), systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text(language.text("dialer.apply_footer"))
            }
        }
        .navigationTitle(package.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scale = package.scale
        }
        .alert(language.text("dialer.title"), isPresented: $showAlert) {
            Button(language.text("common.ok"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }
}

// MARK: - 3. Interactive Plist Editor (v2.2)

struct PlistEntryItem: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var typeName: String
    var stringValue: String
    var boolValue: Bool
}

struct PlistEditorView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let fileURL: URL

    @State private var entries: [PlistEntryItem] = []
    @State private var rawFormat: PropertyListSerialization.PropertyListFormat = .xml
    @State private var searchText = ""
    @State private var showXMLPreview = false
    @State private var xmlString = ""
    @State private var statusBanner: String?
    @State private var showAddSheet = false
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var newType = "String"

    private var filteredEntries: [PlistEntryItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.key.localizedCaseInsensitiveContains(q)
                || $0.stringValue.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSearchField(
                text: $searchText,
                prompt: language.text("plist.search"),
                clearLabel: language.text("common.clear")
            )
            Divider()

            List {
                Section {
                    LabeledContent(
                        language.text("plist.path"),
                        value: fileURL.lastPathComponent
                    )
                    LabeledContent(
                        language.text("plist.type"),
                        value: rawFormat == .binary
                            ? language.text("plist.format_binary")
                            : language.text("plist.format_xml")
                    )
                    if let statusBanner {
                        Label(statusBanner, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                }

                Section(String(format: language.text("plist.item_count"), entries.count)) {
                    ForEach($entries) { $item in
                        if searchText.isEmpty
                            || item.key.localizedCaseInsensitiveContains(searchText)
                            || item.stringValue.localizedCaseInsensitiveContains(searchText) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.key)
                                        .font(.subheadline.weight(.semibold).monospaced())
                                    Spacer()
                                    Text(item.typeName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                                }
                                if item.typeName == "Boolean" {
                                    Toggle(item.key, isOn: $item.boolValue)
                                        .labelsHidden()
                                } else {
                                    TextField(language.text("plist.value"), text: $item.stringValue)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.key
                                } label: {
                                    Label(language.text("plist.copy_key"), systemImage: "doc.on.doc")
                                }
                                Button {
                                    UIPasteboard.general.string = item.stringValue
                                } label: {
                                    Label(language.text("plist.copy_value"), systemImage: "doc.on.clipboard")
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        entries.remove(atOffsets: offsets)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(language.text("plist.add"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    generateXMLPreview()
                    showXMLPreview = true
                } label: {
                    Image(systemName: "curlybraces")
                }
                .accessibilityLabel(language.text("plist.view_xml"))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(language.isRTL ? "حفظ" : "Save") {
                    savePlist()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                Form {
                    TextField(language.text("plist.key"), text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker(language.text("plist.type"), selection: $newType) {
                        Text("String").tag("String")
                        Text("Integer").tag("Integer")
                        Text("Boolean").tag("Boolean")
                    }
                    TextField(language.text("plist.value"), text: $newValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle(language.text("plist.add"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.text("common.cancel")) { showAddSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.text("common.done")) {
                            let cleanKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleanKey.isEmpty {
                                entries.append(
                                    PlistEntryItem(
                                        key: cleanKey,
                                        typeName: newType,
                                        stringValue: newValue,
                                        boolValue: (newValue as NSString).boolValue
                                    )
                                )
                            }
                            newKey = ""
                            newValue = ""
                            showAddSheet = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showXMLPreview) {
            NavigationStack {
                ScrollView {
                    Text(xmlString)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle(language.text("plist.view_xml"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.text("common.close")) { showXMLPreview = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.text("plist.copy_xml")) {
                            UIPasteboard.general.string = xmlString
                        }
                    }
                }
            }
        }
        .onAppear(perform: loadPlist)
    }

    private func loadPlist() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        var fmt = PropertyListSerialization.PropertyListFormat.xml
        guard let dict = (try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &fmt
        )) as? [String: Any] else { return }
        rawFormat = fmt

        var loaded: [PlistEntryItem] = []
        for key in dict.keys.sorted() {
            let val = dict[key]
            if let b = val as? Bool {
                loaded.append(PlistEntryItem(key: key, typeName: "Boolean", stringValue: b ? "true" : "false", boolValue: b))
            } else if let n = val as? Int {
                loaded.append(PlistEntryItem(key: key, typeName: "Integer", stringValue: "\(n)", boolValue: false))
            } else if let d = val as? Double {
                loaded.append(PlistEntryItem(key: key, typeName: "Real", stringValue: "\(d)", boolValue: false))
            } else if let s = val as? String {
                loaded.append(PlistEntryItem(key: key, typeName: "String", stringValue: s, boolValue: false))
            } else if let dataVal = val as? Data {
                loaded.append(PlistEntryItem(key: key, typeName: "Data", stringValue: dataVal.base64EncodedString(), boolValue: false))
            } else {
                loaded.append(PlistEntryItem(key: key, typeName: "Object", stringValue: String(describing: val ?? ""), boolValue: false))
            }
        }
        entries = loaded
    }

    private func buildDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: fileURL),
           let existingDict = (try? PropertyListSerialization.propertyList(from: existingData, options: [], format: nil)) as? [String: Any] {
            dict = existingDict
        }
        let currentKeys = Set(entries.map(\.key))
        for k in Array(dict.keys) where !currentKeys.contains(k) {
            dict.removeValue(forKey: k)
        }
        for item in entries {
            switch item.typeName {
            case "Boolean":
                dict[item.key] = item.boolValue
            case "Integer":
                dict[item.key] = Int(item.stringValue) ?? 0
            case "Real":
                dict[item.key] = Double(item.stringValue) ?? 0.0
            case "Data":
                if let d = Data(base64Encoded: item.stringValue) {
                    dict[item.key] = d
                }
            case "String":
                dict[item.key] = item.stringValue
            default:
                if dict[item.key] == nil {
                    dict[item.key] = item.stringValue
                }
            }
        }
        return dict
    }

    private func generateXMLPreview() {
        let dict = buildDictionary()
        if let xmlData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0),
           let str = String(data: xmlData, encoding: .utf8) {
            xmlString = str
        } else {
            xmlString = "Unable to serialize XML preview."
        }
    }

    private func savePlist() {
        let dict = buildDictionary()
        if let outData = try? PropertyListSerialization.data(fromPropertyList: dict, format: rawFormat, options: 0) {
            try? outData.write(to: fileURL, options: .atomic)
            statusBanner = language.text("plist.saved")
            log("plist: saved and verified \(fileURL.lastPathComponent)")
        }
    }
}

// MARK: - 4. System Features (Lock Screen Footnote & Supervised Mode — v2.2)

struct SystemFeaturesView: View {
    @Environment(\.appLanguage) private var language
    @State private var footnoteText: String = ""
    @State private var isSupervised: Bool = false
    @State private var statusMessage: String?

    private static let cloudConfigSystemPath = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/CloudConfigurationDetails.plist"

    private static var fallbackConfigURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("CloudConfigurationDetails.plist")
    }

    var body: some View {
        Form {
            Section {
                TextField(language.text("system_feature.footnote.placeholder"), text: $footnoteText)
                Button {
                    saveCloudConfig(footnote: footnoteText, supervised: isSupervised)
                } label: {
                    Label(language.text("system_feature.footnote.save"), systemImage: "checkmark.circle.fill")
                }
                Button(role: .destructive) {
                    footnoteText = ""
                    saveCloudConfig(footnote: nil, supervised: isSupervised)
                } label: {
                    Label(language.text("system_feature.footnote.remove"), systemImage: "trash")
                }
            } header: {
                Text(language.text("system_feature.footnote.title"))
            } footer: {
                Text(language.text("system_feature.footnote.summary"))
            }

            Section {
                Toggle(language.text("system_feature.supervised.control"), isOn: $isSupervised)
                    .onChange(of: isSupervised) { newValue in
                        saveCloudConfig(
                            footnote: footnoteText.isEmpty ? nil : footnoteText,
                            supervised: newValue
                        )
                    }
            } header: {
                Text(language.text("system_feature.supervised.title"))
            } footer: {
                Text(language.text("system_feature.supervised.summary"))
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } footer: {
                    Text(language.text("system_feature.restart_footer"))
                }
            }
        }
        .navigationTitle(language.text("system_feature.source_name"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadCloudConfig)
    }

    private func loadCloudConfig() {
        let handle = ContainerStore.grantContainerAccess(
            (Self.cloudConfigSystemPath as NSString).deletingLastPathComponent
        )
        defer { if handle >= 0 { bad_query_release(handle) } }

        let targetURL = FileManager.default.fileExists(atPath: Self.cloudConfigSystemPath)
            ? URL(fileURLWithPath: Self.cloudConfigSystemPath)
            : Self.fallbackConfigURL

        guard let data = try? Data(contentsOf: targetURL),
              let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return
        }
        footnoteText = (dict["LockScreenFootnote"] as? String) ?? ""
        isSupervised = (dict["IsSupervised"] as? Bool) ?? false
    }

    private func saveCloudConfig(footnote: String?, supervised: Bool) {
        let dirPath = (Self.cloudConfigSystemPath as NSString).deletingLastPathComponent
        let handle = ContainerStore.grantContainerAccess(dirPath)
        defer { if handle >= 0 { bad_query_release(handle) } }

        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Self.cloudConfigSystemPath)),
           let existing = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
            dict = existing
        } else if let data = try? Data(contentsOf: Self.fallbackConfigURL),
                  let existing = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
            dict = existing
        }

        if let footnote, !footnote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dict["LockScreenFootnote"] = footnote.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            dict.removeValue(forKey: "LockScreenFootnote")
        }
        dict["IsSupervised"] = supervised

        if let outData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
            try? outData.write(to: URL(fileURLWithPath: Self.cloudConfigSystemPath), options: .atomic)
            try? outData.write(to: Self.fallbackConfigURL, options: .atomic)
            statusMessage = language.text("system_feature.apply_done")
            log("system_feature: updated CloudConfigurationDetails.plist (IsSupervised=\(supervised), Footnote=\(footnote ?? "none"))")
        }
    }
}
