import SwiftUI

// MARK: - True Carry Premium Visual Layer
// All visual assets generated via SwiftUI Canvas — no external images required.

// MARK: 1. Hero Range Scene ──────────────────────────────────────────────────
// Full-width home hero: night range, launch monitor device, ball, gold arc

struct TCHeroRangeScene: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let groundY = h * 0.60

            // ── Sky / Background ──────────────────────────────────────────
            ctx.fill(Path(CGRect(origin:.zero, size:size)),
                     with: .linearGradient(
                        Gradient(stops:[
                            .init(color:Color(red:0.01,green:0.03,blue:0.08), location:0.0),
                            .init(color:Color(red:0.02,green:0.07,blue:0.13), location:0.55),
                            .init(color:Color(red:0.04,green:0.12,blue:0.08), location:1.0)
                        ]),
                        startPoint:.zero, endPoint:CGPoint(x:0,y:h)))

            // ── Horizon atmospheric glow ──────────────────────────────────
            ctx.fill(Path(ellipseIn:CGRect(x:-w*0.05, y:groundY-18, width:w*0.80, height:36)),
                     with:.radialGradient(
                        Gradient(colors:[Color(red:0.20,green:0.55,blue:0.22).opacity(0.14), .clear]),
                        center:CGPoint(x:w*0.35,y:groundY), startRadius:0, endRadius:w*0.44))

            // ── Ground ────────────────────────────────────────────────────
            var ground = Path()
            ground.addRect(CGRect(x:0, y:groundY, width:w, height:h-groundY))
            ctx.fill(ground, with:.linearGradient(
                Gradient(colors:[Color(red:0.09,green:0.22,blue:0.11),
                                  Color(red:0.04,green:0.11,blue:0.06)]),
                startPoint:CGPoint(x:0,y:groundY), endPoint:CGPoint(x:0,y:h)))

            // Fairway trapezoid (receding perspective)
            var fw = Path()
            fw.move(to:CGPoint(x:0, y:groundY))
            fw.addLine(to:CGPoint(x:w*0.61, y:groundY))
            fw.addLine(to:CGPoint(x:w*0.48, y:h))
            fw.addLine(to:CGPoint(x:0, y:h))
            fw.closeSubpath()
            ctx.fill(fw, with:.linearGradient(
                Gradient(colors:[Color(red:0.17,green:0.38,blue:0.19),
                                  Color(red:0.12,green:0.26,blue:0.13)]),
                startPoint:CGPoint(x:0,y:groundY), endPoint:CGPoint(x:0,y:h)))

            // Ground grid lines
            for gy in [CGFloat(0.72), 0.82, 0.90, 0.97] {
                var gl = Path()
                gl.move(to:CGPoint(x:0, y:h*gy))
                gl.addLine(to:CGPoint(x:w*0.60, y:h*gy))
                ctx.stroke(gl, with:.color(Color.white.opacity(0.06)), lineWidth:0.7)
            }

            // Yardage stake markers
            for mx in [CGFloat(0.12), 0.22, 0.34, 0.46, 0.57] {
                let x = w*mx
                var m = Path(); m.move(to:CGPoint(x:x,y:groundY-1)); m.addLine(to:CGPoint(x:x,y:groundY+7))
                ctx.stroke(m, with:.color(Color.white.opacity(0.20)), lineWidth:0.8)
            }

            // ── Launch Monitor Device ─────────────────────────────────────
            let devX = w*0.70, devY = h*0.20, devW = w*0.22, devH = h*0.46

            // Device shadow
            var devShadow = Path()
            devShadow.addRoundedRect(in:CGRect(x:devX+5,y:devY+8,width:devW,height:devH),
                                     cornerSize:CGSize(width:8,height:8))
            ctx.fill(devShadow, with:.color(Color.black.opacity(0.30)))

            // Device body
            var devBody = Path()
            devBody.addRoundedRect(in:CGRect(x:devX,y:devY,width:devW,height:devH),
                                   cornerSize:CGSize(width:8,height:8))
            ctx.fill(devBody, with:.linearGradient(
                Gradient(colors:[Color(red:0.24,green:0.28,blue:0.34),
                                  Color(red:0.11,green:0.14,blue:0.18)]),
                startPoint:CGPoint(x:devX,y:devY), endPoint:CGPoint(x:devX,y:devY+devH)))
            ctx.stroke(devBody, with:.color(Color.white.opacity(0.20)), lineWidth:1)

            // Top edge highlight
            var topEdge = Path()
            topEdge.addRoundedRect(in:CGRect(x:devX+1,y:devY+1,width:devW-2,height:10),
                                   cornerSize:CGSize(width:7,height:7))
            ctx.fill(topEdge, with:.color(Color.white.opacity(0.08)))

            // Screen
            let scrX = devX+devW*0.10, scrY = devY+devH*0.11, scrW = devW*0.80, scrH = devH*0.46
            var screen = Path()
            screen.addRoundedRect(in:CGRect(x:scrX,y:scrY,width:scrW,height:scrH),
                                  cornerSize:CGSize(width:4,height:4))
            ctx.fill(screen, with:.linearGradient(
                Gradient(colors:[Color(red:0.04,green:0.14,blue:0.24),
                                  Color(red:0.02,green:0.08,blue:0.16)]),
                startPoint:CGPoint(x:scrX,y:scrY), endPoint:CGPoint(x:scrX,y:scrY+scrH)))
            ctx.stroke(screen, with:.color(TCTheme.sage.opacity(0.22)), lineWidth:0.8)

            // Screen: primary metric (carry) — gold wide line
            let m0Y = scrY + scrH*0.16
            var m0 = Path(); m0.move(to:CGPoint(x:scrX+scrW*0.10,y:m0Y)); m0.addLine(to:CGPoint(x:scrX+scrW*0.68,y:m0Y))
            ctx.stroke(m0, with:.color(TCTheme.gold.opacity(0.90)), lineWidth:2.2)
            // Value stub right
            var v0 = Path(); v0.move(to:CGPoint(x:scrX+scrW*0.72,y:m0Y)); v0.addLine(to:CGPoint(x:scrX+scrW*0.92,y:m0Y))
            ctx.stroke(v0, with:.color(TCTheme.goldLight.opacity(0.70)), lineWidth:1.5)

            // Secondary metric lines
            for i in 1...3 {
                let mY = scrY + scrH*(0.16 + CGFloat(i)*0.20)
                let mLen = scrW*(i==1 ? 0.44 : i==2 ? 0.38 : 0.50)
                var ml = Path(); ml.move(to:CGPoint(x:scrX+scrW*0.10,y:mY)); ml.addLine(to:CGPoint(x:scrX+scrW*0.10+mLen,y:mY))
                ctx.stroke(ml, with:.color(TCTheme.sage.opacity(0.40)), lineWidth:1.0)
                var vl = Path(); vl.move(to:CGPoint(x:scrX+scrW*0.72,y:mY)); vl.addLine(to:CGPoint(x:scrX+scrW*0.90,y:mY))
                ctx.stroke(vl, with:.color(Color.white.opacity(0.18)), lineWidth:0.8)
            }

            // Bar chart at bottom of screen
            let barsData: [(CGFloat,CGFloat)] = [(0.08,0.60),(0.22,0.85),(0.36,0.45),(0.50,0.95),(0.64,0.72),(0.78,0.55)]
            let barW: CGFloat = scrW*0.10, bBase = scrY+scrH*0.97
            for (bx, bh) in barsData {
                let bHeight = scrH*0.24*bh
                var bar = Path()
                bar.addRoundedRect(in:CGRect(x:scrX+scrW*bx,y:bBase-bHeight,width:barW,height:bHeight),
                                   cornerSize:CGSize(width:2,height:2))
                ctx.fill(bar, with:.color(TCTheme.sage.opacity(0.40+bh*0.28)))
            }

            // Device stand + base
            var stand = Path()
            stand.move(to:CGPoint(x:devX+devW*0.25,y:devY+devH))
            stand.addLine(to:CGPoint(x:devX+devW*0.75,y:devY+devH))
            stand.addLine(to:CGPoint(x:devX+devW*0.82,y:devY+devH+15))
            stand.addLine(to:CGPoint(x:devX+devW*0.18,y:devY+devH+15))
            stand.closeSubpath()
            ctx.fill(stand, with:.color(Color(red:0.15,green:0.18,blue:0.23)))
            var base = Path()
            base.addRoundedRect(in:CGRect(x:devX+devW*0.06,y:devY+devH+14,width:devW*0.88,height:6),
                                cornerSize:CGSize(width:2,height:2))
            ctx.fill(base, with:.color(Color(red:0.20,green:0.24,blue:0.29)))

            // ── Golf Ball on Tee ──────────────────────────────────────────
            let ballX = w*0.14, ballY = groundY-6, ballR: CGFloat = 6.5
            ctx.fill(Path(ellipseIn:CGRect(x:ballX-16,y:ballY-14,width:32,height:28)),
                     with:.radialGradient(Gradient(colors:[Color.white.opacity(0.09),.clear]),
                                          center:CGPoint(x:ballX,y:ballY), startRadius:0, endRadius:15))
            ctx.fill(Path(ellipseIn:CGRect(x:ballX-ballR,y:ballY-ballR,width:ballR*2,height:ballR*2)),
                     with:.linearGradient(Gradient(colors:[Color(white:0.98),Color(white:0.82)]),
                                          startPoint:CGPoint(x:ballX-ballR,y:ballY-ballR),
                                          endPoint:CGPoint(x:ballX+ballR,y:ballY+ballR)))
            var teeStick = Path()
            teeStick.move(to:CGPoint(x:ballX,y:ballY+ballR)); teeStick.addLine(to:CGPoint(x:ballX,y:groundY+1))
            ctx.stroke(teeStick, with:.color(Color(white:0.70)), lineWidth:1.5)

            // ── Shot Arc ──────────────────────────────────────────────────
            let aS = CGPoint(x:ballX,y:ballY), aC = CGPoint(x:w*0.36,y:h*0.09), aE = CGPoint(x:w*0.63,y:groundY+2)
            var arc = Path(); arc.move(to:aS); arc.addQuadCurve(to:aE, control:aC)
            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.10)), style:StrokeStyle(lineWidth:14,lineCap:.round))
            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.20)), style:StrokeStyle(lineWidth:7,lineCap:.round))
            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.35)), style:StrokeStyle(lineWidth:3,lineCap:.round))
            ctx.stroke(arc, with:.linearGradient(
                Gradient(stops:[.init(color:TCTheme.gold.opacity(0.80),location:0),
                                .init(color:TCTheme.goldLight,location:0.50),
                                .init(color:TCTheme.gold.opacity(0.55),location:1)]),
                startPoint:aS, endPoint:aE), style:StrokeStyle(lineWidth:1.8,lineCap:.round))

            // Arc dots
            for t in [CGFloat(0.15),0.30,0.50,0.70,0.86] {
                let bx = (1-t)*(1-t)*aS.x + 2*(1-t)*t*aC.x + t*t*aE.x
                let by = (1-t)*(1-t)*aS.y + 2*(1-t)*t*aC.y + t*t*aE.y
                let dr: CGFloat = 2.8
                ctx.fill(Path(ellipseIn:CGRect(x:bx-dr,y:by-dr,width:dr*2,height:dr*2)),
                         with:.color(TCTheme.goldLight.opacity(0.72)))
            }

            // Landing zone marker
            ctx.fill(Path(ellipseIn:CGRect(x:aE.x-4,y:aE.y-3,width:8,height:6)), with:.color(TCTheme.gold))
            ctx.stroke(Path(ellipseIn:CGRect(x:aE.x-17,y:aE.y-7,width:34,height:14)),
                       with:.color(TCTheme.gold.opacity(0.28)), lineWidth:1)
            ctx.stroke(Path(ellipseIn:CGRect(x:aE.x-29,y:aE.y-12,width:58,height:24)),
                       with:.color(TCTheme.gold.opacity(0.12)), lineWidth:0.8)

            // ── Stars ─────────────────────────────────────────────────────
            let stars: [(CGFloat,CGFloat,CGFloat)] = [
                (0.06,0.04,0.68),(0.20,0.02,0.50),(0.36,0.07,0.58),(0.51,0.03,0.44),
                (0.63,0.08,0.62),(0.77,0.01,0.52),(0.88,0.05,0.38),(0.10,0.13,0.34),
                (0.44,0.17,0.54),(0.68,0.11,0.42),(0.83,0.20,0.48),(0.28,0.22,0.38),
                (0.56,0.25,0.58),(0.91,0.16,0.33),(0.15,0.28,0.44)
            ]
            for (sx,sy,alpha) in stars {
                let sr: CGFloat = 1.0
                ctx.fill(Path(ellipseIn:CGRect(x:w*sx-sr,y:h*sy-sr,width:sr*2,height:sr*2)),
                         with:.color(Color.white.opacity(alpha)))
            }
        }
    }
}

