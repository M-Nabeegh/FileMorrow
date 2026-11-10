import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

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
                            .accessibilityLabel("Category for \(file.name)")

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

struct FilePreview: View {
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

struct QuickLookPreview: NSViewRepresentable {
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

struct TeachOrganizerSheet: View {
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

struct CategoryBadge: View {
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

struct ConfidenceView: View {
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
