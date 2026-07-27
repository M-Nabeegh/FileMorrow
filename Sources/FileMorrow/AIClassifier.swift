import Foundation
import FoundationModels

@Generable
struct AIClassification {
    @Guide(description: "Zero-based index of the single best category from the numbered list", .range(0...50))
    var categoryIndex: Int

    @Guide(description: "Confidence from 0 to 100", .range(0...100))
    var confidence: Int

    @Guide(description: "One concise evidence-based reason")
    var reason: String
}

actor AIClassifier {
    var availability: IntelligenceAvailabilityState {
        IntelligenceAvailabilityState(SystemLanguageModel.default.availability)
    }

    func classify(
        filename: String,
        excerpt: String,
        categories: [CategoryDefinition]
    ) async throws -> (AIClassification, CategoryDefinition) {
        let usable = Array(categories.prefix(51))
        let categoryGuide = usable.enumerated().map { index, category in
            """
            \(index). \(category.name)
               Purpose: \(category.description)
               Examples: \(category.examples.joined(separator: "; "))
            """
        }.joined(separator: "\n")

        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: """
            Classify personal download files privately and conservatively.
            Choose only a zero-based category index from the supplied numbered list.
            Prefer the file's subject over its container format.
            Choose a broad category such as Documents & Books or Code & Data when
            the format is known but the subject is unclear. Use Needs Review only
            when neither the filename, extracted evidence, nor file format supports
            any category, and keep its confidence below 60. Never invent unseen content.
            """
        )
        let prompt = """
        Active organization profile:
        \(categoryGuide)

        Filename: \(filename)
        Extracted local evidence:
        \(excerpt)
        """
        let result = try await session.respond(to: prompt, generating: AIClassification.self).content
        guard usable.indices.contains(result.categoryIndex) else {
            throw AIClassificationError.invalidCategoryIndex
        }
        return (result, usable[result.categoryIndex])
    }
}

enum AIClassificationError: LocalizedError {
    case invalidCategoryIndex

    var errorDescription: String? {
        "Apple Intelligence returned a category outside the active profile."
    }
}
