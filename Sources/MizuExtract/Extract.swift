import Foundation
import FoundationModels

/// Guided-generation target. Every field is optional: the model saying nothing
/// is a far better outcome than the model inventing a value, and an absent field
/// becomes a warning rather than bad data.
@Generable(description: "Structured fields extracted from a job listing description")
struct ListingDraft {
    @Guide(description: "The job title with recruiter noise, req numbers, and location suffixes removed")
    var normalizedTitle: String?

    @Guide(description: "City the position is located in, if stated")
    var city: String?

    @Guide(description: "Two-letter US state code, if stated")
    var state: String?

    @Guide(description: "One of: full_time, part_time, per_diem, locum, prn")
    var employmentType: String?
}

enum Extract {
    static func run() async {
        let listings: [RawListing]
        do {
            listings = try IO.readInput()
        } catch {
            IO.fail("could not parse stdin as [RawListing]: \(error)", code: 65)
        }

        guard case .available = SystemLanguageModel.default.availability else {
            IO.fail("on-device model unavailable; run `mizu-extract probe` for detail", code: 69)
        }

        var results: [ExtractedListing] = []
        for listing in listings {
            results.append(await extractOne(listing))
        }

        do {
            try IO.writeOutput(results)
        } catch {
            IO.fail("could not encode output: \(error)", code: 70)
        }
    }

    private static func extractOne(_ listing: RawListing) async -> ExtractedListing {
        let session = LanguageModelSession(instructions: """
            You extract structured fields from job listings for anesthesia clinicians.
            Only report a value that is explicitly stated in the listing.
            If a field is not stated, leave it null. Never guess or infer.
            Never write placeholder text such as "not stated" or "unknown".
            """)

        do {
            let response = try await session.respond(
                to: listing.rawDescription,
                generating: ListingDraft.self
            )
            let draft = response.content

            // Everything the model returns is scrubbed before it is trusted.
            var title = Sanitize.text(draft.normalizedTitle)
            let city = Sanitize.text(draft.city)
            let state = Sanitize.state(draft.state)
            let employmentType = Sanitize.employmentType(draft.employmentType)

            var warnings: [String] = []

            // A title the model composed rather than read is worse than none.
            if let candidate = title, !isGrounded(candidate, in: listing) {
                warnings.append("title '\(candidate)' not grounded in source text; dropped")
                title = nil
            }

            if title == nil { warnings.append("no title extracted") }
            if state == nil { warnings.append("no state extracted") }
            if city == nil { warnings.append("no city extracted") }
            if employmentType == nil { warnings.append("no employment type extracted") }

            return ExtractedListing(
                source: listing.source,
                externalID: listing.externalID,
                fields: ExtractedFields(
                    normalizedTitle: title,
                    city: city,
                    state: state,
                    employmentType: employmentType
                ),
                confidence: score(warnings: warnings),
                warnings: warnings
            )
        } catch {
            return ExtractedListing(
                source: listing.source,
                externalID: listing.externalID,
                fields: ExtractedFields(),
                confidence: 0.0,
                warnings: ["extraction failed: \(error)"]
            )
        }
    }

    /// Cheap hallucination guard: every meaningful word of an extracted title
    /// should appear somewhere in the text it was supposedly read from.
    private static func isGrounded(_ candidate: String, in listing: RawListing) -> Bool {
        let haystack = ((listing.title ?? "") + " " + listing.rawDescription).lowercased()
        let words = candidate.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count > 2 }
        guard !words.isEmpty else { return false }
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Four fields, each worth a quarter. The Go side decides what threshold
    /// earns auto-publish versus the review queue.
    private static func score(warnings: [String]) -> Double {
        let missing = min(warnings.count, 4)
        return (4.0 - Double(missing)) / 4.0
    }
}
