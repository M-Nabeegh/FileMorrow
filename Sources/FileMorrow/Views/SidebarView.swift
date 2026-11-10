import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var state: AppState

    var body: some View {
        List(selection: Binding(
            get: { state.ageSelection },
            set: { selection in
                state.ageSelection = selection
                if ![.duplicates, .extracted, .installers].contains(selection) {
                    state.categoryFilter = nil
                }
            }
        )) {
            Section("Fresh") {
                ForEach([AgeView.today, .yesterday, .lastWeek]) { item in
                    SidebarRow(title: item.rawValue, icon: item.icon, count: state.count(for: item))
                        .tag(item)
                }
            }

            Section("Library") {
                ForEach([AgeView.ready, .all]) { item in
                    SidebarRow(title: item.rawValue, icon: item.icon, count: state.count(for: item))
                        .tag(item)
                }
            }

            Section("Reclaim Space") {
                SidebarRow(
                    title: AgeView.duplicates.rawValue,
                    icon: AgeView.duplicates.icon,
                    count: state.duplicateExtraCount
                )
                .tag(AgeView.duplicates)

                SidebarRow(
                    title: AgeView.extracted.rawValue,
                    icon: AgeView.extracted.icon,
                    count: state.extractedArchiveCount
                )
                .tag(AgeView.extracted)

                SidebarRow(
                    title: AgeView.installers.rawValue,
                    icon: AgeView.installers.icon,
                    count: state.redundantInstallerCount
                )
                .tag(AgeView.installers)
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
                        .accessibilityLabel("Progress")
                        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                }
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if state.totalReclaimableSize > 0 {
                    Label(
                        "\(ByteCountFormatter.string(fromByteCount: state.totalReclaimableSize, countStyle: .file)) reclaimable",
                        systemImage: "internaldrive"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.indigo)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Butler")
    }
}

struct SidebarRow: View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(count.formatted())
    }
}
