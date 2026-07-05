import SwiftUI

/// Root of the demo app: one tab per act of the talk. The Chat tab is the
/// original `ContentView`, untouched; the other four are the live demos.
struct LabRootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
            ArenaView()
                .tabItem { Label("Arena", systemImage: "flag.checkered") }
            StructuredOutputView()
                .tabItem { Label("Extract", systemImage: "curlybraces") }
            ToolCallingView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            ContextStressView()
                .tabItem { Label("Context", systemImage: "doc.text.magnifyingglass") }
        }
    }
}

// MARK: - Shared demo chrome

/// Failure chip copy + color, shared by every demo tab. Failures render as
/// chips in place — never alerts — because on stage a refusal IS the demo.
extension StreamRun.FailReason {
    var chipText: String {
        switch self {
        case .guardrail: return "AFM safety block"
        case .contextOverflow: return "context limit"
        case .rateLimited: return "rate limited"
        case .other(let message): return message
        }
    }

    var chipColor: Color {
        switch self {
        case .guardrail, .rateLimited: return .orange
        case .contextOverflow, .other: return .red
        }
    }
}

/// Small colored capsule for failure states (and any other status callout).
struct StatusChip: View {
    let text: String
    let color: Color

    init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    init(reason: StreamRun.FailReason) {
        self.init(text: reason.chipText, color: reason.chipColor)
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(2)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule(style: .continuous))
    }
}

/// Engine badge ("AFM" / "MLX") rendered the same way in every tab.
struct EngineBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.accent.opacity(0.12), in: Capsule(style: .continuous))
    }
}

/// Selectable engine chip used by the Extract / Tools / Context tabs.
struct EngineChip: View {
    let title: String
    let selected: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 14)
                .glassPill(height: 34, tint: selected ? DS.accent : nil)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

#Preview { LabRootView() }
