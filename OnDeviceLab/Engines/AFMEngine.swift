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
        displayName: "Apple FM · ~3B · 2-bit",
        badge: "AFM",
        contextWindow: 4_096,
        tokenCountIsEstimated: true)

    /// Prewarmed by `prepare()` and consumed by the next `stream()` call, so AFM
    /// starts warm — the same footing as an MLX lane streaming from its
    /// already-loaded container.
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
        // Runs stay history-free (every call takes a session that has never served
        // a request) but never cold: consume the prewarmed session and immediately
        // replace it with a freshly prewarmed one for the next run.
        let session: LanguageModelSession
        if let system {
            session = LanguageModelSession(instructions: system)
        } else if let warmed = prewarmedSession {
            session = warmed
            let fresh = LanguageModelSession()
            fresh.prewarm()
            prewarmedSession = fresh
        } else {
            session = LanguageModelSession()
        }
        // Same sampling as the MLX lanes (`ModelCatalog.chatSession`): temperature 0.3.
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: maxTokens)

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
                    continuation.finish(throwing: EngineError(generationError: error))
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

extension EngineError {
    /// The one mapping from the system model's failure modes onto the shared
    /// typed surface — used by every AFM code path (arena, extract, tools).
    @available(iOS 26.0, macOS 26.0, *)
    init(generationError error: LanguageModelSession.GenerationError) {
        switch error {
        case .exceededContextWindowSize:
            self = .contextOverflow
        case .guardrailViolation:
            self = .guardrail
        case .rateLimited:
            self = .rateLimited
        case .unsupportedLanguageOrLocale:
            self = .unsupportedLanguage
        default:
            self = .other(error.localizedDescription)
        }
    }
}
#endif