// MARK: 2. Course Aerial Thumbnail ─────────────────────────────────────────
// Top-down aerial view, 4 style variants via seed parameter

struct TCCourseAerialThumbnail: View {
    var seed: Int = 0        // 0–3 style variants
    var showOverlay: Bool = false   // show course name on hover

    private var style: Int { ((seed % 4) + 4) % 4 }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let mid = CGPoint(x:w/2, y:h/2)

            // ── Background rough ──────────────────────────────────────────
            let roughColor: Color
            switch style {
            case 1: roughColor = Color(red:0.06,green:0.14,blue:0.08)   // Coastal dark
            case 2: roughColor = Color(red:0.12,green:0.18,blue:0.08)   // Links brown-green
            case 3: roughColor = Color(red:0.05,green:0.12,blue:0.06)   // Pine heavy shadow
            default: roughColor = Color(red:0.07,green:0.16,blue:0.09)  // Augusta
            }
            ctx.fill(Path(CGRect(origin:.zero,size:size)), with:.color(roughColor))

            // ── Fairway shape ─────────────────────────────────────────────
            let fairwayColor = Color(red:0.18,green:0.40,blue:0.20)

            switch style {
            case 0: // Augusta: gentle S-curve
                var fw = Path()
                fw.move(to:CGPoint(x:w*0.35,y:h*0.05)); fw.addLine(to:CGPoint(x:w*0.65,y:h*0.05))
                fw.addCurve(to:CGPoint(x:w*0.68,y:h*0.95),
                            control1:CGPoint(x:w*0.70,y:h*0.35), control2:CGPoint(x:w*0.55,y:h*0.55))
                fw.addLine(to:CGPoint(x:w*0.42,y:h*0.95))
                fw.addCurve(to:CGPoint(x:w*0.35,y:h*0.05),
                            control1:CGPoint(x:w*0.30,y:h*0.60), control2:CGPoint(x:w*0.25,y:h*0.35))
                fw.closeSubpath()
                ctx.fill(fw, with:.color(fairwayColor))

            case 1: // Pebble: straight with water right
                var fw = Path()
                fw.addRoundedRect(in:CGRect(x:w*0.30,y:h*0.05,width:w*0.38,height:h*0.90),
                                  cornerSize:CGSize(width:w*0.10,height:w*0.10))
                ctx.fill(fw, with:.color(fairwayColor))
                // Water on right
                var water = Path()
                water.addRoundedRect(in:CGRect(x:w*0.76,y:h*0.15,width:w*0.22,height:h*0.60),
                                     cornerSize:CGSize(width:8,height:8))
                ctx.fill(water, with:.color(Color(red:0.06,green:0.14,blue:0.28)))
                ctx.stroke(water, with:.color(Color(red:0.12,green:0.28,blue:0.48).opacity(0.40)), lineWidth:1)

            case 2: // Bandon: wide links, dogleg left
                var fw = Path()
                fw.move(to:CGPoint(x:w*0.25,y:h*0.05)); fw.addLine(to:CGPoint(x:w*0.75,y:h*0.05))
                fw.addCurve(to:CGPoint(x:w*0.65,y:h*0.95),
                            control1:CGPoint(x:w*0.80,y:h*0.40), control2:CGPoint(x:w*0.68,y:h*0.68))
                fw.addLine(to:CGPoint(x:w*0.35,y:h*0.95))
                fw.addCurve(to:CGPoint(x:w*0.25,y:h*0.05),
                            control1:CGPoint(x:w*0.22,y:h*0.68), control2:CGPoint(x:w*0.18,y:h*0.40))
                fw.closeSubpath()
                ctx.fill(fw, with:.color(Color(red:0.20,green:0.44,blue:0.22)))

            case 3: // Pine Valley: irregular, waste areas
                var fw = Path()
                fw.move(to:CGPoint(x:w*0.38,y:h*0.05)); fw.addLine(to:CGPoint(x:w*0.62,y:h*0.05))
                fw.addCurve(to:CGPoint(x:w*0.55,y:h*0.48),
                            control1:CGPoint(x:w*0.72,y:h*0.22), control2:CGPoint(x:w*0.65,y:h*0.38))
                fw.addLine(to:CGPoint(x:w*0.72,y:h*0.48)); fw.addLine(to:CGPoint(x:w*0.68,y:h*0.95))
                fw.addLine(to:CGPoint(x:w*0.32,y:h*0.95)); fw.addLine(to:CGPoint(x:w*0.28,y:h*0.48))
                fw.addLine(to:CGPoint(x:w*0.45,y:h*0.48))
                fw.addCurve(to:CGPoint(x:w*0.38,y:h*0.05),
                            control1:CGPoint(x:w*0.32,y:h*0.38), control2:CGPoint(x:w*0.28,y:h*0.22))
                fw.closeSubpath()
                ctx.fill(fw, with:.color(fairwayColor))
                // Waste areas (sand)
                for rect in [CGRect(x:w*0.06,y:h*0.20,width:w*0.22,height:h*0.35),
                              CGRect(x:w*0.72,y:h*0.55,width:w*0.20,height:h*0.25)] {
                    var waste = Path(); waste.addEllipse(in:rect)
                    ctx.fill(waste, with:.color(Color(red:0.52,green:0.44,blue:0.30).opacity(0.55)))
                }

            default: break
            }

