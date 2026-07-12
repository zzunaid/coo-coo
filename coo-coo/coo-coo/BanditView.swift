import SwiftUI

struct BanditView: View {
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
            let a = CGFloat(osc(t, 0.32, 12 * .pi / 180))
            let cx = size.width/2; let cy = size.height*0.55
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(CGAffineTransform(rotationAngle: a))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        case .idle: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 2.8, 2))*s))
        case .done: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 0.6, 4))*s))
        default: break
        }

        func fc(_ p: Path, _ h: String, _ a: Double = 1) { ctx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func sc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            ctx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        // Striped tail
        let wagPeriod: Double = state == .waiting ? 0.3 : (state == .done ? 0.4 : 1.4)
        let wagRange: Double = state == .waiting ? 28 : (state == .idle || state == .done ? 16 : 4)
        let tailBase = CGPoint(x: 154*s, y: 128*s)
        var tCtx = ctx
        let wagAngle = CGFloat(osc(t, wagPeriod, wagRange * .pi / 180))
        tCtx.concatenate(CGAffineTransform(translationX: -tailBase.x, y: -tailBase.y)
            .concatenating(CGAffineTransform(rotationAngle: wagAngle))
            .concatenating(CGAffineTransform(translationX: tailBase.x, y: tailBase.y)))
        var tail = Path()
        tail.move(to: pt(154, 130))
        tail.addCurve(to: pt(180, 78), control1: pt(174, 118), control2: pt(192, 96))
        // Stripes: alternating dark/light
        tCtx.stroke(tail, with: .color(Color(hex: "1a1a1a")), style: StrokeStyle(lineWidth: 16*s, lineCap: .round))
        tCtx.stroke(tail, with: .color(Color(hex: "9a9a9a")), style: StrokeStyle(lineWidth: 11*s, lineCap: .round))
        tCtx.stroke(tail, with: .color(Color(hex: "1a1a1a")), style: StrokeStyle(lineWidth: 6*s,  lineCap: .round))

        fc(el(100, 183, 46, 5), "000000", 0.10)

        // Head context
        var hCtx = ctx
        if state == .thinking {
            let tilt = CGFloat(osc(t, 3.5, 6 * .pi / 180))
            hCtx.concatenate(CGAffineTransform(translationX: -100*s, y: -76*s)
                .concatenating(CGAffineTransform(rotationAngle: tilt))
                .concatenating(CGAffineTransform(translationX: 100*s, y: 76*s)))
        }
        func hfc(_ p: Path, _ h: String, _ a: Double = 1) { hCtx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func hsc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            hCtx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        // Ears (round, with cream inner)
        hfc(el(66, 48, 17, 20), "7a7a7a"); hfc(el(66, 50, 10, 13), "e8d8c8")
        hfc(el(134, 48, 17, 20), "7a7a7a"); hfc(el(134, 50, 10, 13), "e8d8c8")

        // Body
        fc(el(100, 138, 54, 44), "7a7a7a")
        fc(el(100, 150, 36, 26), "c8c0b8") // belly
        // Paws
        fc(el(78, 181, 14, 9), "7a7a7a"); fc(el(122, 181, 14, 9), "7a7a7a")
        fc(el(78, 188, 14, 6), "9a9a9a"); fc(el(122, 188, 14, 6), "9a9a9a")

        // Head
        hfc(el(100, 76, 40, 36), "7a7a7a")
        hfc(el(100, 88, 22, 13), "c8c0b8") // snout
        hfc(el(100, 82, 9, 7), "1a1a1a")  // nose
        hfc(el(103, 79, 3, 2), "ffffff")   // nose shine

        // THE MASK (black bandit mask)
        hfc(el(80, 68, 22, 14), "1a1a1a")
        hfc(el(120, 68, 22, 14), "1a1a1a")
        // Bridge of nose (gap in mask)
        hfc(el(100, 68, 6, 8), "7a7a7a")

        // Eyes inside mask
        switch state {
        case .idle:
            let blink = min(max((t.truncatingRemainder(dividingBy: 5) - 4.85) / 0.08, 0), 1)
            hfc(el(80,68,10,10), "e8e0c8"); hfc(el(80,70,5,5), "2a1a0a"); hfc(el(82,65,2,2), "ffffff")
            if blink > 0 { hfc(el(80,68,10,CGFloat(10*blink)), "1a1a1a") }
            hfc(el(120,68,10,10), "e8e0c8"); hfc(el(120,70,5,5), "2a1a0a"); hfc(el(122,65,2,2), "ffffff")
            if blink > 0 { hfc(el(120,68,10,CGFloat(10*blink)), "1a1a1a") }
        case .thinking:
            // One eye slightly narrowed (suspicious)
            hfc(el(80,68,10,10), "e8e0c8"); hfc(el(80,70,5,5), "2a1a0a"); hfc(el(82,65,2,2), "ffffff")
            hfc(el(120,68,10,7), "e8e0c8"); hfc(el(120,70,5,4), "2a1a0a"); hfc(el(122,65,2,2), "ffffff")
        case .waiting:
            hfc(el(80,66,12,12), "e8e0c8"); hfc(el(80,68,6,6), "2a1a0a"); hfc(el(83,63,2.5,2.5), "ffffff")
            hfc(el(120,66,12,12), "e8e0c8"); hfc(el(120,68,6,6), "2a1a0a"); hfc(el(123,63,2.5,2.5), "ffffff")
        case .sleepy:
            var le = Path(); le.move(to: pt(68,66)); le.addQuadCurve(to: pt(92,66), control: pt(80,56))
            hsc(le, "e8e0c8", 3, .round)
            var re = Path(); re.move(to: pt(108,66)); re.addQuadCurve(to: pt(132,66), control: pt(120,56))
            hsc(re, "e8e0c8", 3, .round)
        case .done:
            // Mischievous smug look
            hfc(el(80,70,10,7), "e8e0c8"); hfc(el(80,70,5,4), "2a1a0a"); hfc(el(82,66,2,2), "ffffff")
            hfc(el(120,70,10,7), "e8e0c8"); hfc(el(120,70,5,4), "2a1a0a"); hfc(el(122,66,2,2), "ffffff")
            var sm = Path(); sm.move(to: pt(88,97)); sm.addQuadCurve(to: pt(112,97), control: pt(100,104))
            hsc(sm, "2a1a0a", 2.5, .round)
        }

        // State extras
        switch state {
        case .thinking:
            let b = CGFloat(pulse(t,2,4))*s
            ctx.draw(ctx.resolve(Text("👀").font(.system(size: 20*s))), at: CGPoint(x: 160*s, y: 36*s-b), anchor: .center)
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
            let b = CGFloat(pulse(t,0.6,4))*s
            ctx.draw(ctx.resolve(Text("😈").font(.system(size: 20*s))), at: CGPoint(x: 166*s, y: 44*s-b), anchor: .center)
            ctx.draw(ctx.resolve(Text("✨").font(.system(size: 18*s))), at: CGPoint(x: 22*s, y: 40*s-b*0.6), anchor: .center)
        default: break
        }
    }
}
