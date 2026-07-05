import SwiftUI

/// The race: every engine answers the same prompt, side by side, with live
/// TTFT and throughput reading like dashboard instruments. Unavailable engines
/// keep their lane — calm, explained — because that asymmetry is the story.
struct ArenaView: View {
    @State private var runner = ArenaRunner()
    @State private var promptText = PromptLibrary.carRange

    private let presets: [(title: String, prompt: String)] = [
        ("Range question", PromptLibrary.carRange),
        ("Receipt extraction", PromptLibrary.chargingInvoice),
        ("Why on-device?", PromptLibrary.chatDefault),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.section) {
                lanes
                presetRow
                composer
            }
            .padding(DS.Space.gutter)
            .ambientGradientBackground(tint: DS.accent)
            .navigationTitle("Arena")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) { modeMenu }
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

    /// One-click preset chips — no menu digging mid-talk.
    private var presetRow: some View {
        HStack(spacing: DS.Space.row) {
            ForEach(presets, id: \.title) { preset in
                EngineChip(
                    title: preset.title,
                    selected: promptText == preset.prompt,
                    enabled: !runner.isRunning
                ) { promptText = preset.prompt }
            }
            Spacer(minLength: 0)
        }
    }

    /// Parallel/Sequential lives in the toolbar as quiet chrome — a labelled
    /// menu, not a raw segmented picker.
    private var modeMenu: some View {
        Menu {
            Picker("Mode", selection: $runner.parallel) {
                Label("Parallel — all lanes at once", systemImage: "square.split.2x1").tag(true)
                Label("Sequential — one lane at a time", systemImage: "square.stack").tag(false)
            }
        } label: {
            Label(runner.parallel ? "Parallel" : "Sequential",
                  systemImage: runner.parallel ? "square.split.2x1" : "square.stack")
        }
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

    private var tint: Color { DS.engineTint(badge: lane.spec.badge) }
    private var holdsARecord: Bool { isBestTTFT || isBestTokPerSec }

    var body: some View {
        Group {
            if lane.isAvailable {
                activeBody
            } else {
                unavailableBody
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassTile(radius: DS.Radius.card)
        .overlay {
            if holdsARecord {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(tint.opacity(0.5), lineWidth: 1.5)
            }
        }
        .animation(.easeOut(duration: 0.25), value: holdsARecord)
    }

    // MARK: Active lane — header / streaming hero / instrument footer

    private var activeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            output
            instruments
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            EngineBadge(text: lane.spec.badge)
            Text(lane.spec.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            statusIndicator
        }
    }

    @ViewBuilder private var statusIndicator: some View {
        switch lane.run.phase {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                if lane.loadProgress > 0, lane.loadProgress < 1 {
                    Text("\(Int(lane.loadProgress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .streaming:
            HStack(spacing: 6) {
                PulsingDot(color: tint)
                Text("live").font(DS.Typo.label).textCase(.uppercase).foregroundStyle(.secondary)
            }
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let reason):
            StatusChip(reason: reason)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(lane.run.output.isEmpty ? placeholder : lane.run.output)
                    .font(DS.Typo.stream)
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
        case .loading: return "Loading weights…"
        default: return "Waiting for the flag."
        }
    }

    private var instruments: some View {
        HStack(alignment: .top, spacing: 18) {
            InstrumentStat(
                label: "TTFT",
                value: lane.run.ttftMs > 0 ? String(format: "%.0f", lane.run.ttftMs) : "—",
                unit: "ms",
                highlighted: isBestTTFT)
            InstrumentStat(
                label: "Speed",
                value: lane.run.tokPerSec > 0
                    ? (lane.spec.tokenCountIsEstimated ? "≈" : "") + String(format: "%.0f", lane.run.tokPerSec)
                    : "—",
                unit: "tok/s",
                highlighted: isBestTokPerSec)
            Spacer(minLength: 0)
        }
    }

    // MARK: Unavailable lane — dignified, explained, still on the grid

    private var unavailableBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                EngineBadge(text: lane.spec.badge)
                Text(lane.spec.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: lane.spec.badge == "AFM" ? "apple.logo" : "shippingbox")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Sitting this one out")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let reason = lane.unavailabilityReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            Spacer()
        }
    }
}

#Preview { ArenaView() }
