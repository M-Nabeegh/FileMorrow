import Foundation

enum EvidenceClassifier {
    static func classify(_ evidence: String, profile: OrganizationProfile) -> RuleDecision? {
        let normalized = evidence.lowercased()
        let scored = profile.enabledCategories
            .filter { $0.category != .needsReview && !$0.contentKeywords.isEmpty }
            .map { definition in
                let matches = definition.contentKeywords.filter { normalized.contains($0.lowercased()) }
                let score = matches.reduce(0) { partial, phrase in
                    partial + (phrase.contains(" ") ? 3 : 2)
                }
                return (definition, score, matches)
            }
            .sorted { $0.1 > $1.1 }

        guard let winner = scored.first,
              winner.1 >= 4,
              winner.1 - (scored.dropFirst().first?.1 ?? 0) >= 2 else {
            return nil
        }

        return .init(
            category: winner.0.category,
            confidence: min(96, 84 + winner.1),
            reason: "Local content signals: \(winner.2.prefix(3).joined(separator: ", "))"
        )
    }
}
