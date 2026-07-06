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

/// One-line subtitle under each tab's title: what is being compared and what
/// to watch for — so a tab explains itself even to someone who missed the slide.
struct TabExplainer: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Failure chip copy + color, shared by every demo tab. Failures render as
/// chips in place — never alerts — because on stage a refusal IS the demo.
extension StreamRun.FailReason {
    var chipText: String {
        switch self {
        case .guardrail: return "AFM safety block"
        case .contextOverflow: return "context limit"
        case .rateLimited: return "rate limited"
        case .unsupportedLanguage: return "AFM: unsupported language/locale"
        case .other(let message): return message
        }
    }

    var chipColor: Color {
        switch self {
        case .guardrail, .rateLimited, .unsupportedLanguage: return .orange
        case .contextOverflow, .other: return .red
        }
    }
}

/// Small colored capsule for failure states (and any other status callout).
/// `prominent` bumps size and weight for the money-shot chips (context limit).
struct StatusChip: View {
    let text: String
    let color: Color
    var icon: String?
    var prominent = false

    init(text: String, color: Color, icon: String? = nil, prominent: Bool = false) {
        self.text = text
        self.color = color
        self.icon = icon
        self.prominent = prominent
    }

    init(reason: StreamRun.FailReason) {
        self.init(text: reason.chipText, color: reason.chipColor)
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(prominent ? .caption.weight(.bold) : .caption2.weight(.semibold))
            }
            Text(text)
                .font(prominent ? .caption.weight(.bold) : .caption2.weight(.semibold))
                .lineLimit(2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, prominent ? 12 : 10)
        .padding(.vertical, prominent ? 6 : 4)
        .background(color.opacity(prominent ? 0.16 : 0.14), in: Capsule(style: .continuous))
    }
}

/// Engine badge ("AFM" / "MLX") rendered the same way in every tab, in that
/// engine family's identity color.
struct EngineBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .kerning(0.5)
            .foregroundStyle(DS.engineTint(badge: text))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.engineTint(badge: text).opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .strokeBorder(DS.engineTint(badge: text).opacity(0.5), lineWidth: DS.hairlineWidth)
            )
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selected ? AnyShapeStyle(DS.accent) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .pill(height: DS.controlHeight, tint: selected ? DS.accent : nil)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

#Preview { LabRootView() }
