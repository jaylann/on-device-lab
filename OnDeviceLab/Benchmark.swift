import Foundation
import MLXLMCommon

// ════════════════════════════════════════════════════════════════════════════
//  THE BENCHMARK HARNESS  —  milestone 2 ("measure it")
//
//  The loop, warmup, percentiles and JSON export are all written for you.
//  The two numbers that matter — TTFT and tokens/second — are NOT. They live in
//  `measure(...)` below, marked TODO 1 and TODO 2.
//
//  Fill them in, run the benchmark, and shout your numbers. Until you do, the app
//  builds and runs but reports 0 tok/s — that's the whole point of the exercise.
//
//  (Building with the "OnDeviceLab (Solution)" scheme compiles the reference
//   implementation instead, so you can check your answer — or just get numbers fast.)
// ════════════════════════════════════════════════════════════════════════════

struct BenchSample {
    let ttft: TimeInterval        // seconds to the first token
    let tokPerSec: Double         // sustained decode throughput
    let tokens: Int               // generated tokens counted
}

struct ModelBenchResult: Identifiable {
    let id = UUID()
    let modelId: String
    let displayName: String
    let ttftP50Ms: Double
    let ttftP99Ms: Double
    let tokPerSecP50: Double
    let runs: Int
}

@MainActor
@Observable
final class BenchmarkRunner {
    var isRunning = false
    var note = ""
    var results: [ModelBenchResult] = []
    let device = DeviceInfo.label

    /// Defaults mirror `bench/bench.py` (same prompt, same 600-token cap) so the
    /// in-app numbers are comparable to the harness behind the deck's chart.
    func run(models: [LabModel], runs: Int = 5, warmup: Int = 1, maxTokens: Int = 600) async {
        isRunning = true
        defer { isRunning = false }
        results = []

        for model in models {
            note = "Loading \(model.displayName)…"
            let container: ModelContainer
            do {
                container = try await ModelCatalog.loadContainer(for: model) { [weak self] f in
                    Task { @MainActor in self?.note = "Downloading \(model.displayName) \(Int(f * 100))%" }
                }
            } catch {
                note = "Failed to load \(model.displayName): \(error.localizedDescription)"
                continue
            }

            for _ in 0..<warmup {
                note = "\(model.displayName): warmup"
                _ = try? await measure(container: container, prompt: PromptLibrary.benchmark, maxTokens: maxTokens)
            }

            var samples: [BenchSample] = []
            for i in 0..<runs {
                note = "\(model.displayName): run \(i + 1)/\(runs)"
                if let s = try? await measure(container: container, prompt: PromptLibrary.benchmark, maxTokens: maxTokens) {
                    samples.append(s)
                }
            }
            results.append(summarize(model: model, samples: samples))
        }
        note = results.isEmpty ? "No results" : "Done — \(results.count) model(s)"
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  measure() — generate once, time it. THIS is the exercise.
    // ─────────────────────────────────────────────────────────────────────────
    private func measure(container: ModelContainer, prompt: String, maxTokens: Int) async throws -> BenchSample {
        let session = ModelCatalog.chatSession(container, maxTokens: maxTokens)

        let start = Date()
        var firstTokenTime: Date? = nil
        var tokenCount = 0

        // Each `chunk` is the model's next bit of decoded text — roughly one token.
        // The per-token bookkeeping is the exercise: it lives in `tally(...)` below.
        for try await chunk in session.streamResponse(to: prompt) {
            _ = chunk
            tally(firstTokenTime: &firstTokenTime, tokenCount: &tokenCount)
        }

        let end = Date()
        // Done for you: turns your two values into the two numbers. This math
        // deliberately mirrors bench.py's one_run (first token IS counted) — keep
        // them in lock-step even though StreamRun.consume excludes the first delta.
        let ttft = (firstTokenTime ?? end).timeIntervalSince(start)
        let decodeSeconds = max(end.timeIntervalSince(firstTokenTime ?? start), 0.0001)
        let tokPerSec = Double(tokenCount) / decodeSeconds
        return BenchSample(ttft: ttft, tokPerSec: tokPerSec, tokens: tokenCount)
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  MILESTONE 2 · MEASURE IT — round 1 (latency)
    //  Called once per streamed token by `measure()` above. Fill in the two
    //  numbers that decide on-device UX. Until you do, the sheet reports 0 tok/s.
    //  Stuck? Build the "OnDeviceLab (Solution)" scheme (its reference lives in
    //  Solutions/Solutions.swift — no peeking).
    // ─────────────────────────────────────────────────────────────────────────
    #if !SOLUTION
    func tally(firstTokenTime: inout Date?, tokenCount: inout Int) {
        // TODO 1 — TTFT: the FIRST time this is called, record the moment.
        //   Set `firstTokenTime = Date()` exactly once (guard on it being nil).
        //
        // TODO 2 — throughput: count tokens as they stream.
        //   Increment `tokenCount` by one on every call.
    }
    #endif

    private func summarize(model: LabModel, samples: [BenchSample]) -> ModelBenchResult {
        let ttfts = samples.map { $0.ttft * 1000 }.sorted()
        let tps = samples.map { $0.tokPerSec }.sorted()
        return ModelBenchResult(
            modelId: model.id,
            displayName: model.displayName,
            ttftP50Ms: median(ttfts),
            ttftP99Ms: percentile(ttfts, 0.99),
            tokPerSecP50: median(tps),
            runs: samples.count)
    }

    private func median(_ a: [Double]) -> Double { percentile(a, 0.5) }

    /// Linear-interpolated percentile over a pre-sorted array (true median at q = 0.5).
    private func percentile(_ a: [Double], _ q: Double) -> Double {
        guard a.count > 1 else { return a.first ?? 0 }
        let rank = q * Double(a.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        return a[lo] + (a[hi] - a[lo]) * (rank - Double(lo))
    }
}
