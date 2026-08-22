import Foundation
import FoundationModels

/// Guided-generation target mirroring the Go `Salary` type.
///
/// The guides carry the two corrections that observation forced. The model read
/// "190k to 215k" as 190 and 215 until told explicitly to expand the suffix,
/// and it filled fields with zeros until told that absence means null.
@Generable(description: "Base pay stated in a job listing")
struct SalaryDraft {
    @Guide(description: "Lowest base pay figure stated, fully expanded: write 190k as 190000 and 1.2 million as 1200000. No currency symbol, no commas. Null if no base pay is stated.")
    var min: Double?

    @Guide(description: "Highest base pay figure stated, fully expanded the same way. Null if the listing gives a single figure or none.")
    var max: Double?

    @Guide(description: "The period the figures are quoted per. Exactly one of: HOUR, DAY, WEEK, MONTH, YEAR. Null if not stated.")
    var unit: String?
}

/// One description to resolve. Already excerpted around its money tokens by the
/// Go caller, so this is a short passage rather than a full posting.
struct SalaryRequest: Codable {
    var description: String
}

/// A proposal. Every field is optional and "nothing found" is expressed as
/// nulls, never as zeros — the Go side treats a zero as a rejection, and the
/// model's habit of emitting 0 rather than declining is exactly what this
/// contract is defending against.
struct SalaryResponse: Codable {
    var min: Double?
    var max: Double?
    var unit: String?
}

/// Batch salary extraction over stdin/stdout.
///
/// This is the fallback path: the Go patterns already resolved everything with
/// a recognisable pay label, so what arrives here is prose that stated pay
/// without one, such as "Comp is 245k base plus a 20k sign on bonus".
///
/// No plausibility filtering happens here on purpose. The Go side band-checks
/// every proposal, and filtering on both sides would hide this stage's real
/// error rate.
enum Salary {
    /// Units the Go side accepts. Anything else is reported as null rather than
    /// passed through, so an invented unit never reaches the band check.
    static let validUnits: Set<String> = ["HOUR", "DAY", "WEEK", "MONTH", "YEAR"]

    static func run() async {
        let requests: [SalaryRequest]
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            requests = data.isEmpty ? [] : try JSONDecoder().decode([SalaryRequest].self, from: data)
        } catch {
            IO.fail("could not parse stdin as [SalaryRequest]: \(error)", code: 65)
        }

        guard case .available = SystemLanguageModel.default.availability else {
            IO.fail("on-device model unavailable; run `mizu-extract probe` for detail", code: 69)
        }

        var results: [SalaryResponse] = []
        results.reserveCapacity(requests.count)
        for request in requests {
            results.append(await propose(request.description))
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            // Nulls must survive encoding: the response length has to stay
            // aligned with the request, and an omitted field would decode as
            // "no proposal" only by accident.
            FileHandle.standardOutput.write(try encoder.encode(results))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            IO.fail("could not encode output: \(error)", code: 70)
        }
    }

    private static func propose(_ text: String) async -> SalaryResponse {
        let session = LanguageModelSession(instructions: """
            Extract only the base pay a job listing states for the role: a salary or wage.
            Never report a sign-on bonus, retention bonus, relocation allowance, tuition
            benefit, or any budget figure. Those are not base pay.
            If the passage states no base pay, leave every field null.
            Report numbers plainly, with no currency symbol and no thousands separators.
            """)

        do {
            let response = try await session.respond(to: text, generating: SalaryDraft.self)
            let draft = response.content

            guard let unit = draft.unit.map({ $0.uppercased() }), validUnits.contains(unit) else {
                return SalaryResponse(min: nil, max: nil, unit: nil)
            }
            guard let low = draft.min, low > 0 else {
                return SalaryResponse(min: nil, max: nil, unit: nil)
            }
            // A max below the min is a mis-read, not a range. Drop the max and
            // keep the floor rather than discarding a usable figure.
            var high = draft.max
            if let h = high, h < low { high = nil }

            return SalaryResponse(min: low, max: high, unit: unit)
        } catch {
            return SalaryResponse(min: nil, max: nil, unit: nil)
        }
    }
}
