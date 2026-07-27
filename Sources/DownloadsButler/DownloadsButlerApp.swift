import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct DownloadsButlerApp: App {
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

                Button("Show Welcome Guide") {
                    state.requestOnboarding()
                }
            }
        }

        MenuBarExtra("FileMorrow", systemImage: "tray.full.fill") {
            DownloadsButlerMenu(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }
    }
}

private struct DownloadsButlerMenu: View {
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
        Text(state.automaticOrganization ? "Automatic organization: On" : "Automatic organization: Off")

        Divider()

        Button(state.isWorking ? "Scanning…" : "Scan Downloads") {
            Task { await state.scan() }
        }
        .disabled(state.isWorking)

        Button("Check & Organize Now") {
            Task { await state.runAutomaticOrganization() }
        }
        .disabled(state.isWorking || !state.automaticOrganization)

        Button("Scan for Duplicates") {
            Task { await state.scanDuplicates() }
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
