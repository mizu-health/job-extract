import Foundation
import FoundationModels

/// Answers the one question SwiftPM alone cannot: can an unsigned, bundle-less
/// CLI binary actually reach the on-device model at runtime?
enum Probe {
    static func run() async {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            print("availability: available")
        case .unavailable(let reason):
            print("availability: unavailable (\(describe(reason)))")
            exit(1)
        }

        print("supports current locale: \(model.supportsLocale())")

        do {
            let session = LanguageModelSession()
            let started = Date()
            let response = try await session.respond(to: "Reply with exactly one word: ok")
            let elapsed = Date().timeIntervalSince(started)
            print("round-trip: \(response.content.trimmingCharacters(in: .whitespacesAndNewlines))")
            print("latency: \(String(format: "%.2f", elapsed))s")
        } catch {
            print("round-trip failed: \(error)")
            exit(2)
        }
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "device not eligible"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence not enabled in System Settings"
        case .modelNotReady:
            return "model still downloading or not ready"
        @unknown default:
            return "unknown (\(reason))"
        }
    }
}
