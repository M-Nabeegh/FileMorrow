import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var state: AppState
    @AppStorage("archiveDays") private var archiveDays = 7
    @AppStorage("minimumConfidence") private var minimumConfidence = 85

    var body: some View {
        TabView {
            Form {
                Section("Classification") {
                    Picker("Mode", selection: Binding(
                        get: { state.classificationMode },
                        set: { mode in Task { await state.setClassificationMode(mode) } }
                    )) {
                        ForEach(ClassificationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(state.isWorking)

                    Text(state.classificationMode.detail)
                        .foregroundStyle(.secondary)

                    if state.classificationMode == .smartContent {
                        Label(
                            "Apple Intelligence classifications are suggestions and may be inaccurate. Review important files before moving them.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    } else {
                        Label(
                            "Recommended for predictable organization. No content analysis queue is needed.",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }

                Section("Archive") {
                    Toggle("Automatically organize eligible files hourly", isOn: Binding(
                        get: { state.automaticOrganization },
                        set: { state.setAutomaticOrganization($0) }
                    ))
                    Toggle("Launch FileMorrow at login", isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { state.setLaunchAtLogin($0) }
                    ))
                    Stepper("Archive files after \(archiveDays) days", value: $archiveDays, in: 1...30)
                    Slider(value: Binding(
                        get: { Double(minimumConfidence) },
                        set: { minimumConfidence = Int($0) }
                    ), in: 60...100, step: 5) {
                        Text("Minimum confidence")
                    }
                    Text("Checks hourly while the menu-bar helper is running. Only files older than the selected age are moved; uncertain files stay for review.")
                        .foregroundStyle(.secondary)
                    Text("Current confidence threshold: \(minimumConfidence)%")
                        .foregroundStyle(.secondary)
                }

                Section("App") {
                    Toggle("Keep FileMorrow in the Dock", isOn: Binding(
                        get: { state.keepInDock },
                        set: { state.setKeepInDock($0) }
                    ))
                    Text("Turn this off for a menu-bar-only experience. FileMorrow keeps running after its windows close.")
                        .foregroundStyle(.secondary)
                }

                Section("Updates") {
                    Toggle("Check for updates once a day", isOn: Binding(
                        get: { state.automaticUpdateChecks },
                        set: { state.setAutomaticUpdateChecks($0) }
                    ))
                    LabeledContent("Installed version", value: AppState.currentVersion)
                    if let update = state.availableUpdate {
                        Button("Get FileMorrow \(update.version)…") {
                            state.openAvailableUpdate()
                        }
                    } else {
                        Button(state.isCheckingForUpdates ? "Checking…" : "Check Now") {
                            Task { await state.checkForUpdatesNow() }
                        }
                        .disabled(state.isCheckingForUpdates)
                    }
                    Text("Off by default. A check asks GitHub which FileMorrow release is the latest and sends nothing about you or your files. FileMorrow never downloads or installs an update by itself.")
                        .foregroundStyle(.secondary)
                }

                Section("Help") {
                    Button("Show Welcome Guide") {
                        state.requestOnboarding()
                    }
                    Text("Reopen the first-launch explanation without changing your current settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Organization", systemImage: "folder") }

            CategorySettingsView(state: state)
                .tabItem { Label("Categories", systemImage: "slider.horizontal.3") }

            Form {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.intelligenceStatusTitle).font(.headline)
                        Text(state.intelligenceStatusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: state.intelligenceReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.intelligenceReady ? .green : .orange)
                        .accessibilityLabel(state.intelligenceReady ? "Available" : "Needs attention")
                }
                LabeledContent("Privacy", value: "Content stays on this Mac")
                Text("FileMorrow extracts short local evidence and sends it only to Apple Intelligence running on your device.")
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Compatibility", systemImage: "checkmark.shield.fill") }
        }
        .scenePadding()
        .frame(width: 680, height: 480)
    }
}

struct CategorySettingsView: View {
    @Bindable var state: AppState
    @State private var editingCategory: CategoryDefinition?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.profile.name).font(.headline)
                    Text("These definitions guide rules, local content scoring, and Apple Intelligence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import…") { importProfile() }
                Button("Export…") { exportProfile() }
                Button {
                    editingCategory = newCategory()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            List {
                ForEach(state.profile.categories) { definition in
                    HStack(spacing: 12) {
                        Toggle("Use the \(definition.name) category", isOn: Binding(
                            get: { definition.enabled },
                            set: { enabled in
                                Task { await state.setCategoryEnabled(definition.id, enabled: enabled) }
                            }
                        ))
                        .labelsHidden()
                        .disabled(definition.category == .needsReview)

                        Image(systemName: definition.icon)
                            .foregroundStyle(definition.swiftUIColor)
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.name).font(.headline)
                            Text(definition.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(definition.extensions.prefix(5).map { ".\($0)" }.joined(separator: " "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                        Button("Edit") {
                            editingCategory = definition
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .sheet(item: $editingCategory) { definition in
            CategoryEditorView(
                definition: definition,
                canDelete: state.profile.categories.contains(where: { $0.id == definition.id })
                    && definition.category != .needsReview,
                onSave: { updated in
                    Task { await state.upsertCategory(updated) }
                },
                onDelete: {
                    Task { await state.removeCategory(definition.id) }
                }
            )
        }
    }

    private func newCategory() -> CategoryDefinition {
        .init(
            id: UUID().uuidString,
            name: "New Category",
            folderName: "New Category",
            icon: "folder.fill",
            color: "blue",
            description: "Describe what belongs here.",
            enabled: true,
            extensions: [],
            filenameKeywords: [],
            contentKeywords: [],
            examples: [],
            contentAware: true,
            extensionConfidence: 80
        )
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await state.importProfile(from: url) }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "filemorrow-profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await state.exportProfile(to: url) }
    }
}

struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let canDelete: Bool
    let onSave: (CategoryDefinition) -> Void
    let onDelete: () -> Void

    @State private var draft: CategoryDefinition
    @State private var extensionsText: String
    @State private var filenameKeywordsText: String
    @State private var contentKeywordsText: String
    @State private var examplesText: String

    init(
        definition: CategoryDefinition,
        canDelete: Bool,
        onSave: @escaping (CategoryDefinition) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: definition)
        _extensionsText = State(initialValue: definition.extensions.joined(separator: ", "))
        _filenameKeywordsText = State(initialValue: definition.filenameKeywords.joined(separator: ", "))
        _contentKeywordsText = State(initialValue: definition.contentKeywords.joined(separator: ", "))
        _examplesText = State(initialValue: definition.examples.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Identity") {
                    TextField("Name", text: $draft.name)
                    TextField("Destination folder", text: $draft.folderName)
                    TextField("Description", text: $draft.description, axis: .vertical)
                    TextField("SF Symbol", text: $draft.icon)
                    Picker("Color", selection: $draft.color) {
                        ForEach(["indigo", "blue", "cyan", "teal", "mint", "green", "yellow", "orange", "red", "pink", "purple", "brown", "gray"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                }

                Section("Classification guide") {
                    TextField("Extensions", text: $extensionsText, prompt: Text("pdf, docx, epub"))
                    TextField("Filename keywords", text: $filenameKeywordsText, axis: .vertical)
                    TextField("Content keywords", text: $contentKeywordsText, axis: .vertical)
                    TextField("Examples", text: $examplesText, axis: .vertical)
                    Toggle("Inspect content before final classification", isOn: $draft.contentAware)
                    Stepper(
                        "Format confidence: \(draft.extensionConfidence)%",
                        value: $draft.extensionConfidence,
                        in: 0...100,
                        step: 5
                    )
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if canDelete {
                    Button("Delete Category", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.folderName = draft.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.extensions = parse(extensionsText).map {
                        $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    }
                    draft.filenameKeywords = parse(filenameKeywordsText)
                    draft.contentKeywords = parse(contentKeywordsText)
                    draft.examples = parse(examplesText)
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 620, height: 620)
    }

    private func parse(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
