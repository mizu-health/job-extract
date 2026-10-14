import Foundation
import Testing
@testable import MizuExtract

/// The JSON shape `CLIModelEnricher` in the api repository sends and reads.
/// The two sides are versioned separately, so these pin this side's half.
@Suite("Enrich contract")
struct EnrichContractTests {
    @Test("decodes a request as Go sends it")
    func decodesRequest() throws {
        let json = #"[{"description":"Call is 1 in 6.","specialtySlugs":["general-anesthesiology"]}]"#
        let reqs = try Enrich.decode(Data(json.utf8))
        #expect(reqs.count == 1)
        #expect(reqs[0].description == "Call is 1 in 6.")
        #expect(reqs[0].specialtySlugs == ["general-anesthesiology"])
    }

    @Test("treats a null or missing vocabulary as empty, not as a bad batch", arguments: [
        #"[{"description":"x","specialtySlugs":null}]"#,
        #"[{"description":"x"}]"#,
    ])
    func toleratesNoVocabulary(_ json: String) throws {
        let reqs = try Enrich.decode(Data(json.utf8))
        #expect(reqs[0].specialtySlugs == [])
    }

    @Test("rejects a request with no description")
    func requiresDescription() {
        #expect(throws: DecodingError.self) {
            try Enrich.decode(Data(#"[{"specialtySlugs":[]}]"#.utf8))
        }
    }

    @Test("empty stdin is an empty batch")
    func emptyInput() throws {
        #expect(try Enrich.decode(Data()).isEmpty)
    }

    @Test("leaves nil fields out of the output")
    func omitsNils() throws {
        var r = EnrichResponse()
        r.callType = "HOME_CALL"
        r.callRatio = 6
        let json = String(decoding: try Enrich.encode([r]), as: UTF8.self)
        #expect(json == #"[{"callRatio":6,"callType":"HOME_CALL"}]"#)
    }

    @Test("a posting with nothing found encodes as an empty object, keeping alignment")
    func emptyResponseKeepsItsSlot() throws {
        let json = String(decoding: try Enrich.encode([EnrichResponse(), EnrichResponse()]), as: UTF8.self)
        #expect(json == "[{},{}]")
    }

    @Test("reports overflowed groups by name")
    func encodesOverflow() throws {
        var r = EnrichResponse()
        r.overflowed = ["benefits", "duties"]
        let json = String(decoding: try Enrich.encode([r]), as: UTF8.self)
        #expect(json == #"[{"overflowed":["benefits","duties"]}]"#)
    }
}
