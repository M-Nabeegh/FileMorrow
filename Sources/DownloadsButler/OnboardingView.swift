import SwiftUI

struct OnboardingView: View {
    let availability: IntelligenceAvailabilityState
    let onComplete: (ClassificationMode, Bool, Bool) -> Void

    @State private var mode = ClassificationMode.formatOnly
    @State private var automaticOrganization = true
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    rules
                    modePicker
                    safety
                    compatibility
                }
                .padding(32)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Organize automatically after seven days", isOn: $automaticOrganization)
                    Toggle("Launch FileMorrow at login", isOn: $launchAtLogin)
                }
                Spacer()
                Button("Start FileMorrow") {
                    onComplete(mode, automaticOrganization, launchAtLogin)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .frame(width: 720, height: 690)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 82, height: 82)
                .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 5) {
                Text("Welcome to FileMorrow")
                    .font(.largeTitle.bold())
                Text("A calm, private Downloads organizer.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rules: some View {
        OnboardingSection(
            title: "Files get a seven-day head start",
            icon: "calendar.badge.clock",
            tint: .indigo
        ) {
            Text("Today, Yesterday, and the Last 7 Days remain untouched and easy to find. Only older loose files become eligible for organization.")
            Text("Folders are a hard boundary: FileMorrow never moves a downloaded folder or anything inside it.")
                .fontWeight(.medium)
        }
    }

    private var modePicker: some View {
        OnboardingSection(
            title: "Choose how files are classified",
            icon: "switch.2",
            tint: .cyan
        ) {
            Picker("Classification mode", selection: $mode) {
                ForEach(ClassificationMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(mode.detail)
                .foregroundStyle(.secondary)

            if mode == .smartContent {
                Text("Smart Content is optional and can make mistakes. High-confidence local evidence is used first; uncertain files stay visible for review.")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var safety: some View {
        OnboardingSection(
            title: "Every cleanup has a safety net",
            icon: "arrow.uturn.backward.circle.fill",
            tint: .green
        ) {
            Text("Organized batches can be undone. Duplicate detection compares SHA-256 hashes, keeps one copy, and sends selected extras to Trash so they are recoverable.")
        }
    }

    private var compatibility: some View {
        OnboardingSection(
            title: availability.title,
            icon: availability.isReady ? "checkmark.circle.fill" : "info.circle.fill",
            tint: availability.isReady ? .green : .orange
        ) {
            Text(availability.detail)
            Text("Format mode never requires Apple Intelligence.")
                .fontWeight(.medium)
        }
    }
}

private struct OnboardingSection<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content
            }
        }
    }
}
