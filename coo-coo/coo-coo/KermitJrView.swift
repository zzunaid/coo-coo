import SwiftUI

struct KermitJrView: View {
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
            let a = CGFloat(osc(t, 0.28, 14 * .pi / 180))
            let cx = size.width/2; let cy = size.height*0.55
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(CGAffineTransform(rotationAngle: a))
                .concatenating(CGAffineTransform(translationX: cx, y: cy)))
        case .idle: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 2.5, 2))*s))
        case .done: ctx.concatenate(CGAffineTransform(translationX: 0, y: -CGFloat(pulse(t, 0.7, 5))*s))
        default: break
        }

        func fc(_ p: Path, _ h: String, _ a: Double = 1) { ctx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func sc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            ctx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        fc(el(100, 184, 48, 5), "000000", 0.10)

        // Head context (peck/bob for thinking)
        var hCtx = ctx
        if state == .thinking {
            let peck = CGFloat(pulse(t, 1.2, 6))*s
            hCtx.concatenate(CGAffineTransform(translationX: 0, y: peck))
        }
        func hfc(_ p: Path, _ h: String, _ a: Double = 1) { hCtx.fill(p, with: .color(Color(hex: h).opacity(a))) }
        func hsc(_ p: Path, _ h: String, _ w: CGFloat, _ c: CGLineCap = .butt) {
            hCtx.stroke(p, with: .color(Color(hex: h)), style: StrokeStyle(lineWidth: w*s, lineCap: c))
        }

        // Body (wide, low)
        fc(el(100, 148, 58, 38), "5fa050")
        fc(el(100, 156, 44, 24), "8fd080") // belly
        // Tiny hands on sides
        fc(el(46, 150, 12, 8), "5fa050"); fc(el(154, 150, 12, 8), "5fa050")
        fc(el(46, 157, 12, 5), "7fc070"); fc(el(154, 157, 12, 5), "7fc070")
        // Feet
        fc(el(78, 182, 18, 9), "5fa050"); fc(el(122, 182, 18, 9), "5fa050")
        fc(el(78, 189, 18, 6), "7fc070"); fc(el(122, 189, 18, 6), "7fc070")

        // Wide head
        hfc(el(100, 90, 50, 30), "5fa050")
        hfc(el(100, 104, 38, 18), "8fd080") // throat/chin area

        // Throat pouch (inflates in waiting)
        let throatPulse = state == .waiting ? CGFloat(pulse(t, 0.5, 8)) : 0
        hfc(el(100, 108+throatPulse*0.3, 28+throatPulse, 14+throatPulse), "a0d090")

        // Wide frog mouth
        var mouth = Path()
        switch state {
        case .waiting:
            let openAmt = CGFloat(pulse(t, 0.4, 12))
            mouth.move(to: pt(66, 106)); mouth.addQuadCurve(to: pt(134, 106), control: pt(100, 116+openAmt))
            hsc(mouth, "2a4a1a", 3, .round)
            hfc(el(100, 110+openAmt*0.4, 22, 5+openAmt*0.4), "2a1a0a") // open mouth dark
            hfc(el(100, 112+openAmt*0.3, 16, 3+openAmt*0.3), "ff6060") // tongue
        case .done:
            mouth.move(to: pt(70, 104)); mouth.addQuadCurve(to: pt(130, 104), control: pt(100, 116))
            hsc(mouth, "2a4a1a", 3.5, .round)
        default:
            mouth.move(to: pt(72, 106)); mouth.addQuadCurve(to: pt(128, 106), control: pt(100, 112))
            hsc(mouth, "2a4a1a", 2.5, .round)
        }

        // Protruding bulge eyes on top of head
        hfc(el(74, 68, 18, 18), "5fa050")  // eye mound
        hfc(el(126, 68, 18, 18), "5fa050")
        hfc(el(74, 68, 13, 13), "e8e0c8")  // eye white
        hfc(el(126, 68, 13, 13), "e8e0c8")

        switch state {
        case .idle:
            let blink = min(max((t.truncatingRemainder(dividingBy: 4) - 3.85) / 0.08, 0), 1)
            hfc(el(74,70,7,5), "2a2a1a"); hfc(el(77,65,2.5,2.5), "ffffff")
            if blink > 0 { hfc(el(74,68,13,CGFloat(13*blink)), "5fa050") }
            hfc(el(126,70,7,5), "2a2a1a"); hfc(el(129,65,2.5,2.5), "ffffff")
            if blink > 0 { hfc(el(126,68,13,CGFloat(13*blink)), "5fa050") }
        case .thinking:
            hfc(el(74,70,7,5), "2a2a1a"); hfc(el(77,65,2.5,2.5), "ffffff")
            hfc(el(126,70,7,5), "2a2a1a"); hfc(el(129,65,2.5,2.5), "ffffff")
        case .waiting:
            hfc(el(74,68,8,8), "2a2a1a"); hfc(el(77,63,3,3), "ffffff")
            hfc(el(126,68,8,8), "2a2a1a"); hfc(el(129,63,3,3), "ffffff")
        case .sleepy:
            var le = Path(); le.move(to: pt(61,66)); le.addQuadCurve(to: pt(87,66), control: pt(74,56))
            hsc(le, "2a4a1a", 3.5, .round)
            var re = Path(); re.move(to: pt(113,66)); re.addQuadCurve(to: pt(139,66), control: pt(126,56))
            hsc(re, "2a4a1a", 3.5, .round)
        case .done:
            var le = Path(); le.move(to: pt(61,68)); le.addQuadCurve(to: pt(87,68), control: pt(74,57))
            hsc(le, "2a4a1a", 3.5, .round)
            var re = Path(); re.move(to: pt(113,68)); re.addQuadCurve(to: pt(139,68), control: pt(126,57))
            hsc(re, "2a4a1a", 3.5, .round)
        }

        // Nostrils
        hfc(el(94,85,3,2), "2a4a1a"); hfc(el(106,85,3,2), "2a4a1a")

        // State extras
        switch state {
        case .thinking:
            let b = CGFloat(pulse(t,1.2,4))*s
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
            let b = CGFloat(pulse(t,0.7,5))*s
            ctx.draw(ctx.resolve(Text("🌿").font(.system(size: 22*s))), at: CGPoint(x: 166*s, y: 44*s-b), anchor: .center)
            ctx.draw(ctx.resolve(Text("✨").font(.system(size: 18*s))), at: CGPoint(x: 22*s, y: 40*s-b*0.6), anchor: .center)
        default: break
        }
    }
}
