import Foundation
import MLXLLM
import MLXLMCommon

/// One selectable model in the lab.
struct LabModel: Identifiable, Hashable {
    let id: String          // Hugging Face repo id, e.g. "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    let displayName: String
    let note: String
}

enum ModelCatalog {
    static let qwen05B = LabModel(
        id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
        displayName: "Qwen2.5 0.5B · 4-bit",
        note: "Extraction class · ~0.3 GB · runs on nearly everything")
    static let qwen15B = LabModel(
        id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        displayName: "Qwen2.5 1.5B · 4-bit",
        note: "Robust class · ~1 GB · the NeatPass weight class")
    static let smol17B = LabModel(
        id: "mlx-community/SmolLM2-1.7B-Instruct-4bit",
        displayName: "SmolLM2 1.7B · 4-bit",
        note: "Stress model (M3) · feel what +1B params costs")

    static let all: [LabModel] = [qwen05B, qwen15B, smol17B]

    /// The first two are what slide 21 reports; SmolLM is the M3 stress model.
    static let benchmarkSet: [LabModel] = [qwen05B, qwen15B]

    /// Local model share (slide 26): if `~/Documents/models/<repo-leaf>` exists, load it with
    /// no network. Otherwise fall back to a Hugging Face download. `fetch-models.sh` stages this.
    static func localDirectory(for model: LabModel) -> URL? {
        let leaf = model.id.split(separator: "/").last.map(String.init) ?? model.id
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let dir = docs?.appendingPathComponent("models/\(leaf)", isDirectory: true) else { return nil }
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func configuration(for model: LabModel) -> ModelConfiguration {
        if let dir = localDirectory(for: model) {
            return ModelConfiguration(directory: dir)
        }
        return ModelConfiguration(id: model.id)
    }

    /// Shared loader used by both the chat engine and the benchmark.
    static func loadContainer(
        for model: LabModel,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ModelContainer {
        try await LLMModelFactory.shared.loadContainer(configuration: configuration(for: model)) { p in
            progress(p.fractionCompleted)
        }
    }
}
