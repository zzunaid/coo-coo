import SwiftUI

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

struct GeraldView: View {
    let state: CompanionState

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { originalCtx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                render(ctx: originalCtx, size: size, t: t)
            }
        }
    }

    // MARK: - Animation math

    // Oscillates in [-range, range] over period seconds
    private func osc(_ t: Double, _ period: Double, _ range: Double = 1) -> Double {
        sin(2 * .pi * t / period) * range
    }

    // Pulses in [0, range] over period seconds (cosine ramp, starts at 0)
    private func pulse(_ t: Double, _ period: Double, _ range: Double = 1) -> Double {
        (1 - cos(2 * .pi * t / period)) / 2 * range
    }

    // Returns 0 (open) → 1 (closed) for a periodic blink
    private func blinkAmount(_ t: Double) -> CGFloat {
        let p = t.truncatingRemainder(dividingBy: 4.5)
        if p < 0.07 { return CGFloat(p / 0.07) }
        if p < 0.13 { return 1 }
        if p < 0.20 { return CGFloat((0.20 - p) / 0.07) }
        return 0
    }

    // Returns (dx, dy) pupil offset in 200px coordinate space
    private func pupilOffset(_ t: Double, _ period: Double) -> (CGFloat, CGFloat) {
        let p = t.truncatingRemainder(dividingBy: period) / period
        if p > 0.30 && p < 0.50 { return (-2.5, 1.5) }
        if p > 0.65 && p < 0.80 { return (2.5, -1.5) }
        return (0, 0)
    }

    // MARK: - Render

    private func render(ctx originalCtx: GraphicsContext, size: CGSize, t: Double) {
        let s = size.width / 200

        func el(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (cx-rx)*s, y: (cy-ry)*s, width: rx*2*s, height: ry*2*s))
        }
        func ln(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x1*s, y: y1*s))
            p.addLine(to: CGPoint(x: x2*s, y: y2*s))
            return p
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*s, y: y*s) }

        // ── Whole-body transform ─────────────────────────────────────────
        // ctx is copied from originalCtx; all drawing via fc/sc inherits it.
        var ctx = originalCtx

        switch state {
        case .waiting:
            let angle = CGFloat(osc(t, 0.35, 12 * .pi / 180))
            let cx = size.width / 2
            let cy = size.height * 0.55
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        case .idle:
            let bob = CGFloat(pulse(t, 3.2, 2)) * s
            ctx.concatenate(CGAffineTransform(translationX: 0, y: -bob))
        case .done:
            let bob = CGFloat(pulse(t, 0.8, 4)) * s
            ctx.concatenate(CGAffineTransform(translationX: 0, y: -bob))
        default:
            break
        }

        func fc(_ p: Path, _ hex: String, _ a: Double = 1) {
            ctx.fill(p, with: .color(Color(hex: hex).opacity(a)))
        }
        func sc(_ p: Path, _ hex: String, _ w: CGFloat, _ cap: CGLineCap = .butt) {
            ctx.stroke(p, with: .color(Color(hex: hex)), style: StrokeStyle(lineWidth: w*s, lineCap: cap))
        }

        // ── Breathing ────────────────────────────────────────────────────
        let breathPeriod: Double
        switch state {
        case .thinking: breathPeriod = 1.8
        case .sleepy:   breathPeriod = 4.0
        case .done:     breathPeriod = 2.4
        default:        breathPeriod = 3.2
        }
        let breathe: CGFloat = state == .waiting ? 0 : CGFloat(pulse(t, breathPeriod, 2))

        // ── Shadow ───────────────────────────────────────────────────────
        fc(el(100, 178, 48, 6), "000000", 0.12)

        // ── Wings — waiting only, animated flap ──────────────────────────
        if state == .waiting {
            let flapY = CGFloat(pulse(t, 0.25, 22))

            var lw = Path()
            lw.move(to: pt(56, 110 - flapY))
            lw.addQuadCurve(to: pt(12, 140 - flapY * 0.5), control: pt(14, 95 - flapY))
            lw.addQuadCurve(to: pt(60, 128 - flapY * 0.5), control: pt(40, 125 - flapY * 0.5))
            lw.closeSubpath()
            fc(lw, "5a7282")

            var rw = Path()
            rw.move(to: pt(144, 110 - flapY))
            rw.addQuadCurve(to: pt(188, 140 - flapY * 0.5), control: pt(186, 95 - flapY))
            rw.addQuadCurve(to: pt(140, 128 - flapY * 0.5), control: pt(160, 125 - flapY * 0.5))
            rw.closeSubpath()
            fc(rw, "5a7282")
        }

        // ── Body ─────────────────────────────────────────────────────────
        fc(el(100, 130, 62, 50 + breathe), "6b8294")
        fc(el(100, 126, 54, 42 + breathe * 0.7), "8aa0b2")
        fc(el(100, 142, 40, 22), "a8bcc8")

        // ── Head ─────────────────────────────────────────────────────────
        // headCtx inherits the whole-body transform, then adds its own.
        var headCtx = ctx

        switch state {
        case .idle:
            let tilt = CGFloat(osc(t, 6.0, 4 * .pi / 180))
            headCtx.concatenate(CGAffineTransform(translationX: -100*s, y: -72*s)
                .concatenating(CGAffineTransform(rotationAngle: tilt))
                .concatenating(CGAffineTransform(translationX: 100*s, y: 72*s)))
        case .thinking:
            let peck = CGFloat(pulse(t, 0.9, 8)) * s
            headCtx.concatenate(CGAffineTransform(translationX: 0, y: peck))
        default:
            break
        }

        func hfc(_ p: Path, _ hex: String, _ a: Double = 1) {
            headCtx.fill(p, with: .color(Color(hex: hex).opacity(a)))
        }
        func hsc(_ p: Path, _ hex: String, _ w: CGFloat, _ cap: CGLineCap = .butt) {
            headCtx.stroke(p, with: .color(Color(hex: hex)), style: StrokeStyle(lineWidth: w*s, lineCap: cap))
        }

        // Head shell
        hfc(el(100, 72, 44, 42), "6b8294")
        hfc(el(100, 68, 38, 36), "8aa0b2")

        // Iridescent neck patch
        hfc(el(116, 108, 14, 6), "9b59b6", 0.4)
        hfc(el(116, 111, 11, 4), "3498db", 0.35)

        // ── Eyes ─────────────────────────────────────────────────────────
        switch state {
        case .idle:
            let blinkAmt = blinkAmount(t)
            let (pdx, pdy) = pupilOffset(t, 5.0)
            hfc(el(82, 66, 13, 13), "ffffff")
            hfc(el(82 + pdx, 68 + pdy, 6, 6), "1a1a1a")
            hfc(el(84 + pdx, 65 + pdy, 2.5, 2.5), "ffffff")
            if blinkAmt > 0 { hfc(el(82, 66, 13, 13 * blinkAmt), "8aa0b2") }
            hfc(el(118, 66, 13, 13), "ffffff")
            hfc(el(118 + pdx, 68 + pdy, 6, 6), "1a1a1a")
            hfc(el(120 + pdx, 65 + pdy, 2.5, 2.5), "ffffff")
            if blinkAmt > 0 { hfc(el(118, 66, 13, 13 * blinkAmt), "8aa0b2") }

        case .thinking:
            // Narrowed focused eyes + furrowed brows
            hfc(el(82, 66, 12, 12), "ffffff")
            hfc(el(82, 68, 3.5, 7), "1a1a1a")
            hfc(el(83, 64, 2, 2), "ffffff")
            hfc(el(118, 66, 12, 12), "ffffff")
            hfc(el(118, 68, 3.5, 7), "1a1a1a")
            hfc(el(119, 64, 2, 2), "ffffff")
            var bl = Path(); bl.move(to: pt(64, 54)); bl.addLine(to: pt(96, 50))
            hsc(bl, "3a3a3a", 3, .round)
            var br = Path(); br.move(to: pt(104, 50)); br.addLine(to: pt(136, 54))
            hsc(br, "3a3a3a", 3, .round)

        case .waiting:
            let (pdx, pdy) = pupilOffset(t, 0.4)
            hfc(el(78, 60, 20, 20), "ffffff")
            headCtx.stroke(el(78, 60, 20, 20), with: .color(.black), lineWidth: 2*s)
            hfc(el(80 + pdx, 64 + pdy, 8, 8), "1a1a1a")
            hfc(el(83 + pdx, 60 + pdy, 3, 3), "ffffff")
            hfc(el(122, 60, 20, 20), "ffffff")
            headCtx.stroke(el(122, 60, 20, 20), with: .color(.black), lineWidth: 2*s)
            hfc(el(120 + pdx, 64 + pdy, 8, 8), "1a1a1a")
            hfc(el(123 + pdx, 60 + pdy, 3, 3), "ffffff")

        case .sleepy:
            var le = Path(); le.move(to: pt(68, 64)); le.addQuadCurve(to: pt(96, 64), control: pt(82, 56))
            hsc(le, "1a1a1a", 3.5, .round)
            var re = Path(); re.move(to: pt(104, 64)); re.addQuadCurve(to: pt(132, 64), control: pt(118, 56))
            hsc(re, "1a1a1a", 3.5, .round)

        case .done:
            var le = Path(); le.move(to: pt(68, 66)); le.addQuadCurve(to: pt(96, 66), control: pt(82, 54))
            hsc(le, "1a1a1a", 3.5, .round)
            var re = Path(); re.move(to: pt(104, 66)); re.addQuadCurve(to: pt(132, 66), control: pt(118, 54))
            hsc(re, "1a1a1a", 3.5, .round)
        }

        // ── Beak ─────────────────────────────────────────────────────────
        var bk = Path()
        bk.move(to: pt(92, 88)); bk.addLine(to: pt(130, 92)); bk.addLine(to: pt(92, 96))
        bk.closeSubpath()
        headCtx.fill(bk, with: .color(Color(hex: "f4a261")))

        // Screaming open mouth (waiting) — pulses open/shut
        if state == .waiting {
            let mouthOpen = CGFloat(pulse(t, 0.3, 6))
            hfc(el(118, 103, 10, 4 + mouthOpen), "2a1a1a")
        }

        // ── Feet ─────────────────────────────────────────────────────────
        let fa = "f4a261"
        sc(ln(86, 174, 86, 190), fa, 4.5, .round)
        sc(ln(114, 174, 114, 190), fa, 4.5, .round)
        sc(ln(82, 190, 76, 193), fa, 3.5, .round)
        sc(ln(90, 190, 96, 193), fa, 3.5, .round)
        sc(ln(110, 190, 104, 193), fa, 3.5, .round)
        sc(ln(118, 190, 124, 193), fa, 3.5, .round)

        // ── State extras (emoji + text overlay, drawn on transformed ctx) ─
        switch state {
        case .thinking:
            let thoughtBob = CGFloat(pulse(t, 1.8, 4)) * s
            let thought = ctx.resolve(Text("💭").font(.system(size: 24 * s)))
            ctx.draw(thought, at: CGPoint(x: 156*s, y: 36*s - thoughtBob), anchor: .center)

        case .waiting:
            let excl = ctx.resolve(
                Text("!").font(.system(size: 38 * s, weight: .black))
                    .foregroundStyle(Color(hex: "e24b4a"))
            )
            ctx.draw(excl, at: CGPoint(x: 14*s, y: 44*s), anchor: .center)
            ctx.draw(excl, at: CGPoint(x: 186*s, y: 44*s), anchor: .center)

        case .sleepy:
            let zData: [(Int, Double)] = [(0, 0.0), (1, 0.8), (2, 1.6)]
            for (i, delay) in zData {
                let phase = (t + delay).truncatingRemainder(dividingBy: 2.4) / 2.4
                let opacity: Double = phase < 0.15 ? phase / 0.15 : (phase > 0.85 ? (1 - phase) / 0.15 : 1)
                let yOff = CGFloat(phase * 30) * s
                var zCtx = ctx
                zCtx.opacity = opacity
                let zChar = i == 1 ? "Z" : "z"
                let zText = zCtx.resolve(
                    Text(zChar).font(.system(size: 18 * s, weight: .semibold))
                        .foregroundStyle(Color(hex: "7F77DD"))
                )
                zCtx.draw(zText, at: CGPoint(x: (148 + CGFloat(i) * 8) * s, y: 52*s - yOff), anchor: .center)
            }

        case .done:
            let breadBob = CGFloat(pulse(t, 0.8, 5)) * s
            let bread = ctx.resolve(Text("🍞").font(.system(size: 22 * s)))
            ctx.draw(bread, at: CGPoint(x: 166*s, y: 44*s - breadBob), anchor: .center)
            let sparkle = ctx.resolve(Text("✨").font(.system(size: 18 * s)))
            ctx.draw(sparkle, at: CGPoint(x: 22*s, y: 40*s - breadBob * 0.6), anchor: .center)

        default:
            break
        }
    }
}
