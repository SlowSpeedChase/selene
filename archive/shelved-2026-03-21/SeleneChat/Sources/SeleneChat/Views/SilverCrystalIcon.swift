import SeleneShared
import SwiftUI

// MARK: - CrystalIconState

/// Represents the current state of the Silver Crystal menu bar icon.
/// Maps from scheduler state to visual appearance.
enum CrystalIconState: Equatable {
    case idle
    case processing
    case error

    var isAnimating: Bool { self == .processing }
    var showsErrorBadge: Bool { self == .error }

    /// Derive icon state from scheduler properties.
    /// Processing takes priority over error (if Ollama is active, show that).
    static func from(isOllamaActive: Bool, hasError: Bool) -> CrystalIconState {
        if isOllamaActive { return .processing }
        if hasError { return .error }
        return .idle
    }
}

// MARK: - SilverCrystalIcon

/// A Sailor Moon Silver Crystal (Ginzuishou) inspired menu bar icon.
///
/// Three visual states:
/// - **idle**: Static crystal outline with crescent moon silhouette
/// - **processing**: Crystal with pulsing inner glow and orbiting sparkle particles
/// - **error**: Static crystal with small red dot badge in upper-right corner
///
/// Uses `.primary` color throughout so it works as a template image,
/// adapting to both light and dark menu bar appearances.
struct SilverCrystalIcon: View {
    let state: CrystalIconState
    var size: CGFloat = 18

