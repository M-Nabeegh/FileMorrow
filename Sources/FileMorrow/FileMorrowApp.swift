import AppKit
import SwiftUI

@MainActor
enum DockVisibility {
    static func policy(keepInDock: Bool) -> NSApplication.ActivationPolicy {
        keepInDock ? .regular : .accessory
    }

    static func apply(keepInDock: Bool) -> Bool {
        NSApplication.shared.setActivationPolicy(policy(keepInDock: keepInDock))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let keepInDock = UserDefaults.standard.object(forKey: "keepInDock") as? Bool ?? true
        _ = DockVisibility.apply(keepInDock: keepInDock)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct FileMorrowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("FileMorrow", id: "main") {
            RootView(state: state)
        }
        .defaultSize(width: 1_280, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FileMorrow") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(
                            string: "Made by Nabeegh",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                .foregroundColor: NSColor.secondaryLabelColor
                            ]
                        )
                    ])
                }
                Button("Check for Updates…") {
                    Task { await state.checkForUpdatesNow() }
                }
                .disabled(state.isCheckingForUpdates)
            }

            CommandGroup(after: .newItem) {
                Button("Scan Downloads") {
                    Task { await state.scan() }
                }
                .keyboardShortcut("r")
                .disabled(state.isWorking)

                Button("Analyze Ready Files") {
                    state.startAnalysis()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(state.isWorking || state.classificationMode == .formatOnly)

                Button("Undo Last Organization") {
                    Task { await state.undoLastMove() }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(state.isWorking)

                Button("Show Welcome Guide") {
                    state.requestOnboarding()
                }
            }
        }

        MenuBarExtra("FileMorrow", systemImage: "tray.full.fill") {
            FileMorrowMenu(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }
    }
}

private struct FileMorrowMenu: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open FileMorrow") {
            openWindow(id: "main")
            NSApplication.shared.activate()
        }

        Divider()

        Text(state.status)
        Text("\(state.files.count.formatted()) files • \(state.readyFiles.count.formatted()) ready")
        if state.totalReclaimableSize > 0 {
            Text("\(ByteCountFormatter.string(fromByteCount: state.totalReclaimableSize, countStyle: .file)) reclaimable from cleanup")
        }
        Text(state.automaticOrganization ? "Automatic organization: On" : "Automatic organization: Off")
        if let update = state.availableUpdate {
            Button("FileMorrow \(update.version) Is Available…") {
                state.openAvailableUpdate()
            }
        }

        Divider()

        Button(state.isWorking ? "Scanning…" : "Scan Downloads") {
            Task { await state.scan() }
        }
        .disabled(state.isWorking)

        Button(state.organizationProposal == nil ? "Check & Organize Now" : "Review Organization Plan") {
            if state.organizationProposal == nil {
                Task { await state.checkAndPrepareOrganization() }
            } else {
                openWindow(id: "main")
                NSApplication.shared.activate()
            }
        }
        .disabled(state.isWorking)

        Button("Scan for Duplicates") {
            state.startDuplicateScan()
        }
        .disabled(state.isWorking)

        Button("Check Unpacked Archives") {
            state.startExtractedArchiveScan()
        }
        .disabled(state.isWorking)

        Button("Check Used Installers") {
            state.startInstallerScan()
        }
        .disabled(state.isWorking)

        Divider()

        Button("Show Welcome Guide") {
            openWindow(id: "main")
            NSApplication.shared.activate()
            state.requestOnboarding()
        }

        Button("Check for Updates…") {
            NSApplication.shared.activate()
            Task { await state.checkForUpdatesNow() }
        }
        .disabled(state.isCheckingForUpdates)

        SettingsLink {
            Text("Settings…")
        }

        Button("Quit FileMorrow") {
            NSApplication.shared.terminate(nil)
        }
    }
}
