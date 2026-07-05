import Foundation

/// Consumes one engine stream and publishes the live numbers the arena shows —
/// the engine-agnostic sibling of `LLMEngine.send`: same TTFT / tok/s math,
/// but fed by `StreamDelta`s so MLX and AFM are measured identically.
@MainActor
@Observable
final class StreamRun {

    enum FailReason: Equatable {
        case guardrail
        case contextOverflow
        case rateLimited
        case other(String)
    }

    enum Phase: Equatable {
        case idle
        case loading
        case streaming
        case done
        case failed(FailReason)
    }

    var output: String = ""
    var ttftMs: Double = 0
    var tokPerSec: Double = 0
    var tokensEstimated: Bool = false
    var phase: Phase = .idle

    /// Drain a stream to completion, stamping TTFT on the first delta and
    /// updating throughput live (Σ token estimates / elapsed since first delta).
    func consume(_ stream: AsyncThrowingStream<StreamDelta, Error>) async {
        output = ""
        ttftMs = 0
        tokPerSec = 0
        phase = .streaming

        let start = Date()
        var first: Date?
        var tokens: Double = 0
        do {
            for try await delta in stream {
                if first == nil {
                    let now = Date()
                    first = now
                    ttftMs = now.timeIntervalSince(start) * 1000
                }
                output += delta.text
                tokens += delta.tokenEstimate
                let dt = Date().timeIntervalSince(first ?? start)
                if dt > 0 { tokPerSec = tokens / dt }
            }
            phase = .done
        } catch let error as EngineError {
            phase = .failed(FailReason(error))
        } catch {
            phase = .failed(.other(error.localizedDescription))
        }
    }
}

extension StreamRun.FailReason {
    /// Engines throw `EngineError`; the run reports the matching reason.
    init(_ error: EngineError) {
        switch error {
        case .guardrail: self = .guardrail
        case .contextOverflow: self = .contextOverflow
        case .rateLimited: self = .rateLimited
        case .other(let message): self = .other(message)
        }
    }
}
