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

    private static let stateCodes: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI",
        "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN",
        "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
        "OK", "OR", "PA", "PR", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA",
        "WA", "WV", "WI", "WY",
    ]

    private static let employmentTypes: Set<String> = [
        "full_time", "part_time", "per_diem", "locum", "prn",
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

    /// State is a closed set, so it gets checked rather than trusted.
    static func state(_ value: String?) -> String? {
        guard let value = text(value) else { return nil }
        let upper = value.uppercased()
        return stateCodes.contains(upper) ? upper : nil
    }

    /// Same for employment type: the @Guide lists the vocabulary, but nothing
    /// enforces it.
    static func employmentType(_ value: String?) -> String? {
        guard let value = text(value) else { return nil }
        let normalized = value.lowercased().replacingOccurrences(of: " ", with: "_")
        return employmentTypes.contains(normalized) ? normalized : nil
    }
}
