import Foundation

// ════════════════════════════════════════════════════════════════════════════
//  THE ENGINE ABSTRACTION  —  one interface over two very different stacks
//
//  MLX open-weight models and Apple's Foundation Model expose completely
//  different APIs (chat sessions vs. cumulative snapshots, real token counts
//  vs. character estimates). Everything above this layer — the arena UI, the
//  metrics — talks only to `InferenceEngine`, so the two race on equal terms.
// ════════════════════════════════════════════════════════════════════════════

/// Static facts about an engine, enough for the UI to render a fair scoreboard.
struct EngineSpec: Identifiable, Hashable, Sendable {
    let id: String                    // "afm", "mlx:<hf-repo>"
    let displayName: String
    let badge: String                 // "AFM" / "MLX"
    let contextWindow: Int            // tokens the engine can hold
    let tokenCountIsEstimated: Bool   // true for AFM → UI renders "≈"
}

/// Whether an engine can run right now — and if not, why, so the UI can say so.
enum EngineAvailability: Equatable {
    case available
    case unavailable(reason: String)
    case downloading
}

/// One increment of streamed output. MLX chunks are ~1 token each; AFM only
/// hands out cumulative text, so its deltas carry a chars/4 estimate instead.
struct StreamDelta: Sendable {
    let text: String
    let tokenEstimate: Double
}

/// Typed failure surface shared by every engine. Engines map their native
/// errors onto these cases; `StreamRun` turns them into a `FailReason`.
enum EngineError: Error, Equatable {
    case guardrail
    case contextOverflow
    case rateLimited
    case other(String)
}

/// A text-generation engine the arena can load, stream from, and unload.
@MainActor
protocol InferenceEngine: AnyObject {
    var spec: EngineSpec { get }
    var availability: EngineAvailability { get }
    var isReady: Bool { get }

    /// Load weights (or prewarm the system model), reporting 0…1 progress.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws

    /// Stream a reply. Each call is a fresh, history-free session so runs
    /// stay comparable. Errors surface as `EngineError`.
    func stream(prompt: String, system: String?, maxTokens: Int) -> AsyncThrowingStream<StreamDelta, Error>

    /// Release whatever memory the engine holds.
    func unload()
}
