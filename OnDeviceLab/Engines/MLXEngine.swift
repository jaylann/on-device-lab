import Foundation
import MLXLMCommon

/// `InferenceEngine` adapter over the MLX stack. Reuses `ModelCatalog.loadContainer`
/// and `ModelCatalog.chatSession` so behavior matches the Chat tab exactly — same
/// weights, same sampling, same non-thinking setup.
@MainActor
final class MLXEngine: InferenceEngine {

    let spec: EngineSpec
    private let model: LabModel
    private var container: ModelContainer?

    init(model: LabModel, contextWindow: Int) {
        self.model = model
        self.spec = EngineSpec(
            id: "mlx:\(model.id)",
            displayName: model.displayName,
            badge: "MLX",
            contextWindow: contextWindow,
            tokenCountIsEstimated: false)
    }

    // MARK: InferenceEngine

    /// Open weights run anywhere MLX does — no OS gate, no entitlement.
    var availability: EngineAvailability { .available }

    var isReady: Bool { container != nil }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if container != nil { return }
        container = try await ModelCatalog.loadContainer(for: model, progress: progress)
    }

    func stream(prompt: String, system: String?, maxTokens: Int) -> AsyncThrowingStream<StreamDelta, Error> {
        guard let container else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: EngineError.other("Model not loaded — call prepare() first"))
            }
        }
        // Fresh session per call so runs don't share history. `system` folds into the
        // prompt: `ModelCatalog.chatSession` is reused verbatim to stay in lock-step
        // with the Chat tab, and it exposes no instructions slot.
        let fullPrompt = system.map { "\($0)\n\n\(prompt)" } ?? prompt
        let session = ModelCatalog.chatSession(container, maxTokens: maxTokens)

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    // Each chunk is the next bit of decoded text — roughly one token.
                    for try await chunk in session.streamResponse(to: fullPrompt) {
                        continuation.yield(StreamDelta(text: chunk, tokenEstimate: 1.0))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: EngineError.other(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unload() {
        container = nil
    }
}
