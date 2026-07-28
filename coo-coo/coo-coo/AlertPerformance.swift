import AppKit
import SwiftUI

// A separate, non-interactive, card-less character panel that performs a
// short burst of motion when Claude starts waiting, then fades out. It never
// touches the pinned floating widget (FloatingWidgetView/floatingPanel in
// AppDelegate) — that stays exactly where the user put it. Each character has
// its own gait matching its personality (see the per-character MARKs below)
// rather than one generic walk reused for all six — some persist until the
// user moves the mouse (Dog, Duck, Pigeon — "won't stop till you notice" /
// "watchful"), others are finite performances that do their thing and leave
// (Cat, Frog, Raccoon — aloof/zen/chaotic personalities that don't linger).
final class AlertPerformanceController {
    private var panel: NSPanel?
    private var characterView: NSView?
    private var shadowView: NSView?
    private var mouseMonitor: Any?
    private let size = NSSize(width: 70, height: 70)

    // Bumped on every perform()/cancel() so in-flight animation completion
    // chains from a superseded or cancelled performance can recognize
    // they're stale and stop recursing instead of animating a dead panel.
    private var token = 0

    func perform(style: String, character: CharacterID) {
        guard panel == nil, style == "walk" else { return }
        token += 1
        let myToken = token

        let (newPanel, charView, shadow) = makePanel(character: character)
        panel = newPanel
        characterView = charView
        shadowView = shadow
        newPanel.orderFront(nil)

        switch style {
        case "walk":
            switch character {
            // Dog and Duck keep going until the user moves the mouse, rather
            // than a fixed number of steps — "won't stop till you notice"
            // fits both. Pigeon (the flagship/default) gets its own
            // stop-and-peck rhythm but is also persistent — "watchful."
            case .dog:
                startMouseMonitor(token: myToken)
                performDirectionalGait(panel: newPanel, token: myToken, stepRange: 50...100, bobUp: 6, bobDown: -4, durationRange: 0.6...1.0)
            case .duck:
                startMouseMonitor(token: myToken)
                performDirectionalGait(panel: newPanel, token: myToken, stepRange: 60...110, bobUp: 12, bobDown: -10, durationRange: 0.5...0.8)
            case .pigeon:
                startMouseMonitor(token: myToken)
                performPigeonPeckWalk(panel: newPanel, token: myToken)
            // Cat, Frog, and Raccoon are finite performances — aloof/zen/
            // chaotic personalities that do their thing and leave, rather
            // than lingering for acknowledgment.
            case .cat: performCatProwl(panel: newPanel, token: myToken, cyclesRemaining: 4)
            case .frog: performFrogLeap(panel: newPanel, token: myToken, leapsRemaining: 3)
            case .raccoon: performRaccoonDart(panel: newPanel, token: myToken, dartsRemaining: 6)
            }
        default: finish(panel: newPanel, token: myToken)
        }
    }

