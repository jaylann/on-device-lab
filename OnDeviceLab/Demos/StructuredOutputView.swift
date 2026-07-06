import SwiftUI
import Observation

/// The Extract tab: the charging receipt goes into each engine, and what comes
/// back is validated live. Qwen3-0.6B is in the line-up on purpose — it fails
/// more often, and a red dot on stage is worth three slides.
struct StructuredOutputView: View {
    @State private var runner = ExtractionRunner()
    @State private var selectedPreset = presets[0]

    /// Three receipts, same six-field schema: a clean one, a different provider,
    /// and an OCR-grade mess. Each carries its ground truth — extraction is
    /// graded on VALUES, not just parseability.
    struct Preset {
        let title: String
        let prompt: String
        let expected: InvoiceFields
    }

    private static let presets: [Preset] = [
        Preset(title: "IONITY (clean)",
               prompt: PromptLibrary.chargingInvoice,
               expected: InvoiceFields(provider: "IONITY", location: "Stuttgart-Zuffenhausen",
                                       kwh: 43.7, duration_min: 31.2, total_eur: 34.52,
                                       session_id: "IONITY-DE-2207-884131")),
        Preset(title: "EnBW (clean)",
               prompt: PromptLibrary.chargingInvoiceAlt,
               expected: InvoiceFields(provider: "EnBW", location: "Pragsattel",
                                       kwh: 27.9, duration_min: 18.6, total_eur: 17.02,
                                       session_id: "ENBW-DE-0702-113058")),
        Preset(title: "Fastned (messy scan)",
               prompt: PromptLibrary.chargingInvoiceScan,
               expected: InvoiceFields(provider: "Fastned", location: "Kamener Kreuz",
                                       kwh: 61.5, duration_min: 44.8, total_eur: 58.41,
                                       session_id: "FASTNED-DE-1119-002764")),
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
                ForEach(runner.contenders) { contender in
                    EngineChip(
                        title: contender.title,
                        selected: runner.selection == contender.id,
                        enabled: !runner.isRunning
                    ) { runner.selection = contender.id }
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
            if result.errorDescription == nil {
                HStack(spacing: 8) {
                    Image(systemName: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(result.passed ? .green : .red)
                    Text(result.passed ? "All six fields correct" : "Wrong or missing fields")
                        .font(.headline)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(result.checks, id: \.name) { check in
                        GridRow {
                            Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(check.ok ? .green : .red)
                            Text(check.name)
                                .font(DS.Typo.mono)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.got ?? "missing")
                                    .font(DS.Typo.stream.weight(.semibold))
                                    .foregroundStyle(check.got != nil ? (check.ok ? .primary : Color.red) : .secondary)
                                if !check.ok {
                                    Text("expected \(check.expected)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
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
            ForEach(runner.contenders) { contender in
                let results = runner.history[contender.id] ?? []
                HStack(spacing: 10) {
                    Text(contender.title)
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
            Text("Pass = every field parsed AND matching the receipt. AFM's failure mode is refusal, not malformed JSON.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(radius: DS.Radius.tile)
    }

    private var runButton: some View {
        Button { runner.run(prompt: selectedPreset.prompt, expected: selectedPreset.expected) } label: {
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

    struct Contender: Identifiable, Hashable {
        let id: String        // "afm" or a Hugging Face repo id
        let title: String
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

    static let afmID = "afm"

    /// AFM plus the full model catalog — the same lineup the Chat tab offers.
    let contenders: [Contender] =
        [Contender(id: afmID, title: "Apple FM · ~3B · 2-bit")]
        + ModelCatalog.all.map { Contender(id: $0.id, title: $0.displayName) }

    var selection: String = ModelCatalog.qwen06B.id
    var state: State = .idle
    /// Green/red dots per engine, in-memory for the session.
    var history: [String: [Bool]] = [:]

    var isRunning: Bool {
        switch state {
        case .loading, .working, .extracting: return true
        default: return false
        }
    }

    private var mlxEngines: [String: MLXEngine] = [:]
    /// The one MLX model kept resident; switching contenders unloads the last.
    private var loadedEngine: MLXEngine?
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

    func run(prompt: String, expected: InvoiceFields) {
        guard !isRunning else { return }
        let id = selection
        Task { @MainActor in
            if id == Self.afmID {
                await runAFM(prompt: prompt, expected: expected)
            } else if let model = ModelCatalog.all.first(where: { $0.id == id }) {
                await runMLX(model: model, prompt: prompt, expected: expected)
            }
        }
    }

    private func runAFM(prompt: String, expected: InvoiceFields) async {
        if let note = afmAvailabilityNote {
            state = .failed(.other(note))
            return
        }
        state = .extracting
        do {
            let fields = try await AFMExtractor.extractInvoice(prompt: prompt)
            let result = TicketValidator.validate(
                fields: fields, raw: "(structured — schema enforced by the runtime)", expected: expected)
            state = .finished(result)
            history[Self.afmID, default: []].append(result.passed)
        } catch let error as EngineError {
            state = .failed(StreamRun.FailReason(error))
            history[Self.afmID, default: []].append(false)
        } catch {
            state = .failed(.other(error.localizedDescription))
            history[Self.afmID, default: []].append(false)
        }
    }

    private func runMLX(model: LabModel, prompt: String, expected: InvoiceFields) async {
        let engine = mlxEngine(for: model)
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
            let result = TicketValidator.validate(
                fields: fields, raw: "(grammar-locked · mlx-swift-structured)", expected: expected)
            state = .finished(result)
            history[model.id, default: []].append(result.passed)
        } catch let error as EngineError {
            state = .failed(StreamRun.FailReason(error))
            history[model.id, default: []].append(false)
        } catch {
            state = .failed(.other(error.localizedDescription))
            history[model.id, default: []].append(false)
        }
    }

    private func mlxEngine(for model: LabModel) -> MLXEngine {
        let engine = mlxEngines[model.id] ?? EngineRegistry.mlxEngine(for: model)
        mlxEngines[model.id] = engine
        if let loadedEngine, loadedEngine !== engine {
            loadedEngine.unload()
        }
        loadedEngine = engine
        return engine
    }
}

#Preview { StructuredOutputView() }
