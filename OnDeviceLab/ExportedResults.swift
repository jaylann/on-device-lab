import Foundation

// JSON shape identical to bench/bench.py, so bench/apply_bench.py ingests Mac and iPhone runs the same way.

struct ExportResult: Codable {
    let model: String
    let ttft_p50_s: Double
    let ttft_p99_s: Double
    let decode_tps_p50: Double
    let runs: Int
}

struct ExportPayload: Codable {
    let kind: String
    let device: String
    let platform: String
    let max_tokens: Int
    let runs: Int
    let results: [ExportResult]
}

enum ResultsExporter {

    static func payload(from results: [ModelBenchResult], device: String, maxTokens: Int) -> ExportPayload {
        ExportPayload(
            kind: "on-device",
            device: device,
            platform: platformString,
            max_tokens: maxTokens,
            runs: results.map(\.runs).max() ?? 0,
            results: results.map {
                ExportResult(
                    model: $0.modelId,
                    ttft_p50_s: ($0.ttftP50Ms / 1000).rounded(toPlaces: 4),
                    ttft_p99_s: ($0.ttftP99Ms / 1000).rounded(toPlaces: 4),
                    decode_tps_p50: $0.tokPerSecP50.rounded(toPlaces: 1),
                    runs: $0.runs)
            })
    }

    /// Encode to a temporary file and return its URL (for ShareLink / save).
    static func writeTempFile(_ payload: ExportPayload) -> URL? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ondevicelab-results.json")
        do { try data.write(to: url); return url } catch { return nil }
    }

    private static var platformString: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let name = "macOS"
        #else
        let name = "iOS"
        #endif
        return "\(name) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = Foundation.pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}
