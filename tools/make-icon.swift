// Erzeugt das App-Icon (1024x1024 PNG) im Vektor-Look des Spiels:
// dunkler, abgerundeter Hintergrund mit dem Dreiecks-Raumschiff + Triebwerksfeuer.
// Schiffs- und Flammen-Geometrie entsprechen exakt Ship.swift (Nase hier nach oben gedreht).
// Aufruf: swift tools/make-icon.swift <ausgabe.png>
// Aus dem PNG baut build-app.sh anschließend per iconutil das .icns.

import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Icon/icon_1024.png"

let pixels = 1024
let w = CGFloat(pixels)
let h = CGFloat(pixels)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: pixels, height: pixels,
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Konnte CGContext nicht erstellen")
}

// --- Hintergrund: abgerundetes Rechteck, fast schwarz ---
let bgRect = CGRect(x: 0, y: 0, width: w, height: h)
let corner: CGFloat = 230 // nahe an Apples Icon-Rundung
ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0))
ctx.fillPath()

// --- Ein paar dezente Sterne ---
let stars: [(CGFloat, CGFloat, CGFloat)] = [
    (180, 800, 6), (300, 250, 4), (840, 770, 5), (770, 250, 7),
    (150, 470, 4), (880, 470, 5), (470, 880, 4), (560, 160, 4)
]
ctx.setFillColor(CGColor(red: 0.45, green: 0.5, blue: 0.6, alpha: 1.0))
for (sx, sy, sr) in stars {
    ctx.fillEllipse(in: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2))
}

// --- Transform: lokale Schiffskoordinaten (Nase = +x) um 90° drehen (Nase = oben),
//     skalieren und im Bild zentrieren. ---
let scale: CGFloat = 13.0
let cx = w / 2
let cy = h / 2
let midY: CGFloat = -3.0 // Mittelpunkt der vertikalen Ausdehnung (Nase +18 .. Flammenspitze -24)

func tp(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    // 90°-Drehung gegen den Uhrzeigersinn: (x, y) -> (-y, x)
    let rx = -y
    let ry = x
    return CGPoint(x: cx + scale * rx, y: cy + scale * (ry - midY))
}

let cyan = CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
let orange = CGColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)
let yellow = CGColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)

// --- Triebwerksfeuer (zuerst, damit das Schiff darüberliegt) ---
// Äußere Flamme (orange), Form aus Ship.swift.
let flameOuter = CGMutablePath()
flameOuter.move(to: tp(-8, 0))
flameOuter.addLine(to: tp(-16, 5))
flameOuter.addLine(to: tp(-24, 0))
flameOuter.addLine(to: tp(-16, -5))
flameOuter.closeSubpath()
ctx.addPath(flameOuter)
ctx.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.25))
ctx.fillPath()
ctx.addPath(flameOuter)
ctx.setStrokeColor(orange)
ctx.setLineWidth(16)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.strokePath()

// Innere Flamme (gelb), etwas kleiner für den heißen Kern.
let flameInner = CGMutablePath()
flameInner.move(to: tp(-9, 0))
flameInner.addLine(to: tp(-14, 3))
flameInner.addLine(to: tp(-20, 0))
flameInner.addLine(to: tp(-14, -3))
flameInner.closeSubpath()
ctx.addPath(flameInner)
ctx.setFillColor(CGColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 0.35))
ctx.fillPath()
ctx.addPath(flameInner)
ctx.setStrokeColor(yellow)
ctx.setLineWidth(10)
ctx.strokePath()

// --- Raumschiff-Outline (cyan), Form aus Ship.swift ---
let ship = CGMutablePath()
ship.move(to: tp(18, 0))
ship.addLine(to: tp(-12, 10))
ship.addLine(to: tp(-8, 0))
ship.addLine(to: tp(-12, -10))
ship.closeSubpath()

// Dezente Füllung.
ctx.addPath(ship)
ctx.setFillColor(CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.08))
ctx.fillPath()

// Schwacher Glow (breiter, halbtransparent) + harte Kontur darüber.
ctx.addPath(ship)
ctx.setStrokeColor(CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.30))
ctx.setLineWidth(46)
ctx.setLineJoin(.round)
ctx.strokePath()

ctx.addPath(ship)
ctx.setStrokeColor(cyan)
ctx.setLineWidth(26)
ctx.strokePath()

// --- PNG schreiben ---
guard let image = ctx.makeImage() else { fatalError("Konnte Bild nicht rendern") }
let rep = NSBitmapImageRep(cgImage: image)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Konnte PNG nicht kodieren")
}
try! pngData.write(to: URL(fileURLWithPath: outPath))
print("Icon geschrieben: \(outPath)")
