import SwiftUI

struct BenchmarkView: View {
    let models: [LabModel]
    @State private var runner = BenchmarkRunner()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Benchmark").font(.title2.bold())
                    Text(runner.device).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }

            Text("Same prompt, warmup + 5 runs per model. TTFT = time to first token; tok/s = sustained decode. Numbers are 0 until you fill the two TODOs in **Benchmark.swift** (or run the *Solution* scheme).")
                .font(.callout).foregroundStyle(.secondary)

            table

            if runner.isRunning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(runner.note).font(.caption) }
            } else if !runner.note.isEmpty {
                Text(runner.note).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task { await runner.run(models: models) }
                } label: {
                    Label(runner.results.isEmpty ? "Run suite" : "Run again", systemImage: "play.fill")
                }
                .disabled(runner.isRunning)

                if let url = exportURL {
                    ShareLink(item: url) { Label("Export JSON", systemImage: "square.and.arrow.up") }
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 380)
    }

    private var table: some View {
        VStack(spacing: 0) {
            row(header: true, cells: ["Model", "TTFT p50", "TTFT p99", "tok/s"])
            Divider()
            if runner.results.isEmpty {
                Text("No runs yet").font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
            } else {
                ForEach(runner.results) { r in
                    row(header: false, cells: [
                        r.displayName,
                        String(format: "%.0f ms", r.ttftP50Ms),
                        String(format: "%.0f ms", r.ttftP99Ms),
                        String(format: "%.0f", r.tokPerSecP50),
                    ])
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(header: Bool, cells: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(header ? .caption.bold() : .system(.callout, design: .monospaced))
                    .foregroundStyle(header ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var exportURL: URL? {
        guard !runner.results.isEmpty else { return nil }
        let payload = ResultsExporter.payload(from: runner.results, device: runner.device, maxTokens: 128)
        return ResultsExporter.writeTempFile(payload)
    }
}
