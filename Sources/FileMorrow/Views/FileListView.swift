import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

struct FileListView: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            if state.ageSelection == .duplicates {
                DuplicateCenterView(state: state)
            } else if state.ageSelection == .extracted {
                ExtractedArchiveCenterView(state: state)
            } else if state.ageSelection == .installers {
                InstallerCenterView(state: state)
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
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).lineLimit(1)
                                Text(file.isOrganized ? "Organized • \(file.source.rawValue)" : file.source.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityElement(children: .combine)
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

struct OrganizationPlanView: View {
    @Bindable var state: AppState
    let proposal: OrganizationProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Review before organizing", systemImage: "checklist")
                .font(.title2.bold())
                .foregroundStyle(.indigo)

            Text(proposal.automaticCheck
                 ? "FileMorrow’s automatic check found files that are ready. Do you want to arrange your Downloads now?"
                 : "Do you want to arrange these Downloads now?")
                .font(.title3.weight(.semibold))

            HStack {
                Label("\(proposal.fileCount) files", systemImage: "doc.on.doc")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: proposal.totalSize, countStyle: .file))
                    .foregroundStyle(.secondary)
            }

            List(proposal.categoryCounts, id: \.name) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(item.count.formatted())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 150)

            Label(
                "Nothing is deleted. Only eligible loose files move, and Undo Last Organization can restore this entire batch.",
                systemImage: "arrow.uturn.backward.circle.fill"
            )
            .foregroundStyle(.green)
            .fontWeight(.medium)

            HStack {
                Button("Not Now", role: .cancel) {
                    state.organizationProposal = nil
                    state.status = "Organization postponed • No files moved"
                }
                Spacer()
                Button("Organize \(proposal.fileCount) Files") {
                    Task { await state.organizeApproved() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 460)
        .interactiveDismissDisabled(state.isWorking)
    }
}

struct DashboardHeader: View {
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
                    .accessibilityHidden(true)
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

struct MetricCard: View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