            // ── Sand bunkers ──────────────────────────────────────────────
            let bunkerColor = Color(red:0.58,green:0.50,blue:0.34).opacity(0.80)
            switch style {
            case 0: // Augusta: symmetrical pair flanking approach
                for bx in [CGFloat(0.20), 0.72] {
                    var b = Path(); b.addEllipse(in:CGRect(x:w*bx,y:h*0.38,width:w*0.14,height:h*0.10))
                    ctx.fill(b, with:.color(bunkerColor))
                }
                var g2 = Path(); g2.addEllipse(in:CGRect(x:w*0.36,y:h*0.15,width:w*0.10,height:h*0.07))
                ctx.fill(g2, with:.color(bunkerColor))

            case 1: // Pebble: bunker left of green
                var b = Path(); b.addEllipse(in:CGRect(x:w*0.20,y:h*0.10,width:w*0.16,height:h*0.12))
                ctx.fill(b, with:.color(bunkerColor))

            case 2: // Bandon: scattered
                for (bx,by,bw,bh) in [(CGFloat(0.08),0.30,0.14,0.08),(0.80,0.50,0.12,0.09)] {
                    var b = Path(); b.addEllipse(in:CGRect(x:w*bx,y:h*by,width:w*bw,height:h*bh))
                    ctx.fill(b, with:.color(Color(red:0.50,green:0.44,blue:0.30).opacity(0.70)))
                }

            case 3: // Pine Valley: nothing extra needed (waste areas done above)
                var b = Path(); b.addEllipse(in:CGRect(x:w*0.36,y:h*0.66,width:w*0.12,height:h*0.08))
                ctx.fill(b, with:.color(bunkerColor))

            default: break
            }

