import Foundation
import FoundationModels

/// Runs the same fixtures the Go extractor is tested against, so the two can be
/// compared on identical input.
enum SalaryProbe {
    struct Case {
        let name: String
        let text: String
        let expect: String
    }

    static let cases: [Case] = [
        .init(name: "NYP annual range",      text: "Salary Range: $129,681 - $141,006/Annual The hiring rate reflects...", expect: "129681-141006 YEAR"),
        .init(name: "Stanford hourly",       text: "Base Pay Scale: Generally starting at $73.34 - $82.58 per hour", expect: "73.34-82.58 HOUR"),
        .init(name: "Sutter cents",          text: "Pay Range is $142,105.60 to $213,158.40 / annual salary The compensation range may vary...", expect: "142105.6-213158.4 YEAR"),
        .init(name: "locum hourly",          text: "Pay rate: $220 to $250 per hour, 1099.", expect: "220-250 HOUR"),
        .init(name: "project budget TRAP",   text: "Experience delivering projects from $50 to $100M+ range and leading teams", expect: "nothing"),
        .init(name: "sign-on bonus TRAP",    text: "Join our team! We offer a $20,000 sign-on bonus and relocation assistance.", expect: "nothing"),
        .init(name: "bonus under label TRAP", text: "Salary and benefits: $75,000 sign-on bonus for qualified CRNA candidates.", expect: "nothing"),
        .init(name: "ambiguous magnitude",   text: "Salary Range: $1,800 - $2,400", expect: "nothing (no unit)"),
        .init(name: "no pay info",           text: "Competitive compensation and a comprehensive benefits package.", expect: "nothing"),
        .init(name: "recruiter dump",        text: "Comp is 245k base plus a 20k sign on bonus and full benefits including 6 weeks PTO.", expect: "245000 YEAR"),
    ]

    static func run() async {
        guard case .available = SystemLanguageModel.default.availability else {
            IO.fail("model unavailable", code: 69)
        }
        print(String(format: "%-22@ %-26@ %@", "CASE" as NSString, "MODEL SAID" as NSString, "EXPECTED" as NSString))
        print(String(repeating: "-", count: 78))

        for c in cases {
            let session = LanguageModelSession(instructions: """
                Extract only the base pay (salary or wage) stated in a job listing.
                Never report a sign-on bonus, relocation allowance, or any figure
                that is not base pay. If no base pay is stated, leave every field null.
                """)
            var said = "ERROR"
            do {
                let r = try await session.respond(to: c.text, generating: SalaryDraft.self)
                let d = r.content
                if d.min == nil && d.max == nil {
                    said = "nothing"
                } else {
                    let lo = d.min.map { fmt($0) } ?? "?"
                    let hi = d.max.map { "-" + fmt($0) } ?? ""
                    said = "\(lo)\(hi) \(d.unit ?? "?")"
                }
            } catch {
                said = "threw: \(error)"
            }
            print(String(format: "%-22@ %-26@ %@", c.name as NSString, said as NSString, c.expect as NSString))
        }
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
