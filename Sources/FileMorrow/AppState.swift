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
    var automaticOrganization = UserDefaults.standard.object(forKey: "automaticOrganization") as? Bool ?? false
    var launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? false
    var keepInDock = UserDefaults.standard.object(forKey: "keepInDock") as? Bool ?? true
    var duplicateGroups: [DuplicateGroup] = []
    var isScanningDuplicates = false
    var duplicateScanProgress: DuplicateScanProgress?
    var organizationProposal: OrganizationProposal?
    var lastOrganizedCount = 0
    var onboardingRequestID: UUID?
    var profile = ProfileStore.fallback
    private var shouldCancelAnalysis = false

    @ObservationIgnored private let store = PersistenceStore()
    @ObservationIgnored private let profileStore = ProfileStore()
    @ObservationIgnored private let scanner = FileScanner()
    @ObservationIgnored private let extractor = ContentExtractor()
    @ObservationIgnored private let ai = AIClassifier()
    @ObservationIgnored private let duplicateScanner = DuplicateScanner()
    @ObservationIgnored private let folderBranding = FolderBrandingService()
    @ObservationIgnored private lazy var organizer = OrganizerService(store: store)
    @ObservationIgnored private var automaticTask: Task<Void, Never>?
    @ObservationIgnored private var duplicateScanTask: Task<Void, Never>?
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
        return readyFiles.filter {
            $0.source == .rule && ($0.confidence < minimumConfidence || $0.category == .archives)
        }
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
            ? "Automatic checks are on • Approval is required before every move"
            : "Automatic checks are off"
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

        prepareOrganizationProposal(automaticCheck: true)
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
            ? "Setup complete • Hourly checks ask before moving files"
            : "Setup complete • Automatic checks are off"
        await scan()
        if enabled { prepareOrganizationProposal(automaticCheck: true) }
    }

    func analyzeReady(limit: Int? = nil) async {
        guard !isWorking else { return }
        guard classificationMode == .smartContent else {
            status = "Switch to Smart Content in Settings to use Apple Intelligence"
            return
        }
        guard intelligenceReady else {
            status = "Apple Intelligence is not available on this Mac"
            lastError = intelligenceStatusDetail
            return
        }
        let candidates = files.indices.filter {
            !files[$0].isOrganized
                && files[$0].dateAdded < cutoffDate
                && files[$0].source == .rule
                && (files[$0].confidence < minimumConfidence || files[$0].category == .archives)
        }
        let selected = limit.map { Array(candidates.prefix($0)) } ?? candidates
        guard !selected.isEmpty else {
            status = "Nothing needs AI analysis"
            return
        }

        isWorking = true
        isAnalyzing = true
        shouldCancelAnalysis = false
        lastError = nil
        defer {
            isWorking = false
            isAnalyzing = false
            progress = nil
        }

        var completed = 0
        for index in selected {
            guard !Task.isCancelled, !shouldCancelAnalysis else { break }
            let record = files[index]
            status = "Reading \(record.name)…"
            let type = UTType(record.contentType)
            let excerpt = await extractor.extract(from: record.url, contentType: type)
            if let localDecision = EvidenceClassifier.classify(excerpt, profile: profile) {
                files[index].category = localDecision.category
                files[index].confidence = localDecision.confidence
                files[index].reason = localDecision.reason
                files[index].source = .localContent
                files[index].excerpt = excerpt
                try? await saveDecision(for: files[index])
                completed += 1
                progress = Double(completed) / Double(selected.count)
                continue
            }
            do {
                status = "Apple Intelligence • \(completed + 1) of \(selected.count)"
                let (result, definition) = try await ai.classify(
                    filename: record.name,
                    excerpt: excerpt,
                    categories: profile.enabledCategories
                )
                let category = definition.category
                if category == .needsReview, record.category != .needsReview {
                    files[index].category = record.category
                    files[index].confidence = max(record.confidence, minimumConfidence)
                    files[index].reason = "Known \(self.definition(for: record.category).name) format; no stronger subject was found"
                    files[index].source = .formatFallback
                } else {
                    files[index].category = category
                    files[index].confidence = category == .needsReview ? min(result.confidence, 59) : result.confidence
                    files[index].reason = cleanReason(result.reason, category: category)
                    files[index].source = .appleAI
                }
                files[index].excerpt = excerpt
                try await saveDecision(for: files[index])
            } catch {
                // A temporary model failure must never erase a useful format rule.
                files[index] = record
                lastError = error.localizedDescription
            }
            completed += 1
            progress = Double(completed) / Double(selected.count)
        }
        status = shouldCancelAnalysis
            ? "Stopped after \(completed) files • Decisions saved"
            : "Analyzed \(completed) files • No files moved"
    }

    func cancelAnalysis() {
        shouldCancelAnalysis = true
        status = "Stopping after the current file…"
    }

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
            status = "Moved \(count) exact duplicate copies to Trash"
            duplicateGroups = await duplicateScanner.scan(root: downloadsURL)
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Duplicate cleanup needs attention"
        }
        isWorking = false
    }

    func setClassificationMode(_ mode: ClassificationMode) async {
        guard mode != classificationMode else { return }
        if isAnalyzing { cancelAnalysis() }
        classificationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "classificationMode")
        await scan()
    }

    func correctSelected(to category: ArchiveCategory) async {
        guard let id = selectedFileID, let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].category = category
        files[index].confidence = 100
        files[index].reason = "Confirmed by you"
        files[index].source = .user
        try? await saveDecision(for: files[index])
        status = "Saved your correction"
    }

    func teach(
        fileID: String,
        category: ArchiveCategory,
        filenameKeyword: String,
        rememberExtension: Bool
    ) async {
        guard let fileIndex = files.firstIndex(where: { $0.id == fileID }),
              let categoryIndex = profile.categories.firstIndex(where: { $0.category == category }),
              category != .needsReview else { return }

        let filename = files[fileIndex].name
        let keyword = filenameKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty,
           !profile.categories[categoryIndex].filenameKeywords.contains(where: {
               $0.caseInsensitiveCompare(keyword) == .orderedSame
           }) {
            profile.categories[categoryIndex].filenameKeywords.append(keyword)
        }
        if !profile.categories[categoryIndex].examples.contains(where: {
            $0.caseInsensitiveCompare(filename) == .orderedSame
        }) {
            profile.categories[categoryIndex].examples.append(filename)
        }

        let ext = RuleClassifier.normalizedExtension(files[fileIndex].url)
        if rememberExtension, !ext.isEmpty {
            for index in profile.categories.indices {
                profile.categories[index].extensions.removeAll {
                    $0.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        .caseInsensitiveCompare(ext) == .orderedSame
                }
            }
            profile.categories[categoryIndex].extensions.append(ext)
        }

        files[fileIndex].category = category
        files[fileIndex].confidence = 100
        files[fileIndex].reason = "Confirmed by you and added to the organization profile"
        files[fileIndex].source = .user
        do {
            try await profileStore.save(profile)
            try await saveDecision(for: files[fileIndex])
            status = rememberExtension || !keyword.isEmpty
                ? "Correction saved • Future matching files will use it"
                : "Correction saved • Example added for Apple Intelligence"
        } catch {
            lastError = error.localizedDescription
            status = "Could not save teaching rule"
        }
    }

    func setCategoryEnabled(_ id: String, enabled: Bool) async {
        guard let index = profile.categories.firstIndex(where: { $0.id == id }),
              profile.categories[index].category != .needsReview else { return }
        profile.categories[index].enabled = enabled
        await persistProfileAndRescan()
    }

    func upsertCategory(_ definition: CategoryDefinition) async {
        if let index = profile.categories.firstIndex(where: { $0.id == definition.id }) {
            profile.categories[index] = definition
        } else {
            let insertionIndex = profile.categories.firstIndex { $0.category == .needsReview }
                ?? profile.categories.endIndex
            profile.categories.insert(definition, at: insertionIndex)
        }
        await persistProfileAndRescan()
    }

    func removeCategory(_ id: String) async {
        guard id != ArchiveCategory.needsReview.rawValue else { return }
        profile.categories.removeAll { $0.id == id }
        await persistProfileAndRescan()
    }

    func importProfile(from url: URL) async {
        do {
            profile = try await profileStore.importProfile(from: url)
            status = "Imported \(profile.name) profile"
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Profile import failed"
        }
    }

    func exportProfile(to url: URL) async {
        do {
            try await profileStore.export(profile, to: url)
            status = "Exported organization profile"
        } catch {
            lastError = error.localizedDescription
            status = "Profile export failed"
        }
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
            case .duplicates: false
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
        case .duplicates: false
        }
    }

    private func saveDecision(for record: FileRecord) async throws {
        let modified = (try? record.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        try await store.save(.init(
            path: record.url.path,
            modifiedAt: modified,
            category: record.category,
            confidence: record.confidence,
            reason: record.reason,
            source: record.source,
            modelVersion: 6
        ))
    }

    private func cleanReason(_ value: String, category: ArchiveCategory) -> String {
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

    private func persistProfileAndRescan() async {
        do {
            try await profileStore.save(profile)
            status = "Saved profile changes"
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Could not save profile"
        }
    }

    private func startAutomaticScheduler() {
        automaticTask = Task { [weak self] in
            await self?.runAutomaticOrganization()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3_600))
                guard !Task.isCancelled else { return }
                await self?.runAutomaticOrganization()
            }
        }
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}
