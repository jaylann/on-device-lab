import SwiftUI

// Flat, hairline-separated design layer tuned for macOS. Solid surfaces with
// 0.5pt separators; glass appears only as an accent on the circular primary
// action button (`accentGlass`).

enum DS {
    static let accent = Color.accentColor

    #if os(macOS)
    /// Charcoal canvas in dark mode (a notch below the system window gray);
    /// standard window background in light mode.
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.086, green: 0.086, blue: 0.094, alpha: 1)
            : .windowBackgroundColor
    })
    /// Panel surface, slightly raised off the window background.
    static let panelBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.125, green: 0.125, blue: 0.137, alpha: 1)
            : .textBackgroundColor
    })
    static let hairline = Color(nsColor: .separatorColor)
    #else
    static let background = Color(uiColor: .systemBackground)
    static let panelBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let hairline = Color(uiColor: .separator)
    #endif

    static let hairlineWidth: CGFloat = 0.5

    /// Every interactive control (model trigger, Load, send) shares one height
    /// so a row of them reads as a single bar. 32 matches macOS control scale;
    /// iOS keeps the 44pt touch-target floor.
    static let controlHeight: CGFloat = {
        #if os(macOS)
        32
        #else
        44
        #endif
    }()

    enum Radius {
        static let card: CGFloat = 28
        static let tile: CGFloat = 24
        static let control: CGFloat = 22
        static let chip: CGFloat = 12
    }

    enum Space {
        static let gutter: CGFloat = 16
        static let section: CGFloat = 16
        static let row: CGFloat = 10
    }
}

// MARK: - Screen background

extension View {
    /// The one background every screen uses: the flat window background. On
    /// macOS the window-toolbar background is hidden so the same gray runs
    /// under the title bar on every tab.
    @ViewBuilder
    func labScreenBackground() -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            background(DS.background.ignoresSafeArea())
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            background(DS.background.ignoresSafeArea())
        }
        #else
        background(DS.background.ignoresSafeArea())
        #endif
    }
}

// MARK: - Panel surface

/// The single flat surface shared by every card, metric cell, control and
/// composer in the app: solid panel fill with a hairline border, so they all
/// read as the same material. An optional fixed `height` stops cells from
/// resizing as their content changes (a metric reading "—" and one reading
/// "412 ms" occupy the same box). A `tint` swaps in a faint tinted fill and
/// tinted hairline; `prominent` fills solid accent for the primary action.
struct Panel: ViewModifier {
    var radius: CGFloat = DS.Radius.tile
    var height: CGFloat?
    var tint: Color?
    var prominent = false
    var capsule = false

    func body(content: Content) -> some View {
        let shape: AnyShape = capsule
            ? AnyShape(Capsule(style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        let framed = content.frame(height: height)
        if prominent {
            framed.background(tint ?? DS.accent, in: shape)
        } else {
            framed
                .background(tint.map { $0.opacity(0.08) } ?? DS.panelBackground, in: shape)
                .overlay(shape.stroke(tint?.opacity(0.35) ?? DS.hairline, lineWidth: DS.hairlineWidth))
        }
    }
}

extension View {
    /// Flat panel surface. Provide `height` for fixed-size cells; omit it
    /// for content that should size to fit (the output card).
    func panel(radius: CGFloat = DS.Radius.tile, height: CGFloat? = nil, tint: Color? = nil) -> some View {
        modifier(Panel(radius: radius, height: height, tint: tint))
    }

    /// Fully-rounded flat capsule for pill controls and cells.
    /// `prominent` fills solid accent (pair with white foreground).
    func pill(height: CGFloat? = nil, tint: Color? = nil, prominent: Bool = false) -> some View {
        modifier(Panel(height: height, tint: tint, prominent: prominent, capsule: true))
    }
}

// MARK: - Glass accent

/// Glass survives in exactly one region: the composer bar. The accent-tinted
/// primary action button gets real glass on OS 26+, solid accent everywhere
/// else (older OS or Reduce Transparency) — the fallback is indistinguishable
/// from flat.
private struct AccentGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if !reduceTransparency, #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(DS.accent), in: shape)
        } else {
            content.background(DS.accent, in: shape)
        }
    }
}

/// Untinted glass for the composer field and its secondary controls.
/// Material + hairline fallback below OS 26 / under Reduce Transparency.
private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if !reduceTransparency, #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(DS.hairline, lineWidth: DS.hairlineWidth))
        }
    }
}

extension View {
    func accentGlass(in shape: some Shape) -> some View {
        modifier(AccentGlass(shape: shape))
    }

    func glass(in shape: some Shape) -> some View {
        modifier(GlassSurface(shape: shape))
    }
}

// MARK: - Hairline

/// 0.5pt separator line — the section divider of the flat layout.
struct Hairline: View {
    var vertical = false

    var body: some View {
        if vertical {
            DS.hairline.frame(width: DS.hairlineWidth)
        } else {
            DS.hairline.frame(height: DS.hairlineWidth)
        }
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
                if highlighted {
                    Image(systemName: "laurel.trailing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
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