            // ── Green (at top / far end) ──────────────────────────────────
            let greenR: CGFloat = min(w,h) * 0.12
            let greenCenter: CGPoint
            switch style {
            case 0: greenCenter = CGPoint(x:w*0.50,y:h*0.10)
            case 1: greenCenter = CGPoint(x:w*0.48,y:h*0.11)
            case 2: greenCenter = CGPoint(x:w*0.50,y:h*0.09)
            case 3: greenCenter = CGPoint(x:w*0.50,y:h*0.11)
            default: greenCenter = CGPoint(x:w*0.50,y:h*0.10)
            }
            ctx.fill(Path(ellipseIn:CGRect(x:greenCenter.x-greenR,y:greenCenter.y-greenR*0.70,
                                            width:greenR*2,height:greenR*1.40)),
                     with:.color(Color(red:0.24,green:0.56,blue:0.26)))

            // Pin
            var pin = Path()
            pin.move(to:CGPoint(x:greenCenter.x,y:greenCenter.y-greenR*0.55))
            pin.addLine(to:CGPoint(x:greenCenter.x,y:greenCenter.y+greenR*0.40))
            ctx.stroke(pin, with:.color(Color.white.opacity(0.85)), lineWidth:1)
            // Flag
            var flag = Path()
            flag.move(to:CGPoint(x:greenCenter.x,y:greenCenter.y-greenR*0.55))
            flag.addLine(to:CGPoint(x:greenCenter.x+greenR*0.60,y:greenCenter.y-greenR*0.30))
            flag.addLine(to:CGPoint(x:greenCenter.x,y:greenCenter.y-greenR*0.08))
            flag.closeSubpath()
            ctx.fill(flag, with:.color(TCTheme.gold))

            // ── Trees ─────────────────────────────────────────────────────
            let treeColor = Color(red:0.05,green:0.13,blue:0.06)
            switch style {
            case 0: // Augusta: heavy tree lines both sides
                for ty in stride(from: h*0.10, through: h*0.85, by: h*0.12) {
                    var t = Path(); t.addEllipse(in:CGRect(x:-w*0.01,y:ty,width:w*0.26,height:h*0.08))
                    ctx.fill(t, with:.color(treeColor))
                    var t2 = Path(); t2.addEllipse(in:CGRect(x:w*0.74,y:ty,width:w*0.28,height:h*0.08))
                    ctx.fill(t2, with:.color(treeColor))
                }
            case 1: // Pebble: sparse left
                for ty in [CGFloat(0.20),0.42,0.65,0.80] {
                    var t = Path(); t.addEllipse(in:CGRect(x:0,y:h*ty,width:w*0.22,height:h*0.10))
                    ctx.fill(t, with:.color(treeColor))
                }
            case 2: // Bandon: no trees (links)
                break
            case 3: // Pine Valley: dense trees everywhere
                for ty in stride(from: h*0.08, through: h*0.90, by: h*0.10) {
                    var tl = Path(); tl.addEllipse(in:CGRect(x:-w*0.02,y:ty,width:w*0.30,height:h*0.09))
                    ctx.fill(tl, with:.color(treeColor))
                    var tr = Path(); tr.addEllipse(in:CGRect(x:w*0.70,y:ty,width:w*0.32,height:h*0.09))
                    ctx.fill(tr, with:.color(treeColor))
                }
            default: break
            }

            // ── Overall tint overlay ──────────────────────────────────────
            // Gives a subtle aerial photography feel
            ctx.fill(Path(CGRect(origin:.zero,size:size)),
                     with:.linearGradient(
                        Gradient(colors:[Color.black.opacity(0.08), .clear, Color.black.opacity(0.12)]),
                        startPoint:.zero, endPoint:CGPoint(x:0,y:h)))

            // ── Gold shot arc marker ──────────────────────────────────────
            let teePt = CGPoint(x:w*0.50,y:h*0.90)
            let midPt = mid
            var sArc = Path(); sArc.move(to:teePt)
            sArc.addQuadCurve(to:greenCenter, control:midPt)
            ctx.stroke(sArc, with:.color(TCTheme.gold.opacity(0.45)),
                       style:StrokeStyle(lineWidth:1.2,lineCap:.round,dash:[3,2]))
            let _ = mid // suppress warning
        }
    }
}

// MARK: 3. Dispersion Fairway Graphic ──────────────────────────────────────
// Large, premium aerial fairway with detailed dispersion visualization

struct TCDispersionFairwayGraphic: View {
    var dots: [(x: CGFloat, y: CGFloat)] = []
    var showRings: Bool = true

