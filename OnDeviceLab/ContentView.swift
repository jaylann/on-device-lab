import SwiftUI

struct ContentView: View {
    @State private var engine = LLMEngine()
    @State private var selectedModel = ModelCatalog.qwen06B
    @State private var promptText = PromptLibrary.chatDefault
    @State private var showingBenchmark = false
    @State private var showingModelPicker = false
    @State private var genTask: Task<Void, Never>?

    private let outputBottomID = "output-bottom"

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                controlBar
                Hairline()
                output
                Hairline()
                metrics
                composer
            }
            .padding(DS.Space.gutter)
            .labScreenBackground()
            .navigationTitle("On-Device Lab")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Chat prompt") { promptText = PromptLibrary.chatDefault }
                        Button("Ticket extraction prompt") { promptText = PromptLibrary.extraction }
                        Button("Long-context prompt (M3)") { promptText = PromptLibrary.longContext }
                    } label: {
                        Label("Sample prompts", systemImage: "text.badge.plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingBenchmark = true } label: {
                        Label("Benchmark", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    }
                }
            }
            .navigationDestination(isPresented: $showingBenchmark) {
                BenchmarkView(models: ModelCatalog.benchmarkSet)
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerSheet(models: ModelCatalog.featured, selection: $selectedModel)
        }
    }

    // MARK: Controls — device label + model picker + load

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DeviceInfo.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: DS.Space.row) {
                modelTrigger
                loadButton
            }
        }
    }

    /// Picker trigger: icon · title · value (secondary) · up/down chevron.
    private var modelTrigger: some View {
        Button { showingModelPicker = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "cpu").font(.body).foregroundStyle(DS.accent).frame(width: 22)
                Text("Model").font(.subheadline).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(selectedModel.displayName)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .pill(height: DS.controlHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var loadButton: some View {
        switch engine.loadState {
        case .loading(let f):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("\(Int(f * 100))%").font(.subheadline.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .pill(height: DS.controlHeight)
        default:
            let loaded = engine.isLoaded && engine.loadedModel?.id == selectedModel.id
            Button { Task { await engine.load(selectedModel) } } label: {
                Text(loaded ? "Loaded" : "Load")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(loaded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                    .padding(.horizontal, 20)
                    .pill(height: DS.controlHeight, prominent: !loaded)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(loaded)
        }
    }

    // MARK: Output — the hero surface, flexes to fill

    private var output: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(outputEyebrow)
                .font(.caption2.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(engine.output.isEmpty ? placeholder : engine.output)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(engine.output.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id(outputBottomID)
                }
                .onChange(of: engine.output) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(outputBottomID, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var outputEyebrow: String {
        if engine.isGenerating { return "Streaming" }
        return engine.output.isEmpty ? "Ready" : "Response"
    }

    private var placeholder: String {
        switch engine.loadState {
        case .idle: return "Pick a model and press Load. First load downloads the weights (or reads them from the local share); after that it's instant and offline."
        case .loading: return "Loading model…"
        case .failed(let m): return "Load failed:\n\(m)"
        case .loaded: return "Loaded \(engine.loadedModel?.displayName ?? ""). Type a prompt and press send — watch the first token, then the stream."
        }
    }

    // MARK: Metrics — small flat readouts (no surface)

    private var metrics: some View {
        HStack(spacing: 22) {
            flatStat("TTFT", engine.ttftMs > 0 ? String(format: "%.0f ms", engine.ttftMs) : "—")
            flatStat("Tokens/s", engine.tokensPerSecond > 0 ? String(format: "%.0f", engine.tokensPerSecond) : "—")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    private func flatStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
    }

    // MARK: Composer — fixed-height field + send

    private var composer: some View {
        HStack(alignment: .bottom, spacing: DS.Space.row) {
            TextField("Message", text: $promptText, axis: .vertical)
                .font(.callout)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .glass(in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .onSubmit(send)
            sendControl
        }
    }

    @ViewBuilder private var sendControl: some View {
        if engine.isGenerating {
            Button { genTask?.cancel(); engine.isGenerating = false } label: {
                Image(systemName: "stop.fill").font(.body)
                    .frame(width: DS.controlHeight, height: DS.controlHeight)
                    .glass(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            Button(action: send) {
                Group {
                    let icon = Image(systemName: "arrow.up").font(.body.weight(.bold))
                        .foregroundStyle(sendEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: DS.controlHeight, height: DS.controlHeight)
                    if sendEnabled {
                        icon.accentGlass(in: Circle())
                    } else {
                        icon.glass(in: Circle())
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!sendEnabled)
        }
    }

    private var sendEnabled: Bool {
        engine.isLoaded && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard sendEnabled, !engine.isGenerating else { return }
        let p = promptText
        genTask = Task { await engine.send(p) }
    }
}

#Preview { ContentView() }
