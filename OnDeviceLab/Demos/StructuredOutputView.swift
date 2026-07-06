import SwiftUI
import Observation

/// The Extract tab: the charging receipt goes into each engine, and what comes
/// back is validated live. Qwen3-0.6B is in the line-up on purpose — it fails
/// more often, and a red dot on stage is worth three slides.
struct StructuredOutputView: View {
    @State private var runner = ExtractionRunner()
    @State private var selectedPreset = presets[0]

    /// Three receipts, same six-field schema: a clean one, a different provider,
    /// and an OCR-grade mess where engines are allowed to stumble.
    private static let presets: [(title: String, prompt: String)] = [
        ("IONITY (clean)", PromptLibrary.chargingInvoice),
        ("EnBW (clean)", PromptLibrary.chargingInvoiceAlt),
        ("Fastned (messy scan)", PromptLibrary.chargingInvoiceScan),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                TabExplainer("Same receipt into each engine, out comes typed JSON — Apple FM via @Generable constrained decoding, open weights via an XGrammar grammar lock.")
                engineChips
                presetChips
                resultCard
                scoreboard
                runButton
            }
            .padding(DS.Space.gutter)
            .labScreenBackground(tint: DS.accent)
            .navigationTitle("Structured Output")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var engineChips: some View {
        // Horizontal scroll so the chip row can never shove a compact layout off-screen.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.row) {
                ForEach(ExtractionRunner.EngineChoice.allCases) { choice in
                    EngineChip(
                        title: runner.title(for: choice),
                        selected: runner.selection == choice,
                        enabled: !runner.isRunning
                    ) { runner.selection = choice }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.row) {
                ForEach(Self.presets, id: \.title) { preset in
                    EngineChip(
                        title: preset.title,
                        selected: selectedPreset.title == preset.title,
                        enabled: !runner.isRunning
                    ) { selectedPreset = preset }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(eyebrow)
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
        case .working, .extracting: return "Extracting"
        case .finished(let r): return r.passed ? "Parsed · all fields present" : "Validation failed"
        case .failed: return "Run failed"
        }
    }

    @ViewBuilder private var resultBody: some View {
        switch runner.state {
        case .idle:
            Text("The charging receipt below goes to the selected engine; the reply is decoded into typed fields and checked one by one.\n\n"
                 + selectedPreset.prompt)
                .font(DS.Typo.mono)
                .foregroundStyle(.secondary)
        case .loading(let progress):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress > 0 && progress < 1 ? "Loading… \(Int(progress * 100))%" : "Loading…")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .working(let streamed):
            Text(streamed.isEmpty ? "Waiting for the first token…" : streamed)
                .font(DS.Typo.stream)
                .foregroundStyle(streamed.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        case .extracting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Generating into the schema — constrained decoding, no token stream on this path.")
                    .font(.callout).foregroundStyle(.secondary)
            }
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
        VStack(alignment: .leading, spacing: 14) {
            if let fields = result.fields {
                HStack(spacing: 8) {
                    Image(systemName: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(result.passed ? .green : .red)
                    Text(result.passed ? "All six fields parsed" : "Schema incomplete")
                        .font(.headline)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(fields.fieldPairs, id: \.name) { pair in
                        GridRow {
                            Image(systemName: pair.value != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(pair.value != nil ? .green : .red)
                            Text(pair.name)
                                .font(DS.Typo.mono)
                                .foregroundStyle(.secondary)
                            Text(pair.value ?? "missing")
                                .font(DS.Typo.stream.weight(.semibold))
                                .foregroundStyle(pair.value != nil ? .primary : .secondary)
                        }
                    }
                }
                if !result.missing.isEmpty {
                    StatusChip(text: "missing: \(result.missing.joined(separator: ", "))",
                               color: .red, icon: "exclamationmark.triangle.fill")
                }
            } else {
                // Exhibit A: the verbatim broken output, deliberately framed.
                StatusChip(text: result.errorDescription ?? "JSON decode failed",
                           color: .red, icon: "xmark.octagon.fill")
                Eyebrow("Exhibit A — verbatim model output")
                Text(result.raw)
                    .font(DS.Typo.mono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.red.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(Color.red.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: Scoreboard — one row per engine, dots as session history

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Scoreboard")
            ForEach(ExtractionRunner.EngineChoice.allCases) { choice in
                let results = runner.history[choice] ?? []
                HStack(spacing: 10) {
                    Text(runner.title(for: choice))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                    if results.isEmpty {
                        Text("no runs yet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        HStack(spacing: 5) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, passed in
                                Circle()
                                    .fill(passed ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(results.isEmpty ? "—" : "\(results.filter { $0 }.count)/\(results.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text("AFM's failure mode is refusal, not malformed JSON.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(radius: DS.Radius.tile)
    }

    private var runButton: some View {
        Button { runner.run(prompt: selectedPreset.prompt) } label: {
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
        /// The AFM path: constrained decoding returns in one piece — no stream to show.
        case extracting
        case finished(ValidationResult)
        case failed(StreamRun.FailReason)
    }

    var selection: EngineChoice = .qwen06B
    var state: State = .idle
    /// Green/red dots per engine, in-memory for the session.
    var history: [EngineChoice: [Bool]] = [:]

    var isRunning: Bool {
        switch state {
        case .loading, .working, .extracting: return true
        default: return false
        }
    }

    private let qwen06 = EngineRegistry.mlxEngine(for: ModelCatalog.qwen06B)
    private let qwen17 = EngineRegistry.mlxEngine(for: ModelCatalog.qwen17B)
    private let afmEngine = EngineRegistry.makeEngines().first { $0.spec.id == "afm" }

    /// Computed on every run, not cached: Apple Intelligence can finish
    /// downloading (or be toggled) while the app is open.
    private var afmAvailabilityNote: String? {
        guard let afmEngine else { return "Needs macOS 26 / iOS 26" }
        switch afmEngine.availability {
        case .available: return nil
        case .downloading: return "Model downloading"
        case .unavailable(let reason): return reason
        }
    }

    func title(for choice: EngineChoice) -> String {
        switch choice {
        case .afm: return "Apple FM · ~3B · 2-bit"
        case .qwen06B: return ModelCatalog.qwen06B.displayName
        case .qwen17B: return ModelCatalog.qwen17B.displayName
        }
    }

    func run(prompt: String) {
        guard !isRunning else { return }
        let choice = selection
        Task { @MainActor in
            switch choice {
            case .afm: await runAFM(prompt: prompt)
            case .qwen06B: await runMLX(qwen06, choice: choice, prompt: prompt)
            case .qwen17B: await runMLX(qwen17, choice: choice, prompt: prompt)
            }
        }
    }

    private func runAFM(prompt: String) async {
        if let note = afmAvailabilityNote {
            state = .failed(.other(note))
            return
        }
        state = .extracting
        do {
            let fields = try await AFMExtractor.extractInvoice(prompt: prompt)
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

    private func runMLX(_ engine: MLXEngine, choice: EngineChoice, prompt: String) async {
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
        do {
            // Grammar-locked with mlx-swift-structured — the open-weight mirror of AFM's
            // @Generable. XGrammar constrains decoding to the six-field invoice schema, so
            // (like the Apple path) malformed JSON is impossible; the result decodes straight
            // into typed fields.
            let fields = try await engine.structured(
                prompt: prompt,
                schema: GrammarLock.invoiceSchema,
                as: InvoiceFields.self,
                maxTokens: 512)
            let result = TicketValidator.validate(fields: fields, raw: "(grammar-locked · mlx-swift-structured)")
            state = .finished(result)
            history[choice, default: []].append(result.passed)
        } catch let error as EngineError {
            state = .failed(StreamRun.FailReason(error))
            history[choice, default: []].append(false)
        } catch {
            state = .failed(.other(error.localizedDescription))
            history[choice, default: []].append(false)
        }
    }
}

#Preview { StructuredOutputView() }
