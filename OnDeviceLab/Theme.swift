import SwiftUI

// Lightweight, self-contained Liquid Glass design layer for the demo.
// Native iOS 26 / macOS 26 glass APIs, with graceful fallbacks when
// Reduce Transparency or Increase Contrast are on.

enum DS {
    static let accent = Color.accentColor

    #if os(macOS)
    static let background = Color(nsColor: .windowBackgroundColor)
    #else
    static let background = Color(uiColor: .systemBackground)
    #endif

    /// Every interactive control (model trigger, Load, send) shares one height
    /// so a row of them reads as a single bar.
    static let controlHeight: CGFloat = 48

    enum Radius {
        static let card: CGFloat = 28
        static let tile: CGFloat = 24
        static let control: CGFloat = 14
        static let chip: CGFloat = 12
    }

    enum Space {
        static let gutter: CGFloat = 16
        static let section: CGFloat = 16
        static let row: CGFloat = 10
    }
}

// MARK: - Ambient gradient background

private struct AmbientGradientBackground: ViewModifier {
    let tint: Color
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if contrast == .increased || reduceTransparency {
                DS.background.ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [tint.opacity(0.18), DS.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Glass card surface

private struct GlassCard: ViewModifier {
    var radius: CGFloat = DS.Radius.card
    var padding: CGFloat = DS.Space.gutter
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content.padding(padding)
        if !reduceTransparency, #available(iOS 26.0, macOS 26.0, *) {
            padded.glassEffect(.regular, in: shape)
        } else {
            padded.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    func ambientGradientBackground(tint: Color = DS.accent) -> some View {
        modifier(AmbientGradientBackground(tint: tint))
    }

    func glassCard(radius: CGFloat = DS.Radius.card, padding: CGFloat = DS.Space.gutter) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }
}

// MARK: - Glass tile

/// The single rounded-rect glass surface shared by every panel, metric cell,
/// control and composer in the app, so they all read as the same material.
/// An optional fixed `height` stops tiles from resizing as their content
/// changes (a metric reading "—" and one reading "412 ms" occupy the same box).
/// Falls back to a material fill when Reduce Transparency is on.
struct GlassTile: ViewModifier {
    var radius: CGFloat = DS.Radius.tile
    var height: CGFloat?
    var tint: Color?
    var capsule = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        let shape: AnyShape = capsule
            ? AnyShape(Capsule(style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        let framed = content.frame(height: height)
        if !reduceTransparency, #available(iOS 26.0, macOS 26.0, *) {
            if let tint {
                framed.glassEffect(.regular.tint(tint.opacity(0.5)), in: shape)
            } else {
                framed.glassEffect(.regular, in: shape)
            }
        } else {
            framed
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

extension View {
    /// Rounded-rect glass surface. Provide `height` for fixed-size cells; omit it
    /// for content that should size to fit (the output card).
    func glassTile(radius: CGFloat = DS.Radius.tile, height: CGFloat? = nil, tint: Color? = nil) -> some View {
        modifier(GlassTile(radius: radius, height: height, tint: tint))
    }

    /// Fully-rounded (capsule) glass surface for pill controls and cells.
    func glassPill(height: CGFloat? = nil, tint: Color? = nil) -> some View {
        modifier(GlassTile(height: height, tint: tint, capsule: true))
    }
}

// MARK: - Demo-overhaul tokens (additive)

extension DS {
    /// One hue per runtime family so a lane's identity reads from the back row:
    /// Apple's system model is indigo, everything open-weight via MLX is teal.
    static func engineTint(badge: String) -> Color {
        badge == "AFM" ? .indigo : .teal
    }

    enum Typo {
        /// Streaming model output — the hero text. Sized for a projector, so a
        /// notch above the platform default on macOS.
        static var stream: Font {
            #if os(macOS)
            .system(size: 15, design: .monospaced)
            #else
            .system(.callout, design: .monospaced)
            #endif
        }

        /// Small monospaced metadata: raw model output, trace details.
        static var mono: Font {
            #if os(macOS)
            .system(size: 12, design: .monospaced)
            #else
            .system(.caption, design: .monospaced)
            #endif
        }

        /// Big instrument readout (TTFT, tok/s) — the numbers ARE the demo.
        static let statValue = Font.system(size: 26, weight: .semibold, design: .monospaced)
        /// Mid-size readout for table rows.
        static let statValueSmall = Font.system(size: 17, weight: .semibold, design: .monospaced)
        /// Unit trailing a readout ("ms", "tok/s").
        static let statUnit = Font.system(size: 12, weight: .semibold, design: .monospaced)
        /// Uppercase eyebrow / stat label.
        static let label = Font.caption2.weight(.semibold)
    }
}

/// Uppercase eyebrow that opens every card — one voice for section labels.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Typo.label)
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Instrument-style readout: uppercase label above a large monospaced value.
/// The value keeps its box while it counts up (`numericText`), so live races
/// read like a dashboard, not a reflowing paragraph.
struct InstrumentStat: View {
    let label: String
    let value: String
    var unit: String?
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if highlighted {
                    Image(systemName: "laurel.leading")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
                Text(label)
                    .font(DS.Typo.label)
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(DS.Typo.statValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(highlighted ? AnyShapeStyle(DS.accent) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(DS.Typo.statUnit)
                        .fixedSize()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Small breathing dot — the "this lane is live" indicator.
struct PulsingDot: View {
    var color: Color = DS.accent

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .phaseAnimator([0.35, 1.0]) { view, phase in
                view.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.7)
            }
    }
}
