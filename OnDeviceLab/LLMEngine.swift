import Foundation

/// Loads a model and streams a chat reply — the working core behind milestone 1 ("run it").
/// Routes through `InferenceEngine`, so the Chat tab can drive both the MLX
/// open-weight models and Apple's Foundation Model with one code path.
@MainActor
@Observable
final class LLMEngine {

    enum LoadState: Equatable {
        case idle
        case loading(Double)
        case loaded
        case failed(String)
    }

    var loadState: LoadState = .idle
    var loadedModel: LabModel?
    var output: String = ""
    var ttftMs: Double = 0
    var tokensPerSecond: Double = 0
    var isGenerating = false

    private(set) var engine: (any InferenceEngine)?

    var isLoaded: Bool { if case .loaded = loadState { return true } else { return false } }

    /// True when the loaded engine can only estimate token counts (AFM) —
    /// the UI prefixes the tok/s readout with "≈".
    var tokensEstimated: Bool { engine?.spec.tokenCountIsEstimated ?? false }

    func load(_ model: LabModel) async {
        if loadedModel?.id == model.id, engine?.isReady == true { return }
        engine = nil
        loadedModel = model
        loadState = .loading(0)

        let candidate: any InferenceEngine
        if model.id == ModelCatalog.afmChat.id {
            guard let afm = Self.makeAFMEngine() else {
                loadState = .failed("Apple Foundation Models need macOS 26 / iOS 26.")
                return
            }
            if case .unavailable(let reason) = afm.availability {
                loadState = .failed(reason)
                return
            }
            candidate = afm
        } else {
            candidate = EngineRegistry.mlxEngine(for: model)
        }

        do {
            try await candidate.prepare { [weak self] fraction in
                Task { @MainActor in
                    if case .loading = self?.loadState { self?.loadState = .loading(fraction) }
                }
            }
            engine = candidate
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Stream a reply, updating `output`, `ttftMs` and `tokensPerSecond` live.
    func send(_ prompt: String, maxTokens: Int = 512) async {
        guard let engine else { return }
        isGenerating = true
        defer { isGenerating = false }
        output = ""
        ttftMs = 0
        tokensPerSecond = 0

        let start = Date()
        var first: Date?
        var tokens = 0.0
        do {
            for try await delta in engine.stream(prompt: prompt, system: nil, maxTokens: maxTokens) {
                if first == nil {
                    let now = Date()
                    first = now
                    ttftMs = now.timeIntervalSince(start) * 1000
                }
                tokens += delta.tokenEstimate
                output += delta.text
                let dt = Date().timeIntervalSince(first ?? start)
                if dt > 0 { tokensPerSecond = tokens / dt }
            }
        } catch {
            output += "\n\n[generation error: \(error.localizedDescription)]"
        }
    }

    private static func makeAFMEngine() -> (any InferenceEngine)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return AFMEngine()
        }
        #endif
        return nil
    }
}
