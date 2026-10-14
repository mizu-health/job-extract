import Testing
@testable import MizuExtract

/// The check that decides whether a copied span gets a second ask. Go applies
/// the same comparison and rejects what fails it, so a mismatch here would
/// either waste a retry or let a paraphrase through to be dropped.
@Suite("Verbatim check")
struct VerbatimTests {
    let source = """
        Benefits

        Health insurance, 401(k) match,
        6 weeks PTO and a $5,000 CME allowance.
        """

    @Test("collapses runs of whitespace and newlines to single spaces")
    func normalizes() {
        #expect(Enrich.normalized("  a\n\n b\t c ") == "a b c")
    }

    @Test("accepts an exact copy")
    func exactCopy() {
        #expect(Enrich.isVerbatim(["6 weeks PTO and a $5,000 CME allowance."], in: source))
    }

    @Test("accepts a copy that wraps lines differently from the source")
    func whitespaceDifferences() {
        #expect(Enrich.isVerbatim(["Health insurance, 401(k) match, 6 weeks PTO"], in: source))
    }

    @Test("rejects a paraphrase")
    func paraphrase() {
        #expect(!Enrich.isVerbatim(["Six weeks of paid time off."], in: source))
    }

    @Test("rejects the group if any one span was reworded")
    func oneBadSpan() {
        #expect(!Enrich.isVerbatim(["Health insurance", "Generous CME budget"], in: source))
    }

    @Test("nil and blank spans have nothing to check", arguments: [
        [nil], [""], ["  \n "], [nil, "401(k) match"],
    ] as [[String?]])
    func nothingToCheck(_ spans: [String?]) {
        #expect(Enrich.isVerbatim(spans, in: source))
    }

    @Test("is case sensitive, as the Go check is")
    func caseSensitive() {
        #expect(!Enrich.isVerbatim(["health insurance"], in: source))
    }
}
