import AppKit
import Foundation
import UniformTypeIdentifiers

// Update checks.
extension AppState {
    func setAutomaticUpdateChecks(_ enabled: Bool) {
        automaticUpdateChecks = enabled
        UserDefaults.standard.set(enabled, forKey: "automaticUpdateChecks")
        if enabled {
            Task { await checkForUpdatesIfDue() }
        }
    }

    /// The menu command and the Settings button. Always tells the user what it found.
    func checkForUpdatesNow() async {
        guard !isCheckingForUpdates else { return }
        let result = await runUpdateCheck()
        presentUpdateResult(result)
    }

    /// The daily check, only when the user has turned it on. Stays quiet unless there is an update.
    func checkForUpdatesIfDue(now: Date = .now) async {
        guard automaticUpdateChecks, !isCheckingForUpdates,
              UpdateChecker.isDue(lastCheck: UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date, now: now)
        else { return }
        _ = await runUpdateCheck()
    }

    func openAvailableUpdate() {
        NSWorkspace.shared.open(availableUpdate?.page ?? UpdateChecker.releasesPage)
    }

    private func runUpdateCheck() async -> UpdateCheckResult {
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        let result = await UpdateChecker.check(currentVersion: Self.currentVersion)
        switch result {
        case let .available(release):
            availableUpdate = release
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        case .upToDate:
            availableUpdate = nil
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        case .failed:
            break
        }
        return result
    }

    private func presentUpdateResult(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        switch result {
        case let .available(release):
            alert.messageText = "FileMorrow \(release.version) is available"
            alert.informativeText = "You have \(Self.currentVersion). The download page lists what changed and the checksums to verify."
            alert.addButton(withTitle: "Open Download Page")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.page)
            }
        case let .upToDate(current):
            alert.messageText = "FileMorrow is up to date"
            alert.informativeText = "\(current) is the latest release."
            alert.runModal()
        case let .failed(reason):
            alert.alertStyle = .warning
            alert.messageText = "Could not check for updates"
            alert.informativeText = reason
            alert.runModal()
        }
    }
}
