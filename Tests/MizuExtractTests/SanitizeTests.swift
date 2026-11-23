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

/// A bonus the model copied verbatim and correctly can still be useless. These
/// are the answers it actually gave over the MedStar corpus.
@Suite("Incentive guard")
struct IncentiveTests {
    @Test("nils out a bonus that is only an adjective", arguments: [
        "Bonus",
        "Competitive Bonus",
        "Competitive Bonus and incentive",
        "Premium Base Salary and Competitive Bonus",
        "Premium Base Salary & Competitive Bonus",
        "Premium Base Salary, Competitive Bonus & yearly incentive",
        "Competitive bonus structure",
    ])
    func dropsWordingOnly(_ input: String) {
        #expect(Sanitize.incentive(input) == nil)
    }

    @Test("keeps a bonus that states an amount", arguments: [
        "• $75,000 sign-on & retention bonus with full-time commitment",
        "• Competitive $100,000 bonus",
        "Call requirement includes 1/week and 1/weekend per month - $25,000 additional on top of salary",
        "$50K signing bonus",
    ])
    func keepsAmounts(_ input: String) {
        #expect(Sanitize.incentive(input) == input)
    }

    @Test("keeps a bonus that names its kind without an amount", arguments: [
        "Sign-on bonus available for qualified candidates",
        "Retention bonus paid at the end of year two",
        "A commencement bonus is offered",
        "Productivity bonus based on collections",
    ])
    func keepsNamedKinds(_ input: String) {
        #expect(Sanitize.incentive(input) == input)
    }

    @Test("still applies the null sentinels")
    func sentinelsStillApply() {
        #expect(Sanitize.incentive("none") == nil)
        #expect(Sanitize.incentive("not stated") == nil)
        #expect(Sanitize.incentive(nil) == nil)
        #expect(Sanitize.incentive("   ") == nil)
    }
}
