import Foundation
import LillistCore
#if canImport(FoundationModels)
import FoundationModels

/// Shared plumbing for the on-device and Private Cloud Compute translators:
/// building the session instructions and running the guided-generation
/// call. Kept in one place so both tiers stay byte-identical in how they
/// talk to the model — only which `LanguageModel` they hand to the session
/// differs.
@available(iOS 26, macOS 26, *)
enum FoundationModelsInstructions {
    /// Builds the closed-vocabulary instructions for a translation session.
    /// Field/comparator vocabularies are derived from `Field`/`Op` directly
    /// (never hand-duplicated), and known tag names come from `context` so
    /// the model grounds "tagged Home" against what actually exists rather
    /// than inventing one.
    static func build(for context: TranslationContext) -> String {
        let fields = GeneratedFilter.offeredFields(from: context).map(\.rawValue).sorted()
        let comparators = GeneratedFilter.offeredComparators.map(\.rawValue).sorted()
        let tagNames = context.knownTags.map(\.name).sorted()
        return """
        Translate a task-search query into structured filter clauses. Only
        emit a clause for something the query actually asks about — never
        add extra clauses to fill out the schema.

        Legal field names: \(fields.joined(separator: ", ")).
        Legal comparators: \(comparators.joined(separator: ", ")).
        Known tag names: \(tagNames.isEmpty ? "(none)" : tagNames.joined(separator: ", ")).

        Dates are day-granularity only — there is no "now", only whole days.
        "in the past" or "overdue" means the relevant date field is BEFORE
        "today" (not after). "added"/"created" refers to the createdAt
        field. "due"/"deadline" refers to the deadline field.
        "incomplete" or "not done" means status is not "closed".
        "tagged X" or "with the X tag" means the tag field includesAny
        tagNames: [X] — NOT a title/notes text search.
        Never invent a field, comparator, or tag name outside the lists
        above.

        Examples:
        - "added before today" -> field: createdAt, comparator: before, relativeDate: today
        - "tagged Work" -> field: tag, comparator: includesAny, tagNames: ["Work"]
        - "due in the past and incomplete" -> two clauses: (field: deadline, comparator: before, relativeDate: today) and (field: status, comparator: isNot, statuses: ["closed"])
        """
    }

    /// Runs the guided-generation call and normalizes any failure into
    /// `TranslationFailure.underlying` — network errors, quota limits, and
    /// service-unavailable errors on the Private Cloud Compute tier all
    /// surface the same way to callers, which decide independently whether
    /// to degrade to a lower tier.
    static func respond(session: LanguageModelSession, query: String) async throws -> GeneratedFilter {
        do {
            let result = try await session.respond(to: query, generating: GeneratedFilter.self)
            return result.content
        } catch let failure as TranslationFailure {
            throw failure
        } catch {
            throw TranslationFailure.underlying(String(describing: error))
        }
    }
}
#endif
