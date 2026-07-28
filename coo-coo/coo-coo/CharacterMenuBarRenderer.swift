import SwiftUI

// Renders a simplified animated character into a GraphicsContext at 22×22px.
// Called from Canvas { } inside ImageRenderer so Date() gives the real frame time.
enum CharacterMenuBarRenderer {

    static func render(ctx: GraphicsContext, size: CGSize, character: CharacterID, state: CompanionState, t: Double) {
        let s = size.width / 22

        func el(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (cx - rx) * s, y: (cy - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
        }
        func osc(_ period: Double, _ range: Double) -> CGFloat { CGFloat(sin(2 * .pi * t / period) * range) }
        func pulse(_ period: Double, _ range: Double) -> CGFloat { CGFloat((1 - cos(2 * .pi * t / period)) / 2 * range) }

        let colors = character.menuBarColors

        // Untransformed copy, used at the end for a fixed-position state accent
        // dot that shouldn't inherit the whole-body wobble below.
        let baseCtx = ctx

        // Whole-body transform
        var ctx = ctx
        switch state {
        case .waiting:
            let angle = osc(0.35, 14 * .pi / 180)
            let cx = size.width / 2, cy = size.height * 0.6
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(.init(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        case .idle:
            ctx.concatenate(CGAffineTransform(translationX: 0, y: -pulse(3.2, 1) * s))
        case .done:
            ctx.concatenate(CGAffineTransform(translationX: 0, y: -pulse(0.8, 2) * s))
        default: break
        }

        func fc(_ p: Path, _ c: Color, _ a: Double = 1) { ctx.fill(p, with: .color(c.opacity(a))) }

        // Shadow
        fc(el(11, 20.5, 7, 0.8), .black, 0.15)

        // Body
        fc(el(11, 14, 7, 5.5), Color(hex: colors.body))
        fc(el(11, 15, 5.5, 4), Color(hex: colors.light))

        // Head context
        var hCtx = ctx
        switch state {
        case .thinking:
            let peck = pulse(0.9, 2) * s
            hCtx.concatenate(CGAffineTransform(translationX: 0, y: peck))
        case .idle:
            let tilt = osc(6.0, 3 * .pi / 180)
            hCtx.concatenate(CGAffineTransform(translationX: -11 * s, y: -8 * s)
                .concatenating(.init(rotationAngle: tilt))
                .concatenating(CGAffineTransform(translationX: 11 * s, y: 8 * s)))
        default: break
        }
        func hfc(_ p: Path, _ c: Color, _ a: Double = 1) { hCtx.fill(p, with: .color(c.opacity(a))) }

        // Head
        hfc(el(11, 8, 5.5, 5), Color(hex: colors.body))
        hfc(el(11, 7.5, 4.5, 4), Color(hex: colors.light))

        // Eyes
        switch state {
        case .waiting:
            let pdx = osc(0.4, 1.2)
            hfc(el(8, 7, 2.8, 2.8), .white)
            hfc(el(8 + pdx, 7.5, 1.2, 1.2), .black)
            hfc(el(14, 7, 2.8, 2.8), .white)
            hfc(el(14 + pdx, 7.5, 1.2, 1.2), .black)
        case .sleepy:
            var le = Path(); le.move(to: CGPoint(x: 5.5 * s, y: 7 * s))
            le.addQuadCurve(to: CGPoint(x: 10.5 * s, y: 7 * s), control: CGPoint(x: 8 * s, y: 5 * s))
            hCtx.stroke(le, with: .color(.black), lineWidth: 0.9 * s)
            var re = Path(); re.move(to: CGPoint(x: 11.5 * s, y: 7 * s))
            re.addQuadCurve(to: CGPoint(x: 16.5 * s, y: 7 * s), control: CGPoint(x: 14 * s, y: 5 * s))
            hCtx.stroke(re, with: .color(.black), lineWidth: 0.9 * s)
        case .done:
            var le = Path(); le.move(to: CGPoint(x: 5.5 * s, y: 7.5 * s))
            le.addQuadCurve(to: CGPoint(x: 10.5 * s, y: 7.5 * s), control: CGPoint(x: 8 * s, y: 5 * s))
            hCtx.stroke(le, with: .color(.black), lineWidth: 0.9 * s)
            var re = Path(); re.move(to: CGPoint(x: 11.5 * s, y: 7.5 * s))
            re.addQuadCurve(to: CGPoint(x: 16.5 * s, y: 7.5 * s), control: CGPoint(x: 14 * s, y: 5 * s))
            hCtx.stroke(re, with: .color(.black), lineWidth: 0.9 * s)
        default:
            // Idle / thinking — simple dot eyes, periodic blink
            let blinkP = t.truncatingRemainder(dividingBy: 4.5)
            let blink: CGFloat = blinkP < 0.07 ? CGFloat(blinkP / 0.07)
                : blinkP < 0.13 ? 1
                : blinkP < 0.20 ? CGFloat((0.20 - blinkP) / 0.07) : 0
            hfc(el(8, 7, 2, 2), .white)
            hfc(el(8, 7.5, 1.0, 1.0), .black)
            if blink > 0 { hfc(el(8, 7, 2, 2 * blink), Color(hex: colors.body)) }
            hfc(el(14, 7, 2, 2), .white)
            hfc(el(14, 7.5, 1.0, 1.0), .black)
            if blink > 0 { hfc(el(14, 7, 2, 2 * blink), Color(hex: colors.body)) }
        }

        // Character-specific accent (beak for pigeon, nose for others)
        let accent = Color(hex: colors.accent)
        switch character {
        case .pigeon, .duck:
            var bk = Path()
            bk.move(to: CGPoint(x: 9 * s, y: 10 * s))
            bk.addLine(to: CGPoint(x: 14 * s, y: 11 * s))
            bk.addLine(to: CGPoint(x: 9 * s, y: 12 * s))
            bk.closeSubpath()
            hCtx.fill(bk, with: .color(accent))
        default:
            hfc(el(11, 11, 1.5, 1.5), accent)
        }

        // Waiting extras — tiny ! marks
        if state == .waiting {
            let excl = ctx.resolve(
                Text("!").font(.system(size: 7 * s, weight: .black))
                    .foregroundStyle(Color(hex: "e24b4a"))
            )
            ctx.draw(excl, at: CGPoint(x: 1.5 * s, y: 5 * s), anchor: .center)
            ctx.draw(excl, at: CGPoint(x: 20.5 * s, y: 5 * s), anchor: .center)
        }

        // Sleepy — small z
        if state == .sleepy {
            let phase = t.truncatingRemainder(dividingBy: 2.4) / 2.4
            let op = phase < 0.15 ? phase / 0.15 : (phase > 0.85 ? (1 - phase) / 0.15 : 1)
            let yOff = CGFloat(phase * 8) * s
            var zc = ctx; zc.opacity = op
            let zt = zc.resolve(Text("z").font(.system(size: 6 * s, weight: .semibold))
                .foregroundStyle(Color(hex: "7F77DD")))
            zc.draw(zt, at: CGPoint(x: 18 * s, y: (6 - yOff / s) * s), anchor: .center)
        }

        // State accent dot — fixed bottom-LEFT corner, consistent across all 5
        // states (unlike the waiting "!" / sleepy "z" extras above, which only
        // exist for two of them). A quick glance at color alone should tell you
        // the state regardless of which character is shown. Bottom-right is
        // reserved for the per-session identity dot AppDelegate draws as a
        // post-process overlay (renderIconImage) when multiple sessions are
        // active — these two must not collide.
        var dotCtx = baseCtx
        dotCtx.fill(el(2.7, 18.6, 1.8, 1.8), with: .color(state.accentColor))
        dotCtx.stroke(el(2.7, 18.6, 1.8, 1.8), with: .color(.black.opacity(0.18)), lineWidth: 0.6 * s)
    }
}

extension CharacterID {
    struct MenuBarColors { let body: String; let light: String; let accent: String }

    var menuBarColors: MenuBarColors {
        switch self {
        case .pigeon:  return MenuBarColors(body: "6b8294", light: "8aa0b2", accent: "f4a261")
        case .dog:     return MenuBarColors(body: "c89968", light: "d4a878", accent: "2a1a0a")
        case .cat:     return MenuBarColors(body: "3a3a3a", light: "525252", accent: "ff9bb3")
        case .frog:    return MenuBarColors(body: "5fa050", light: "7fc070", accent: "2a4a1a")
        case .raccoon: return MenuBarColors(body: "7a7a7a", light: "9a9a9a", accent: "1a1a1a")
        case .duck:    return MenuBarColors(body: "f7d959", light: "fae477", accent: "ff8a3d")
        }
    }
}
