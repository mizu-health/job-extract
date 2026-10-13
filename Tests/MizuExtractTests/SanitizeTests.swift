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
}
