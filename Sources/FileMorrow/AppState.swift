import AppKit
import Foundation
import Observation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    var files: [FileRecord] = []
    var ageSelection: AgeView = .today
    var categoryFilter: ArchiveCategory?
    var selectedFileID: String?
    var query = ""
    var status = "Ready"
    var progress: Double?
    var isWorking = false
    var lastError: String?
    var isAnalyzing = false
    var intelligenceAvailability = IntelligenceAvailabilityState.checking
    var classificationMode = ClassificationMode(
        rawValue: UserDefaults.standard.string(forKey: "classificationMode") ?? ""
    ) ?? .formatOnly
    var automaticOrganization = UserDefaults.standard.object(forKey: "automaticOrganization") as? Bool ?? true
    var launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
    var keepInDock = UserDefaults.standard.object(forKey: "keepInDock") as? Bool ?? true
    /// Off unless the user turns it on: FileMorrow makes no network request on its own.
    var automaticUpdateChecks = UserDefaults.standard.bool(forKey: "automaticUpdateChecks")
    var availableUpdate: ReleaseInfo?
    var isCheckingForUpdates = false
    var duplicateGroups: [DuplicateGroup] = []
    var isScanningDuplicates = false
    var duplicateScanProgress: DuplicateScanProgress?
    var extractedArchives: [ExtractedArchive] = []
    var isScanningExtractedArchives = false
    var extractedArchiveScanProgress: ExtractedArchiveScanProgress?
    var hasScannedExtractedArchives = false
    var redundantInstallers: [RedundantInstaller] = []
    var isScanningInstallers = false
    var installerScanProgress: InstallerScanProgress?
    var hasScannedInstallers = false
    var organizationProposal: OrganizationProposal?
    var lastOrganizedCount = 0
    var onboardingRequestID: UUID?
    var profile = ProfileStore.fallback
    var shouldCancelAnalysis = false

    @ObservationIgnored let store = PersistenceStore()
    @ObservationIgnored let profileStore = ProfileStore()
    @ObservationIgnored private let scanner = FileScanner()
    @ObservationIgnored let extractor = ContentExtractor()
    @ObservationIgnored let ai = AIClassifier()
    @ObservationIgnored let duplicateScanner = DuplicateScanner()
    @ObservationIgnored let archiveScanner = ExtractedArchiveScanner()
    @ObservationIgnored let installerScanner = InstallerScanner()
    @ObservationIgnored private let folderBranding = FolderBrandingService()
    @ObservationIgnored private lazy var organizer = OrganizerService(store: store)
    @ObservationIgnored private var automaticTask: Task<Void, Never>?
    @ObservationIgnored var duplicateScanTask: Task<Void, Never>?
    @ObservationIgnored var archiveScanTask: Task<Void, Never>?
    @ObservationIgnored var installerScanTask: Task<Void, Never>?
    @ObservationIgnored var analysisTask: Task<Void, Never>?
    @ObservationIgnored let downloadsURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")

    private var archiveDays: Int { max(1, UserDefaults.standard.integer(forKey: "archiveDays").nonZero(or: 7)) }
    var minimumConfidence: Int { max(60, UserDefaults.standard.integer(forKey: "minimumConfidence").nonZero(or: 85)) }
    var cutoffDate: Date { Date().addingTimeInterval(TimeInterval(-archiveDays * 24 * 60 * 60)) }

    var visibleFiles: [FileRecord] {
        files.filter { record in
            ageMatches(record)
                && (categoryFilter == nil || record.category == categoryFilter)
                && (query.isEmpty || record.name.localizedCaseInsensitiveContains(query))
        }
        .sorted { $0.dateAdded > $1.dateAdded }
    }

    var selectedFile: FileRecord? {
        guard let selectedFileID else { return nil }
        return files.first { $0.id == selectedFileID }
    }

    var readyFiles: [FileRecord] {
        files.filter { ArchiveEligibility.isEligible($0, cutoffDate: cutoffDate) }
    }
    var approvedReadyFiles: [FileRecord] {
        readyFiles.filter { $0.confidence >= minimumConfidence && $0.category != .needsReview }
    }
    var awaitingAnalysisFiles: [FileRecord] {
        guard classificationMode == .smartContent else { return [] }
        return files.filter(needsAnalysis)
    }
    var needsHumanReviewFiles: [FileRecord] {
        readyFiles.filter {
            (classificationMode == .formatOnly && $0.category == .needsReview)
                || ($0.source != .rule && ($0.confidence < minimumConfidence || $0.category == .needsReview))
        }
    }
    var awaitingAnalysisCount: Int { awaitingAnalysisFiles.count }
    var reviewCount: Int { needsHumanReviewFiles.count }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var enabledCategories: [CategoryDefinition] { profile.enabledCategories }
    var visibleCategories: [CategoryDefinition] {
        enabledCategories.filter { definition in
            definition.category != .needsReview
                && files.contains { $0.category == definition.category }
        }
    }
    var duplicateExtraCount: Int { duplicateGroups.reduce(0) { $0 + $1.extras.count } }
    var duplicateWastedSize: Int64 { duplicateGroups.reduce(0) { $0 + $1.wastedSize } }
    var extractedArchiveCount: Int { extractedArchives.count }
    var extractedArchiveReclaimableSize: Int64 {
        extractedArchives.reduce(0) { $0 + $1.archiveSize }
    }
    var redundantInstallerCount: Int { redundantInstallers.count }
    var redundantInstallerReclaimableSize: Int64 {
        redundantInstallers.reduce(0) { $0 + $1.installerSize }
    }
    var totalReclaimableSize: Int64 {
        duplicateWastedSize + extractedArchiveReclaimableSize + redundantInstallerReclaimableSize
    }
    var intelligenceReady: Bool { intelligenceAvailability.isReady }
    var intelligenceStatusTitle: String { intelligenceAvailability.title }
    var intelligenceStatusDetail: String { intelligenceAvailability.detail }

    init() {
        startAutomaticScheduler()
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"), launchAtLogin {
            try? SMAppService.mainApp.register()
        }
    }

    deinit {
        automaticTask?.cancel()
        duplicateScanTask?.cancel()
        archiveScanTask?.cancel()
        installerScanTask?.cancel()
    }

    func definition(for category: ArchiveCategory) -> CategoryDefinition {
        profile.definition(for: category)
            ?? profile.definition(for: .needsReview)
            ?? ProfileStore.fallback.categories.last!
    }

    func requestOnboarding() {
        onboardingRequestID = UUID()
    }

    func scan() async {
        isWorking = true
        progress = nil
        status = "Scanning Downloads…"
        defer { isWorking = false }
        let saved = await store.decisions()
        profile = await profileStore.load()
        intelligenceAvailability = await ai.availability
        files = await scanner.scan(
            downloadsURL: downloadsURL,
            saved: saved,
            profile: profile,
            mode: classificationMode
        )
        folderBranding.brandManagedFolders(downloadsURL: downloadsURL, profile: profile)
        if !files.isEmpty {
            try? await store.pruneDecisions(
                keeping: FileScanner.livePaths(for: files, downloadsURL: downloadsURL)
            )
        }
        status = classificationMode == .formatOnly
            ? "Scanned \(files.count.formatted()) files • Organized by format"
            : "Scanned \(files.count.formatted()) files • Smart content mode"
        if selectedFileID != nil && selectedFile == nil { selectedFileID = nil }
    }

    func refreshAfterActivation() async {
        guard !isWorking else { return }
        let previousCount = files.count
        let previousSelection = selectedFileID
        await scan()

        let removedCount = max(0, previousCount - files.count)
        if removedCount > 0 {
            status = "Refreshed • Removed \(removedCount) deleted file\(removedCount == 1 ? "" : "s")"
        } else if previousSelection != nil, selectedFileID == nil {
            status = "Refreshed • Cleared deleted file preview"
        }
    }

    func setAutomaticOrganization(_ enabled: Bool) {
        automaticOrganization = enabled
        UserDefaults.standard.set(enabled, forKey: "automaticOrganization")
        status = enabled
            ? "Automatic organization is on • Checks hourly"
            : "Automatic organization is off"
        if enabled {
            Task { await runAutomaticOrganization() }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            lastError = error.localizedDescription
            status = "Could not change Launch at Login"
        }
    }

    func setKeepInDock(_ enabled: Bool) {
        guard DockVisibility.apply(keepInDock: enabled) else {
            lastError = "macOS could not change the Dock visibility."
            status = "Could not change Dock visibility"
            return
        }
        keepInDock = enabled
        UserDefaults.standard.set(enabled, forKey: "keepInDock")
        status = enabled
            ? "FileMorrow will stay in the Dock"
            : "FileMorrow is running from the menu bar"
        if enabled {
            NSApplication.shared.activate()
        }
    }

    func runAutomaticOrganization() async {
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
              automaticOrganization,
              !isWorking
        else { return }
        await scan()

        if classificationMode == .smartContent, intelligenceReady, !awaitingAnalysisFiles.isEmpty {
            await analyzeReady()
        }

        guard !approvedReadyFiles.isEmpty else {
            status = reviewCount == 0
                ? "Automatic check complete • Nothing is older than \(archiveDays) days"
                : "Automatic check complete • \(reviewCount) uncertain files need review"
            return
        }

        let count = approvedReadyFiles.count
        await organizeApproved()
        status = "Automatically organized \(count) files • Undo Last Organization is available"
    }

    func checkAndPrepareOrganization() async {
        guard !isWorking else { return }
        await scan()
        if classificationMode == .smartContent, intelligenceReady, !awaitingAnalysisFiles.isEmpty {
            await analyzeReady()
        }
        prepareOrganizationProposal()
    }

    func completeOnboarding(
        mode: ClassificationMode,
        automaticOrganization enabled: Bool,
        launchAtLogin launchEnabled: Bool
    ) async {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        automaticOrganization = enabled
        UserDefaults.standard.set(enabled, forKey: "automaticOrganization")
        await setClassificationMode(mode)
        setLaunchAtLogin(launchEnabled)
        status = enabled
            ? "Setup complete • Automatic organization runs hourly"
            : "Setup complete • Automatic organization is off"
        if enabled { await runAutomaticOrganization() }
    }

    func prepareOrganizationProposal(automaticCheck: Bool = false) {
        let candidates = approvedReadyFiles
        guard !candidates.isEmpty else {
            status = "Nothing is ready to organize"
            return
        }
        let grouped = Dictionary(grouping: candidates) { definition(for: $0.category).name }
        organizationProposal = .init(
            fileCount: candidates.count,
            totalSize: candidates.reduce(0) { $0 + $1.size },
            categoryCounts: grouped.map { ($0.key, $0.value.count) }.sorted { $0.name < $1.name },
            automaticCheck: automaticCheck
        )
        status = automaticCheck
            ? "Automatic check found \(candidates.count) files • Waiting for your approval"
            : "Review the organization plan"
    }

    func organizeApproved() async {
        guard !isWorking else { return }
        isWorking = true
        status = "Organizing approved files…"
        defer { isWorking = false }
        do {
            let count = try await organizer.organize(
                approvedReadyFiles,
                downloadsURL: downloadsURL,
                minimumConfidence: minimumConfidence,
                profile: profile
            )
            lastOrganizedCount = count
            organizationProposal = nil
            status = "Organized \(count) files • Undo Last Organization is available"
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Organization stopped safely"
        }
    }

    func undoLastMove() async {
        guard !isWorking else { return }
        isWorking = true
        status = "Undoing last organization…"
        defer { isWorking = false }
        do {
            let count = try await organizer.undoLast()
            if count > 0 { lastOrganizedCount = 0 }
            status = count == 0 ? "Nothing to undo" : "Restored \(count) files"
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Undo needs attention"
        }
    }

    func count(for view: AgeView) -> Int {
        files.filter {
            switch view {
            case .today: Calendar.current.isDateInToday($0.dateAdded)
            case .yesterday: Calendar.current.isDateInYesterday($0.dateAdded)
            case .lastWeek: $0.dateAdded >= cutoffDate
            case .ready: ArchiveEligibility.isEligible($0, cutoffDate: cutoffDate)
            case .all: true
            case .duplicates, .extracted, .installers: false
            }
        }.count
    }

    private func ageMatches(_ record: FileRecord) -> Bool {
        switch ageSelection {
        case .today: Calendar.current.isDateInToday(record.dateAdded)
        case .yesterday: Calendar.current.isDateInYesterday(record.dateAdded)
        case .lastWeek: record.dateAdded >= cutoffDate
        case .ready: ArchiveEligibility.isEligible(record, cutoffDate: cutoffDate)
        case .all: true
        case .duplicates, .extracted, .installers: false
        }
    }

    func saveDecision(for record: FileRecord) async throws {
        try await store.save(decision(for: record))
    }

    func decision(for record: FileRecord) -> SavedDecision {
        let modified = (try? record.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return .init(
            path: record.url.path,
            modifiedAt: modified,
            category: record.category,
            confidence: record.confidence,
            reason: record.reason,
            source: record.source,
            modelVersion: 6
        )
    }

    func cleanReason(_ value: String, category: ArchiveCategory) -> String {
        let cleaned = value
            .replacingOccurrences(of: #"[\{\}\[\]\"]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lowercased = cleaned.lowercased()
        let weakPhrases = [
            "confirmation request", "information retrieval", "filename analysis",
            "file classification", "classifier", "insufficient evidence"
        ]
        let hasWeakPhrase = weakPhrases.contains(where: lowercased.contains)
        let hasFormattingJunk = cleaned.contains("=") || cleaned.contains("\\")
        let wordCount = cleaned.split(separator: " ").count
        guard !cleaned.isEmpty, !hasWeakPhrase, !hasFormattingJunk, (3...18).contains(wordCount) else {
            return category == .needsReview
                ? "Content is too ambiguous for safe automatic organization"
                : "Content and filename match \(definition(for: category).name)"
        }
        return String(cleaned.prefix(140))
    }

    private func startAutomaticScheduler() {
        automaticTask = Task { [weak self] in
            await self?.runAutomaticOrganization()
            await self?.checkForUpdatesIfDue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3_600))
                guard !Task.isCancelled else { return }
                await self?.runAutomaticOrganization()
                await self?.checkForUpdatesIfDue()
            }
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}