    func cancel() {
        token += 1 // invalidates any in-flight completion chain
        stopMouseMonitor()
        guard let panel else { return }
        self.panel = nil
        characterView = nil
        shadowView = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - Panel setup
    //
    // The panel's content is two sibling layers, not one — a character view
    // and a separate ground shadow beneath it — so a step's squash-and-stretch
    // can animate the character while the shadow pulses independently
    // underneath it, instead of scaling as one rigid unit.

    private func makePanel(character: CharacterID) -> (NSPanel, NSView, NSView) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true // purely decorative — never fights the user for clicks
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: size))

        let shadow = NSView(frame: NSRect(x: size.width / 2 - 16, y: 6, width: 32, height: 9))
        shadow.wantsLayer = true
        shadow.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        shadow.layer?.cornerRadius = shadow.frame.height / 2
        container.addSubview(shadow)

        let hostingView = NSHostingView(rootView: CharacterView(character: character, state: .waiting))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true
        container.addSubview(hostingView)

        panel.contentView = container
        return (panel, hostingView, shadow)
    }

    private func finish(panel: NSPanel, token: Int) {
        guard token == self.token else { return } // superseded/cancelled — a newer call already handled cleanup
        stopMouseMonitor()
        self.panel = nil
        characterView = nil
        shadowView = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - Mouse-movement stop condition (Dog, Duck, Pigeon)

    private func startMouseMonitor(token: Int) {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self, token == self.token, let panel = self.panel else { return }
            self.finish(panel: panel, token: token)
        }
    }

    private func stopMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }

    // Squash-and-stretch on the character, with the shadow pulsing the
    // opposite way underneath it (shrinks/lightens as the character
    // stretches "up" mid-stride, grows back as it settles) — classic
    // animation weight cues, applied at the start of each step/drop.
    private func animateStep(duration: Double) {
        guard let charLayer = characterView?.layer, let shadowLayer = shadowView?.layer else { return }

        let squash = NSValue(caTransform3D: CATransform3DMakeScale(1.12, 0.88, 1))
        let stretch = NSValue(caTransform3D: CATransform3DMakeScale(0.93, 1.1, 1))
        let identity = NSValue(caTransform3D: CATransform3DIdentity)
        let timing = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeIn),
        ]

        let charAnim = CAKeyframeAnimation(keyPath: "transform")
        charAnim.values = [identity, squash, stretch, identity]
        charAnim.keyTimes = [0, 0.12, 0.55, 1]
        charAnim.duration = duration
        charAnim.timingFunctions = timing
        charLayer.add(charAnim, forKey: "squashStretch")

        let shadowAnim = CAKeyframeAnimation(keyPath: "transform")
        shadowAnim.values = [
            identity,
            NSValue(caTransform3D: CATransform3DMakeScale(0.7, 0.7, 1)),
            NSValue(caTransform3D: CATransform3DMakeScale(0.8, 0.8, 1)),
            identity,
        ]
        shadowAnim.keyTimes = [0, 0.12, 0.55, 1]
        shadowAnim.duration = duration
        shadowAnim.timingFunctions = timing
        shadowLayer.add(shadowAnim, forKey: "shadowPulse")
    }

    // MARK: - Directional gait: small uneven steps in one direction, bob
    // alternating up/down each step. Shared shape for Dog/Duck (both persist
    // until the mouse moves — startMouseMonitor); tuned per character via
    // stepRange/bob magnitude/duration so a lurch and a waddle don't feel
    // the same even though the underlying motion is the same code.

    private func performDirectionalGait(
        panel: NSPanel, token: Int,
        stepRange: ClosedRange<CGFloat>, bobUp: CGFloat, bobDown: CGFloat, durationRange: ClosedRange<Double>,
        baseY: CGFloat? = nil, goingUp: Bool = true
    ) {
        guard token == self.token else { return }
        guard let screen = panel.screen ?? NSScreen.main else {
            finish(panel: panel, token: token)
            return
        }
        let visible = screen.visibleFrame
        let y = baseY ?? (visible.minY + 40)
        if panel.frame.origin == .zero {
            panel.setFrameOrigin(NSPoint(x: visible.minX + 20, y: y))
        }
        let maxX = visible.maxX - size.width
        guard panel.frame.origin.x < maxX else {
            finish(panel: panel, token: token)
            return
        }

        let stepDistance = CGFloat.random(in: stepRange)
        let nextX = min(panel.frame.origin.x + stepDistance, maxX)
        let bob: CGFloat = goingUp ? bobUp : bobDown
        let duration = Double.random(in: durationRange)
        let target = NSRect(x: nextX, y: y + bob, width: size.width, height: size.height)

        animateStep(duration: duration)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.performDirectionalGait(panel: panel, token: token, stepRange: stepRange, bobUp: bobUp, bobDown: bobDown, durationRange: durationRange, baseY: y, goingUp: !goingUp)
        })
    }

    // MARK: - Pigeon: short pecking steps with a "watch" pause between each
    // — also persists until the mouse moves (watchful, the flagship default).

    private func performPigeonPeckWalk(panel: NSPanel, token: Int, baseY: CGFloat? = nil) {
        guard token == self.token else { return }
        guard let screen = panel.screen ?? NSScreen.main else {
            finish(panel: panel, token: token)
            return
        }
        let visible = screen.visibleFrame
        let y = baseY ?? (visible.minY + 40)
        if panel.frame.origin == .zero {
            panel.setFrameOrigin(NSPoint(x: visible.minX + 20, y: y))
        }
        let maxX = visible.maxX - size.width
        guard panel.frame.origin.x < maxX else {
            finish(panel: panel, token: token)
            return
        }

        let nextX = min(panel.frame.origin.x + CGFloat.random(in: 20...35), maxX)
        let duration = 0.3
        let target = NSRect(x: nextX, y: y, width: size.width, height: size.height)

        animateStep(duration: duration)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, token == self.token else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.6...1.1)) { [weak self] in
                self?.performPigeonPeckWalk(panel: panel, token: token, baseY: y)
            }
        })
    }

    // MARK: - Cat: prowl a short distance, pause to "judge," repeat a few
    // times, then leave — aloof, unhurried, doesn't linger for attention.

    private func performCatProwl(panel: NSPanel, token: Int, cyclesRemaining: Int, baseY: CGFloat? = nil) {
        guard token == self.token else { return }
        guard cyclesRemaining > 0, let screen = panel.screen ?? NSScreen.main else {
            finish(panel: panel, token: token)
            return
        }
        let visible = screen.visibleFrame
        let y = baseY ?? (visible.minY + 40)
        if panel.frame.origin == .zero {
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: y))
        }
        let nextX = min(max(panel.frame.origin.x + CGFloat.random(in: 30...60), visible.minX), visible.maxX - size.width)
        let duration = 0.6
        let target = NSRect(x: nextX, y: y, width: size.width, height: size.height)

        animateStep(duration: duration)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, token == self.token else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.0...1.8)) { [weak self] in
                self?.performCatProwl(panel: panel, token: token, cyclesRemaining: cyclesRemaining - 1, baseY: y)
            }
        })
    }

    // MARK: - Frog: a few big, unhurried leaps to random spots, resting
    // between each — chill, zen, sees the work as it is.

    private func performFrogLeap(panel: NSPanel, token: Int, leapsRemaining: Int) {
        guard token == self.token else { return }
        guard leapsRemaining > 0, let screen = panel.screen ?? NSScreen.main else {
            finish(panel: panel, token: token)
            return
        }
        let visible = screen.visibleFrame
        if panel.frame.origin == .zero {
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 40))
        }
        let minX = visible.minX
        let maxX = visible.maxX - size.width
        guard maxX > minX else {
            finish(panel: panel, token: token)
            return
        }
        let targetX = CGFloat.random(in: minX...maxX)
        let duration = 0.5
        let target = NSRect(x: targetX, y: panel.frame.origin.y, width: size.width, height: size.height)

        animateStep(duration: duration)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, token == self.token else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.5...2.5)) { [weak self] in
                self?.performFrogLeap(panel: panel, token: token, leapsRemaining: leapsRemaining - 1)
            }
        })
    }

    // MARK: - Raccoon: rapid, short, unpredictable-direction darts, then
    // vanishes in a flash — chaos energy, gone as quick as it showed up.

    private func performRaccoonDart(panel: NSPanel, token: Int, dartsRemaining: Int) {
        guard token == self.token else { return }
        guard dartsRemaining > 0, let screen = panel.screen ?? NSScreen.main else {
            finish(panel: panel, token: token)
            return
        }
        let visible = screen.visibleFrame
        if panel.frame.origin == .zero {
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 40))
        }
        let minX = visible.minX
        let maxX = visible.maxX - size.width
        let nextX = min(max(panel.frame.origin.x + CGFloat.random(in: -50...50), minX), maxX)
        let duration = Double.random(in: 0.15...0.3)
        let target = NSRect(x: nextX, y: panel.frame.origin.y, width: size.width, height: size.height)

        animateStep(duration: duration)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.performRaccoonDart(panel: panel, token: token, dartsRemaining: dartsRemaining - 1)
        })
    }

}
