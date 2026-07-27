import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

struct RootView: View {
    @State var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOrganizeConfirmation = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var hasPerformedInitialScan = false

    var body: some View {
        NavigationSplitView {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } content: {
            FileListView(state: state)
                .navigationSplitViewColumnWidth(min: 500, ideal: 680)
        } detail: {
            InspectorView(state: state)
                .navigationSplitViewColumnWidth(min: 280, ideal: 330)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $state.query, placement: .toolbar, prompt: "Search Downloads")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await state.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(state.isWorking)

                if state.isAnalyzing {
                    Button {
                        state.cancelAnalysis()
                    } label: {
                        Label("Stop Analysis", systemImage: "stop.fill")
                    }
                } else {
                    Menu {
                        Button("Analyze Next 25") {
                            Task { await state.analyzeReady(limit: 25) }
                        }
                        Button("Analyze All Remaining") {
                            Task { await state.analyzeReady() }
                        }
                    } label: {
                        Label("Analyze", systemImage: "sparkles")
                    }
                    .disabled(state.isWorking || state.classificationMode == .formatOnly)
                }

                Button {
                    showOrganizeConfirmation = true
                } label: {
                    Label("Organize", systemImage: "folder.badge.plus")
                }
                .disabled(state.isWorking || state.approvedReadyFiles.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Button {
                    Task { await state.undoLastMove() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(state.isWorking)
            }
        }
        .confirmationDialog(
            "Organize \(state.approvedReadyFiles.count) approved files?",
            isPresented: $showOrganizeConfirmation
        ) {
            Button("Move into category folders") {
                Task { await state.organizeApproved() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only files older than the archive window and above your confidence threshold will move into category folders directly inside Downloads. You can undo the batch.")
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(availability: state.intelligenceAvailability) { mode, automatic, launchAtLogin in
                Task {
                    await state.completeOnboarding(
                        mode: mode,
                        automaticOrganization: automatic,
                        launchAtLogin: launchAtLogin
                    )
                    hasCompletedOnboarding = true
                    showOnboarding = false
                }
            }
        }
        .task {
            await state.scan()
            hasPerformedInitialScan = true
            showOnboarding = !hasCompletedOnboarding
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, hasPerformedInitialScan else { return }
            Task { await state.refreshAfterActivation() }
        }
    }
}

struct SidebarView: View {
    @Bindable var state: AppState

    var body: some View {
        List(selection: Binding(
            get: { state.ageSelection },
            set: { selection in
                state.ageSelection = selection
                if selection != .duplicates { state.categoryFilter = nil }
            }
        )) {
            Section("Fresh") {
                ForEach([AgeView.today, .yesterday, .lastWeek]) { item in
                    SidebarRow(title: item.rawValue, icon: item.icon, count: state.count(for: item))
                        .tag(item)
                }
            }

            Section("Library") {
                ForEach([AgeView.ready, .all, .duplicates]) { item in
                    SidebarRow(title: item.rawValue, icon: item.icon, count: state.count(for: item))
                        .tag(item)
                }
            }

            Section("Categories") {
                Button {
                    state.categoryFilter = nil
                    state.ageSelection = .all
                } label: {
                    Label("All Categories", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)

                ForEach(state.visibleCategories) { definition in
                    Button {
                        state.categoryFilter = definition.category
                        state.ageSelection = .all
                    } label: {
                        Label(definition.name, systemImage: definition.icon)
                            .foregroundStyle(definition.swiftUIColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let progress = state.progress {
                    ProgressView(value: progress)
                        .tint(.indigo)
                }
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Butler")
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let count: Int

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(count.formatted())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}

struct FileListView: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            if state.ageSelection == .duplicates {
                DuplicateCenterView(state: state)
            } else {
                VStack(spacing: 0) {
                    DashboardHeader(state: state)
                    Divider()
                    if state.visibleFiles.isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "tray",
                    description: Text("Try another date view or clear the search.")
                )
                    } else {
                        Table(state.visibleFiles, selection: $state.selectedFileID) {
                    TableColumn("File") { file in
                        let definition = state.definition(for: file.category)
                        HStack(spacing: 10) {
                            Image(systemName: definition.icon)
                                .foregroundStyle(definition.swiftUIColor)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).lineLimit(1)
                                Text(file.isOrganized ? "Organized • \(file.source.rawValue)" : file.source.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .width(min: 260, ideal: 360)

                    TableColumn("Folder") { file in
                        if file.source == .rule && file.category == .needsReview {
                            Label("Awaiting Analysis", systemImage: "sparkles")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.indigo.opacity(0.10), in: Capsule())
                        } else {
                            CategoryBadge(definition: state.definition(for: file.category))
                        }
                    }
                    .width(min: 140, ideal: 170)

                    TableColumn("Confidence") { file in
                        ConfidenceView(value: file.confidence)
                    }
                    .width(100)
                        }
                    }
                }
            }
        }
        .navigationTitle(state.ageSelection.rawValue)
    }
}

private struct DuplicateCenterView: View {
    @Bindable var state: AppState
    @State private var pendingGroup: DuplicateGroup?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exact Duplicates").font(.title2.bold())
                    Text("Only loose files directly in Downloads are checked. Folders and everything inside them are never touched. SHA-256 verifies identical bytes.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(state.isScanningDuplicates ? "Scanning…" : "Find Duplicates") {
                    Task { await state.scanDuplicates() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isWorking)
            }
            .padding(20)

            Divider()

            if state.duplicateGroups.isEmpty {
                ContentUnavailableView(
                    "No duplicate scan results",
                    systemImage: "doc.on.doc",
                    description: Text("Run a scan to find byte-for-byte duplicate loose files in Downloads.")
                )
            } else {
                List(state.duplicateGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(
                                "\(group.files.count) identical copies",
                                systemImage: "doc.on.doc.fill"
                            )
                            .font(.headline)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: group.wastedSize, countStyle: .file) + " recoverable")
                                .foregroundStyle(.secondary)
                            Button("Move \(group.extras.count) Extras to Trash", role: .destructive) {
                                pendingGroup = group
                            }
                        }
                        Label("Keep: \(group.keeper.path)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .textSelection(.enabled)
                        ForEach(group.extras, id: \.path) { url in
                            Label(url.path, systemImage: "trash")
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Move exact duplicate copies to Trash?",
            isPresented: Binding(
                get: { pendingGroup != nil },
                set: { if !$0 { pendingGroup = nil } }
            ),
            presenting: pendingGroup
        ) { group in
            Button("Move \(group.extras.count) Extras to Trash", role: .destructive) {
                Task {
                    await state.trashDuplicateExtras(in: group)
                    pendingGroup = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingGroup = nil }
        } message: { group in
            Text("FileMorrow will keep \(group.keeper.lastPathComponent). Only SHA-256-identical extras move to recoverable macOS Trash.")
        }
    }
}

private struct DashboardHeader: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A calmer Downloads folder.")
                        .font(.title2.bold())
                    Text("Fresh files stay visible. Older files wait for a confident, reversible decision.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 16))
            }

            HStack(spacing: 12) {
                MetricCard(title: "Ready", value: state.readyFiles.count.formatted(), icon: "archivebox")
                MetricCard(title: "Approved", value: state.approvedReadyFiles.count.formatted(), icon: "checkmark.seal", tint: .green)
                MetricCard(title: "Awaiting analysis", value: state.awaitingAnalysisCount.formatted(), icon: "sparkles", tint: .indigo)
                MetricCard(title: "Needs review", value: state.reviewCount.formatted(), icon: "exclamationmark.bubble", tint: .orange)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.10), Color.purple.opacity(0.03), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = .indigo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.primary.opacity(0.06))
        }
    }
}

struct InspectorView: View {
    @Bindable var state: AppState
    @State private var teachingFile: FileRecord?

    var body: some View {
        Group {
            if let file = state.selectedFile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        FilePreview(url: file.url)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(file.name)
                                .font(.title3.bold())
                                .textSelection(.enabled)
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Suggested folder").font(.headline)
                            Picker("Category", selection: Binding(
                                get: { file.category },
                                set: { category in Task { await state.correctSelected(to: category) } }
                            )) {
                                ForEach(state.enabledCategories) { definition in
                                    Label(definition.name, systemImage: definition.icon)
                                        .tag(definition.category)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)

                            ConfidenceView(value: file.confidence)
                            Text(file.reason)
                                .foregroundStyle(.secondary)
                            Label(file.source.rawValue, systemImage: file.source == .user ? "person.fill.checkmark" : "cpu")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if file.isOrganized {
                                Label("Already organized", systemImage: "folder.fill.badge.checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        HStack {
                            Button("Open File") {
                                NSWorkspace.shared.open(file.url)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Teach Organizer…") {
                                teachingFile = file
                            }
                            .buttonStyle(.bordered)
                        }

                        if let excerpt = file.excerpt, !excerpt.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Evidence used").font(.headline)
                                Text(excerpt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(12)
                                    .textSelection(.enabled)
                            }
                        }

                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Select a file",
                    systemImage: "sidebar.right",
                    description: Text("Review the evidence, change its folder, or reveal it in Finder.")
                )
            }
        }
        .navigationTitle("Inspector")
        .sheet(item: $teachingFile) { file in
            TeachOrganizerSheet(state: state, file: file)
        }
    }
}

private struct FilePreview: View {
    let url: URL

