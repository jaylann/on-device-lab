import Foundation
import MLXLMCommon

/// Loads a model and streams a chat reply — the working core behind milestone 1 ("run it").
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

    private(set) var container: ModelContainer?

    var isLoaded: Bool { if case .loaded = loadState { return true } else { return false } }

    func load(_ model: LabModel) async {
        if loadedModel?.id == model.id, container != nil { return }
        container = nil
        loadedModel = model
        loadState = .loading(0)
        do {
            let c = try await ModelCatalog.loadContainer(for: model) { [weak self] fraction in
                Task { @MainActor in
                    if case .loading = self?.loadState { self?.loadState = .loading(fraction) }
                }
            }
            container = c
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Stream a reply, updating `output`, `ttftMs` and `tokensPerSecond` live.
    func send(_ prompt: String, maxTokens: Int = 512) async {
        guard let container else { return }
        isGenerating = true
        defer { isGenerating = false }
        output = ""
        ttftMs = 0
        tokensPerSecond = 0

        var params = GenerateParameters()
        params.temperature = 0.3
        params.maxTokens = maxTokens
        // Qwen3 thinks by default; keep the chat box answering directly (no <think> trace), as NeatPass does.
        let session = ChatSession(container, generateParameters: params,
                                  additionalContext: ["enable_thinking": false])

        let start = Date()
        var first: Date?
        var count = 0
        do {
            for try await chunk in session.streamResponse(to: prompt) {
                if first == nil {
                    first = Date()
                    ttftMs = first!.timeIntervalSince(start) * 1000
                }
                count += 1
                output += chunk
                let dt = Date().timeIntervalSince(first ?? start)
                if dt > 0 { tokensPerSecond = Double(count) / dt }
            }
        } catch {
            output += "\n\n[generation error: \(error.localizedDescription)]"
        }
    }
}