    var body: some View {
        let useDots = dots
        Canvas { ctx, size in
            let w = size.width, h = size.height, mx = w/2

            // Background rough
            ctx.fill(Path(CGRect(origin:.zero,size:size)),
                     with:.linearGradient(
                        Gradient(colors:[Color(red:0.06,green:0.14,blue:0.08),
                                          Color(red:0.04,green:0.10,blue:0.05)]),
                        startPoint:.zero, endPoint:CGPoint(x:0,y:h)))

            // Rough side bands
            let fw: CGFloat = w*0.34
            var roughL = Path(); roughL.addRect(CGRect(x:0,y:0,width:mx-fw,height:h))
            var roughR = Path(); roughR.addRect(CGRect(x:mx+fw,y:0,width:mx-fw,height:h))
            ctx.fill(roughL, with:.color(Color(red:0.05,green:0.11,blue:0.06)))
            ctx.fill(roughR, with:.color(Color(red:0.05,green:0.11,blue:0.06)))

            // Fairway
            var fairway = Path()
            fairway.addRect(CGRect(x:mx-fw,y:0,width:fw*2,height:h))
            ctx.fill(fairway, with:.linearGradient(
                Gradient(colors:[Color(red:0.16,green:0.36,blue:0.18),
                                  Color(red:0.13,green:0.28,blue:0.14)]),
                startPoint:.zero, endPoint:CGPoint(x:0,y:h)))

            // Tree clusters
            let treeClumps: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
                (0.01,0.05,0.18,0.25),(0.80,0.05,0.19,0.22),
                (0.00,0.35,0.16,0.28),(0.84,0.38,0.16,0.25),
                (0.02,0.68,0.17,0.30),(0.81,0.70,0.17,0.28)
            ]
            for (tx,ty,tw,th) in treeClumps {
                var t = Path(); t.addEllipse(in:CGRect(x:w*tx,y:h*ty,width:w*tw,height:h*th))
                ctx.fill(t, with:.color(Color(red:0.04,green:0.10,blue:0.05)))
            }

            // Sand bunkers in rough
            let bunkers: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
                (0.06,0.25,0.12,0.08),(0.82,0.28,0.11,0.07),
                (0.05,0.60,0.13,0.07),(0.83,0.62,0.10,0.07)
            ]
            for (bx,by,bw,bh) in bunkers {
                var b = Path(); b.addEllipse(in:CGRect(x:w*bx,y:h*by,width:w*bw,height:h*bh))
                ctx.fill(b, with:.color(Color(red:0.50,green:0.44,blue:0.30).opacity(0.55)))
            }

            // Green at top
            let gR: CGFloat = w*0.10
            ctx.fill(Path(ellipseIn:CGRect(x:mx-gR,y:h*0.04-gR*0.65,width:gR*2,height:gR*1.30)),
                     with:.color(Color(red:0.22,green:0.54,blue:0.24)))
            // Pin
            var pin = Path()
            pin.move(to:CGPoint(x:mx,y:h*0.04-gR*0.58)); pin.addLine(to:CGPoint(x:mx,y:h*0.04+gR*0.38))
            ctx.stroke(pin, with:.color(Color.white.opacity(0.80)), lineWidth:1)
            var flag = Path()
            flag.move(to:CGPoint(x:mx,y:h*0.04-gR*0.58))
            flag.addLine(to:CGPoint(x:mx+gR*0.55,y:h*0.04-gR*0.34))
            flag.addLine(to:CGPoint(x:mx,y:h*0.04-gR*0.10))
            flag.closeSubpath()
            ctx.fill(flag, with:.color(TCTheme.gold))

            // Tee area at bottom
            ctx.fill(Path(ellipseIn:CGRect(x:mx-w*0.06,y:h*0.91,width:w*0.12,height:h*0.06)),
                     with:.color(Color(red:0.22,green:0.50,blue:0.24)))

            // ── Dispersion rings ──────────────────────────────────────────
            if showRings {
                let ringCenter = CGPoint(x:mx, y:h*0.52)
                for (ri, r) in [CGFloat(0.08),0.16,0.24,0.32,0.40].enumerated() {
                    let rx = w*r, ry = h*r*0.55
                    let alpha: CGFloat = ri == 2 ? 0.22 : 0.12
                    ctx.stroke(Path(ellipseIn:CGRect(x:ringCenter.x-rx,y:ringCenter.y-ry,width:rx*2,height:ry*2)),
                               with:.color(Color.white.opacity(alpha)), lineWidth: ri==2 ? 1.5 : 0.8)
                }
            }

            // Centerline
            var cl = Path()
            cl.move(to:CGPoint(x:mx,y:h*0.04)); cl.addLine(to:CGPoint(x:mx,y:h*0.97))
            ctx.stroke(cl, with:.color(TCTheme.sage.opacity(0.20)),
                       style:StrokeStyle(lineWidth:0.8,dash:[5,4]))

            // ── Ball dots (real shot data) ────────────────────────────────
            for d in useDots {
                ctx.fill(Path(ellipseIn:CGRect(x:d.x*w-4.5,y:d.y*h-4.5,width:9,height:9)),
                         with:.color(Color.white.opacity(0.88)))
                ctx.fill(Path(ellipseIn:CGRect(x:d.x*w-8,y:d.y*h-8,width:16,height:16)),
                         with:.color(TCTheme.cyan.opacity(0.18)))
            }

            // Mean dot — only when real data present
            if !useDots.isEmpty {
                let meanX = useDots.map { $0.x }.reduce(0, +) / CGFloat(useDots.count)
                let meanY = useDots.map { $0.y }.reduce(0, +) / CGFloat(useDots.count)
                ctx.fill(Path(ellipseIn:CGRect(x:w*meanX-7,y:h*meanY-7,width:14,height:14)),
                         with:.color(TCTheme.sage))
                ctx.stroke(Path(ellipseIn:CGRect(x:w*meanX-7,y:h*meanY-7,width:14,height:14)),
                           with:.color(.white.opacity(0.60)), lineWidth:1.5)
            }

            // ── Distance labels (as lines) ────────────────────────────────
            for (labelY, labelLen) in [(CGFloat(0.28),CGFloat(0.08)),(0.50,0.08),(0.72,0.08)] {
                var lLine = Path()
                lLine.move(to:CGPoint(x:mx-fw+8,y:h*labelY))
                lLine.addLine(to:CGPoint(x:mx-fw+8+w*labelLen,y:h*labelY))
                ctx.stroke(lLine, with:.color(TCTheme.gold.opacity(0.30)), lineWidth:0.8)
            }
        }
    }
}

// MARK: 4. Golf Bag Illustration ───────────────────────────────────────────
// Premium dark golf bag with clubs visible

