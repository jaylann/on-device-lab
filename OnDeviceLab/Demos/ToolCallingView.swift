import SwiftUI
import Observation

/// The Tools tab: same driver question, two very different call loops. AFM's
/// runtime manages the tools itself; the open-weight model follows a JSON
/// protocol we invented in a system prompt — every hop lands in the trace.
struct ToolCallingView: View {
    @State private var runner = ToolCallRunner()
    @State private var promptText = "I'm at 20% battery near Stuttgart — where should I charge?"

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                engineChips
                traceCard
                composer
            }
            .padding(DS.Space.gutter)
            .ambientGradientBackground(tint: DS.accent)
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
            case .afm: return "Apple FM"
            case .qwen17B: return "Qwen3 1.7B"
            }
        }
    }

    var selection: EngineChoice = .qwen17B
    var trace: [ToolTraceStep] = []
    var isRunning = false
    var loadProgress: Double?

    private let mlx = MLXEngine(model: ModelCatalog.qwen17B, contextWindow: 32_768)

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
        append(.model, "Apple FM", "session with 3 registered tools", ok: true)
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

    // MARK: MLX — hand-rolled JSON protocol, max 2 hops

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

        var transcript = prompt
        for hop in 0..<2 {
            append(.model, "Qwen3 1.7B · turn \(hop + 1)", "", ok: true)
            let reply: String
            do {
                reply = try await collect(prompt: transcript)
            } catch {
                append(.failure, "generation failed", error.localizedDescription, ok: false)
                return
            }
            guard let call = MLXToolProtocol.parseToolCall(reply) else {
                // No JSON — the model is answering in prose. Done.
                append(.answer, "answer", reply.trimmingCharacters(in: .whitespacesAndNewlines), ok: true)
                return
            }
            let argsText = (try? JSONSerialization.data(withJSONObject: call.arguments))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            guard let result = CarToolbox.dispatch(name: call.name, arguments: call.arguments) else {
                append(.toolCall, "\(call.name)(\(argsText))", "unknown tool — not in the toolbox", ok: false)
                transcript += "\n\n\(reply)\nTOOL RESULT: error — unknown tool \"\(call.name)\". "
                    + "Answer the driver with what you know."
                continue
            }
            append(.toolCall, "\(call.name)(\(argsText))", "", ok: true)
            append(.toolResult, "result", result, ok: true)
            transcript += "\n\n\(reply)\nTOOL RESULT: \(result)\n\n"
                + "Using the tool result above, answer the driver's question in one or two short sentences (no JSON)."
        }
        append(.failure, "max hops reached", "still emitting tool calls after 2 turns", ok: false)
    }

    private func collect(prompt: String) async throws -> String {
        var text = ""
        for try await delta in mlx.stream(prompt: prompt, system: MLXToolProtocol.systemPrompt, maxTokens: 384) {
            text += delta.text
        }
        return text
    }

    private func append(_ kind: ToolTraceStep.Kind, _ title: String, _ detail: String, ok: Bool) {
        trace.append(ToolTraceStep(kind: kind, title: title, detail: detail, ok: ok))
    }
}

#Preview { ToolCallingView() }
