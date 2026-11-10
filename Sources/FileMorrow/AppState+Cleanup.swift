import AppKit
import Foundation
import UniformTypeIdentifiers

// Duplicates, unpacked archives and used installers.
extension AppState {
    func startDuplicateScan() {
        guard !isWorking else { return }
        duplicateScanTask?.cancel()
        duplicateScanTask = Task { await scanDuplicates() }
    }

    func scanDuplicates() async {
        guard !isWorking else { return }
        isWorking = true
        isScanningDuplicates = true
        duplicateScanProgress = nil
        status = "Finding exact duplicates…"
        let result = await duplicateScanner.scan(root: downloadsURL) { [weak self] update in
            await MainActor.run {
                self?.duplicateScanProgress = update
                self?.progress = update.fraction
                self?.status = update.currentFile.map {
                    "\(update.stage.rawValue) • \($0)"
                } ?? update.stage.rawValue
            }
        }
        if !Task.isCancelled { duplicateGroups = result }
        isScanningDuplicates = false
        isWorking = false
        progress = nil
        duplicateScanProgress = nil
        status = Task.isCancelled
            ? "Duplicate scan stopped"
            : duplicateGroups.isEmpty
                ? "No exact duplicates found"
                : "Found \(duplicateExtraCount) potential duplicate copies to review"
    }

    func cancelDuplicateScan() {
        duplicateScanTask?.cancel()
        status = "Stopping duplicate scan…"
    }

    func trashDuplicateExtras(in group: DuplicateGroup) async {
        guard !isWorking else { return }
        isWorking = true
        status = "Moving duplicate copies to Trash…"
        do {
            let count = try await duplicateScanner.trashExtras(in: group)
            status = "Moved \(count) exact duplicate \(count == 1 ? "copy" : "copies") to Trash"
            duplicateGroups = await duplicateScanner.scan(root: downloadsURL)
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Duplicate cleanup needs attention"
        }
        isWorking = false
    }

    func startExtractedArchiveScan() {
        guard !isWorking else { return }
        archiveScanTask?.cancel()
        archiveScanTask = Task { [weak self] in await self?.scanExtractedArchives() }
    }

    func scanExtractedArchives() async {
        guard !isWorking else { return }
        isWorking = true
        isScanningExtractedArchives = true
        extractedArchiveScanProgress = nil
        status = "Checking which archives are already unpacked…"
        let result = await archiveScanner.scan(
            root: downloadsURL,
            profile: profile
        ) { [weak self] update in
            await MainActor.run {
                self?.extractedArchiveScanProgress = update
                self?.progress = update.fraction
                self?.status = update.currentArchive.map { "Checking \($0)…" }
                    ?? "Checking archives…"
            }
        }
        if !Task.isCancelled {
            extractedArchives = result
            hasScannedExtractedArchives = true
        }
        isScanningExtractedArchives = false
        isWorking = false
        progress = nil
        extractedArchiveScanProgress = nil
        status = Task.isCancelled
            ? "Archive check stopped"
            : extractedArchives.isEmpty
                ? "No archives are fully unpacked yet"
                : "\(extractedArchiveCount) unpacked archives • \(ByteCountFormatter.string(fromByteCount: extractedArchiveReclaimableSize, countStyle: .file)) reclaimable"
    }

    func cancelExtractedArchiveScan() {
        archiveScanTask?.cancel()
        status = "Stopping archive check…"
    }

    func trashExtractedArchives(_ archives: [ExtractedArchive]) async {
        guard !isWorking, !archives.isEmpty else { return }
        isWorking = true
        status = "Moving unpacked archives to Trash…"
        defer { isWorking = false }

        var reclaimed: Int64 = 0
        var resolved: Set<String> = []
        var firstFailure: String?
        for archive in archives {
            do {
                if try await archiveScanner.trash(archive) {
                    reclaimed += archive.archiveSize
                }
                // Either it moved to Trash or it was already gone; both mean
                // it no longer belongs in the list.
                resolved.insert(archive.id)
            } catch {
                if firstFailure == nil { firstFailure = error.localizedDescription }
            }
        }

        let trashed = resolved.count
        extractedArchives.removeAll { resolved.contains($0.id) }
        lastError = firstFailure
        status = trashed == 0
            ? "No archives were moved to Trash"
            : "Moved \(trashed) unpacked \(trashed == 1 ? "archive" : "archives") to Trash • \(ByteCountFormatter.string(fromByteCount: reclaimed, countStyle: .file)) reclaimed"
        await scan()
    }

    func startInstallerScan() {
        guard !isWorking else { return }
        installerScanTask?.cancel()
        installerScanTask = Task { [weak self] in await self?.scanInstallers() }
    }

    func scanInstallers() async {
        guard !isWorking else { return }
        isWorking = true
        isScanningInstallers = true
        installerScanProgress = nil
        status = "Checking which installers you have already used…"
        let result = await installerScanner.scan(root: downloadsURL, profile: profile) { [weak self] update in
            await MainActor.run {
                self?.installerScanProgress = update
                self?.progress = update.fraction
                self?.status = update.currentInstaller.map { "Checking \($0)…" }
                    ?? "Checking installers…"
            }
        }
        if !Task.isCancelled {
            redundantInstallers = result
            hasScannedInstallers = true
        }
        isScanningInstallers = false
        isWorking = false
        progress = nil
        installerScanProgress = nil
        status = Task.isCancelled
            ? "Installer check stopped"
            : redundantInstallers.isEmpty
                ? "No installers match software already on this Mac"
                : "\(redundantInstallerCount) used installers • \(ByteCountFormatter.string(fromByteCount: redundantInstallerReclaimableSize, countStyle: .file)) reclaimable"
    }

    func cancelInstallerScan() {
        installerScanTask?.cancel()
        status = "Stopping installer check…"
    }

    func trashInstallers(_ installers: [RedundantInstaller]) async {
        guard !isWorking, !installers.isEmpty else { return }
        isWorking = true
        status = "Moving used installers to Trash…"
        defer { isWorking = false }

        var reclaimed: Int64 = 0
        var resolved: Set<String> = []
        var firstFailure: String?
        for installer in installers {
            do {
                if try await installerScanner.trash(installer) {
                    reclaimed += installer.installerSize
                }
                resolved.insert(installer.id)
            } catch {
                if firstFailure == nil { firstFailure = error.localizedDescription }
            }
        }

        let trashed = resolved.count
        redundantInstallers.removeAll { resolved.contains($0.id) }
        lastError = firstFailure
        status = trashed == 0
            ? "No installers were moved to Trash"
            : "Moved \(trashed) used \(trashed == 1 ? "installer" : "installers") to Trash • \(ByteCountFormatter.string(fromByteCount: reclaimed, countStyle: .file)) reclaimed"
        await scan()
    }

    /// Lets the user pick which copy of a duplicate group survives cleanup.
    func setDuplicateKeeper(_ url: URL, in group: DuplicateGroup) {
        guard let index = duplicateGroups.firstIndex(where: { $0.id == group.id }) else { return }
        duplicateGroups[index] = duplicateGroups[index].keeping(url)
    }
}
