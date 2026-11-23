import Foundation

/// A small model told to "leave it null" will often write a string saying so
/// instead. Guided generation constrains the shape of the output, not its
/// honesty, so every field gets scrubbed before it is trusted.
enum Sanitize {
    /// Phrases the model reaches for in place of an actual null.
    private static let nullSentinels: Set<String> = [
        "not stated", "notstated", "not specified", "unspecified", "not provided",
        "not listed", "not mentioned", "not given", "unknown", "n/a", "na",
        "none", "null", "nil", "tbd", "doe", "varies", "multiple", "various",
        "not applicable", "see description", "upon request", "",
    ]

    /// Trims, then nils out anything that is a stand-in for "I don't know".
    static func text(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Trailing punctuation is stripped only for the sentinel comparison:
        // the model writes "null," and "none." as often as the bare word, and
        // a real answer keeps whatever punctuation it came with.
        let bare = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        if nullSentinels.contains(bare.lowercased()) { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Words naming which kind of bonus is on offer. One of these, or a
    /// figure, is what separates an offer from an adjective.
    private static let bonusKinds = [
        "sign on", "sign-on", "signon", "signing", "commencement",
        "retention", "completion", "stay", "productivity", "quality",
        "performance",
    ]

    /// Like text, and additionally nils out a bonus that is only an adjective.
    ///
    /// Same reasoning as the sentinels above, one step further on. The guide
    /// tells the model not to copy wording that merely asserts a bonus exists,
    /// and a small model does it anyway: on one run over 37 MedStar postings,
    /// 20 of the 27 answers it produced carried no figure and named no kind of
    /// bonus. They read "Bonus", "Competitive Bonus", "Competitive Bonus and
    /// incentive", "Premium Base Salary and Competitive Bonus". Each is a
    /// verbatim span, so the copy checks pass them, and each renders on a job
    /// page as a labelled field saying nothing. Several also lead with base
    /// salary, which the same guide forbids.
    ///
    /// On three further runs over the same corpus the model produced none of
    /// them, which is the reason this is a function and not a sentence added
    /// to the guide. The failure is real and intermittent, so wording cannot
    /// be shown to have fixed it and a check can be shown to have. The same
    /// argument applies to DutiesDraft, where no such check exists yet.
    ///
    /// A figure or a named kind is the test, and not a cadence: "yearly
    /// incentive" dates a bonus without saying what it is or what it pays.
    static func incentive(_ value: String?) -> String? {
        guard let trimmed = text(value) else { return nil }
        if trimmed.contains(where: { $0.isNumber }) { return trimmed }
        let folded = trimmed.lowercased()
        return bonusKinds.contains(where: { folded.contains($0) }) ? trimmed : nil
    }
}
