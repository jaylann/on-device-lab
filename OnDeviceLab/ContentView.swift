import SwiftUI

struct ContentView: View {
    @State private var engine = LLMEngine()
    @State private var net = NetworkMonitor()
    @State private var selectedModel = ModelCatalog.qwen05B
    @State private var promptText = PromptLibrary.chatDefault
    @State private var showingBenchmark = false
    @State private var genTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            output
            Divider()
            metrics
            promptBar
        }
        .sheet(isPresented: $showingBenchmark) {
            BenchmarkView(models: ModelCatalog.benchmarkSet)
        }
    }

    // MARK: Header — model picker, network chip, load state

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("On-Device Lab").font(.headline)
                Text(DeviceInfo.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            networkChip
            Picker("Model", selection: $selectedModel) {
                ForEach(ModelCatalog.all) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 230)
            loadButton
        }
        .padding(12)
    }

    @ViewBuilder private var loadButton: some View {
        switch engine.loadState {
        case .loading(let f):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("\(Int(f * 100))%").monospacedDigit() }
        default:
            Button(engine.isLoaded && engine.loadedModel?.id == selectedModel.id ? "Loaded" : "Load") {
                Task { await engine.load(selectedModel) }
            }
            .disabled(engine.isLoaded && engine.loadedModel?.id == selectedModel.id)
        }
    }

    private var networkChip: some View {
        Label(net.isOnline ? "online" : "offline", systemImage: net.isOnline ? "wifi" : "wifi.slash")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(net.isOnline ? Color.secondary.opacity(0.15) : Color.green.opacity(0.22), in: Capsule())
            .foregroundStyle(net.isOnline ? Color.secondary : Color.green)
    }

    // MARK: Output

    private var output: some View {
        ScrollView {
            Text(engine.output.isEmpty ? placeholder : engine.output)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(engine.output.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    private var placeholder: String {
        switch engine.loadState {
        case .idle: return "Pick a model and press Load. First load downloads the weights (or reads them from the local share); after that it's instant and offline."
        case .loading: return "Loading model…"
        case .failed(let m): return "Load failed:\n\(m)"
        case .loaded: return "Loaded \(engine.loadedModel?.displayName ?? ""). Type a prompt and press Send — watch the first token, then the stream."
        }
    }

    // MARK: Metrics

    private var metrics: some View {
        HStack(spacing: 28) {
            metric("TTFT", engine.ttftMs > 0 ? String(format: "%.0f ms", engine.ttftMs) : "—")
            metric("throughput", engine.tokensPerSecond > 0 ? String(format: "%.0f tok/s", engine.tokensPerSecond) : "—")
            Spacer()
            Button { showingBenchmark = true } label: { Label("Benchmark", systemImage: "gauge.with.dots.needle.bottom.50percent") }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
    }

    // MARK: Prompt bar

    private var promptBar: some View {
        HStack(spacing: 10) {
            TextField("Prompt", text: $promptText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(send)
            if engine.isGenerating {
                Button("Stop") { genTask?.cancel(); engine.isGenerating = false }
            } else {
                Button("Send", action: send)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!engine.isLoaded || promptText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func send() {
        guard engine.isLoaded, !engine.isGenerating else { return }
        let p = promptText
        genTask = Task { await engine.send(p) }
    }
}

#Preview { ContentView() }
