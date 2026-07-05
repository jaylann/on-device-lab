import Foundation

/// Builds the arena line-up: Apple's Foundation Model first (when the OS ships
/// it — its `availability` explains itself when it can't run, so the UI greys
/// it out with the reason), then the MLX contenders from `ModelCatalog.arenaSet`.
@MainActor
enum EngineRegistry {

    /// Context windows for the MLX models, keyed by Hugging Face repo id.
    private static let contextWindows: [String: Int] = [
        ModelCatalog.qwen06B.id: 32_768,
        ModelCatalog.qwen17B.id: 32_768,
        ModelCatalog.qwen4B.id: 32_768,
        ModelCatalog.smolLM3.id: 65_536,
        ModelCatalog.smolLM2.id: 8_192,
    ]

    static func makeEngines() -> [any InferenceEngine] {
        var engines: [any InferenceEngine] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            engines.append(AFMEngine())
        }
        #endif
        for model in ModelCatalog.arenaSet {
            engines.append(MLXEngine(model: model, contextWindow: contextWindows[model.id] ?? 32_768))
        }
        return engines
    }
}