struct TCGolfBagIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // ── Bag body ──────────────────────────────────────────────────
            let bagLeft  = w*0.18, bagRight = w*0.82
            let bagTop   = h*0.32, bagBot   = h*0.96
            let bagW = bagRight - bagLeft

            // Shadow
            var shadow = Path()
            shadow.addRoundedRect(in:CGRect(x:bagLeft+4,y:bagTop+8,width:bagW,height:bagBot-bagTop),
                                  cornerSize:CGSize(width:bagW*0.22,height:bagW*0.22))
            ctx.fill(shadow, with:.color(Color.black.opacity(0.28)))

            // Main body
            var body2 = Path()
            body2.addRoundedRect(in:CGRect(x:bagLeft,y:bagTop,width:bagW,height:bagBot-bagTop),
                                 cornerSize:CGSize(width:bagW*0.22,height:bagW*0.22))
            ctx.fill(body2, with:.linearGradient(
                Gradient(colors:[Color(red:0.14,green:0.17,blue:0.22),
                                  Color(red:0.08,green:0.10,blue:0.14)]),
                startPoint:CGPoint(x:bagLeft,y:bagTop), endPoint:CGPoint(x:bagRight,y:bagBot)))
            ctx.stroke(body2, with:.color(Color.white.opacity(0.14)), lineWidth:1)

            // Left edge highlight
            var leftHighlight = Path()
            leftHighlight.addRoundedRect(in:CGRect(x:bagLeft,y:bagTop+8,width:bagW*0.06,height:bagBot-bagTop-16),
                                         cornerSize:CGSize(width:4,height:4))
            ctx.fill(leftHighlight, with:.color(Color.white.opacity(0.07)))

            // ── Side pockets ──────────────────────────────────────────────
            // Large pocket (lower)
            var pkt1 = Path()
            pkt1.addRoundedRect(in:CGRect(x:bagLeft+bagW*0.08,y:bagTop+(bagBot-bagTop)*0.54,
                                          width:bagW*0.84,height:(bagBot-bagTop)*0.32),
                                cornerSize:CGSize(width:6,height:6))
            ctx.fill(pkt1, with:.color(Color(red:0.10,green:0.12,blue:0.17)))
            ctx.stroke(pkt1, with:.color(Color.white.opacity(0.10)), lineWidth:0.8)
            // Pocket zipper line
            var zip1 = Path()
            zip1.move(to:CGPoint(x:bagLeft+bagW*0.12,y:bagTop+(bagBot-bagTop)*0.56))
            zip1.addLine(to:CGPoint(x:bagLeft+bagW*0.88,y:bagTop+(bagBot-bagTop)*0.56))
            ctx.stroke(zip1, with:.color(TCTheme.gold.opacity(0.35)),
                       style:StrokeStyle(lineWidth:0.8,dash:[2,2]))

            // Small pocket (upper-side)
            var pkt2 = Path()
            pkt2.addRoundedRect(in:CGRect(x:bagLeft+bagW*0.08,y:bagTop+(bagBot-bagTop)*0.36,
                                          width:bagW*0.84,height:(bagBot-bagTop)*0.15),
                                cornerSize:CGSize(width:5,height:5))
            ctx.fill(pkt2, with:.color(Color(red:0.10,green:0.12,blue:0.17)))
            ctx.stroke(pkt2, with:.color(Color.white.opacity(0.10)), lineWidth:0.8)

            // Gold accent stripe
            var stripe = Path()
            stripe.addRect(CGRect(x:bagLeft,y:bagTop+(bagBot-bagTop)*0.34,width:bagW,height:2))
            ctx.fill(stripe, with:.color(TCTheme.gold.opacity(0.40)))

            // ── Hood / Top collar ─────────────────────────────────────────
            let hoodH: CGFloat = h*0.16
            var hood = Path()
            hood.addRoundedRect(in:CGRect(x:bagLeft-2,y:bagTop-hoodH,width:bagW+4,height:hoodH+12),
                                cornerSize:CGSize(width:bagW*0.20,height:bagW*0.20))
            ctx.fill(hood, with:.linearGradient(
                Gradient(colors:[Color(red:0.20,green:0.24,blue:0.30),
                                  Color(red:0.13,green:0.16,blue:0.22)]),
                startPoint:CGPoint(x:bagLeft,y:bagTop-hoodH), endPoint:CGPoint(x:bagLeft,y:bagTop+12)))
            ctx.stroke(hood, with:.color(Color.white.opacity(0.18)), lineWidth:1)

            // ── Club shafts (visible above hood) ─────────────────────────
            let clubXs: [CGFloat] = [0.26,0.35,0.44,0.54,0.63,0.72]
            let clubLen = h*0.30
            let clubColors: [Color] = [
                Color(red:0.65,green:0.65,blue:0.70), // driver - silver
                Color(red:0.60,green:0.60,blue:0.65),
                Color(red:0.55,green:0.55,blue:0.62),
                Color(red:0.52,green:0.52,blue:0.60),
                Color(red:0.50,green:0.50,blue:0.58),
                Color(red:0.48,green:0.50,blue:0.56)  // putter
            ]
            for (i, cx) in clubXs.enumerated() {
                let topY = bagTop - hoodH - clubLen
                let botY = bagTop - hoodH + 8
                // Shaft
                var shaft = Path()
                shaft.move(to:CGPoint(x:w*cx,y:topY))
                shaft.addLine(to:CGPoint(x:w*cx+w*0.01,y:botY))
                ctx.stroke(shaft, with:.color(clubColors[i].opacity(0.80)), lineWidth:2.5)
                // Club head (different per type)
                let headX = w*cx + w*0.01, headY = topY - 4
                if i == 0 { // Driver head - larger oval
                    ctx.fill(Path(ellipseIn:CGRect(x:headX-7,y:headY-5,width:14,height:10)),
                             with:.color(clubColors[i]))
                    ctx.stroke(Path(ellipseIn:CGRect(x:headX-7,y:headY-5,width:14,height:10)),
                               with:.color(TCTheme.gold.opacity(0.40)), lineWidth:0.8)
                } else if i < 4 { // Irons - narrow head
                    var head = Path()
                    head.addRect(CGRect(x:headX-4,y:headY-3,width:8,height:5))
                    ctx.fill(head, with:.color(clubColors[i]))
                } else { // Wedge/putter
                    var head = Path()
                    head.addRoundedRect(in:CGRect(x:headX-5,y:headY-4,width:10,height:7),
                                        cornerSize:CGSize(width:2,height:2))
                    ctx.fill(head, with:.color(clubColors[i]))
                }
                let _ = i
            }

            // ── Carry handle ──────────────────────────────────────────────
            var handle = Path()
            handle.addArc(center:CGPoint(x:w/2,y:bagTop-hoodH-4), radius:w*0.15,
                          startAngle:.degrees(220), endAngle:.degrees(320), clockwise:false)
            ctx.stroke(handle, with:.linearGradient(
                Gradient(colors:[Color(red:0.40,green:0.44,blue:0.50),
                                  Color(red:0.24,green:0.27,blue:0.33)]),
                startPoint:CGPoint(x:w*0.35,y:bagTop-hoodH),
                endPoint:CGPoint(x:w*0.65,y:bagTop-hoodH)),
                       style:StrokeStyle(lineWidth:5,lineCap:.round))

            // ── Stand legs ────────────────────────────────────────────────
            let legTop = bagBot - (bagBot-bagTop)*0.20
            for lx in [CGFloat(0.30), 0.70] {
                var leg = Path()
                leg.move(to:CGPoint(x:w*lx,y:legTop))
                leg.addLine(to:CGPoint(x:w*lx+(lx<0.5 ? -w*0.10 : w*0.10),y:bagBot+10))
                ctx.stroke(leg, with:.color(Color(red:0.25,green:0.28,blue:0.34)), lineWidth:3)
            }
        }
    }
}

