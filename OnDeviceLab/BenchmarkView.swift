import SwiftUI

struct BenchmarkView: View {
    let models: [LabModel]
    @State private var runner = BenchmarkRunner()
    @State private var exportURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.section) {
                Text("Same prompt, warmup + 5 runs per model. TTFT = time to first token; tok/s = sustained decode. Numbers stay 0 until you fill the two TODOs in Benchmark.swift (or run the Solution scheme).")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                resultsCard
                statusLine
            }
            .padding(DS.Space.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ambientGradientBackground(tint: DS.accent)
        .onChange(of: runner.isRunning) { _, running in
            // Write the export file once, when a run finishes — not on every redraw.
            guard !running else { exportURL = nil; return }
            exportURL = runner.results.isEmpty ? nil
                : ResultsExporter.writeTempFile(
                    ResultsExporter.payload(from: runner.results, device: runner.device, maxTokens: 128))
        }
        .navigationTitle("Benchmark")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let url = exportURL {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
                Button {
                    Task { await runner.run(models: models) }
                } label: {
                    Label(runner.results.isEmpty ? "Run" : "Run again", systemImage: "play.fill")
                }
                .disabled(runner.isRunning)
            }
        }
    }

    // MARK: Results card

    private var resultsCard: some View {
        VStack(spacing: 0) {
            row(["Model", "TTFT p50", "TTFT p99", "tok/s"], header: true)
            Divider().overlay(Color.primary.opacity(0.08)).padding(.vertical, 10)

            if runner.results.isEmpty {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    row([model.displayName, "—", "—", "—"], header: false).padding(.vertical, 6)
                    if index < models.count - 1 { rowDivider }
                }
            } else {
                ForEach(Array(runner.results.enumerated()), id: \.element.id) { index, r in
                    row([
                        r.displayName,
                        String(format: "%.0f ms", r.ttftP50Ms),
                        String(format: "%.0f ms", r.ttftP99Ms),
                        String(format: "%.0f", r.tokPerSecP50),
                    ], header: false).padding(.vertical, 6)
                    if index < runner.results.count - 1 { rowDivider }
                }
            }
        }
        .padding(18)
        .glassTile(radius: DS.Radius.card)
    }

    private var rowDivider: some View {
        Divider().overlay(Color.primary.opacity(0.05))
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(header ? .caption2.weight(.semibold) : .system(.callout, design: .monospaced))
                    .foregroundStyle(header ? .secondary : (i == 0 ? .primary : .secondary))
                    .textCase(header ? .uppercase : nil)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if runner.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(runner.note.isEmpty ? "Running…" : runner.note)
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if !runner.note.isEmpty {
            Text(runner.note).font(.caption).foregroundStyle(.secondary)
        }
    }

}