    var body: some View {
        if state.isAnimating {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                crystalCanvas(date: timeline.date)
            }
            .frame(width: size, height: size)
        } else {
            crystalCanvas(date: Date())
                .frame(width: size, height: size)
        }
    }

    // MARK: - Canvas Drawing

    private func crystalCanvas(date: Date) -> some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let cy = h / 2

            // Animation time (seconds since reference)
            let t = state.isAnimating ? date.timeIntervalSinceReferenceDate : 0

            // Draw inner glow when processing
            if state.isAnimating {
                drawInnerGlow(context: context, cx: cx, cy: cy, w: w, h: h, t: t)
            }

            // Draw the crystal body
            drawCrystal(context: context, cx: cx, cy: cy, w: w, h: h)

            // Draw facet lines inside the crystal
            drawFacetLines(context: context, cx: cx, cy: cy, w: w, h: h)

            // Draw crescent moon inside the crystal
            drawCrescentMoon(context: context, cx: cx, cy: cy, w: w, h: h)

            // Draw sparkle particles when processing
            if state.isAnimating {
                drawSparkles(context: context, cx: cx, cy: cy, w: w, h: h, t: t)
            }

            // Draw error badge
            if state.showsErrorBadge {
                drawErrorBadge(context: context, w: w, h: h)
            }
        }
    }

    // MARK: - Crystal Shape

    /// The main crystal outline: a faceted diamond/octagonal form.
    /// Vertically elongated with a pointed top and bottom,
    /// wider facets on the sides.
    private func crystalPath(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) -> Path {
        var path = Path()

        // Crystal proportions relative to frame
        let topY = h * 0.05
        let upperY = h * 0.28
        let midY = h * 0.45
        let lowerY = h * 0.72
        let bottomY = h * 0.95

        let narrowX = w * 0.15
        let wideX = w * 0.08

        // Top point
        path.move(to: CGPoint(x: cx, y: topY))

        // Upper-right facet
        path.addLine(to: CGPoint(x: cx + narrowX * 1.2, y: upperY))

        // Right wide point
        path.addLine(to: CGPoint(x: w - wideX, y: midY))

        // Lower-right facet
        path.addLine(to: CGPoint(x: cx + narrowX, y: lowerY))

        // Bottom point
        path.addLine(to: CGPoint(x: cx, y: bottomY))

        // Lower-left facet
        path.addLine(to: CGPoint(x: cx - narrowX, y: lowerY))

        // Left wide point
        path.addLine(to: CGPoint(x: wideX, y: midY))

        // Upper-left facet
        path.addLine(to: CGPoint(x: cx - narrowX * 1.2, y: upperY))

        path.closeSubpath()

        return path
    }

    private func drawCrystal(context: GraphicsContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        let path = crystalPath(cx: cx, cy: cy, w: w, h: h)

        // Stroke the crystal outline
        context.stroke(
            path,
            with: .color(.primary),
            lineWidth: max(1, size / 18)
        )
    }

    // MARK: - Facet Lines

    /// Internal facet lines that give the crystal its cut-gem appearance.
    private func drawFacetLines(context: GraphicsContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        let lineWidth = max(0.5, size / 36)
        let topY = h * 0.05
        let upperY = h * 0.28
        let midY = h * 0.45
        let lowerY = h * 0.72
        let bottomY = h * 0.95
        let wideX = w * 0.08

        var facets = Path()

        // Horizontal facet line across the widest point
        facets.move(to: CGPoint(x: wideX, y: midY))
        facets.addLine(to: CGPoint(x: w - wideX, y: midY))

        // Top point to left-wide
        facets.move(to: CGPoint(x: cx, y: topY))
        facets.addLine(to: CGPoint(x: wideX, y: midY))

        // Top point to right-wide
        facets.move(to: CGPoint(x: cx, y: topY))
        facets.addLine(to: CGPoint(x: w - wideX, y: midY))

        // Bottom point to left-wide
        facets.move(to: CGPoint(x: cx, y: bottomY))
        facets.addLine(to: CGPoint(x: wideX, y: midY))

        // Bottom point to right-wide
        facets.move(to: CGPoint(x: cx, y: bottomY))
        facets.addLine(to: CGPoint(x: w - wideX, y: midY))

        // Center vertical line (top to bottom through crystal)
        facets.move(to: CGPoint(x: cx, y: upperY))
        facets.addLine(to: CGPoint(x: cx, y: lowerY))

        let opacity: Double = 0.4
        context.stroke(
            facets,
            with: .color(.primary.opacity(opacity)),
            lineWidth: lineWidth
        )
    }

    // MARK: - Crescent Moon

    /// A small crescent moon silhouette centered in the crystal.
    private func drawCrescentMoon(context: GraphicsContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        let moonCenterX = cx
        let moonCenterY = h * 0.44
        let moonRadius = w * 0.13

        // Full circle for the moon
        let moonCircle = Path(ellipseIn: CGRect(
            x: moonCenterX - moonRadius,
            y: moonCenterY - moonRadius,
            width: moonRadius * 2,
            height: moonRadius * 2
        ))

        // Offset circle to create crescent cutout
        let cutoutOffsetX = moonRadius * 0.7
        let cutoutRadius = moonRadius * 0.85
        let cutoutCircle = Path(ellipseIn: CGRect(
            x: moonCenterX - cutoutRadius + cutoutOffsetX,
            y: moonCenterY - cutoutRadius,
            width: cutoutRadius * 2,
            height: cutoutRadius * 2
        ))

        // Draw the moon then subtract the cutout using even-odd fill
        var crescentPath = Path()
        crescentPath.addPath(moonCircle)
        crescentPath.addPath(cutoutCircle)

        context.fill(
            crescentPath,
            with: .color(.primary.opacity(0.7)),
            style: FillStyle(eoFill: true)
        )
    }

    // MARK: - Inner Glow (Processing)

    /// Pulsing fill inside the crystal body when processing.
    private func drawInnerGlow(context: GraphicsContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, t: Double) {
        let path = crystalPath(cx: cx, cy: cy, w: w, h: h)

        // Gentle pulse: oscillate opacity between 0.08 and 0.25
        let pulse = (sin(t * 2.5) + 1) / 2  // 0..1
        let opacity = 0.08 + pulse * 0.17

        context.fill(
            path,
            with: .color(.primary.opacity(opacity))
        )
    }

    // MARK: - Sparkle Particles (Processing)

    /// Small diamond shapes that orbit and twinkle around the crystal facets.
    private func drawSparkles(context: GraphicsContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, t: Double) {
        let sparkleCount = 5
        let orbitRadius = w * 0.42
        let sparkleSize = max(1.5, size / 12)

        for i in 0..<sparkleCount {
            let phase = Double(i) / Double(sparkleCount) * 2 * .pi
            let speed = 1.2 + Double(i) * 0.15
            let angle = t * speed + phase

            // Orbit position around the crystal center
            let sx = cx + cos(angle) * orbitRadius * (0.8 + 0.2 * sin(angle * 1.7))
            let sy = cy + sin(angle) * orbitRadius * 0.85

            // Twinkle: each sparkle fades in and out independently
            let twinkle = (sin(t * 3.5 + phase * 2.3) + 1) / 2
            let opacity = 0.3 + twinkle * 0.7

            // Only draw if within a reasonable frame
            guard sx > -sparkleSize && sx < w + sparkleSize &&
                  sy > -sparkleSize && sy < h + sparkleSize else {
                continue
            }

            // Draw diamond-shaped sparkle
            var diamond = Path()
            diamond.move(to: CGPoint(x: sx, y: sy - sparkleSize))
            diamond.addLine(to: CGPoint(x: sx + sparkleSize * 0.5, y: sy))
            diamond.addLine(to: CGPoint(x: sx, y: sy + sparkleSize))
            diamond.addLine(to: CGPoint(x: sx - sparkleSize * 0.5, y: sy))
            diamond.closeSubpath()

            context.fill(
                diamond,
                with: .color(.primary.opacity(opacity))
            )
        }
    }

    // MARK: - Error Badge

    /// Small red circle in the upper-right corner of the icon.
    private func drawErrorBadge(context: GraphicsContext, w: CGFloat, h: CGFloat) {
        let badgeRadius = max(2, size / 7)
        let badgeX = w - badgeRadius * 0.6
        let badgeY = badgeRadius * 0.6

        let badge = Path(ellipseIn: CGRect(
            x: badgeX - badgeRadius,
            y: badgeY - badgeRadius,
            width: badgeRadius * 2,
            height: badgeRadius * 2
        ))

        context.fill(badge, with: .color(.red))
    }
}

// MARK: - Preview

#if DEBUG
struct SilverCrystalIconPreview: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 24) {
            VStack {
                SilverCrystalIcon(state: .idle, size: 44)
                Text("Idle").font(.caption)
            }
            VStack {
                SilverCrystalIcon(state: .processing, size: 44)
                Text("Processing").font(.caption)
            }
            VStack {
                SilverCrystalIcon(state: .error, size: 44)
                Text("Error").font(.caption)
            }
        }
        .padding(32)
        .previewDisplayName("Silver Crystal - All States (44pt)")
    }
}
#endif
