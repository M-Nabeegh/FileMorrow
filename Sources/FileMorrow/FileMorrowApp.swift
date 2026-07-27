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
            }

            CommandGroup(after: .newItem) {
                Button("Scan Downloads") {
                    Task { await state.scan() }
                }
                .keyboardShortcut("r")

                Button("Analyze Ready Files") {
                    Task { await state.analyzeReady() }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Undo Last Organization") {
                    Task { await state.undoLastMove() }
                }
                .keyboardShortcut("z", modifiers: .command)

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
        Text(state.automaticOrganization ? "Automatic checks: On • approval required" : "Automatic checks: Off")

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

        Divider()

        Button("Show Welcome Guide") {
            openWindow(id: "main")
            NSApplication.shared.activate()
            state.requestOnboarding()
        }

        SettingsLink {
            Text("Settings…")
        }

        Button("Quit FileMorrow") {
            NSApplication.shared.terminate(nil)
        }
    }
}
