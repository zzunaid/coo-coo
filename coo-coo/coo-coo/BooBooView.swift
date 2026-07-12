import SwiftUI

struct BooBooView: View {
    let state: CompanionState

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { originalCtx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                render(ctx: originalCtx, size: size, t: t)
            }
        }
    }

    private func osc(_ t: Double, _ period: Double, _ range: Double = 1) -> Double {
        sin(2 * .pi * t / period) * range
    }
    private func pulse(_ t: Double, _ period: Double, _ range: Double = 1) -> Double {
        (1 - cos(2 * .pi * t / period)) / 2 * range
    }
    private func blinkAmount(_ t: Double) -> CGFloat {
        let p = t.truncatingRemainder(dividingBy: 5.0)
        if p < 0.07 { return CGFloat(p / 0.07) }
        if p < 0.13 { return 1 }
        if p < 0.20 { return CGFloat((0.20 - p) / 0.07) }
        return 0
    }

    private func render(ctx originalCtx: GraphicsContext, size: CGSize, t: Double) {
        let s = size.width / 200

        func el(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (cx - rx) * s, y: (cy - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        // ── Whole-body transform ──────────────────────────────────────────
        var ctx = originalCtx

        switch state {
        case .waiting:
            let angle = CGFloat(osc(t, 0.35, 12 * .pi / 180))
            let cx = size.width / 2; let cy = size.height * 0.55
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        case .idle:
            let bob = CGFloat(pulse(t, 3.0, 2)) * s
            ctx.concatenate(CGAffineTransform(translationX: 0, y: -bob))
        case .done:
            let bob = CGFloat(pulse(t, 0.5, 5)) * s
            ctx.concatenate(CGAffineTransform(translationX: 0, y: -bob))
        default:
            break
        }

        func fc(_ p: Path, _ hex: String, _ a: Double = 1) {
            ctx.fill(p, with: .color(Color(hex: hex).opacity(a)))
        }
        func sc(_ p: Path, _ hex: String, _ w: CGFloat, _ cap: CGLineCap = .butt) {
            ctx.stroke(p, with: .color(Color(hex: hex)), style: StrokeStyle(lineWidth: w * s, lineCap: cap))
        }

        // ── Tail (wags with state) ────────────────────────────────────────
        let wagPeriod: Double; let wagRange: Double; let tailDown: Bool
        switch state {
        case .idle:     wagPeriod = 1.2; wagRange = 18; tailDown = false
        case .thinking: wagPeriod = 3.0; wagRange = 5;  tailDown = true
        case .waiting:  wagPeriod = 0.3; wagRange = 30; tailDown = false
        case .sleepy:   wagPeriod = 5.0; wagRange = 3;  tailDown = true
        case .done:     wagPeriod = 0.5; wagRange = 35; tailDown = false
        }
        let tailBase = CGPoint(x: 155 * s, y: 128 * s)
        var tailCtx = ctx
        let wagAngle = CGFloat(osc(t, wagPeriod, wagRange * .pi / 180))
        tailCtx.concatenate(
            CGAffineTransform(translationX: -tailBase.x, y: -tailBase.y)
                .concatenating(CGAffineTransform(rotationAngle: wagAngle))
                .concatenating(CGAffineTransform(translationX: tailBase.x, y: tailBase.y))
        )
        var tail = Path()
        if tailDown {
            tail.move(to: pt(157, 130))
            tail.addCurve(to: pt(168, 178), control1: pt(172, 142), control2: pt(180, 164))
        } else {
            tail.move(to: pt(157, 130))
            tail.addCurve(to: pt(182, 82), control1: pt(172, 120), control2: pt(190, 98))
        }
        tailCtx.stroke(tail, with: .color(Color(hex: "a67c52")), style: StrokeStyle(lineWidth: 14 * s, lineCap: .round))
        tailCtx.stroke(tail, with: .color(Color(hex: "c89968")), style: StrokeStyle(lineWidth: 9 * s, lineCap: .round))

        // ── Shadow ────────────────────────────────────────────────────────
        fc(el(100, 182, 48, 6), "000000", 0.10)

        // ── Head context (handles head-only tilt) ─────────────────────────
        var headCtx = ctx
        switch state {
        case .thinking:
            let tilt = CGFloat(osc(t, 5.0, 8 * .pi / 180))
            headCtx.concatenate(CGAffineTransform(translationX: -100 * s, y: -76 * s)
                .concatenating(CGAffineTransform(rotationAngle: tilt))
                .concatenating(CGAffineTransform(translationX: 100 * s, y: 76 * s)))
        default:
            break
        }

        func hfc(_ p: Path, _ hex: String, _ a: Double = 1) {
            headCtx.fill(p, with: .color(Color(hex: hex).opacity(a)))
        }
        func hsc(_ p: Path, _ hex: String, _ w: CGFloat, _ cap: CGLineCap = .butt) {
            headCtx.stroke(p, with: .color(Color(hex: hex)), style: StrokeStyle(lineWidth: w * s, lineCap: cap))
        }

        // Floppy ears drawn before head so head overlaps top
        hfc(el(64, 97, 18, 36), "a67c52")
        hfc(el(136, 97, 18, 36), "a67c52")

        // ── Body ──────────────────────────────────────────────────────────
        fc(el(100, 138, 58, 46), "c89968")
        fc(el(100, 150, 38, 24), "d4a878")

        // Front paws
        fc(el(78, 180, 14, 10), "c89968")
        fc(el(122, 180, 14, 10), "c89968")
        fc(el(78, 188, 14, 6), "d4a878")
        fc(el(122, 188, 14, 6), "d4a878")

        // ── Head ─────────────────────────────────────────────────────────
        hfc(el(100, 76, 40, 38), "c89968")
        hfc(el(100, 61, 30, 20), "d4a878")

        // ── Snout ────────────────────────────────────────────────────────
        hfc(el(102, 90, 22, 13), "e8c49a")
        hfc(el(102, 84, 9, 7), "2a1a0a")
        hfc(el(105, 81, 3, 2), "ffffff")

        // ── Eyes ─────────────────────────────────────────────────────────
        switch state {
        case .idle:
            let blink = blinkAmount(t)
            hfc(el(80, 68, 11, 11), "ffffff")
            hfc(el(80, 70, 6, 6), "3a1a00")
            hfc(el(82, 66, 2.5, 2.5), "ffffff")
            if blink > 0 { hfc(el(80, 68, 11, 11 * blink), "c89968") }
            hfc(el(120, 68, 11, 11), "ffffff")
            hfc(el(120, 70, 6, 6), "3a1a00")
            hfc(el(122, 66, 2.5, 2.5), "ffffff")
            if blink > 0 { hfc(el(120, 68, 11, 11 * blink), "c89968") }

        case .thinking:
            hfc(el(80, 68, 11, 11), "ffffff")
            hfc(el(80, 70, 6, 6), "3a1a00")
            hfc(el(82, 66, 2.5, 2.5), "ffffff")
            hfc(el(120, 68, 11, 11), "ffffff")
            hfc(el(120, 70, 6, 6), "3a1a00")
            hfc(el(122, 66, 2.5, 2.5), "ffffff")
            // One raised brow (curious)
            var lb = Path(); lb.move(to: pt(68, 56)); lb.addQuadCurve(to: pt(93, 52), control: pt(80, 46))
            hsc(lb, "2a1a0a", 2.5, .round)
            var rb = Path(); rb.move(to: pt(107, 54)); rb.addLine(to: pt(132, 54))
            hsc(rb, "2a1a0a", 2.5, .round)

        case .waiting:
            let mOpen = CGFloat(pulse(t, 0.4, 6))
            hfc(el(78, 66, 14, 14), "ffffff")
            headCtx.stroke(el(78, 66, 14, 14), with: .color(.black), lineWidth: 1.5 * s)
            hfc(el(79, 68, 7, 7), "3a1a00")
            hfc(el(82, 63, 3, 3), "ffffff")
            hfc(el(122, 66, 14, 14), "ffffff")
            headCtx.stroke(el(122, 66, 14, 14), with: .color(.black), lineWidth: 1.5 * s)
            hfc(el(122, 68, 7, 7), "3a1a00")
            hfc(el(125, 63, 3, 3), "ffffff")
            var mp = Path(); mp.move(to: pt(88, 98)); mp.addQuadCurve(to: pt(116, 98), control: pt(102, 104))
            headCtx.stroke(mp, with: .color(Color(hex: "2a1a0a")), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            hfc(el(102, 101 + mOpen * 0.5, 10, 5 + mOpen), "ff7e7e")

        case .sleepy:
            var le = Path(); le.move(to: pt(68, 68)); le.addQuadCurve(to: pt(92, 68), control: pt(80, 58))
            hsc(le, "2a1a0a", 3.5, .round)
            var re = Path(); re.move(to: pt(108, 68)); re.addQuadCurve(to: pt(132, 68), control: pt(120, 58))
            hsc(re, "2a1a0a", 3.5, .round)

        case .done:
            var le = Path(); le.move(to: pt(68, 70)); le.addQuadCurve(to: pt(92, 70), control: pt(80, 58))
            hsc(le, "3a1a00", 3.5, .round)
            var re = Path(); re.move(to: pt(108, 70)); re.addQuadCurve(to: pt(132, 70), control: pt(120, 58))
            hsc(re, "3a1a00", 3.5, .round)
            var sm = Path(); sm.move(to: pt(88, 98)); sm.addQuadCurve(to: pt(116, 98), control: pt(102, 106))
            hsc(sm, "2a1a0a", 2.5, .round)
            hfc(el(102, 102, 8, 4), "ff7e7e")
        }

        // ── State extras ─────────────────────────────────────────────────
        switch state {
        case .thinking:
            let bob = CGFloat(pulse(t, 1.8, 4)) * s
            let thought = ctx.resolve(Text("💭").font(.system(size: 24 * s)))
            ctx.draw(thought, at: CGPoint(x: 156 * s, y: 36 * s - bob), anchor: .center)

        case .waiting:
            let excl = ctx.resolve(
                Text("!").font(.system(size: 38 * s, weight: .black))
                    .foregroundStyle(Color(hex: "e24b4a"))
            )
            ctx.draw(excl, at: CGPoint(x: 14 * s, y: 44 * s), anchor: .center)
            ctx.draw(excl, at: CGPoint(x: 186 * s, y: 44 * s), anchor: .center)

        case .sleepy:
            let zData: [(Int, Double)] = [(0, 0.0), (1, 0.8), (2, 1.6)]
            for (i, delay) in zData {
                let phase = (t + delay).truncatingRemainder(dividingBy: 2.4) / 2.4
                let opacity: Double = phase < 0.15 ? phase / 0.15 : (phase > 0.85 ? (1 - phase) / 0.15 : 1)
                let yOff = CGFloat(phase * 30) * s
                var zCtx = ctx; zCtx.opacity = opacity
                let ch = i == 1 ? "Z" : "z"
                let zt = zCtx.resolve(Text(ch).font(.system(size: 18 * s, weight: .semibold))
                    .foregroundStyle(Color(hex: "7F77DD")))
                zCtx.draw(zt, at: CGPoint(x: (148 + CGFloat(i) * 8) * s, y: 52 * s - yOff), anchor: .center)
            }

        case .done:
            let bob = CGFloat(pulse(t, 0.5, 5)) * s
            let bone = ctx.resolve(Text("🦴").font(.system(size: 22 * s)))
            ctx.draw(bone, at: CGPoint(x: 166 * s, y: 44 * s - bob), anchor: .center)
            let sparkle = ctx.resolve(Text("✨").font(.system(size: 18 * s)))
            ctx.draw(sparkle, at: CGPoint(x: 22 * s, y: 40 * s - bob * 0.6), anchor: .center)

        default:
            break
        }
    }
}
