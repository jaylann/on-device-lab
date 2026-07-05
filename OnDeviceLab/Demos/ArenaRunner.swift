import Foundation
import Observation

/// Drives the side-by-side race: one lane per engine from `EngineRegistry`,
/// each lane pairing an engine with its own `StreamRun` for live metrics.
@MainActor
@Observable
final class ArenaRunner {

    /// One racing lane. Unavailable engines still get a lane — greyed out with
    /// their reason — because "AFM can't run here" is itself a talking point.
    @MainActor
    @Observable
    final class Lane: Identifiable {
        let engine: any InferenceEngine
        let run = StreamRun()
        var loadProgress: Double = 0

        nonisolated var id: String { spec.id }
        nonisolated let spec: EngineSpec

        init(engine: any InferenceEngine) {
            self.engine = engine
            self.spec = engine.spec
        }

        var isAvailable: Bool { engine.availability == .available }

        var unavailabilityReason: String? {
            switch engine.availability {
            case .available: return nil
            case .downloading: return "Model downloading — try again shortly"
            case .unavailable(let reason): return reason
            }
        }
    }

    var lanes: [Lane]
    var isRunning = false

    /// Parallel races look great on the Mac; on iPhone two resident models can
    /// evict each other, so sequential (load → run → unload) is the default.
    #if os(macOS)
    var parallel = true
    #else
    var parallel = false
    #endif

    private var raceTask: Task<Void, Never>?

    init() {
        lanes = EngineRegistry.makeEngines().map(Lane.init)
    }

    // MARK: Winner highlights (valid once the race has settled)

    var raceFinished: Bool {
        !isRunning && lanes.contains { $0.run.phase == .done }
    }

    var bestTTFTLaneID: String? {
        guard raceFinished else { return nil }
        return lanes.filter { $0.run.phase == .done && $0.run.ttftMs > 0 }
            .min { $0.run.ttftMs < $1.run.ttftMs }?.id
    }

    var bestTokPerSecLaneID: String? {
        guard raceFinished else { return nil }
        return lanes.filter { $0.run.phase == .done && $0.run.tokPerSec > 0 }
            .max { $0.run.tokPerSec < $1.run.tokPerSec }?.id
    }

    // MARK: Control

    func start(prompt: String, maxTokens: Int = 512) {
        guard !isRunning else { return }
        isRunning = true
        let runnable = lanes.filter { $0.isAvailable }
        for lane in runnable {
            lane.run.output = ""
            lane.run.phase = .idle
        }
        raceTask = Task { [weak self] in
            guard let self else { return }
            if self.parallel {
                await withTaskGroup(of: Void.self) { group in
                    for lane in runnable {
                        group.addTask { @MainActor in
                            await Self.race(lane: lane, prompt: prompt, maxTokens: maxTokens)
                        }
                    }
                }
            } else {
                for (index, lane) in runnable.enumerated() {
                    if Task.isCancelled { break }
                    await Self.race(lane: lane, prompt: prompt, maxTokens: maxTokens)
                    // Sequential mode exists to protect memory: drop the MLX
                    // weights before the next lane loads its own.
                    if lane.spec.badge == "MLX", index < runnable.count - 1 {
                        lane.engine.unload()
                    }
                }
            }
            self.isRunning = false
        }
    }

    func stop() {
        raceTask?.cancel()
        raceTask = nil
        isRunning = false
        for lane in lanes where lane.run.phase == .streaming || lane.run.phase == .loading {
            lane.run.phase = .idle
        }
    }

    private static func race(lane: Lane, prompt: String, maxTokens: Int) async {
        lane.run.phase = .loading
        lane.loadProgress = 0
        do {
            try await lane.engine.prepare { p in
                Task { @MainActor in lane.loadProgress = p }
            }
        } catch {
            lane.run.phase = .failed(.other(error.localizedDescription))
            return
        }
        guard !Task.isCancelled else {
            lane.run.phase = .idle
            return
        }
        let stream = lane.engine.stream(
            prompt: prompt,
            system: systemPrompt(for: lane.engine),
            maxTokens: maxTokens)
        await lane.run.consume(stream)
    }

    /// SmolLM3 thinks by default. `enable_thinking: false` from
    /// `ModelCatalog.chatSession` does reach its chat template (verified:
    /// ChatSession → UserInput.additionalContext → applyChatTemplate), but on
    /// stage we add the model's own "/no_think" soft switch as insurance.
    static func systemPrompt(for engine: any InferenceEngine) -> String? {
        engine.spec.id.contains("SmolLM3") ? "/no_think" : nil
    }
}
