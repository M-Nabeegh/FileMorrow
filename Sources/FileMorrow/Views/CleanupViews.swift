import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

struct DuplicateCenterView: View {
    @Bindable var state: AppState
    @State private var pendingGroup: DuplicateGroup?

    var body: some View {
        VStack(spacing: 0) {
            CleanupHeader(
                title: "Exact Duplicates",
                subtitle: "Every accessible folder inside Downloads is checked read-only. SHA-256 verifies identical bytes; only copies you confirm move to recoverable Trash.",
                caution: "Nested project and app files can be intentionally identical. Review every full path before using Trash.",
                summary: state.duplicateGroups.isEmpty
                    ? nil
                    : "\(state.duplicateExtraCount) extra copies • \(ByteCountFormatter.string(fromByteCount: state.duplicateWastedSize, countStyle: .file)) reclaimable",
                isScanning: state.isScanningDuplicates,
                actionTitle: "Find Duplicates",
                cancelTitle: "Stop Scan",
                isDisabled: state.isWorking,
                onScan: { state.startDuplicateScan() },
                onCancel: { state.cancelDuplicateScan() }
            )

            Divider()

            if state.isScanningDuplicates, let scan = state.duplicateScanProgress {
                CleanupProgressView(
                    fraction: scan.fraction,
                    headline: scan.stage.rawValue,
                    detail: "\(scan.completedFiles.formatted()) of \(scan.totalFiles.formatted()) checks • \(ByteCountFormatter.string(fromByteCount: scan.processedBytes, countStyle: .file)) read",
                    currentItem: scan.currentFile
                )
            } else if state.duplicateGroups.isEmpty {
                ContentUnavailableView(
                    "No duplicate scan results",
                    systemImage: "doc.on.doc",
                    description: Text("Run a scan to find byte-for-byte duplicates anywhere inside Downloads.")
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
                        ForEach(group.files, id: \.path) { url in
                            let isKeeper = url == group.keeper
                            HStack(spacing: 8) {
                                Label(
                                    url.path,
                                    systemImage: isKeeper ? "checkmark.circle.fill" : "trash"
                                )
                                .foregroundStyle(isKeeper ? .green : .secondary)
                                .textSelection(.enabled)
                                Spacer()
                                if !isKeeper {
                                    Button("Keep This One") {
                                        state.setDuplicateKeeper(url, in: group)
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                }
                            }
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
            Text("FileMorrow will keep \(group.keeper.path). Verify every path: nested project and app files may intentionally be identical. Confirmed SHA-256-identical extras move to recoverable macOS Trash.")
        }
    }
}

/// Shared chrome for the Reclaim Space workflows, so the duplicate, archive,
/// and installer screens read as one feature rather than three.
struct CleanupHeader: View {
    let title: String
    let subtitle: String
    var caution: String? = nil
    let summary: String?
    let isScanning: Bool
    let actionTitle: String
    var cancelTitle: String = "Stop Check"
    let isDisabled: Bool
    let onScan: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary)
                if let caution {
                    Label(caution, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let summary {
                    Label(summary, systemImage: "internaldrive")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.indigo)
                }
            }
            Spacer()
            if isScanning {
                Button(cancelTitle, role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            } else {
                Button(actionTitle, action: onScan)
                    .buttonStyle(.borderedProminent)
                    .disabled(isDisabled)
            }
        }
        .padding(20)
    }
}

struct CleanupProgressView: View {
    let fraction: Double?
    let headline: String
    let detail: String
    let currentItem: String?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView(value: fraction)
                .frame(maxWidth: 420)
                .accessibilityLabel(headline)
            Text(headline).font(.headline)
            Text(detail).foregroundStyle(.secondary)
            if let currentItem {
                Text(currentItem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct CleanupSelectionFooter: View {
    let selectedCount: Int
    let totalCount: Int
    let selectedSize: Int64
    let actionTitle: String
    let isDisabled: Bool
    let onToggleAll: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack {
            Button(selectedCount == totalCount ? "Deselect All" : "Select All", action: onToggleAll)
                .buttonStyle(.link)

            Spacer()

            if selectedCount > 0 {
                Text("\(selectedCount) selected • \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(actionTitle, role: .destructive, action: onAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDisabled)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }
}

struct InstallerCenterView: View {
    @Bindable var state: AppState
    @State private var selection: Set<String> = []
    @State private var showConfirmation = false

    private var selected: [RedundantInstaller] {
        state.redundantInstallers.filter { selection.contains($0.id) }
    }

    private var selectedSize: Int64 {
        selected.reduce(0) { $0 + $1.installerSize }
    }

    var body: some View {
        VStack(spacing: 0) {
            CleanupHeader(
                title: "Installers",
                subtitle: "Finds .dmg and .pkg installers whose software is already on this Mac. Packages are checked against the install receipts macOS keeps; disk images are matched to the app in Applications. Nothing is mounted, opened, or run.",
                summary: state.redundantInstallers.isEmpty
                    ? nil
                    : "\(state.redundantInstallerCount) already used • \(ByteCountFormatter.string(fromByteCount: state.redundantInstallerReclaimableSize, countStyle: .file)) reclaimable",
                isScanning: state.isScanningInstallers,
                actionTitle: "Check Installers",
                isDisabled: state.isWorking,
                onScan: { state.startInstallerScan() },
                onCancel: { state.cancelInstallerScan() }
            )
            Divider()
            content
        }
        .confirmationDialog(
            "Move \(selected.count) used \(selected.count == 1 ? "installer" : "installers") to Trash?",
            isPresented: $showConfirmation
        ) {
            Button("Move to Trash", role: .destructive) {
                let installers = selected
                Task {
                    await state.trashInstallers(installers)
                    selection.removeAll()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The installed software is not touched. Only the installer files move to recoverable macOS Trash, and they can be downloaded again at any time. An installer newer than what is installed is never listed here.")
        }
        .onChange(of: state.redundantInstallers) { _, installers in
            selection.formIntersection(Set(installers.map(\.id)))
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.isScanningInstallers, let scan = state.installerScanProgress {
            CleanupProgressView(
                fraction: scan.fraction,
                headline: "Checking installers",
                detail: "\(scan.completedInstallers.formatted()) of \(scan.totalInstallers.formatted()) installers",
                currentItem: scan.currentInstaller
            )
        } else if state.redundantInstallers.isEmpty {
            ContentUnavailableView(
                state.hasScannedInstallers ? "No used installers" : "No installer check yet",
                systemImage: "shippingbox",
                description: Text(
                    state.hasScannedInstallers
                        ? "Every installer in Downloads is either for software that is not installed, or newer than what is installed."
                        : "Run a check to find .dmg and .pkg files for software you have already installed."
                )
            )
        } else {
            VStack(spacing: 0) {
                List(state.redundantInstallers, selection: $selection) { installer in
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(.indigo)
                            .font(.title3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(installer.name).fontWeight(.medium)
                            HStack(spacing: 6) {
                                Text(installer.evidence.rawValue)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        (installer.evidence == .packageReceipt ? Color.green : Color.indigo)
                                            .opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(installer.evidence == .packageReceipt ? .green : .indigo)
                                Text(installer.comparison.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(installer.installedLocation) • \(installer.versionSummary)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: installer.installerSize, countStyle: .file))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .tag(installer.id)
                }
                .listStyle(.inset)

                Divider()

                CleanupSelectionFooter(
                    selectedCount: selection.count,
                    totalCount: state.redundantInstallers.count,
                    selectedSize: selectedSize,
                    actionTitle: "Move \(selection.count) to Trash",
                    isDisabled: selection.isEmpty || state.isWorking,
                    onToggleAll: {
                        selection = selection.count == state.redundantInstallers.count
                            ? []
                            : Set(state.redundantInstallers.map(\.id))
                    },
                    onAction: { showConfirmation = true }
                )
            }
        }
    }
}

struct ExtractedArchiveCenterView: View {
    @Bindable var state: AppState
    @State private var selection: Set<String> = []
    @State private var showConfirmation = false

    private var selected: [ExtractedArchive] {
        state.extractedArchives.filter { selection.contains($0.id) }
    }

    private var selectedSize: Int64 {
        selected.reduce(0) { $0 + $1.archiveSize }
    }

    var body: some View {
        VStack(spacing: 0) {
            CleanupHeader(
                title: "Extracted Archives",
                subtitle: "Finds ZIP files whose contents are already unpacked next to them. Every entry must match the unpacked file byte-for-byte in size before an archive is listed here.",
                summary: state.extractedArchives.isEmpty
                    ? nil
                    : "\(state.extractedArchiveCount) unpacked • \(ByteCountFormatter.string(fromByteCount: state.extractedArchiveReclaimableSize, countStyle: .file)) reclaimable",
                isScanning: state.isScanningExtractedArchives,
                actionTitle: "Check Archives",
                isDisabled: state.isWorking,
                onScan: { state.startExtractedArchiveScan() },
                onCancel: { state.cancelExtractedArchiveScan() }
            )
            Divider()
            content
        }
        .confirmationDialog(
            "Move \(selected.count) unpacked \(selected.count == 1 ? "archive" : "archives") to Trash?",
            isPresented: $showConfirmation
        ) {
            Button("Move to Trash", role: .destructive) {
                let archives = selected
                Task {
                    await state.trashExtractedArchives(archives)
                    selection.removeAll()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only the .zip files move to recoverable macOS Trash. The unpacked folders stay exactly where they are, and every archive is re-verified against them one final time before it is moved.")
        }
        .onChange(of: state.extractedArchives) { _, archives in
            let ids = Set(archives.map(\.id))
            selection.formIntersection(ids)
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.isScanningExtractedArchives, let scan = state.extractedArchiveScanProgress {
            CleanupProgressView(
                fraction: scan.fraction,
                headline: "Verifying archive contents",
                detail: "\(scan.completedArchives.formatted()) of \(scan.totalArchives.formatted()) archives",
                currentItem: scan.currentArchive
            )
        } else if state.extractedArchives.isEmpty {
            ContentUnavailableView(
                state.hasScannedExtractedArchives ? "No unpacked archives" : "No archive check yet",
                systemImage: "archivebox",
                description: Text(
                    state.hasScannedExtractedArchives
                        ? "Every ZIP in Downloads is either still packed or does not fully match a folder next to it."
                        : "Run a check to find ZIP files you already extracted and no longer need."
                )
            )
        } else {
            VStack(spacing: 0) {
                List(state.extractedArchives, selection: $selection) { archive in
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.indigo)
                            .font(.title3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(archive.name)
                                .fontWeight(.medium)
                            Label(
                                "Unpacked to \(archive.destinationName)",
                                systemImage: "arrow.turn.down.right"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text("\(archive.entryCount.formatted()) files verified • \(ByteCountFormatter.string(fromByteCount: archive.extractedSize, countStyle: .file)) on disk")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: archive.archiveSize, countStyle: .file))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .tag(archive.id)
                }
                .listStyle(.inset)

                Divider()

                CleanupSelectionFooter(
                    selectedCount: selection.count,
                    totalCount: state.extractedArchives.count,
                    selectedSize: selectedSize,
                    actionTitle: "Move \(selection.count) to Trash",
                    isDisabled: selection.isEmpty || state.isWorking,
                    onToggleAll: {
                        selection = selection.count == state.extractedArchives.count
                            ? []
                            : Set(state.extractedArchives.map(\.id))
                    },
                    onAction: { showConfirmation = true }
                )
            }
        }
    }
}
