import Foundation
import FoundationModels

/// One posting to enrich.
///
/// The whole description, not excerpts. An earlier contract sent passages
/// selected by keyword matching on the Go side, which meant a section written
/// in unexpected words was never sent at all and the result was
/// indistinguishable from a posting that had no such section.
///
/// Measured across live federal announcements the assembled description runs
/// about 5,700 characters at the median and 8,000 at the longest, roughly 1,400
/// and 2,000 tokens, against a 4,096-token window covering instructions, input,
/// schema and output together. So they fit, and the rare one that does not is
/// reported rather than split pre-emptively.
struct EnrichRequest: Codable {
    var description: String
    /// The specialty vocabulary this posting's site accepts. Sent from Go so
    /// the model chooses from the real taxonomy rather than inventing labels.
    var specialtySlugs: [String] = []
}

/// What the model proposes. Every field optional; absence is expressed as null,
/// never as an empty string or a zero.
struct EnrichResponse: Codable {
    var callType: String?
    var callRatio: Int?
    var shift: String?
    var shiftHours: [Int]?
    var scheduleDetails: String?
    var benefits: String?
    var incentiveCompensation: String?
    var responsibilities: String?
    var specialties: [String]?
    /// Field groups whose prompt did not fit the context window, named so the
    /// caller can tell "the description says nothing about benefits" apart from
    /// "we never managed to ask". Empty on the ordinary path.
    ///
    /// This is the signal that decides whether splitting descriptions is worth
    /// building. Until it starts appearing, it is not.
    var overflowed: [String]? = nil
}

/// Scheduling fields. The closed sets are named in the guides so the model has
/// a vocabulary to choose from rather than one to invent; the Go side rejects
/// anything outside them regardless.
@Generable(description: "On-call requirement stated in a job listing")
struct CallDraft {
    @Guide(description: "How call works for this role. NO_CALL if it says there is no call. HOME_CALL if call is taken from home or by pager. IN_HOUSE_CALL if the clinician must be physically present. SHARED_CALL if call is rotated, shared, or pooled among a group. Null only if the passage never mentions call at all.")
    var callType: String?

    @Guide(description: "Call frequency denominator only, so '1 in 6 call' is 6 and 'one in seven' is 7. Null if no frequency is stated.")
    var callRatio: Int?
}

@Generable(description: "Working hours stated in a job listing")
struct ScheduleDraft {
    @Guide(description: "Shift pattern. Exactly one of: DAY, EVENING, NIGHT, ROTATING. Null if not stated.")
    var shift: String?

    @Guide(description: "Length of a single shift in whole hours, one of 8, 10, 12, 16 or 24. If the listing gives start and end times, work out the length. Null if it cannot be determined.")
    var shiftHours: [Int]?

    @Guide(description: "ONE single continuous sentence describing the work schedule, copied EXACTLY word for word from the text. Never join two sentences. Never add or remove punctuation. Null if the text has no such sentence.")
    var scheduleDetails: String?
}

/// Duties, a pure verbatim lift.
@Generable(description: "Duties and responsibilities stated in a job listing")
struct DutiesDraft {
    @Guide(description: "ONLY the sentences describing what the person will actually do in the job, copied EXACTLY word for word from a single continuous run of text. Start at the first duty. Stop at the last duty. Do NOT include pay, benefits, leave, insurance, work schedule, hours, telework, relocation, appointment type, or how to apply. Do NOT include an opening paragraph about the announcement, the deadline, or the facility. Null if the text lists no duties.")
    var responsibilities: String?
}

/// Clinical specialties, chosen from the site's own taxonomy.
@Generable(description: "Clinical anesthesia specialties a job listing calls for")
struct SpecialtyDraft {
    @Guide(description: "Specialty slugs from the provided list that the passage actually calls for. Choose only from the list given in the prompt, copying each slug exactly. Include a specialty only if the passage names that kind of work; do not infer it from the employer being a hospital. Empty if none apply.")
    var specialties: [String]?
}