    var body: some View {
        QuickLookPreview(url: url)
            .frame(minHeight: 220, idealHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.primary.opacity(0.08))
            }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else {
            return NSView()
        }
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? QLPreviewView else { return }
        view.previewItem = url as NSURL
    }
}

private struct TeachOrganizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    let file: FileRecord

    @State private var category: ArchiveCategory
    @State private var filenameKeyword = ""
    @State private var rememberExtension = false

    init(state: AppState, file: FileRecord) {
        self.state = state
        self.file = file
        _category = State(initialValue: file.category == .needsReview ? .documents : file.category)
    }

    private var availableCategories: [CategoryDefinition] {
        state.enabledCategories.filter { $0.category != .needsReview }
    }

    private var fileExtension: String {
        RuleClassifier.normalizedExtension(file.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Teach the Organizer").font(.title2.bold())
                Text(file.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Form {
                Picker("Correct category", selection: $category) {
                    ForEach(availableCategories) { definition in
                        Label(definition.name, systemImage: definition.icon)
                            .tag(definition.category)
                    }
                }

                TextField("Reusable filename word or phrase", text: $filenameKeyword)
                Text("Optional. For example: “operating systems”, “invoice”, or a course code. Matching future filenames will use this category.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !fileExtension.isEmpty {
                    Toggle("Always categorize .\(fileExtension) files this way", isOn: $rememberExtension)
                    Text("Use this only when the format always belongs here. It will replace any previous category assignment for .\(fileExtension).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text("The current file is corrected immediately and added as an example for the on-device model. Optional rules also improve future files.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save & Teach") {
                    Task {
                        await state.teach(
                            fileID: file.id,
                            category: category,
                            filenameKeyword: filenameKeyword,
                            rememberExtension: rememberExtension
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(category == .needsReview)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct CategoryBadge: View {
    let definition: CategoryDefinition

    var body: some View {
        Label(definition.name, systemImage: definition.icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(definition.swiftUIColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(definition.swiftUIColor.opacity(0.10), in: Capsule())
    }
}

private struct ConfidenceView: View {
    let value: Int

    private var color: Color {
        if value >= 85 { return .green }
        if value >= 60 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: 42 * Double(value) / 100)
            }
            .frame(width: 42, height: 6)

            Text("\(value)%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(value >= 85 ? .primary : color)
        }
        .accessibilityLabel("Confidence \(value) percent")
    }
}

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
                    Toggle("Automatically organize old files", isOn: Binding(
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

private struct CategorySettingsView: View {
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
                        Toggle("", isOn: Binding(
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
        panel.nameFieldStringValue = "downloads-butler-profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await state.exportProfile(to: url) }
    }
}

private struct CategoryEditorView: View {
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
