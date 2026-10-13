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
}