// MARK: 5. Mode Illustrations ──────────────────────────────────────────────
// Custom illustrations for Play screen mode cards

struct TCModeRangeIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, mx = w/2, my = h/2
            ctx.fill(Path(CGRect(origin:.zero,size:size)), with:.color(TCTheme.cyan.opacity(0.06)))
            // Concentric target rings
            for (i, r) in [CGFloat(0.45),0.35,0.24,0.15,0.07].enumerated() {
                let R = min(w,h)*r
                let alpha: CGFloat = i == 4 ? 0.90 : 0.30 + CGFloat(i)*0.10
                ctx.stroke(Path(ellipseIn:CGRect(x:mx-R,y:my-R,width:R*2,height:R*2)),
                           with:.color(TCTheme.cyan.opacity(alpha)), lineWidth: i==4 ? 2 : 1)
            }
            // Crosshairs
            for (from, to) in [(CGPoint(x:mx,y:0),CGPoint(x:mx,y:h)),
                                (CGPoint(x:0,y:my),CGPoint(x:w,y:my))] {
                var l = Path(); l.move(to:from); l.addLine(to:to)
                ctx.stroke(l, with:.color(TCTheme.cyan.opacity(0.20)), lineWidth:0.6)
            }
            // Center gold dot
            ctx.fill(Path(ellipseIn:CGRect(x:mx-5,y:my-5,width:10,height:10)),
                     with:.color(TCTheme.gold))
            ctx.fill(Path(ellipseIn:CGRect(x:mx-10,y:my-10,width:20,height:20)),
                     with:.color(TCTheme.gold.opacity(0.20)))
            // Mini shot arc
            var arc = Path()
            arc.move(to:CGPoint(x:mx-w*0.30,y:my+h*0.28))
            arc.addQuadCurve(to:CGPoint(x:mx+w*0.20,y:my+h*0.25),
                             control:CGPoint(x:mx-w*0.05,y:my-h*0.25))
            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.55)),
                       style:StrokeStyle(lineWidth:1.5,lineCap:.round))
        }
    }
}

struct TCModeSimIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin:.zero,size:size)), with:.color(TCTheme.gold.opacity(0.05)))
            // Monitor screen
            let scrX = w*0.05, scrY = h*0.08, scrW = w*0.90, scrH = h*0.58
            var screen = Path()
            screen.addRoundedRect(in:CGRect(x:scrX,y:scrY,width:scrW,height:scrH),
                                  cornerSize:CGSize(width:8,height:8))
            ctx.fill(screen, with:.linearGradient(
                Gradient(colors:[Color(red:0.04,green:0.14,blue:0.08),
                                  Color(red:0.02,green:0.08,blue:0.04)]),
                startPoint:CGPoint(x:scrX,y:scrY), endPoint:CGPoint(x:scrX,y:scrY+scrH)))
            ctx.stroke(screen, with:.color(TCTheme.gold.opacity(0.35)), lineWidth:1.5)
            // Course on screen: fairway
            var fw = Path()
            fw.addRoundedRect(in:CGRect(x:scrX+scrW*0.20,y:scrY+scrH*0.10,
                                        width:scrW*0.60,height:scrH*0.80),
                              cornerSize:CGSize(width:scrW*0.06,height:scrW*0.06))
            ctx.fill(fw, with:.color(Color(red:0.16,green:0.36,blue:0.18)))
            // Screen arc
            var arc = Path()
            arc.move(to:CGPoint(x:scrX+scrW*0.28,y:scrY+scrH*0.85))
            arc.addQuadCurve(to:CGPoint(x:scrX+scrW*0.72,y:scrY+scrH*0.30),
                             control:CGPoint(x:scrX+scrW*0.50,y:scrY+scrH*0.05))
            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.65)),
                       style:StrokeStyle(lineWidth:1.5,lineCap:.round))
            // Monitor stand
            var stand = Path()
            stand.move(to:CGPoint(x:w*0.40,y:scrY+scrH))
            stand.addLine(to:CGPoint(x:w*0.60,y:scrY+scrH))
            stand.addLine(to:CGPoint(x:w*0.65,y:scrY+scrH+h*0.12))
            stand.addLine(to:CGPoint(x:w*0.35,y:scrY+scrH+h*0.12))
            stand.closeSubpath()
            ctx.fill(stand, with:.color(Color(red:0.18,green:0.22,blue:0.28)))
            var base = Path()
            base.addRoundedRect(in:CGRect(x:w*0.20,y:scrY+scrH+h*0.11,width:w*0.60,height:h*0.05),
                                cornerSize:CGSize(width:4,height:4))
            ctx.fill(base, with:.color(Color(red:0.22,green:0.26,blue:0.32)))
            // Mat/floor
            var mat = Path()
            mat.addRoundedRect(in:CGRect(x:0,y:scrY+scrH+h*0.22,width:w,height:h*0.16),
                               cornerSize:CGSize(width:4,height:4))
            ctx.fill(mat, with:.color(Color(red:0.14,green:0.18,blue:0.22)))
            ctx.stroke(mat, with:.color(TCTheme.gold.opacity(0.20)), lineWidth:0.8)
        }
    }
}

