import SwiftUI

/// Kitsune that grows one tail per ninth of a focus session. Drawn in a 100×100 unit space.
struct NineTailFox: View {
    let progress: Double
    let resting: Bool
    let isRunning: Bool

    private static let tailCount = 9
    private static let fur = Color(red: 0.98, green: 0.55, blue: 0.2)
    private static let furLight = Color(red: 1, green: 0.75, blue: 0.4)
    private static let cream = Color(red: 1, green: 0.95, blue: 0.86)
    private static let ink = Color(red: 0.12, green: 0.08, blue: 0.06)

    var body: some View {
        // Animates only while the timer runs; static otherwise.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isRunning)) { context in
            Canvas { ctx, size in
                ctx.scaleBy(x: size.width / 100, y: size.height / 100)
                let time = context.date.timeIntervalSinceReferenceDate
                drawTails(&ctx, time: time)
                drawBody(&ctx)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Tails fan out from the centre; rank 0 (centre) appears first, the outer pair last.
    private func drawTails(_ ctx: inout GraphicsContext, time: TimeInterval) {
        let center = Self.tailCount / 2
        let tails = (0..<Self.tailCount).sorted { abs($0 - center) > abs($1 - center) } // outer drawn first
        let grown = resting ? Double(Self.tailCount) : progress * Double(Self.tailCount)

        for index in tails {
            let offset = index - center
            let rank = abs(offset) * 2 - (offset < 0 ? 1 : 0)
            let grow = min(1, max(0, grown - Double(rank)))
            guard grow > 0 else { continue }

            let sway = isRunning ? sin(time * 1.6 + Double(index) * 0.7) * 4 : 0
            var tail = ctx
            tail.translateBy(x: 50, y: 72)
            tail.rotate(by: .degrees(Double(offset) * 20 + sway))
            if offset < 0 { tail.scaleBy(x: -1, y: 1) } // curl away from the centre on both sides

            let length = 50 * grow, halfWidth = 7 * min(1, grow * 1.5)
            let path = tailPath(length: length, halfWidth: halfWidth)
            defer { tail.stroke(path, with: .color(Color(red: 0.75, green: 0.35, blue: 0.1).opacity(0.7)), lineWidth: 0.8) }
            tail.fill(path, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Self.fur, location: 0),
                    .init(color: Self.furLight, location: 0.68),
                    .init(color: Self.cream, location: 0.82),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: -length)
            ))
        }
    }

    /// Slender plume from a narrow base, widest past the middle, tip curling to +x.
    private func tailPath(length l: CGFloat, halfWidth w: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -w * 0.35, y: 0))
        p.addCurve(to: CGPoint(x: w * 0.9, y: -l), control1: CGPoint(x: -w * 1.7, y: -l * 0.5), control2: CGPoint(x: -w * 0.8, y: -l * 0.95))
        p.addCurve(to: CGPoint(x: w * 0.35, y: 0), control1: CGPoint(x: w * 2, y: -l * 0.8), control2: CGPoint(x: w * 1.5, y: -l * 0.3))
        p.closeSubpath()
        return p
    }

    private func drawBody(_ ctx: inout GraphicsContext) {
        // Sitting body and chest.
        ctx.fill(Path(ellipseIn: CGRect(x: 36, y: 58, width: 28, height: 36)), with: .color(Self.fur))
        ctx.fill(Path(ellipseIn: CGRect(x: 43, y: 66, width: 14, height: 26)), with: .color(Self.cream))

        // Ears with dark inner ear.
        for side: CGFloat in [-1, 1] {
            var ear = Path()
            ear.move(to: CGPoint(x: 50 + 15 * side, y: 49))
            ear.addLine(to: CGPoint(x: 50 + 14 * side, y: 29))
            ear.addLine(to: CGPoint(x: 50 + 4 * side, y: 41))
            ear.closeSubpath()
            ctx.fill(ear, with: .color(Self.fur))
            var inner = Path()
            inner.move(to: CGPoint(x: 50 + 13 * side, y: 45))
            inner.addLine(to: CGPoint(x: 50 + 13 * side, y: 33))
            inner.addLine(to: CGPoint(x: 50 + 7 * side, y: 41))
            inner.closeSubpath()
            ctx.fill(inner, with: .color(Self.ink.opacity(0.8)))
        }

        // Face: round brow tapering to a pointed muzzle.
        var face = Path()
        face.move(to: CGPoint(x: 34, y: 48))
        face.addQuadCurve(to: CGPoint(x: 66, y: 48), control: CGPoint(x: 50, y: 33))
        face.addQuadCurve(to: CGPoint(x: 50, y: 66), control: CGPoint(x: 63, y: 60))
        face.addQuadCurve(to: CGPoint(x: 34, y: 48), control: CGPoint(x: 37, y: 60))
        ctx.fill(face, with: .color(Self.fur))

        var cheeks = Path()
        cheeks.move(to: CGPoint(x: 38, y: 54))
        cheeks.addQuadCurve(to: CGPoint(x: 62, y: 54), control: CGPoint(x: 50, y: 58))
        cheeks.addQuadCurve(to: CGPoint(x: 50, y: 66), control: CGPoint(x: 59, y: 63))
        cheeks.addQuadCurve(to: CGPoint(x: 38, y: 54), control: CGPoint(x: 41, y: 63))
        ctx.fill(cheeks, with: .color(Self.cream))

        // Kitsune forehead mark.
        ctx.fill(Path(ellipseIn: CGRect(x: 48.8, y: 39, width: 2.4, height: 6)), with: .color(Color(red: 0.85, green: 0.1, blue: 0.15)))

        // Eyes: open while focusing, closed (resting) otherwise.
        for x: CGFloat in [44, 56] {
            if isRunning && !resting {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: 49.5, width: 3.2, height: 4.5)), with: .color(Self.ink))
            } else {
                var lid = Path()
                lid.move(to: CGPoint(x: x - 2.5, y: 51.5))
                lid.addQuadCurve(to: CGPoint(x: x + 2.5, y: 51.5), control: CGPoint(x: x, y: 53.8))
                ctx.stroke(lid, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
        ctx.fill(Path(ellipseIn: CGRect(x: 48.4, y: 62, width: 3.2, height: 2.6)), with: .color(Self.ink))
    }
}