/// Benefits and incentives, both pure verbatim lifts.
@Generable(description: "Benefits and incentive pay stated in a job listing")
struct BenefitsDraft {
    @Guide(description: "The passage describing benefits, copied EXACTLY word for word from the text. Do not paraphrase, summarise or shorten. Null if the text describes no benefits.")
    var benefits: String?

    @Guide(description: "The passage describing bonuses or incentive pay the employer is actually offering, copied EXACTLY word for word. Do not include base salary. If the text says an incentive is not authorized, not available, or none, that is not an incentive being offered: answer null. Null if absent.")
    var incentiveCompensation: String?
}

/// Batch enrichment over stdin/stdout.
///
/// This is the extractive pass: the model decides which span of the text answers
/// each field, and copies it. It never writes anything of its own. That
/// constraint is what makes the output checkable — the Go side rejects any span
/// that does not appear character for character in the source, which is the one
/// verification a generative answer could never support.
enum Enrich {
    static func run() async {
        let requests: [EnrichRequest]
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            requests = data.isEmpty ? [] : try JSONDecoder().decode([EnrichRequest].self, from: data)
        } catch {
            IO.fail("could not parse stdin as [EnrichRequest]: \(error)", code: 65)
        }

        guard case .available = SystemLanguageModel.default.availability else {
            IO.fail("on-device model unavailable; run `mizu-extract probe` for detail", code: 69)
        }

