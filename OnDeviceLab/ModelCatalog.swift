import Foundation
import MLXLLM
import MLXLMCommon

/// One selectable model in the lab.
struct LabModel: Identifiable, Hashable {
    let id: String          // Hugging Face repo id, e.g. "mlx-community/Qwen3-0.6B-4bit"
    let displayName: String
    let note: String
}

enum ModelCatalog {
    static let qwen06B = LabModel(
        id: "mlx-community/Qwen3-0.6B-4bit",
        displayName: "Qwen3 0.6B · 4-bit",
        note: "Extraction class · ~0.3 GB · runs on nearly everything")
    static let qwen17B = LabModel(
        id: "mlx-community/Qwen3-1.7B-4bit",
        displayName: "Qwen3 1.7B · 4-bit",
        note: "Robust class · ~1 GB · the model NeatPass ships")
    static let qwen4B = LabModel(
        id: "mlx-community/Qwen3-4B-4bit",
        displayName: "Qwen3 4B · 4-bit",
        note: "Stress model (M3) · ~2.3 GB · feel the reasoning class")
    static let smolLM3 = LabModel(
        id: "mlx-community/SmolLM3-3B-4bit",
        displayName: "SmolLM3 3B · 4-bit",
        note: "Arena class · ~1.7 GB · 64k ctx · /think //no_think dual mode")
    static let smolLM2 = LabModel(
        // No official mlx-community 4-bit exists; this community quant is verified
        // working (mlx-lm 0.31.3, sane JSON extraction, ~1.2 GB peak).
        id: "Irfanuruchi/SmolLM2-1.7B-Instruct-MLX-4bit",
        displayName: "SmolLM2 1.7B · 4-bit",
        note: "Arena class · ~1 GB · 8k ctx · llama-arch")

    static let all: [LabModel] = [qwen06B, qwen17B, qwen4B, smolLM3, smolLM2]

    /// The first two are what slide 21 reports; the 4B is the M3 stress model.
    static let benchmarkSet: [LabModel] = [qwen06B, qwen17B]

    /// AFM's sparring partners in the arena — same ~size class as the on-device
    /// 3B foundation model, so the race is fair.
    static let arenaSet: [LabModel] = [qwen17B, smolLM3]

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

    /// A chat session configured the way the talk uses Qwen3, shared by the chat engine and the
    /// benchmark so they stay in lock-step: low temperature, and non-thinking — NeatPass runs
    /// extraction without a `<think>` trace for fast, clean JSON, so we match that here.
    static func chatSession(_ container: ModelContainer, maxTokens: Int) -> ChatSession {
        var params = GenerateParameters()
        params.temperature = 0.3
        params.maxTokens = maxTokens
        return ChatSession(container, generateParameters: params,
                           additionalContext: ["enable_thinking": false])
    }
}
