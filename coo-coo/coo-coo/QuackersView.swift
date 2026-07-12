import SwiftUI

struct QuackersView: View {
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
            let a = CGFloat(osc(t, 0.3, 12 * .pi / 180))
            let cx = size.width/2; let cy = size.height*0.55
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(CGAffineTransform(rotationAngle: a))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        case .idle: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 2.0, 2))*s))
        case .done: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 0.5, 5))*s))
        default: break
        }

        func fc(_ p: Path, _ h: String, _ a: Double = 1) { ctx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func sc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            ctx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        fc(el(100, 184, 48, 5), "000000", 0.10)

        // Head context
        var hCtx = ctx
        switch state {
        case .thinking:
            let tilt = CGFloat(osc(t, 4.0, 7 * .pi / 180))
            hCtx.concatenate(CGAffineTransform(translationX: -100*s, y: -74*s)
                .concatenating(CGAffineTransform(rotationAngle: tilt))
                .concatenating(CGAffineTransform(translationX: 100*s, y: 74*s)))
        case .sleepy:
            // Head droops down (tucked under wing)
            let droop = CGFloat(pulse(t, 3.0, 8))*s
            hCtx.concatenate(CGAffineTransform(translationX: 0, y: droop))
        default: break
        }

        func hfc(_ p: Path, _ h: String, _ a: Double = 1) { hCtx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func hsc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            hCtx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        // Body
        fc(el(100, 142, 58, 44), "f7d959")
        fc(el(100, 154, 40, 26), "fae477") // belly highlight
        // Wing patches (slightly darker yellow on sides)
        fc(el(52, 140, 16, 22), "e8c840"); fc(el(148, 140, 16, 22), "e8c840")
        // Feet
        fc(el(80, 182, 16, 9), "ff8a3d"); fc(el(120, 182, 16, 9), "ff8a3d")
        fc(el(80, 189, 16, 6), "e87830"); fc(el(120, 189, 16, 6), "e87830")
        // Toe lines
        for ox: CGFloat in [68,80,92] {
            var toe = Path(); toe.move(to: pt(ox,189)); toe.addLine(to: pt(ox-4,196))
            sc(toe, "e87830", 2.5, .round)
        }
        for ox: CGFloat in [108,120,132] {
            var toe = Path(); toe.move(to: pt(ox,189)); toe.addLine(to: pt(ox+4,196))
            sc(toe, "e87830", 2.5, .round)
        }

        // Head
        hfc(el(100, 74, 36, 34), "f7d959")
        hfc(el(100, 60, 28, 20), "fae477")

        // Bill (flat, wide, orange) - right side of head
        var bill = Path()
        bill.move(to: pt(116, 78))
        bill.addCurve(to: pt(148, 82), control1: pt(130, 72), control2: pt(148, 76))
        bill.addCurve(to: pt(116, 90), control1: pt(148, 90), control2: pt(130, 96))
        bill.closeSubpath()
        hfc(bill, "ff8a3d")
        // Bill line (nostril/detail)
        var billLine = Path(); billLine.move(to: pt(118,84)); billLine.addLine(to: pt(144,84))
        hsc(billLine, "e06820", 1.5, .round)

        // Waiting: bill opens
        if state == .waiting {
            let openAmt = CGFloat(pulse(t, 0.35, 8))
            var billTop = Path()
            billTop.move(to: pt(116, 78-openAmt))
            billTop.addCurve(to: pt(148, 78-openAmt), control1: pt(130, 70-openAmt), control2: pt(148, 74-openAmt))
            hfc(billTop, "ff8a3d")
            var billBot = Path()
            billBot.move(to: pt(116, 90+openAmt))
            billBot.addCurve(to: pt(148, 90+openAmt), control1: pt(148, 90+openAmt), control2: pt(130, 96+openAmt))
            hfc(billBot, "ff8a3d")
            hfc(el(132, 84, 10, 3+openAmt*0.4), "2a1a0a") // open mouth dark
        }

        // Eye (right side of head, ducks have side eyes)
        switch state {
        case .idle:
            let blink = min(max((t.truncatingRemainder(dividingBy: 4.5) - 4.3) / 0.1, 0), 1)
            hfc(el(118, 64, 10, 10), "ffffff"); hfc(el(120, 66, 5, 5), "1a1a1a"); hfc(el(122, 62, 2.5, 2.5), "ffffff")
            if blink > 0 { hfc(el(118, 64, 10, CGFloat(10*blink)), "f7d959") }
        case .thinking:
            hfc(el(118, 64, 10, 10), "ffffff"); hfc(el(120, 66, 5, 5), "1a1a1a"); hfc(el(122, 62, 2.5, 2.5), "ffffff")
        case .waiting:
            hfc(el(118, 62, 12, 12), "ffffff")
            hCtx.stroke(el(118, 62, 12, 12), with: .color(.black), lineWidth: 1.5*s)
            hfc(el(119, 64, 6, 6), "1a1a1a"); hfc(el(122, 59, 3, 3), "ffffff")
        case .sleepy:
            var le = Path(); le.move(to: pt(106,64)); le.addQuadCurve(to: pt(130,64), control: pt(118,54))
            hsc(le, "1a1a1a", 3.5, .round)
        case .done:
            var le = Path(); le.move(to: pt(106,66)); le.addQuadCurve(to: pt(130,66), control: pt(118,55))
            hsc(le, "1a1a1a", 3.5, .round)
        }

        // State extras
        switch state {
        case .thinking:
            let b = CGFloat(pulse(t,2,4))*s
            ctx.draw(ctx.resolve(Text("💭").font(.system(size: 22*s))), at: CGPoint(x: 40*s, y: 36*s-b), anchor: .center)
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
            let b = CGFloat(pulse(t,0.5,5))*s
            ctx.draw(ctx.resolve(Text("🦆").font(.system(size: 22*s))), at: CGPoint(x: 166*s, y: 44*s-b), anchor: .center)
            ctx.draw(ctx.resolve(Text("✨").font(.system(size: 18*s))), at: CGPoint(x: 22*s, y: 40*s-b*0.6), anchor: .center)
        default: break
        }
    }
}
