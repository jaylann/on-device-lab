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
    let promptTokens: Int         // prompt length (from the model, for context)
}

struct ModelBenchResult: Identifiable {
    let id = UUID()
    let modelId: String
    let displayName: String
    let ttftP50Ms: Double
    let ttftP99Ms: Double
    let tokPerSecP50: Double
    let promptTokens: Int
    let runs: Int
}

@MainActor
@Observable
final class BenchmarkRunner {
    var isRunning = false
    var note = ""
    var results: [ModelBenchResult] = []
    let device = DeviceInfo.label

    func run(models: [LabModel], runs: Int = 5, warmup: Int = 1, maxTokens: Int = 128) async {
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
                _ = try? await measure(container: container, prompt: PromptLibrary.extraction, maxTokens: maxTokens)
            }

            var samples: [BenchSample] = []
            for i in 0..<runs {
                note = "\(model.displayName): run \(i + 1)/\(runs)"
                if let s = try? await measure(container: container, prompt: PromptLibrary.extraction, maxTokens: maxTokens) {
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
        var params = GenerateParameters()
        params.temperature = 0.3
        params.maxTokens = maxTokens
        let session = ChatSession(container, generateParameters: params)

        let start = Date()
        var firstTokenTime: Date? = nil
        var tokenCount = 0

        // Each `chunk` is the model's next bit of decoded text — roughly one token.
        for try await chunk in session.streamResponse(to: prompt) {
            #if SOLUTION
            if firstTokenTime == nil { firstTokenTime = Date() }   // TTFT: stamp the first token
            tokenCount += 1                                        // throughput: count every token
            #else
            // ─────────────────────────────────────────────────────────────────
            // TODO 1 — TTFT: the FIRST time through this loop, record the time.
            //   Set `firstTokenTime = Date()` exactly once (guard on it being nil).
            //
            // TODO 2 — throughput: count tokens as they stream.
            //   Increment `tokenCount` once per chunk.
            // ─────────────────────────────────────────────────────────────────
            _ = chunk
            #endif
        }

        let end = Date()
        // Done for you: turns your two values into the two numbers.
        let ttft = (firstTokenTime ?? end).timeIntervalSince(start)
        let decodeSeconds = max(end.timeIntervalSince(firstTokenTime ?? start), 0.0001)
        let tokPerSec = Double(tokenCount) / decodeSeconds
        return BenchSample(ttft: ttft, tokPerSec: tokPerSec, tokens: tokenCount, promptTokens: 0)
    }

    private func summarize(model: LabModel, samples: [BenchSample]) -> ModelBenchResult {
        let ttfts = samples.map { $0.ttft * 1000 }.sorted()
        let tps = samples.map { $0.tokPerSec }.sorted()
        return ModelBenchResult(
            modelId: model.id,
            displayName: model.displayName,
            ttftP50Ms: median(ttfts),
            ttftP99Ms: percentile(ttfts, 0.99),
            tokPerSecP50: median(tps),
            promptTokens: samples.last?.promptTokens ?? 0,
            runs: samples.count)
    }

    private func median(_ a: [Double]) -> Double { a.isEmpty ? 0 : a[a.count / 2] }
    private func percentile(_ a: [Double], _ q: Double) -> Double {
        guard !a.isEmpty else { return 0 }
        let k = Int((q * Double(a.count - 1)).rounded())
        return a[min(a.count - 1, max(0, k))]
    }
}
