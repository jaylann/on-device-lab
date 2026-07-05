import SwiftUI

/// The race: every engine answers the same prompt, side by side, with live
/// TTFT and throughput. Unavailable engines stay on screen, greyed, with the
/// reason — that asymmetry is part of the story.
struct ArenaView: View {
    @State private var runner = ArenaRunner()
    @State private var promptText = PromptLibrary.carRange

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                lanes
                composer
            }
            .padding(DS.Space.gutter)
            .ambientGradientBackground(tint: DS.accent)
            .navigationTitle("Arena")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) { presetMenu }
                ToolbarItem(placement: .primaryAction) { modeToggle }
            }
        }
    }

    // MARK: Lanes

    @ViewBuilder private var lanes: some View {
        #if os(macOS)
        HStack(spacing: DS.Space.row) {
            ForEach(runner.lanes) { lane in laneCard(lane) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        ScrollView {
            VStack(spacing: DS.Space.row) {
                ForEach(runner.lanes) { lane in
                    laneCard(lane).frame(height: 280)
                }
            }
        }
        #endif
    }

    private func laneCard(_ lane: ArenaRunner.Lane) -> some View {
        ArenaLaneView(
            lane: lane,
            isBestTTFT: runner.bestTTFTLaneID == lane.id,
            isBestTokPerSec: runner.bestTokPerSecLaneID == lane.id)
    }

    // MARK: Controls

    private var presetMenu: some View {
        Menu {
            Button("Driver range question") { promptText = PromptLibrary.carRange }
            Button("Charging receipt extraction") { promptText = PromptLibrary.chargingInvoice }
            Button("Why on-device?") { promptText = PromptLibrary.chatDefault }
        } label: {
            Label("Presets", systemImage: "text.badge.plus")
        }
    }

    private var modeToggle: some View {
        Picker("Mode", selection: $runner.parallel) {
            Text("Parallel").tag(true)
            Text("Sequential").tag(false)
        }
        .pickerStyle(.segmented)
        .disabled(runner.isRunning)
        .help("Sequential unloads each open-weight model before the next lane runs — the memory-safe mode for iPhone.")
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: DS.Space.row) {
            TextField("Prompt for every lane", text: $promptText, axis: .vertical)
                .font(.callout)
                .lineLimit(2, reservesSpace: true)
                .textFieldStyle(.plain)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .glassTile(radius: DS.Radius.tile)
                .onSubmit(go)
            goControl
        }
    }

    @ViewBuilder private var goControl: some View {
        if runner.isRunning {
            Button { runner.stop() } label: {
                Image(systemName: "stop.fill").font(.body)
                    .frame(width: DS.controlHeight, height: DS.controlHeight)
                    .glassPill()
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button(action: go) {
                Image(systemName: "flag.checkered").font(.body.weight(.bold))
                    .foregroundStyle(goEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: DS.controlHeight, height: DS.controlHeight)
                    .glassPill(tint: goEnabled ? DS.accent : nil)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!goEnabled)
        }
    }

    private var goEnabled: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func go() {
        guard goEnabled, !runner.isRunning else { return }
        runner.start(prompt: promptText)
    }
}

// MARK: - One lane

private struct ArenaLaneView: View {
    let lane: ArenaRunner.Lane
    let isBestTTFT: Bool
    let isBestTokPerSec: Bool

    private let bottomID = "lane-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            output
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassTile(radius: DS.Radius.card)
        .opacity(lane.isAvailable ? 1 : 0.5)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EngineBadge(text: lane.spec.badge)
                Text(lane.spec.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            if let reason = lane.unavailabilityReason {
                Text(reason).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(lane.run.output.isEmpty ? placeholder : lane.run.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(lane.run.output.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 1).id(bottomID)
            }
            .onChange(of: lane.run.output) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placeholder: String {
        switch lane.run.phase {
        case .loading:
            return lane.loadProgress > 0 && lane.loadProgress < 1
                ? "Loading… \(Int(lane.loadProgress * 100))%"
                : "Loading…"
        default:
            return lane.isAvailable ? "Waiting for the flag." : "Out of the race on this machine."
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            stat("TTFT",
                 lane.run.ttftMs > 0 ? String(format: "%.0f ms", lane.run.ttftMs) : "—",
                 highlighted: isBestTTFT)
            stat("tok/s",
                 lane.run.tokPerSec > 0
                     ? (lane.spec.tokenCountIsEstimated ? "≈" : "") + String(format: "%.0f", lane.run.tokPerSec)
                     : "—",
                 highlighted: isBestTokPerSec)
            Spacer(minLength: 0)
            trailingStatus
        }
    }

    @ViewBuilder private var trailingStatus: some View {
        switch lane.run.phase {
        case .loading:
            ProgressView().controlSize(.mini)
        case .streaming:
            Text("streaming").font(.caption2).foregroundStyle(.secondary)
        case .failed(let reason):
            StatusChip(reason: reason)
        case .done, .idle:
            EmptyView()
        }
    }

    private func stat(_ label: String, _ value: String, highlighted: Bool) -> some View {
        HStack(spacing: 4) {
            if highlighted {
                Image(systemName: "trophy.fill").font(.caption2).foregroundStyle(DS.accent)
            }
            Text(label).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(highlighted ? AnyShapeStyle(DS.accent) : AnyShapeStyle(.primary))
                .contentTransition(.numericText())
        }
    }
}

#Preview { ArenaView() }
