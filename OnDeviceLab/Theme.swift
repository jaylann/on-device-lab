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
