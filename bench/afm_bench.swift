// AFM benchmark CLI — Apple Foundation Models on macOS 26.
// Measures first-snapshot TTFT and ≈tok/s (chars/4, no client token API on macOS 26).
// Mirrors bench.py: same long-form generation prompt, warmup + N runs, p50/p99, JSON out.
// Long-form prose (≥500 tok) keeps chars/4 ≈ true tokens and gives a stable steady-state decode.
import Foundation
import FoundationModels

let PROMPT = """
You are an in-car voice assistant. A passenger asks how regenerative braking works and how it \
affects the car's range in city versus highway driving. Answer in clear, friendly prose of at \
least 500 words. Cover the physics of turning motion back into charge, what the driver feels \
through the pedal, when it helps most, when it barely helps, and its limits in cold weather and \
at high speed.
"""

func percentile(_ values: [Double], _ q: Double) -> Double {
    let vs = values.sorted()
    let k = min(vs.count - 1, max(0, Int((q * Double(vs.count - 1)).rounded())))
    return vs[k]
}

struct RunResult {
    var ttft: Double
    var tps: Double
    var chars: Int
}

@main
struct AFMBench {
    static func main() async {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            print("AFM availability: available")
        case .unavailable(let reason):
            print("AFM UNAVAILABLE: \(reason)")
            exit(2)
        @unknown default:
            print("AFM availability: unknown case")
            exit(2)
        }

        let runs = 5
        var results: [RunResult] = []

        // Prewarm once with a fresh session, mirroring app behavior at tab-open.
        do {
            let warm = LanguageModelSession()
            warm.prewarm()
            _ = try await warm.respond(to: "Reply with OK")
        } catch {
            print("warmup failed: \(error)")
        }

        for i in 0..<(runs) {
            do {
                let session = LanguageModelSession()
                session.prewarm()
                // brief settle so prewarm isn't racing the request
                try? await Task.sleep(nanoseconds: 300_000_000)
                let start = Date()
                var firstSnapshot: Date? = nil
                var finalText = ""
                let stream = session.streamResponse(to: PROMPT)
                for try await partial in stream {
                    if firstSnapshot == nil { firstSnapshot = Date() }
                    finalText = partial.content
                }
                let end = Date()
                guard let first = firstSnapshot else { print("run \(i+1): no output"); continue }
                let ttft = first.timeIntervalSince(start)
                let decode = max(end.timeIntervalSince(first), 1e-6)
                let estTokens = Double(finalText.count) / 4.0
                let tps = estTokens / decode
                results.append(RunResult(ttft: ttft, tps: tps, chars: finalText.count))
                print(String(format: "    run %d/%d: TTFT %6.0f ms · ≈%5.1f tok/s · %d chars", i + 1, runs, ttft * 1000, tps, finalText.count))
                if i == 0 { print("    --- first output ---\n\(finalText)\n    ---") }
                try? await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                print("    run \(i+1) FAILED: \(error)")
            }
        }

        guard !results.isEmpty else { print("no successful runs"); exit(1) }
        let ttfts = results.map(\.ttft)
        let tpss = results.map(\.tps)
        let summary: [String: Any] = [
            "kind": "on-device",
            "device": "Apple M2 Pro · macOS 26.5.1 · Apple Foundation Models (gen 2, ~3B, 2-bit QAT)",
            "engine": "FoundationModels.framework",
            "token_metric": "estimated (chars/4) — no client token API on macOS 26",
            "runs": results.count,
            "results": [[
                "model": "apple/AFM-on-device (system)",
                "ttft_p50_s": (percentile(ttfts, 0.5) * 10000).rounded() / 10000,
                "ttft_p99_s": (percentile(ttfts, 0.99) * 10000).rounded() / 10000,
                "decode_tps_p50": (percentile(tpss, 0.5) * 10).rounded() / 10,
                "decode_tps_p99": (percentile(tpss, 0.99) * 10).rounded() / 10,
                "gen_chars_median": Int(percentile(results.map { Double($0.chars) }, 0.5)),
                "tokens_estimated": true,
            ]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "afm-mac.json"
        try! data.write(to: URL(fileURLWithPath: out))
        print("Wrote \(out)")
    }
}
