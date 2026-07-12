import SwiftUI

struct MrWhiskersView: View {
    let state: CompanionState

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in render(ctx: ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate) }
        }
    }

    private func osc(_ t: Double, _ p: Double, _ r: Double = 1) -> Double { sin(2 * .pi * t / p) * r }
    private func pulse(_ t: Double, _ p: Double, _ r: Double = 1) -> Double { (1 - cos(2 * .pi * t / p)) / 2 * r }

    private func render(ctx originalCtx: GraphicsContext, size: CGSize, t: Double) {
        let s = size.width / 200
        func el(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (cx-rx)*s, y: (cy-ry)*s, width: rx*2*s, height: ry*2*s))
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*s, y: y*s) }

        var ctx = originalCtx
        switch state {
        case .waiting:
            let a = CGFloat(osc(t, 0.3, 10 * .pi / 180))
            let cx = size.width/2; let cy = size.height*0.55
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(CGAffineTransform(rotationAngle: a))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        case .idle: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 4.0, 1.5))*s))
        case .done: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 1.0, 3))*s))
        default: break
        }

        func fc(_ p: Path, _ h: String, _ a: Double = 1) { ctx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func sc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            ctx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        // Tail wraps around front
        let wag: CGFloat = (state == .idle || state == .done) ? CGFloat(osc(t, 2.0, 8 * .pi / 180)) : 0
        var tCtx = ctx
        if wag != 0 {
            let tb = CGPoint(x: 148*s, y: 138*s)
            tCtx.concatenate(CGAffineTransform(translationX: -tb.x, y: -tb.y)
                .concatenating(CGAffineTransform(rotationAngle: wag))
                .concatenating(CGAffineTransform(translationX: tb.x, y: tb.y)))
        }
        var tail = Path()
        tail.move(to: pt(148, 138))
        tail.addCurve(to: pt(58, 178), control1: pt(188, 155), control2: pt(188, 182))
        tail.addCurve(to: pt(78, 183), control1: pt(48, 184), control2: pt(60, 190))
        tCtx.stroke(tail, with: .color(Color(hex: "3a3a3a")), style: StrokeStyle(lineWidth: 12*s, lineCap: .round))
        tCtx.stroke(tail, with: .color(Color(hex: "525252")), style: StrokeStyle(lineWidth: 7*s, lineCap: .round))

        fc(el(100, 184, 44, 5), "000000", 0.10)

        // Head context
        var hCtx = ctx
        if state == .thinking {
            let tilt = CGFloat(osc(t, 4.0, 5 * .pi / 180))
            hCtx.concatenate(CGAffineTransform(translationX: -100*s, y: -76*s)
                .concatenating(CGAffineTransform(rotationAngle: tilt))
                .concatenating(CGAffineTransform(translationX: 100*s, y: 76*s)))
        }
        func hfc(_ p: Path, _ h: String, _ a: Double = 1) { hCtx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func hsc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            hCtx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        // Ears (triangles, drawn before head)
        for (tip, bl, br): (CGPoint, CGPoint, CGPoint) in [
            (pt(72, 28), pt(57, 62), pt(87, 60)),
            (pt(128, 28), pt(113, 60), pt(143, 62))
        ] {
            var ear = Path(); ear.move(to: tip); ear.addLine(to: bl); ear.addLine(to: br); ear.closeSubpath()
            hfc(ear, "3a3a3a")
        }
        for (tip, bl, br): (CGPoint, CGPoint, CGPoint) in [
            (pt(72, 36), pt(63, 60), pt(83, 58)),
            (pt(128, 36), pt(117, 58), pt(137, 60))
        ] {
            var inner = Path(); inner.move(to: tip); inner.addLine(to: bl); inner.addLine(to: br); inner.closeSubpath()
            hfc(inner, "ff9bb3", 0.7)
        }

        // Body
        fc(el(100, 142, 48, 42), "3a3a3a")
        fc(el(100, 154, 32, 22), "525252")
        fc(el(78, 183, 13, 8), "3a3a3a"); fc(el(122, 183, 13, 8), "3a3a3a")
        fc(el(78, 189, 13, 5), "525252"); fc(el(122, 189, 13, 5), "525252")

        // Head
        hfc(el(100, 76, 36, 34), "3a3a3a")
        hfc(el(100, 64, 28, 18), "525252")
        hfc(el(100, 88, 5, 4), "ff9bb3") // nose

        // Whiskers (3 per side)
        for (ox, oy, tx, ty): (CGFloat, CGFloat, CGFloat, CGFloat) in [
            (93,84,60,82),(93,89,58,89),(93,94,60,96),
            (107,84,140,82),(107,89,142,89),(107,94,140,96)
        ] {
            var w = Path(); w.move(to: pt(ox,oy)); w.addLine(to: pt(tx,ty))
            hsc(w, "777777", 0.9, .round)
        }

        // Eyes (amber, vertical slit)
        switch state {
        case .idle:
            let blink = min(max((t.truncatingRemainder(dividingBy: 6) - 5.85) / 0.08, 0), 1)
            hfc(el(80,68,11,11), "f0c040"); hfc(el(80,68,3,9), "1a1a1a"); hfc(el(82,64,2,2), "ffffff")
            if blink > 0 { hfc(el(80,68,11,CGFloat(11*blink)), "3a3a3a") }
            hfc(el(120,68,11,11), "f0c040"); hfc(el(120,68,3,9), "1a1a1a"); hfc(el(122,64,2,2), "ffffff")
            if blink > 0 { hfc(el(120,68,11,CGFloat(11*blink)), "3a3a3a") }
        case .thinking:
            hfc(el(80,68,11,8), "f0c040"); hfc(el(80,68,2.5,7), "1a1a1a"); hfc(el(82,64,2,2), "ffffff")
            hfc(el(120,68,11,8), "f0c040"); hfc(el(120,68,2.5,7), "1a1a1a"); hfc(el(122,64,2,2), "ffffff")
        case .waiting:
            hfc(el(80,66,13,13), "f0c040"); hfc(el(80,66,6,13), "1a1a1a"); hfc(el(83,61,3,3), "ffffff")
            hfc(el(120,66,13,13), "f0c040"); hfc(el(120,66,6,13), "1a1a1a"); hfc(el(123,61,3,3), "ffffff")
        case .sleepy:
            hfc(el(80,68,11,5), "f0c040"); hfc(el(80,68,2,3), "1a1a1a")
            var ll = Path(); ll.move(to: pt(68,64)); ll.addQuadCurve(to: pt(92,64), control: pt(80,74))
            hsc(ll, "3a3a3a", 4, .round)
            hfc(el(120,68,11,5), "f0c040"); hfc(el(120,68,2,3), "1a1a1a")
            var rl = Path(); rl.move(to: pt(108,64)); rl.addQuadCurve(to: pt(132,64), control: pt(120,74))
            hsc(rl, "3a3a3a", 4, .round)
        case .done:
            hfc(el(80,70,11,7), "f0c040"); hfc(el(80,70,2.5,6), "1a1a1a"); hfc(el(82,66,2,2), "ffffff")
            hfc(el(120,70,11,7), "f0c040"); hfc(el(120,70,2.5,6), "1a1a1a"); hfc(el(122,66,2,2), "ffffff")
        }

        // State extras
        switch state {
        case .thinking:
            let b = CGFloat(pulse(t,2,4))*s
            ctx.draw(ctx.resolve(Text("💭").font(.system(size: 22*s))), at: CGPoint(x: 158*s, y: 36*s-b), anchor: .center)
        case .waiting:
            let e = ctx.resolve(Text("!").font(.system(size: 36*s, weight: .black)).foregroundStyle(Color(hex: "e24b4a")))
            ctx.draw(e, at: CGPoint(x: 14*s, y: 44*s), anchor: .center)
            ctx.draw(e, at: CGPoint(x: 186*s, y: 44*s), anchor: .center)
        case .sleepy:
            for (i, d) in [(0, 0.0), (1, 0.8), (2, 1.6)] {
                let ph = (t+d).truncatingRemainder(dividingBy: 2.4) / 2.4
                let op = ph < 0.15 ? ph/0.15 : (ph > 0.85 ? (1-ph)/0.15 : 1)
                var zc = ctx; zc.opacity = op
                let zt = zc.resolve(Text(i==1 ? "Z":"z").font(.system(size: 18*s, weight: .semibold)).foregroundStyle(Color(hex: "7F77DD")))
                zc.draw(zt, at: CGPoint(x: (148+CGFloat(i)*8)*s, y: 52*s-CGFloat(ph*30)*s), anchor: .center)
            }
        case .done:
            let b = CGFloat(pulse(t,1,4))*s
            ctx.draw(ctx.resolve(Text("😏").font(.system(size: 20*s))), at: CGPoint(x: 166*s, y: 44*s-b), anchor: .center)
        default: break
        }
    }
}
