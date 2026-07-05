#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// `InferenceEngine` adapter over Apple's on-device Foundation Model (~3B).
/// The API gives no token counts and only cumulative text snapshots, so this
/// engine diffs snapshots into deltas and estimates tokens at chars/4 — which
/// is exactly why `EngineSpec.tokenCountIsEstimated` exists.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class AFMEngine: InferenceEngine {

    let spec = EngineSpec(
        id: "afm",
        displayName: "Apple Foundation Model",
        badge: "AFM",
        contextWindow: 4_096,
        tokenCountIsEstimated: true)

    /// Kept alive after `prepare()` so the prewarmed state isn't dropped.
    private var prewarmedSession: LanguageModelSession?

    // MARK: InferenceEngine

    /// The system model gates on device class and the Apple Intelligence
    /// setting — surface the exact reason so the UI can grey it out honestly.
    var availability: EngineAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(reason: "Device not eligible for Apple Intelligence")
            case .appleIntelligenceNotEnabled:
                return .unavailable(reason: "Apple Intelligence not enabled in Settings")
            case .modelNotReady:
                return .downloading
            @unknown default:
                return .unavailable(reason: "Apple Intelligence unavailable")
            }
        @unknown default:
            return .unavailable(reason: "Apple Intelligence unavailable")
        }
    }

    var isReady: Bool { prewarmedSession != nil }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if case .unavailable(let reason) = availability {
            throw EngineError.other(reason)
        }
        // The OS already holds the weights — "loading" is just a prewarm.
        let session = LanguageModelSession()
        session.prewarm()
        prewarmedSession = session
        progress(1.0)
    }

    func stream(prompt: String, system: String?, maxTokens: Int) -> AsyncThrowingStream<StreamDelta, Error> {
        // Fresh session per call so runs don't share history, matching MLXEngine.
        let session = system.map { LanguageModelSession(instructions: $0) } ?? LanguageModelSession()
        let options = GenerationOptions(maximumResponseTokens: maxTokens)

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                var previous = ""
                do {
                    // Snapshots are CUMULATIVE — diff against the last one.
                    for try await partial in session.streamResponse(to: prompt, options: options) {
                        let full = partial.content
                        let new = String(full.dropFirst(previous.count))
                        previous = full
                        guard !new.isEmpty else { continue }
                        continuation.yield(StreamDelta(text: new, tokenEstimate: Double(new.count) / 4.0))
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: EngineError(error))
                } catch {
                    continuation.finish(throwing: EngineError.other(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unload() {
        prewarmedSession = nil
    }
}

private extension EngineError {
    /// Map the system model's failure modes onto the shared typed surface.
    @available(iOS 26.0, macOS 26.0, *)
    init(_ error: LanguageModelSession.GenerationError) {
        switch error {
        case .exceededContextWindowSize:
            self = .contextOverflow
        case .guardrailViolation:
            self = .guardrail
        case .rateLimited:
            self = .rateLimited
        default:
            self = .other(error.localizedDescription)
        }
    }
}
#endif
