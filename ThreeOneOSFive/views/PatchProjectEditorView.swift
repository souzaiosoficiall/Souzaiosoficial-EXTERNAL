import SwiftUI
import UniformTypeIdentifiers

struct PatchProjectEditorView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let existingProject: PatchProject?
    let passwordIsProtected: Bool
    let initialDraft: PatchProjectDraft?
    let onSave: (PatchProject, String?) -> Void

    @State private var name: String
    @State private var author: String
    @State private var isPrivate: Bool
    @State private var bundleID: String
    @State private var bundleIdentifiers: [String]
    @State private var directories: [PatchDirectory]
    @State private var rules: [PatchRule]
    @State private var password = ""
    @State private var ruleEditor: PatchRuleEditorContext?
    @State private var validationMessageKey: String?

    init(
        existingProject: PatchProject?,
        passwordIsProtected: Bool,
        initialDraft: PatchProjectDraft? = nil,
        onSave: @escaping (PatchProject, String?) -> Void
    ) {
        self.existingProject = existingProject
        self.passwordIsProtected = passwordIsProtected
        self.initialDraft = initialDraft
        self.onSave = onSave
        _name = State(initialValue: existingProject?.name ?? initialDraft?.name ?? "")
        _author = State(initialValue: existingProject?.author ?? "")
        _isPrivate = State(initialValue: existingProject?.isPrivate ?? false)
        _bundleID = State(
            initialValue: existingProject?.bundleIdentifiers.first
                ?? initialDraft?.bundleIdentifiers.first
                ?? ""
        )
        _bundleIdentifiers = State(
            initialValue: existingProject?.bundleIdentifiers
                ?? initialDraft?.bundleIdentifiers
                ?? []
        )
        _directories = State(
            initialValue: existingProject?.directories ?? initialDraft?.directories ?? []
        )
        _rules = State(initialValue: existingProject?.rules ?? initialDraft?.rules ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("patch.project")) {
                    TextField(language.text("patch.project_name"), text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(language.text("patch.author_optional"), text: $author)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                if existingProject == nil {
                    Section {
                        if let capturedBundle = initialDraft?.bundleIdentifiers.first {
                            LabeledContent(language.text("patch.target_bundle")) {
                                Text(capturedBundle)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            TextField("com.example.app", text: $bundleID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body.monospaced())
                        }
                    } header: {
                        Text(language.text("patch.target_bundle"))
                    } footer: {
                        Text(language.text("patch.workspace_bundle_footer"))
                    }
                }

                Section {
                    ForEach(rules) { rule in
                        Button {
                            ruleEditor = PatchRuleEditorContext(rule: rule)
                        } label: {
                            HStack(spacing: 10) {
                                ruleRow(rule)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(language.text("patch.edit_rule_hint"))
                    }
                    .onDelete { rules.remove(atOffsets: $0) }

                    Button {
                        let defaultBundle = normalizeBundleID(bundleID)
                        let templateRule: PatchRule? = defaultBundle.isEmpty
                            ? nil
                            : PatchRule(
                                bundleID: defaultBundle,
                                relativePath: "",
                                replacementFilename: "",
                                replacementData: Data()
                            )
                        ruleEditor = PatchRuleEditorContext(rule: templateRule, isNew: true)
                    } label: {
                        Label(language.text("patch.add_rule"), systemImage: "plus.circle.fill")
                    }

                    if !directories.isEmpty {
                        LabeledContent(language.text("patch.folders")) {
                            Text("\(directories.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(language.text("patch.rules"))
                } footer: {
                    Text(language.text("patch.workspace_edit_footer"))
                }

                Section {
                    if existingProject == nil {
                        SecureField(language.text("patch.password_optional"), text: $password)
                            .textContentType(.newPassword)
                    } else {
                        Label(
                            language.text(passwordIsProtected ? "patch.password_locked" : "patch.no_password"),
                            systemImage: passwordIsProtected ? "lock.fill" : "lock.open"
                        )
                    }
                } header: {
                    Text(language.text("patch.password"))
                } footer: {
                    Text(language.text(existingProject == nil
                        ? "patch.password_immutable_footer"
                        : "patch.password_existing_footer"))
                }

                Section {
                    Toggle(isOn: $isPrivate) {
                        Label(
                            language.text("patch.private"),
                            systemImage: "eye.slash.fill"
                        )
                    }
                    .disabled(existingProject != nil)
                } header: {
                    Text(language.text("patch.privacy"))
                } footer: {
                    Text(language.text(existingProject == nil
                        ? "patch.private_footer"
                        : "patch.private_existing_footer"))
                }

                if let validationMessageKey {
                    Section {
                        Label(language.text(validationMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(language.text(existingProject == nil ? "patch.new" : "patch.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: save)
                }
            }
            .sheet(item: $ruleEditor) { context in
                PatchRuleEditorView(rule: context.rule) { savedRule in
                    if !context.isNew, let index = rules.firstIndex(where: { $0.id == savedRule.id }) {
                        rules[index] = savedRule
                    } else {
                        rules.append(savedRule)
                    }
                    if bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        bundleID = savedRule.bundleID
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if rule.hasReplacement {
                Text(rule.replacementFilename)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            } else {
                Label(language.text("patch.replacement_required"), systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private func normalizeBundleID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let valid = try? PatchPathValidator.canonicalBundleIdentifier(trimmed) {
            return valid
        }
        let alnum = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        guard !alnum.isEmpty else { return "com.apple.springboard" }
        return "com.app.\(alnum.lowercased())"
    }

    private func save() {
        var projectName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if projectName.isEmpty, let firstRule = rules.first {
            projectName = firstRule.replacementFilename
        }
        let projectAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectName.isEmpty, projectName.utf8.count <= 120 else {
            validationMessageKey = "patch.error.invalid_project"
            return
        }
        guard projectAuthor.utf8.count <= PatchPackageLimits.maximumAuthorBytes,
              !projectAuthor.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
              ) else {
            validationMessageKey = "patch.error.invalid_author"
            return
        }
        author = projectAuthor
        if existingProject == nil, isPrivate, password.isEmpty {
            validationMessageKey = "patch.error.private_password"
            return
        }
        if existingProject == nil, initialDraft == nil {
            let candidateBundle = normalizeBundleID(bundleID)
            if !candidateBundle.isEmpty {
                bundleID = candidateBundle
                var allBundles = [candidateBundle]
                for r in rules where !allBundles.contains(r.bundleID) {
                    allBundles.append(r.bundleID)
                }
                bundleIdentifiers = allBundles
            } else if !rules.isEmpty {
                var allBundles: [String] = []
                for r in rules where !allBundles.contains(r.bundleID) {
                    allBundles.append(r.bundleID)
                }
                bundleIdentifiers = allBundles
                bundleID = allBundles.first ?? ""
            } else {
                bundleID = "com.apple.springboard"
                bundleIdentifiers = ["com.apple.springboard"]
            }
        }
        guard !bundleIdentifiers.isEmpty || !rules.isEmpty || !directories.isEmpty else {
            validationMessageKey = "patch.error.invalid_project"
            return
        }
        guard let incompleteRule = rules.first(where: { !$0.hasReplacement }) else {
            saveCompleteProject(named: projectName)
            return
        }
        validationMessageKey = "patch.error.replacement_required"
        ruleEditor = PatchRuleEditorContext(rule: incompleteRule, isNew: false)
    }

    private func saveCompleteProject(named projectName: String) {
        var mergedBundles = bundleIdentifiers
        for r in rules where !mergedBundles.contains(r.bundleID) {
            mergedBundles.append(r.bundleID)
        }
        for d in directories where !mergedBundles.contains(d.bundleID) {
            mergedBundles.append(d.bundleID)
        }
        let project = PatchProject(
            id: existingProject?.id ?? UUID(),
            name: projectName,
            author: author,
            isPrivate: isPrivate,
            createdAt: existingProject?.createdAt ?? Date(),
            updatedAt: Date(),
            bundleIdentifiers: mergedBundles,
            directories: directories,
            rules: rules
        )
        do {
            try PatchPackageCodec.validate(project)
            onSave(project, existingProject == nil && !password.isEmpty ? password : nil)
            dismiss()
        } catch let error as PatchPackageError {
            validationMessageKey = error.localizationKey
        } catch {
            validationMessageKey = "patch.error.invalid_project"
        }
    }
}

private struct PatchRuleEditorContext: Identifiable {
    let id = UUID()
    let rule: PatchRule?
    var isNew: Bool = false
}

struct PatchRuleEditorView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let originalRule: PatchRule?
    let onSave: (PatchRule) -> Void

    @State private var bundleID: String
    @State private var relativePath: String
    @State private var replacementFilename: String
    @State private var replacementData: Data
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var validationMessageKey: String?

    init(rule: PatchRule?, onSave: @escaping (PatchRule) -> Void) {
        originalRule = rule
        self.onSave = onSave
        _bundleID = State(initialValue: rule?.bundleID ?? "")
        _relativePath = State(initialValue: rule?.relativePath ?? "")
        _replacementFilename = State(initialValue: rule?.replacementFilename ?? "")
        _replacementData = State(initialValue: rule?.replacementData ?? Data())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("com.example.app", text: $bundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField("Library/Preferences/file.plist", text: $relativePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text(language.text("patch.destination"))
                } footer: {
                    Text(language.text("patch.bundle_not_uuid_footer"))
                }

                Section(language.text("patch.replacement_file")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: replacementFilename.isEmpty ? "doc.badge.plus" : "doc.fill")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(replacementFilename.isEmpty
                                     ? language.text("patch.choose_file")
                                     : replacementFilename)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(language.text(replacementFilename.isEmpty
                                     ? "patch.replacement_required"
                                     : "patch.change_replacement"))
                                    .font(.caption)
                                    .foregroundStyle(replacementFilename.isEmpty ? Color.orange : Color.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(isImporting)
                    if isImporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(language.text("patch.importing_replacement"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !replacementFilename.isEmpty {
                        LabeledContent(
                            language.text("patch.file_size"),
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(replacementData.count),
                                countStyle: .file
                            )
                        )
                    }
                }

                if let validationMessageKey {
                    Section {
                        Label(language.text(validationMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(language.text(originalRule == nil ? "patch.add_rule" : "patch.edit_rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: save)
                        .disabled(isImporting)
                }
            }
            .sheet(isPresented: $showFileImporter) {
                FileDocumentPicker(
                    allowedContentTypes: [.item, .data],
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showFileImporter = false
                        importFile(result)
                    },
                    onCancel: {
                        showFileImporter = false
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isImporting = true
        validationMessageKey = nil
        let hasAccess = url.startAccessingSecurityScopedResource()
        let immediateData = try? Data(contentsOf: url)
        let fileName = url.lastPathComponent
        if hasAccess { url.stopAccessingSecurityScopedResource() }

        if let immediateData {
            replacementData = immediateData
            replacementFilename = fileName
            if relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                relativePath = "Documents/\(fileName)"
            }
            isImporting = false
        } else {
            validationMessageKey = "patch.error.invalid_project"
            isImporting = false
        }
    }

    private func save() {
        do {
            var rawBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            if rawBundle.isEmpty {
                rawBundle = "com.apple.springboard"
            } else if !rawBundle.contains(".") {
                let clean = rawBundle.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
                rawBundle = "com.app.\(clean.isEmpty ? "target" : clean.lowercased())"
            }
            let canonicalBundle = try PatchPathValidator.canonicalBundleIdentifier(rawBundle)

            var rawRelPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            while rawRelPath.hasPrefix("/") {
                rawRelPath.removeFirst()
            }
            if rawRelPath.isEmpty && !replacementFilename.isEmpty {
                rawRelPath = "Documents/\(replacementFilename)"
            }
            let canonicalPath = try PatchPathValidator.canonicalRelativePath(rawRelPath)
            guard !replacementFilename.isEmpty else {
                validationMessageKey = "patch.error.replacement_required"
                return
            }
            onSave(PatchRule(
                id: originalRule?.id ?? UUID(),
                bundleID: canonicalBundle,
                relativePath: canonicalPath,
                replacementFilename: replacementFilename,
                replacementData: replacementData
            ))
            dismiss()
        } catch let error as PatchPackageError {
            validationMessageKey = error.localizationKey
        } catch {
            validationMessageKey = "patch.error.invalid_project"
        }
    }
}
