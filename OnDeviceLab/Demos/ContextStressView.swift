import SwiftUI
import Observation

/// The Context tab: the same needle-in-a-trip-log prompt, scaled from ~1k to
/// ~16k tokens, against engines with very different windows. Two lessons on
/// one screen: AFM's 4,096-token hard wall, and TTFT growing with prompt size
/// (prompt eval is the cost you pay before the first token).
struct ContextStressView: View {
    @State private var runner = ContextStressRunner()
    @State private var selectedTokens = 1_000

    /// `PromptLibrary.contextBlock` entries are ~35 tokens each.
    private static let tokensPerRepeat = 35
    private let presets = [1_000, 3_000, 5_000, 8_000, 16_000]

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                sizeChips
                engineChips
                resultsTable
                footer
                runButton
            }
            .padding(DS.Space.gutter)
            .ambientGradientBackground(tint: DS.accent)
            .navigationTitle("Context Stress")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var sizeChips: some View {
        HStack(spacing: DS.Space.row) {
            ForEach(presets, id: \.self) { tokens in
                EngineChip(
                    title: "~\(tokens / 1_000)k tok",
                    selected: selectedTokens == tokens,
                    enabled: !runner.isRunning
                ) { selectedTokens = tokens }
            }
            Spacer(minLength: 0)
        }
    }

    private var engineChips: some View {
        HStack(spacing: DS.Space.row) {
            ForEach(runner.engineInfos, id: \.id) { info in
                EngineChip(
                    title: info.shortName,
                    selected: runner.selectedEngineIDs.contains(info.id),
                    enabled: !runner.isRunning
                ) { runner.toggle(info.id) }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Results (completed rows stay listed so TTFT growth is visible)

    private var resultsTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Results")
            tableHeader
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if runner.rows.isEmpty {
                            Text("Pick a size, pick engines, run — rows accumulate so you can watch TTFT climb as the prompt grows.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                        ForEach(runner.rows) { row in
                            resultRow(row)
                            Divider().opacity(0.5)
                        }
                        Color.clear.frame(height: 1).id("rows-bottom")
                    }
                }
                .onChange(of: runner.rows.count) {
                    proxy.scrollTo("rows-bottom", anchor: .bottom)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassTile(radius: DS.Radius.card)
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text("Engine")
                .frame(minWidth: 90, alignment: .leading)
            Spacer(minLength: 0)
            Text("Prompt")
                .frame(width: 90, alignment: .trailing)
            Text("TTFT")
                .frame(width: 90, alignment: .trailing)
            Text("Result")
                .frame(minWidth: 110, alignment: .trailing)
        }
        .font(DS.Typo.label)
        .kerning(0.8)
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
    }

    private func resultRow(_ row: ContextStressRunner.ResultRow) -> some View {
        HStack(spacing: 10) {
            EngineBadge(text: row.badge)
            Text(row.engineName)
                .font(.footnote.weight(.semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Text("~\(row.approxTokens.formatted())")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(row.ttftMs.map { String(format: "%.0f ms", $0) } ?? "—")
                .font(DS.Typo.statValueSmall)
                .contentTransition(.numericText())
                .frame(width: 90, alignment: .trailing)
            outcomeView(row)
                .frame(minWidth: 110, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private func outcomeView(_ row: ContextStressRunner.ResultRow) -> some View {
        switch row.outcome {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("loading").font(.caption2).foregroundStyle(.secondary)
            }
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("streaming").font(.caption2).foregroundStyle(.secondary)
            }
        case .ok(let tokPerSec):
            StatusChip(
                text: String(format: "%@%.0f tok/s", row.tokensEstimated ? "≈" : "", tokPerSec),
                color: .green, icon: "checkmark")
        case .failed(let reason):
            if case .contextOverflow = reason {
                // The money shot of this tab: the hard wall, unmissable.
                StatusChip(text: "\(row.contextWindow.formatted())-token hard limit",
                           color: .red, icon: "nosign", prominent: true)
            } else {
                StatusChip(reason: reason)
            }
        }
    }

    private var footer: some View {
        Text("Context windows: Apple FM 4,096 · Qwen3 32k · SmolLM3 64k")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private var runButton: some View {
        Button {
            runner.run(approxTokens: selectedTokens,
                       repeats: max(1, selectedTokens / Self.tokensPerRepeat))
        } label: {
            Text(runner.isRunning ? "Running…" : "Send ~\(selectedTokens.formatted()) tokens")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(runButtonEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity)
                .glassPill(height: DS.controlHeight, tint: runButtonEnabled ? DS.accent : nil)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!runButtonEnabled)
    }

    private var runButtonEnabled: Bool {
        !runner.isRunning && !runner.selectedEngineIDs.isEmpty
    }
}

// MARK: - Runner

@MainActor
@Observable
final class ContextStressRunner {

    enum Outcome {
        case loading
        case running
        case ok(tokPerSec: Double)
        case failed(StreamRun.FailReason)
    }

    struct ResultRow: Identifiable {
        let id = UUID()
        let engineName: String
        let badge: String
        let contextWindow: Int
        let tokensEstimated: Bool
        let approxTokens: Int
        var ttftMs: Double?
        var outcome: Outcome
    }

    struct EngineInfo {
        let id: String
        let shortName: String
    }

    /// AFM + Qwen3 1.7B + SmolLM3 — exactly what the registry's arena set gives us.
    private let engines: [any InferenceEngine] = EngineRegistry.makeEngines()

    var rows: [ResultRow] = []
    var selectedEngineIDs: Set<String>
    var isRunning = false

    init() {
        selectedEngineIDs = Set(engines.map { $0.spec.id })
    }

    var engineInfos: [EngineInfo] {
        engines.map { engine in
            EngineInfo(id: engine.spec.id, shortName: shortName(for: engine.spec))
        }
    }

    func toggle(_ id: String) {
        if selectedEngineIDs.contains(id) {
            selectedEngineIDs.remove(id)
        } else {
            selectedEngineIDs.insert(id)
        }
    }

    /// Sequential on purpose: one model in flight keeps TTFT numbers honest.
    func run(approxTokens: Int, repeats: Int) {
        guard !isRunning else { return }
        isRunning = true
        let prompt = PromptLibrary.contextBlock(repeats: repeats)
        let selected = engines.filter { selectedEngineIDs.contains($0.spec.id) }
        Task { @MainActor in
            for engine in selected {
                await self.runOne(engine, prompt: prompt, approxTokens: approxTokens)
            }
            self.isRunning = false
        }
    }

    private func runOne(_ engine: any InferenceEngine, prompt: String, approxTokens: Int) async {
        let spec = engine.spec
        var row = ResultRow(
            engineName: shortName(for: spec),
            badge: spec.badge,
            contextWindow: spec.contextWindow,
            tokensEstimated: spec.tokenCountIsEstimated,
            approxTokens: approxTokens,
            ttftMs: nil,
            outcome: .loading)

        if case .unavailable(let reason) = engine.availability {
            row.outcome = .failed(.other(reason))
            rows.append(row)
            return
        }

        rows.append(row)
        let index = rows.count - 1

        do {
            try await engine.prepare { _ in }
        } catch {
            rows[index].outcome = .failed(.other(error.localizedDescription))
            return
        }

        rows[index].outcome = .running
        let run = StreamRun()
        // Short completions: the needle answer is one line, and we're here to
        // measure prompt eval, not generation. Same SmolLM3 /no_think guard as
        // the arena.
        await run.consume(engine.stream(
            prompt: prompt,
            system: ArenaRunner.systemPrompt(for: engine),
            maxTokens: 96))

        rows[index].ttftMs = run.ttftMs > 0 ? run.ttftMs : nil
        switch run.phase {
        case .failed(let reason):
            rows[index].outcome = .failed(reason)
        default:
            rows[index].outcome = .ok(tokPerSec: run.tokPerSec)
        }
    }

    private func shortName(for spec: EngineSpec) -> String {
        if spec.id == "afm" { return "Apple FM" }
        if spec.id.contains("SmolLM3") { return "SmolLM3 3B" }
        if spec.id.contains("Qwen3-1.7B") { return "Qwen3 1.7B" }
        return spec.displayName
    }
}

#Preview { ContextStressView() }
