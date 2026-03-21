import SeleneShared
import SwiftUI
import AppKit
import Combine

/// Manages an NSStatusItem with a crystalline crescent moon icon.
///
/// Renders the icon directly to NSImage via Core Graphics for reliable
/// menu bar animation. The crescent moon shimmers with a traveling highlight
/// and orbiting sparkle points. Animation intensifies when Ollama is processing.
@MainActor
final class CrystalStatusItem {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var animationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let scheduler: WorkflowScheduler
    private let iconSize: CGFloat = 18

    // MARK: - Init

    init(scheduler: WorkflowScheduler) {
        self.scheduler = scheduler
    }

    // MARK: - Setup

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        updateIcon()
        startAnimation()

        scheduler.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.schedulerDidChange() }
            }
            .store(in: &cancellables)
    }

    func uninstall() {
        stopAnimation()
        cancellables.removeAll()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        popover = nil
    }

    // MARK: - State

    private var currentState: CrystalIconState = .idle

    private func schedulerDidChange() {
        let newState = CrystalIconState.from(
            isOllamaActive: scheduler.isOllamaActive,
            hasError: scheduler.lastError != nil
        )
        if newState != currentState {
            currentState = newState
            startAnimation()
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        stopAnimation()
        updateIcon()
        guard currentState.isAnimating else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateIcon()
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        button.image = CrystalMoonRenderer.render(
            state: currentState,
            size: iconSize,
            time: Date().timeIntervalSinceReferenceDate
        )
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarStatusView()
                .environmentObject(scheduler)
        )
        self.popover = popover

        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

// MARK: - CrystalMoonRenderer

/// Renders a crystalline crescent moon icon using Core Graphics.
/// The crescent has faceted internal lines and animated shimmer/sparkle effects.
enum CrystalMoonRenderer {

    /// Pale gold base color for the crescent moon.
    private static let moonColor = NSColor(red: 1.0, green: 0.88, blue: 0.55, alpha: 1.0)

    static func render(state: CrystalIconState, size: CGFloat, time: Double) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelSize = NSSize(width: size * scale, height: size * scale)

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!)

        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // lockFocus already handles point-to-pixel scaling via the bitmap rep
        let w = size
        let h = size
        let cx = w / 2
        let cy = h / 2

        // Crescent moon geometry
        let moonRadius = w * 0.4
        let moonCenterX = cx - w * 0.02
        let moonCenterY = cy
        let cutoutOffsetX = moonRadius * 0.55
        let cutoutRadius = moonRadius * 0.82

        if state.isAnimating {
            // -- Animated crescent with shimmer --
            let pulse = (sin(time * 1.8) + 1) / 2
            let baseAlpha = 0.5 + pulse * 0.3
            drawCrescent(ctx: ctx, cx: moonCenterX, cy: moonCenterY,
                         moonRadius: moonRadius, cutoutOffsetX: cutoutOffsetX,
                         cutoutRadius: cutoutRadius,
                         color: moonColor.withAlphaComponent(baseAlpha))

            // Traveling highlight
            let highlightY = moonCenterY + sin(time * 2.0) * moonRadius * 0.6
            let highlightRadius = moonRadius * 0.3
            let highlightAlpha = 0.3 + pulse * 0.3

            ctx.saveGState()
            addCrescentClip(ctx: ctx, cx: moonCenterX, cy: moonCenterY,
                            moonRadius: moonRadius, cutoutOffsetX: cutoutOffsetX,
                            cutoutRadius: cutoutRadius)
            let highlightRect = CGRect(
                x: moonCenterX - highlightRadius,
                y: highlightY - highlightRadius,
                width: highlightRadius * 2,
                height: highlightRadius * 2
            )
            ctx.setFillColor(NSColor.white.withAlphaComponent(highlightAlpha).cgColor)
            ctx.fillEllipse(in: highlightRect)
            ctx.restoreGState()

            // Facet lines
            drawFacetLines(ctx: ctx, cx: moonCenterX, cy: moonCenterY,
                           moonRadius: moonRadius, cutoutOffsetX: cutoutOffsetX,
                           cutoutRadius: cutoutRadius, size: size)

            // Sparkle diamonds
            drawSparkles(ctx: ctx, cx: cx, cy: cy, w: w, h: h,
                         time: time, moonRadius: moonRadius)
        } else {
            // -- Static crescent when idle --
            drawCrescent(ctx: ctx, cx: moonCenterX, cy: moonCenterY,
                         moonRadius: moonRadius, cutoutOffsetX: cutoutOffsetX,
                         cutoutRadius: cutoutRadius,
                         color: moonColor.withAlphaComponent(0.6))
        }

        // -- Error badge --
        if state.showsErrorBadge {
            let badgeD: CGFloat = max(4, size / 4)
            ctx.setFillColor(NSColor.red.cgColor)
            ctx.fillEllipse(in: CGRect(x: w - badgeD, y: 0, width: badgeD, height: badgeD))
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Crescent Shape

    private static func drawCrescent(ctx: CGContext, cx: CGFloat, cy: CGFloat,
                                     moonRadius: CGFloat, cutoutOffsetX: CGFloat,
                                     cutoutRadius: CGFloat, color: NSColor) {
        let moonRect = CGRect(x: cx - moonRadius, y: cy - moonRadius,
                              width: moonRadius * 2, height: moonRadius * 2)
        let cutoutRect = CGRect(x: cx - cutoutRadius + cutoutOffsetX,
                                y: cy - cutoutRadius,
                                width: cutoutRadius * 2, height: cutoutRadius * 2)
        // Draw the full moon
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: moonRect)
        // Erase the cutout by clipping to it and clearing
        ctx.addEllipse(in: cutoutRect)
        ctx.clip()
        ctx.clear(cutoutRect)
        ctx.restoreGState()
    }

    private static func addCrescentClip(ctx: CGContext, cx: CGFloat, cy: CGFloat,
                                        moonRadius: CGFloat, cutoutOffsetX: CGFloat,
                                        cutoutRadius: CGFloat) {
        let moonRect = CGRect(x: cx - moonRadius, y: cy - moonRadius,
                              width: moonRadius * 2, height: moonRadius * 2)
        let cutoutRect = CGRect(x: cx - cutoutRadius + cutoutOffsetX,
                                y: cy - cutoutRadius,
                                width: cutoutRadius * 2, height: cutoutRadius * 2)
        // Clip to moon circle
        ctx.addEllipse(in: moonRect)
        ctx.clip()
        // Exclude cutout: large rect + cutout ellipse with even-odd = everything except cutout
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: moonRadius * 10, height: moonRadius * 10))
        path.addEllipse(in: cutoutRect)
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
    }

    // MARK: - Facet Lines

    private static func drawFacetLines(ctx: CGContext, cx: CGFloat, cy: CGFloat,
                                       moonRadius: CGFloat, cutoutOffsetX: CGFloat,
                                       cutoutRadius: CGFloat, size: CGFloat) {
        ctx.saveGState()
        addCrescentClip(ctx: ctx, cx: cx, cy: cy, moonRadius: moonRadius,
                        cutoutOffsetX: cutoutOffsetX, cutoutRadius: cutoutRadius)

        ctx.setStrokeColor(moonColor.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(max(0.5, size / 36))

        // Horizontal facet
        ctx.move(to: CGPoint(x: cx - moonRadius, y: cy))
        ctx.addLine(to: CGPoint(x: cx + moonRadius, y: cy))
        ctx.strokePath()

        // Diagonal facets from top
        let topY = cy - moonRadius * 0.75
        ctx.move(to: CGPoint(x: cx - moonRadius * 0.3, y: topY))
        ctx.addLine(to: CGPoint(x: cx - moonRadius * 0.6, y: cy + moonRadius * 0.4))
        ctx.strokePath()

        // Diagonal facets from bottom
        let bottomY = cy + moonRadius * 0.75
        ctx.move(to: CGPoint(x: cx - moonRadius * 0.3, y: bottomY))
        ctx.addLine(to: CGPoint(x: cx - moonRadius * 0.6, y: cy - moonRadius * 0.4))
        ctx.strokePath()

        ctx.restoreGState()
    }

    // MARK: - Sparkles

    private static func drawSparkles(ctx: CGContext, cx: CGFloat, cy: CGFloat,
                                     w: CGFloat, h: CGFloat, time: Double,
                                     moonRadius: CGFloat) {
        let count = 4
        let sparkleSize = max(1.2, w / 14)
        let orbitRadius = moonRadius * 1.15

        for i in 0..<count {
            let phase = Double(i) / Double(count) * 2 * .pi
            let speed = 1.5 + Double(i) * 0.2
            let angle = time * speed + phase

            let sx = cx + CGFloat(cos(angle)) * orbitRadius * 0.9
            let sy = cy + CGFloat(sin(angle)) * orbitRadius

            let twinkle = CGFloat((sin(time * 4.0 + phase * 2.3) + 1) / 2)
            let alpha = 0.5 + twinkle * 0.5

            guard sx > 0 && sx < w && sy > 0 && sy < h else { continue }

            ctx.saveGState()
            ctx.setFillColor(moonColor.withAlphaComponent(alpha).cgColor)
            ctx.move(to: CGPoint(x: sx, y: sy - sparkleSize))
            ctx.addLine(to: CGPoint(x: sx + sparkleSize * 0.5, y: sy))
            ctx.addLine(to: CGPoint(x: sx, y: sy + sparkleSize))
            ctx.addLine(to: CGPoint(x: sx - sparkleSize * 0.5, y: sy))
            ctx.closePath()
            ctx.fillPath()
            ctx.restoreGState()
        }
    }
}
