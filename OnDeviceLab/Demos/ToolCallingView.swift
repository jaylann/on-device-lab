import SwiftUI
import Observation

/// The Tools tab: same driver question, same three tools, two call loops. AFM's
/// runtime manages the tools itself; the open-weight model runs a grammar-locked
/// JSON loop — every hop lands in the trace either way.
struct ToolCallingView: View {
    @State private var runner = ToolCallRunner()
    @State private var promptText = "I'm at 20% battery near Stuttgart — where should I charge?"

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                TabExplainer("One question, real tool calls, the same three tools — AFM's native Tool loop vs a grammar-locked JSON loop, every hop in the trace.")
                engineChips
                traceCard
                composer
            }
            .padding(DS.Space.gutter)
            .labScreenBackground(tint: DS.accent)
            .navigationTitle("Tool Calling")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var engineChips: some View {
        // Horizontal scroll so the chip row can never shove a compact layout off-screen.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.row) {
                ForEach(ToolCallRunner.EngineChoice.allCases) { choice in
                    EngineChip(
                        title: choice.title,
                        selected: runner.selection == choice,
                        enabled: !runner.isRunning
                    ) { runner.selection = choice }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Trace timeline

    private var traceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(runner.isRunning ? "Running" : (runner.trace.isEmpty ? "Ready" : "Trace"))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if runner.trace.isEmpty {
                            Text("Press run: the timeline shows every hop — model turn, tool call, tool result, final answer. Parse failures land here too, on purpose.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(runner.trace.enumerated()), id: \.element.id) { index, step in
                            traceRow(step, isLast: index == runner.trace.count - 1)
                        }
                        Color.clear.frame(height: 1).id("trace-bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: runner.trace.count) {
                    proxy.scrollTo("trace-bottom", anchor: .bottom)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassTile(radius: DS.Radius.card)
    }

    /// One hop, sequence-diagram style: tinted node, connector down to the
    /// next hop, payload in monospace.
    private func traceRow(_ step: ToolTraceStep, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(tint(for: step).opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon(for: step.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint(for: step))
                }
                if !isLast {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(step.title).font(.footnote.weight(.semibold))
                    if !step.ok {
                        StatusChip(text: "fail", color: .red, icon: "xmark")
                    }
                }
                .frame(minHeight: 28)
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(DS.Typo.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tint(for step: ToolTraceStep) -> Color {
        if !step.ok { return .red }
        switch step.kind {
        case .model: return DS.accent
        case .toolCall, .toolResult: return .orange
        case .answer: return .green
        case .failure: return .red
        }
    }

    private func icon(for kind: ToolTraceStep.Kind) -> String {
        switch kind {
        case .model: return "brain"
        case .toolCall: return "wrench.and.screwdriver.fill"
        case .toolResult: return "arrow.turn.down.right"
        case .answer: return "checkmark.bubble.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: DS.Space.row) {
            TextField("Driver question", text: $promptText, axis: .vertical)
                .font(.callout)
                .lineLimit(2, reservesSpace: true)
                .textFieldStyle(.plain)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .glassTile(radius: DS.Radius.tile)
            runControl
        }
    }

    @ViewBuilder private var runControl: some View {
        if runner.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if let p = runner.loadProgress, p > 0, p < 1 {
                    Text("\(Int(p * 100))%").font(.subheadline.monospacedDigit())
                }
            }
            .padding(.horizontal, 18)
            .glassPill(height: DS.controlHeight)
        } else {
            Button { runner.run(prompt: promptText) } label: {
                Image(systemName: "arrow.up").font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: DS.controlHeight, height: DS.controlHeight)
                    .glassPill(tint: DS.accent)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// MARK: - Runner

@MainActor
@Observable
final class ToolCallRunner {

    enum EngineChoice: String, CaseIterable, Identifiable {
        case afm, qwen17B
        var id: String { rawValue }
        var title: String {
            switch self {
            case .afm: return "Apple FM · ~3B · 2-bit"
            case .qwen17B: return ModelCatalog.qwen17B.displayName
            }
        }
    }

    var selection: EngineChoice = .qwen17B
    var trace: [ToolTraceStep] = []
    var isRunning = false
    var loadProgress: Double?

    /// Both engines register the same toolbox; `final_answer` is the grammar
    /// lock's loop terminator, not a tool.
    private static let toolCount = GrammarLock.toolNames.count - 1

    private let mlx = EngineRegistry.mlxEngine(for: ModelCatalog.qwen17B)

    func run(prompt: String) {
        guard !isRunning else { return }
        isRunning = true
        trace = []
        let choice = selection
        Task { @MainActor in
            switch choice {
            case .afm: await runAFM(prompt: prompt)
            case .qwen17B: await runMLX(prompt: prompt)
            }
            self.isRunning = false
            self.loadProgress = nil
        }
    }

    // MARK: AFM — the runtime drives the loop, tools report into the trace

    private func runAFM(prompt: String) async {
        append(.model, "Apple FM · ~3B · 2-bit",
               "session · \(Self.toolCount) registered tools · native Tool loop", ok: true)
        do {
            let answer = try await AFMToolFacade.answer(prompt: prompt) { call, result in
                Task { @MainActor in
                    self.append(.toolCall, call, "", ok: true)
                    self.append(.toolResult, "result", result, ok: true)
                }
            }
            append(.answer, "answer", answer, ok: true)
        } catch let error as EngineError {
            append(.failure, StreamRun.FailReason(error).chipText, "", ok: false)
        } catch {
            append(.failure, "failed", error.localizedDescription, ok: false)
        }
    }

    // MARK: MLX — grammar-locked tool loop (mlx-swift-structured)

    /// Each turn is a schema-constrained tool call: the tool name can only be one of the
    /// allowed values, so the open model can never emit a bad name or a non-JSON reply —
    /// the same guarantee AFM's runtime gives. Loops until `final_answer`, forcing a
    /// grounded answer if the model repeats a call or hits the hop cap. This is the fair
    /// mirror of AFM's native loop (and matches the measured re-run in the capability eval).
    private func runMLX(prompt: String) async {
        loadProgress = 0
        do {
            try await mlx.prepare { p in
                Task { @MainActor in self.loadProgress = p }
            }
        } catch {
            append(.failure, "load failed", error.localizedDescription, ok: false)
            return
        }
        loadProgress = nil
        append(.model, ModelCatalog.qwen17B.displayName,
               "session · \(Self.toolCount) registered tools · grammar-locked JSON loop", ok: true)

        var transcript = prompt
        var called = Set<String>()
        for hop in 0..<4 {
            append(.model, "turn \(hop + 1)", "grammar-locked tool call", ok: true)
            let call: ToolCall
            do {
                call = try await mlx.structured(
                    prompt: transcript, system: GrammarLock.toolSystem,
                    schema: GrammarLock.toolCallSchema, as: ToolCall.self, maxTokens: 200)
            } catch {
                append(.failure, "generation failed", error.localizedDescription, ok: false)
                return
            }
            if call.tool == "final_answer" {
                append(.answer, "answer",
                       (call.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines), ok: true)
                return
            }
            var args: [String: Any] = [:]
            if let near = call.near { args["near"] = near }
            if let at = call.at { args["at"] = at }
            let argsText = args.map { "\($0): \"\($1)\"" }.joined(separator: ", ")
            guard let result = CarToolbox.dispatch(name: call.tool, arguments: args) else {
                append(.toolCall, "\(call.tool)(\(argsText))", "unknown tool — not in the toolbox", ok: false)
                return
            }
            append(.toolCall, "\(call.tool)(\(argsText))", "", ok: true)
            append(.toolResult, "result", result, ok: true)
            transcript += "\n\nTOOL RESULT [\(call.tool)]: \(result)"

            let sig = "\(call.tool)|\(call.near ?? "")|\(call.at ?? "")"
            if called.contains(sig) { await forceFinalAnswer(transcript); return }
            called.insert(sig)
        }
        await forceFinalAnswer(transcript)
    }

    /// Ground a final answer once the model loops or runs out of hops (isolates grounding
    /// from the small-model self-termination weakness — same trick as the eval harness).
    private func forceFinalAnswer(_ transcript: String) async {
        if let final = try? await mlx.structured(
            prompt: transcript + "\n\nNow reply with the final grounded answer for the driver.",
            system: GrammarLock.toolSystem, schema: GrammarLock.finalAnswerSchema,
            as: FinalAnswer.self, maxTokens: 200) {
            append(.answer, "answer", final.answer.trimmingCharacters(in: .whitespacesAndNewlines), ok: true)
        } else {
            append(.failure, "no final answer", "model did not produce a grounded reply", ok: false)
        }
    }

    private func append(_ kind: ToolTraceStep.Kind, _ title: String, _ detail: String, ok: Bool) {
        trace.append(ToolTraceStep(kind: kind, title: title, detail: detail, ok: ok))
    }
}

#Preview { ToolCallingView() }