struct TCModeCourseIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, mx = w/2
            ctx.fill(Path(CGRect(origin:.zero,size:size)), with:.color(TCTheme.sage.opacity(0.06)))
            // Aerial green
            let gR: CGFloat = min(w,h)*0.28
            ctx.fill(Path(ellipseIn:CGRect(x:mx-gR,y:h*0.12,width:gR*2,height:gR*1.10)),
                     with:.color(Color(red:0.20,green:0.52,blue:0.22)))
            // Fairway
            var fw = Path()
            fw.move(to:CGPoint(x:mx-w*0.18,y:h*0.30)); fw.addLine(to:CGPoint(x:mx+w*0.18,y:h*0.30))
            fw.addLine(to:CGPoint(x:mx+w*0.24,y:h)); fw.addLine(to:CGPoint(x:mx-w*0.24,y:h))
            fw.closeSubpath()
            ctx.fill(fw, with:.color(Color(red:0.16,green:0.38,blue:0.18)))
            // Pin
            var pin = Path()
            pin.move(to:CGPoint(x:mx,y:h*0.15)); pin.addLine(to:CGPoint(x:mx,y:h*0.52))
            ctx.stroke(pin, with:.color(Color.white.opacity(0.90)), lineWidth:1.5)
            var flag = Path()
            flag.move(to:CGPoint(x:mx,y:h*0.15))
            flag.addLine(to:CGPoint(x:mx+w*0.16,y:h*0.26))
            flag.addLine(to:CGPoint(x:mx,y:h*0.36))
            flag.closeSubpath()
            ctx.fill(flag, with:.color(TCTheme.gold))
            // Distance rings
            for r in [CGFloat(0.36),0.50,0.65] {
                let R = min(w,h)*r
                ctx.stroke(Path(ellipseIn:CGRect(x:mx-R,y:h*0.67-R*0.55,width:R*2,height:R*1.10)),
                           with:.color(Color.white.opacity(0.12)), lineWidth:0.8)
            }
            // Yardage arc
            var arc = Path()
            arc.move(to:CGPoint(x:mx,y:h*0.92))
            arc.addQuadCurve(to:CGPoint(x:mx,y:h*0.35), control:CGPoint(x:mx+w*0.30,y:h*0.60))
            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.50)),
                       style:StrokeStyle(lineWidth:1.5,lineCap:.round,dash:[4,3]))
        }
    }
}

// MARK: 6. Shot Arc Thumbnail (enhanced) ───────────────────────────────────
// Used in Past Sessions, Locker saved shots

struct TCShotArcThumbPremium: View {
    var yards: Int = 245
    var ballSpeed: Int = 152
    var isDriver: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // Background: dark fairway
            ctx.fill(Path(CGRect(origin:.zero,size:size)),
                     with:.linearGradient(
                        Gradient(colors:[Color(red:0.02,green:0.08,blue:0.12),
                                          Color(red:0.04,green:0.12,blue:0.06)]),
                        startPoint:.zero, endPoint:CGPoint(x:0,y:h)))

            // Ground
            var ground = Path()
            ground.addRect(CGRect(x:0,y:h*0.72,width:w,height:h*0.28))
            ctx.fill(ground, with:.color(Color(red:0.10,green:0.22,blue:0.11)))

            // Arc (higher peak for driver)
            let peakY: CGFloat = isDriver ? h*0.08 : h*0.15
            let aS = CGPoint(x:w*0.08,y:h*0.72)
            let aC = CGPoint(x:w*0.50,y:peakY)
            let aE = CGPoint(x:w*0.92,y:h*0.72)
            var arc = Path(); arc.move(to:aS); arc.addQuadCurve(to:aE,control:aC)

            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.14)), style:StrokeStyle(lineWidth:8,lineCap:.round))
            ctx.stroke(arc, with:.color(TCTheme.gold.opacity(0.28)), style:StrokeStyle(lineWidth:4,lineCap:.round))
            ctx.stroke(arc, with:.color(TCTheme.goldLight.opacity(0.80)), style:StrokeStyle(lineWidth:1.5,lineCap:.round))

            // Peak dot (apogee)
            ctx.fill(Path(ellipseIn:CGRect(x:w*0.50-3,y:peakY-3,width:6,height:6)),
                     with:.color(TCTheme.goldLight))

            // Landing dot
            ctx.fill(Path(ellipseIn:CGRect(x:aE.x-3.5,y:aE.y-2.5,width:7,height:5)),
                     with:.color(TCTheme.gold))
        }
    }
}

// MARK: 7. Round Map Thumbnail ─────────────────────────────────────────────
// Compact top-down view for activity feed / past sessions round card

struct TCRoundThumbnail: View {
    var seed: Int = 0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, mx = w/2

            // Dark background
            ctx.fill(Path(CGRect(origin:.zero,size:size)),
                     with:.color(Color(red:0.04,green:0.10,blue:0.06)))

            // Simplified aerial: rough + fairway
            let fw: CGFloat = w*0.38
            var fair = Path()
            fair.addRect(CGRect(x:mx-fw,y:0,width:fw*2,height:h))
            ctx.fill(fair, with:.color(Color(red:0.14,green:0.30,blue:0.15)))

            // Green
            let gR: CGFloat = w*0.14
            ctx.fill(Path(ellipseIn:CGRect(x:mx-gR,y:h*0.06,width:gR*2,height:gR*1.20)),
                     with:.color(Color(red:0.20,green:0.52,blue:0.22)))

            // Pin
            var pin = Path(); pin.move(to:CGPoint(x:mx,y:h*0.08)); pin.addLine(to:CGPoint(x:mx,y:h*0.35))
            ctx.stroke(pin, with:.color(Color.white.opacity(0.80)), lineWidth:1)
            var flag = Path(); flag.move(to:CGPoint(x:mx,y:h*0.08))
            flag.addLine(to:CGPoint(x:mx+gR*0.80,y:h*0.18))
            flag.addLine(to:CGPoint(x:mx,y:h*0.27))
            flag.closeSubpath()
            ctx.fill(flag, with:.color(TCTheme.gold))

            // Score overlay ring
            let sx = w*0.78, sy = h*0.76, sr: CGFloat = min(w,h)*0.16
            ctx.fill(Path(ellipseIn:CGRect(x:sx-sr,y:sy-sr,width:sr*2,height:sr*2)),
                     with:.color(Color(red:0.02,green:0.06,blue:0.12).opacity(0.80)))
            ctx.stroke(Path(ellipseIn:CGRect(x:sx-sr,y:sy-sr,width:sr*2,height:sr*2)),
                       with:.color(TCTheme.gold.opacity(0.60)), lineWidth:1.5)
        }
    }
}
