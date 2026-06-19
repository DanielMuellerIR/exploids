// generate-dmg-background.swift
//
// Erzeugt das Hintergrundbild für das Exploids-DMG-Installationsfenster.
// Ausführen mit:
//
//   swift assets/generate-dmg-background.swift assets/dmg-background.png
//
// Ergebnis: 600×400-PNG, das im DMG hinter den beiden Icons liegt
// (Exploids.app links, Applications-Symlink rechts), mit Pfeil + Text im
// dunklen Vektor-Weltraum-Look des Spiels.
//
// Die Bildgröße ist exakt das Finder-Fenster-Innenmaß im DMG — sonst
// Skalier-Artefakte und das Layout passt nicht zu den Icon-Positionen.

import AppKit
import CoreGraphics

// ---------- Argumente ----------

let args = CommandLine.arguments
guard args.count == 2 else {
  FileHandle.standardError.write("Usage: swift generate-dmg-background.swift <output.png>\n".data(using: .utf8)!)
  exit(1)
}
let outputPath = args[1]

// ---------- Maße (müssen zum AppleScript-Fenster in sign-and-release.sh passen) ----------

let width: CGFloat  = 600
let height: CGFloat = 400
let appCenter: CGPoint = CGPoint(x: 150, y: 180)   // y von oben gemessen
let dirCenter: CGPoint = CGPoint(x: 450, y: 180)
let iconSize:  CGFloat = 128

// ---------- Bitmap-Context (2× für Retina) ----------

let scale: CGFloat = 2
let pxWidth  = Int(width  * scale)
let pxHeight = Int(height * scale)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
  data: nil, width: pxWidth, height: pxHeight,
  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
  FileHandle.standardError.write("CGContext-Erzeugung fehlgeschlagen\n".data(using: .utf8)!)
  exit(1)
}

// CoreGraphics-Ursprung ist unten-links → einmal kippen, damit y von oben zählt.
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: height)
ctx.scaleBy(x: 1, y: -1)

// ---------- Hintergrund: tiefes Weltraum-Blau (wie das App-Icon) ----------

let topColor    = CGColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1.0)
let bottomColor = CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0)
if let gradient = CGGradient(colorsSpace: colorSpace,
                             colors: [topColor, bottomColor] as CFArray, locations: [0.0, 1.0]) {
  ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                         end: CGPoint(x: 0, y: height), options: [])
}

// ---------- Sternenfeld (deterministisch, kein Zufall → reproduzierbares Bild) ----------

// Feste Positionen + Helligkeiten, damit jeder Build dasselbe PNG erzeugt.
let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
  (60, 70, 1.4, 0.7), (140, 300, 1.0, 0.5), (210, 120, 1.6, 0.8), (300, 250, 1.1, 0.6),
  (360, 60, 1.3, 0.7), (430, 330, 1.5, 0.6), (500, 100, 1.0, 0.5), (560, 220, 1.4, 0.8),
  (90, 200, 0.9, 0.4), (250, 350, 1.2, 0.5), (390, 180, 1.0, 0.6), (540, 320, 1.1, 0.5),
]
for s in stars {
  ctx.setFillColor(CGColor(red: 0.8, green: 0.88, blue: 1.0, alpha: s.a))
  ctx.fillEllipse(in: CGRect(x: s.x - s.r, y: s.y - s.r, width: s.r * 2, height: s.r * 2))
}

// ---------- Hilfsfunktion: zentrierter Text ----------

func drawCenteredText(_ text: String, at center: CGPoint, font: NSFont, color: NSColor) {
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .center
  let attrs: [NSAttributedString.Key: Any] = [
    .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
  ]
  let attr = NSAttributedString(string: text, attributes: attrs)
  let size = attr.size()
  let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                    width: size.width, height: size.height)
  // Lokal nochmal kippen, sonst steht der Text auf dem Kopf.
  ctx.saveGState()
  ctx.translateBy(x: 0, y: rect.midY * 2)
  ctx.scaleBy(x: 1, y: -1)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
  attr.draw(in: rect)
  NSGraphicsContext.restoreGraphicsState()
  ctx.restoreGState()
}

// ---------- Texte ----------

let cyan          = NSColor(red: 0.25, green: 0.88, blue: 1.0, alpha: 1.0)   // Akzent wie das Schiff
let subtitleColor = NSColor(white: 0.72, alpha: 1.0)

drawCenteredText("Install Exploids",
                 at: CGPoint(x: width / 2, y: 50),
                 font: NSFont.systemFont(ofSize: 24, weight: .semibold), color: cyan)
drawCenteredText("Drag the icon into the Applications folder.",
                 at: CGPoint(x: width / 2, y: 82),
                 font: NSFont.systemFont(ofSize: 13, weight: .regular), color: subtitleColor)
drawCenteredText("Then double-click to play.",
                 at: CGPoint(x: width / 2, y: 350),
                 font: NSFont.systemFont(ofSize: 12, weight: .regular), color: subtitleColor)

// ---------- Pfeil zwischen den Icon-Plätzen ----------

let arrowPadding: CGFloat = iconSize / 2 + 20
let arrowStart = CGPoint(x: appCenter.x + arrowPadding, y: appCenter.y)
let arrowEnd   = CGPoint(x: dirCenter.x - arrowPadding, y: dirCenter.y)
let arrowColor = cyan.withAlphaComponent(0.85).cgColor
ctx.setStrokeColor(arrowColor); ctx.setFillColor(arrowColor)
ctx.setLineWidth(3); ctx.setLineCap(.round)
ctx.move(to: arrowStart)
ctx.addLine(to: CGPoint(x: arrowEnd.x - 8, y: arrowEnd.y))
ctx.strokePath()
let headLength: CGFloat = 18
let headWidth:  CGFloat = 14
ctx.beginPath()
ctx.move(to: arrowEnd)
ctx.addLine(to: CGPoint(x: arrowEnd.x - headLength, y: arrowEnd.y - headWidth / 2))
ctx.addLine(to: CGPoint(x: arrowEnd.x - headLength, y: arrowEnd.y + headWidth / 2))
ctx.closePath()
ctx.fillPath()

// ---------- PNG schreiben ----------

guard let cgImage = ctx.makeImage() else {
  FileHandle.standardError.write("Bild-Render fehlgeschlagen\n".data(using: .utf8)!)
  exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: width, height: height)   // DPI 144 → Finder behandelt es als Retina-Asset
guard let pngData = rep.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write("PNG-Encoding fehlgeschlagen\n".data(using: .utf8)!)
  exit(1)
}
do {
  try pngData.write(to: URL(fileURLWithPath: outputPath))
  print("✓ Geschrieben: \(outputPath) (\(pxWidth)×\(pxHeight) px)")
} catch {
  FileHandle.standardError.write("Schreiben fehlgeschlagen: \(error)\n".data(using: .utf8)!)
  exit(1)
}
