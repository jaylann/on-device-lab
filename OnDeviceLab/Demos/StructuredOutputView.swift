import SwiftUI
import Observation

/// The Extract tab: the charging receipt goes into each engine, and what comes
/// back is validated live. Qwen3-0.6B is in the line-up on purpose — it fails
/// more often, and a red dot on stage is worth three slides.
struct StructuredOutputView: View {
    @State private var runner = ExtractionRunner()

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                engineChips
                resultCard
                historyStrip
                footer
                runButton
            }
            .padding(DS.Space.gutter)
            .ambientGradientBackground(tint: DS.accent)
            .navigationTitle("Structured Output")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var engineChips: some View {
        HStack(spacing: DS.Space.row) {
            ForEach(ExtractionRunner.EngineChoice.allCases) { choice in
                EngineChip(
                    title: runner.title(for: choice),
                    selected: runner.selection == choice,
                    enabled: !runner.isRunning
                ) { runner.selection = choice }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.caption2.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(.secondary)
            ScrollView {
                resultBody.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassTile(radius: DS.Radius.card)
    }

    private var eyebrow: String {
        switch runner.state {
        case .idle: return "Ready"
        case .loading: return "Loading model"
        case .working: return "Extracting"
        case .finished(let r): return r.passed ? "Parsed · all fields present" : "Validation failed"
        case .failed: return "Run failed"
        }
    }

    @ViewBuilder private var resultBody: some View {
        switch runner.state {
        case .idle:
            Text("The charging receipt below goes to the selected engine; the reply is stripped, decoded and checked field by field.\n\n"
                 + PromptLibrary.chargingInvoice)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        case .loading(let progress):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress > 0 && progress < 1 ? "Loading… \(Int(progress * 100))%" : "Loading…")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .working(let streamed):
            Text(streamed.isEmpty ? "Waiting for the first token…" : streamed)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(streamed.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        case .finished(let result):
            validationView(result)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 10) {
                StatusChip(reason: reason)
                if case .guardrail = reason {
                    Text("The system model declined the request — schema was never even in question.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func validationView(_ result: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let fields = result.fields {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(fields.fieldPairs, id: \.name) { pair in
                        GridRow {
                            Image(systemName: pair.value != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(pair.value != nil ? .green : .red)
                            Text(pair.name)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(pair.value ?? "missing")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(pair.value != nil ? .primary : .secondary)
                        }
                    }
                }
                if !result.missing.isEmpty {
                    StatusChip(text: "missing: \(result.missing.joined(separator: ", "))", color: .red)
                }
            } else {
                StatusChip(text: result.errorDescription ?? "JSON decode failed", color: .red)
                Text("Raw output — exactly what the model sent back:")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(result.raw)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: History + footer

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ExtractionRunner.EngineChoice.allCases) { choice in
                HStack(spacing: 6) {
                    Text(runner.title(for: choice))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    ForEach(Array((runner.history[choice] ?? []).enumerated()), id: \.offset) { _, passed in
                        Circle()
                            .fill(passed ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var footer: some View {
        Text("AFM's failure mode is refusal, not malformed JSON.")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private var runButton: some View {
        Button { runner.run() } label: {
            Text(runner.isRunning ? "Running…" : "Run extraction")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(runner.isRunning ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .frame(maxWidth: .infinity)
                .glassPill(height: DS.controlHeight, tint: runner.isRunning ? nil : DS.accent)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
    }
}

// MARK: - Runner

@MainActor
@Observable
final class ExtractionRunner {

    enum EngineChoice: String, CaseIterable, Identifiable {
        case afm, qwen06B, qwen17B
        var id: String { rawValue }
    }

    enum State {
        case idle
        case loading(Double)
        case working(streamed: String)
        case finished(ValidationResult)
        case failed(StreamRun.FailReason)
    }

    var selection: EngineChoice = .qwen06B
    var state: State = .idle
    /// Green/red dots per engine, in-memory for the session.
    var history: [EngineChoice: [Bool]] = [:]

    var isRunning: Bool {
        switch state {
        case .loading, .working: return true
        default: return false
        }
    }

    private let qwen06 = MLXEngine(model: ModelCatalog.qwen06B, contextWindow: 32_768)
    private let qwen17 = MLXEngine(model: ModelCatalog.qwen17B, contextWindow: 32_768)
    private let afmAvailabilityNote: String? = {
        let afm = EngineRegistry.makeEngines().first { $0.spec.id == "afm" }
        guard let afm else { return "Needs macOS 26 / iOS 26" }
        switch afm.availability {
        case .available: return nil
        case .downloading: return "Model downloading"
        case .unavailable(let reason): return reason
        }
    }()

    func title(for choice: EngineChoice) -> String {
        switch choice {
        case .afm: return "Apple FM"
        case .qwen06B: return "Qwen3 0.6B"
        case .qwen17B: return "Qwen3 1.7B"
        }
    }

    func run() {
        guard !isRunning else { return }
        let choice = selection
        Task { @MainActor in
            switch choice {
            case .afm: await runAFM()
            case .qwen06B: await runMLX(qwen06, choice: choice)
            case .qwen17B: await runMLX(qwen17, choice: choice)
            }
        }
    }

    private func runAFM() async {
        if let note = afmAvailabilityNote {
            state = .failed(.other(note))
            return
        }
        state = .working(streamed: "")
        do {
            let fields = try await AFMExtractor.extractInvoice(prompt: PromptLibrary.chargingInvoice)
            let result = TicketValidator.validate(fields: fields, raw: "(structured — schema enforced by the runtime)")
            state = .finished(result)
            history[.afm, default: []].append(result.passed)
        } catch let error as EngineError {
            state = .failed(StreamRun.FailReason(error))
            history[.afm, default: []].append(false)
        } catch {
            state = .failed(.other(error.localizedDescription))
            history[.afm, default: []].append(false)
        }
    }

    private func runMLX(_ engine: MLXEngine, choice: EngineChoice) async {
        state = .loading(0)
        do {
            try await engine.prepare { p in
                Task { @MainActor in
                    if case .loading = self.state { self.state = .loading(p) }
                }
            }
        } catch {
            state = .failed(.other(error.localizedDescription))
            return
        }
        state = .working(streamed: "")
        var streamed = ""
        do {
            for try await delta in engine.stream(
                prompt: PromptLibrary.chargingInvoice, system: nil, maxTokens: 512
            ) {
                streamed += delta.text
                state = .working(streamed: streamed)
            }
        } catch let error as EngineError {
            state = .failed(StreamRun.FailReason(error))
            history[choice, default: []].append(false)
            return
        } catch {
            state = .failed(.other(error.localizedDescription))
            history[choice, default: []].append(false)
            return
        }
        let result = TicketValidator.validate(rawOutput: streamed)
        state = .finished(result)
        history[choice, default: []].append(result.passed)
    }
}

#Preview { StructuredOutputView() }
