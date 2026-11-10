import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

struct RootView: View {
    @State var state: AppState
    @Environment(\.scenePhase) private var scenePhase
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
                            state.startAnalysis(limit: 25)
                        }
                        Button("Analyze All Remaining") {
                            state.startAnalysis()
                        }
                    } label: {
                        Label("Analyze", systemImage: "sparkles")
                    }
                    .disabled(state.isWorking || state.classificationMode == .formatOnly)
                }

                Button {
                    state.prepareOrganizationProposal()
                } label: {
                    Label("Organize", systemImage: "folder.badge.plus")
                }
                .disabled(state.isWorking || state.approvedReadyFiles.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Button {
                    Task { await state.undoLastMove() }
                } label: {
                    Label(
                        state.lastOrganizedCount > 0
                            ? "Undo Last Organization (\(state.lastOrganizedCount))"
                            : "Undo Last Organization",
                        systemImage: "arrow.uturn.backward"
                    )
                }
                .disabled(state.isWorking)
                .keyboardShortcut("z", modifiers: .command)
            }
        }
        .sheet(item: $state.organizationProposal) { proposal in
            OrganizationPlanView(state: state, proposal: proposal)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                availability: state.intelligenceAvailability,
                initialMode: state.classificationMode,
                initialAutomaticOrganization: state.automaticOrganization,
                initialLaunchAtLogin: state.launchAtLogin
            ) { mode, automatic, launchAtLogin in
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
        .onChange(of: state.onboardingRequestID) { _, requestID in
            guard requestID != nil else { return }
            showOnboarding = true
        }
    }
}
