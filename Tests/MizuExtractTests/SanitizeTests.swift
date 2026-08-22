import Testing
@testable import MizuExtract

@Suite("Sanitize")
struct SanitizeTests {
    @Test("nils out placeholder text the model writes instead of null", arguments: [
        "not stated", "Not Specified", "N/A", "unknown", "TBD", "  ", "DOE",
    ])
    func nullsSentinels(_ input: String) {
        #expect(Sanitize.text(input) == nil)
    }

    @Test("keeps real values and trims them")
    func keepsRealValues() {
        #expect(Sanitize.text("  Asheville ") == "Asheville")
    }

    @Test("accepts valid state codes in any case")
    func acceptsStates() {
        #expect(Sanitize.state("nc") == "NC")
        #expect(Sanitize.state("NC") == "NC")
    }

    @Test("rejects anything outside the closed state set")
    func rejectsNonStates() {
        #expect(Sanitize.state("North Carolina") == nil)
        #expect(Sanitize.state("ZZ") == nil)
        #expect(Sanitize.state("not stated") == nil)
    }

    @Test("normalizes employment type and rejects invented ones")
    func employmentTypes() {
        #expect(Sanitize.employmentType("Full Time") == "full_time")
        #expect(Sanitize.employmentType("locum") == "locum")
        #expect(Sanitize.employmentType("contract-to-hire") == nil)
    }
}
