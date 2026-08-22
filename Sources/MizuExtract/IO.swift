import Foundation

/// One raw listing as harvested by the Go crawler, before any interpretation.
struct RawListing: Codable {
    /// Stable identity from the source system. Carried through untouched so the
    /// Go side can upsert idempotently and detect reposts.
    var source: String
    var externalID: String
    var url: String?
    var title: String?
    var rawDescription: String
}

/// What the extractor hands back. Deliberately separate from the API's own job
/// model: this is a proposal, not a job. The Go side validates and decides.
struct ExtractedListing: Codable {
    var source: String
    var externalID: String
    var fields: ExtractedFields
    /// 0.0-1.0. Drives auto-publish vs. review queue on the Go side.
    var confidence: Double
    /// Human-readable notes on anything the extractor was unsure about.
    var warnings: [String]
}

/// Placeholder shape. The real field schema is still to be designed; this exists
/// so the guided-generation path is proven end to end.
struct ExtractedFields: Codable {
    var normalizedTitle: String?
    var city: String?
    var state: String?
    var employmentType: String?
}

enum IO {
    static func readInput() throws -> [RawListing] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([RawListing].self, from: data)
    }

    static func writeOutput(_ listings: [ExtractedListing]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(listings)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("mizu-extract: \(message)\n".utf8))
        exit(code)
    }
}