        var results: [EnrichResponse] = []
        results.reserveCapacity(requests.count)
        for request in requests {
            results.append(await enrichOne(request))
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(results))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            IO.fail("could not encode output: \(error)", code: 70)
        }
    }

    /// Five focused calls over the whole description.
    ///
    /// Field groups stay separate because bundling them made the model answer
    /// the easy parts and leave the rest null: asked about call alongside
    /// hours, it reported the hours and said nothing about call even where the
    /// text described it plainly.
    private static func enrichOne(_ req: EnrichRequest) async -> EnrichResponse {
        var out = EnrichResponse()
        let text = req.description
        guard !text.isEmpty else { return out }
        var overflowed: [String] = []

        func record(_ group: String, _ overflow: Bool) {
            if overflow, !overflowed.contains(group) { overflowed.append(group) }
        }

        // Call is asked separately from the hours questions for the reason
        // above: bundled, it was the field the model dropped.
        let call = await propose(CallDraft.self, from: text, instructions: """
            The passage is from a clinical job listing. Decide how on-call duty works for this role.
            Answer from what the passage says, not from what is typical.
            Leave the field null only if call is never mentioned.
            """)
        record("call", call.overflowed)
        if let c = call.value {
            out.callType = c.callType
            out.callRatio = c.callRatio
        }

        let schedule = await propose(ScheduleDraft.self, from: text, instructions: """
            Read the passage and report only what it actually states about working hours.
            Copy any quoted sentence exactly as written, word for word, from a single
            continuous run of text. Never join separate sentences together.
            If the passage does not state something, leave that field null. Never guess.
            """)
        record("schedule", schedule.overflowed)
        if let d = schedule.value {
            out.shift = d.shift
            out.shiftHours = d.shiftHours
            out.scheduleDetails = Sanitize.text(d.scheduleDetails)
        }

        let benefits = await proposeVerbatim(BenefitsDraft.self, from: text, instructions: """
            Read the passage and copy out the parts describing benefits and incentive pay.
            Copy them exactly as written, word for word. Never summarise or rewrite.
            An incentive the employer says is not authorized or not available is not
            an incentive being offered; leave that field null.
            If the passage does not describe something, leave that field null.
            """, spans: { [$0.benefits, $0.incentiveCompensation] })
        record("benefits", benefits.overflowed)
        if let d = benefits.value {
            out.benefits = Sanitize.text(d.benefits)
            out.incentiveCompensation = Sanitize.text(d.incentiveCompensation)
        }

        let duties = await proposeVerbatim(DutiesDraft.self, from: text, instructions: """
            Copy out only the part that says what this person will do in the job.
            Copy it exactly as written, word for word. Never summarise or rewrite.

            A job listing surrounds its duties with other things: an opening
            paragraph about the announcement, pay and benefits, the work
            schedule, telework and relocation notes, how to apply. None of those
            are duties. Begin at the first duty and end at the last one.

            Leave it null if the passage lists no duties.
            """, spans: { [$0.responsibilities] })
        record("duties", duties.overflowed)
        if let d = duties.value {
            out.responsibilities = Sanitize.text(d.responsibilities)
        }

        if !req.specialtySlugs.isEmpty {
            let list = req.specialtySlugs.joined(separator: ", ")
            let specialty = await propose(SpecialtyDraft.self, from: """
                Allowed specialties: \(list)

                Listing text:
                \(text)
                """, instructions: """
                Decide which of the allowed specialties the listing actually calls for.
                Use only slugs from the allowed list, copied exactly.
                Choose none rather than guessing. A general anesthesia post that never
                mentions a subspecialty gets only general-anesthesiology.
                """)
            record("specialty", specialty.overflowed)
            out.specialties = specialty.value?.specialties
        }

        if !overflowed.isEmpty { out.overflowed = overflowed }
        return out
    }

    /// The outcome of one ask. Overflow is separated from a null answer because
    /// they mean opposite things: one is the model reporting that the text says
    /// nothing, the other is us failing to ask.
    struct Proposal<T> {
        var value: T?
        var overflowed: Bool = false
    }

    /// Like propose, but checks its own answer and asks again when the model
    /// reworded instead of copying.
    ///
    /// The Go caller rejects any span that is not a verbatim substring, which is
    /// the real gate. Checking here too converts about half of those rejections
    /// into a second attempt that succeeds, rather than losing the field: on a
    /// federal corpus the model paraphrased benefits roughly half the time on
    /// the first ask.
    private static func proposeVerbatim<T: Generable>(
        _ type: T.Type,
        from text: String,
        instructions: String,
        spans: (T) -> [String?]
    ) async -> Proposal<T> {
        let haystack = normalized(text)

        for attempt in 0..<2 {
            let extra = attempt == 0 ? "" : """


                Your previous answer was NOT copied from the passage. Copy an exact
                run of characters from it this time, or answer null.
                """
            let p = await propose(type, from: text, instructions: instructions + extra)
            if p.overflowed { return p }
            guard let candidate = p.value else { continue }

            let bad = spans(candidate).contains { value in
                guard let v = value, !normalized(v).isEmpty else { return false }
                return !haystack.contains(normalized(v))
            }
            if !bad { return p }
            if attempt == 1 { return p }  // let Go record the rejection
        }
        return Proposal(value: nil)
    }

    /// Whitespace-insensitive comparison, matching what the Go side does before
    /// its own check. Without it every span with a newline in it would fail.
    private static func normalized(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func propose<T: Generable>(_ type: T.Type, from text: String, instructions: String) async -> Proposal<T> {
        let session = LanguageModelSession(instructions: instructions)
        do {
            return Proposal(value: try await session.respond(to: text, generating: type).content)
        } catch let error as LanguageModelSession.GenerationError {
            // Overflow is the one failure worth telling the caller about: it is
            // the only one that means the description was never read, and the
            // only one a change on our side could fix.
            if case .exceededContextWindowSize = error {
                FileHandle.standardError.write(Data("context window exceeded on a \(text.count)-character prompt\n".utf8))
                return Proposal(value: nil, overflowed: true)
            }
            // A refusal or a guardrail trip is an ordinary outcome here, not a
            // failure worth aborting the batch for.
            return Proposal(value: nil)
        } catch {
            return Proposal(value: nil)
        }
    }
}
