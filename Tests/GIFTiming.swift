import Foundation
import CoreGraphics
import ImageIO

@main @MainActor
struct GIFTimingTest {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for fps in [24, 25, 30, 60, 120] {
            var images: [CGImage] = []
            for index in 0..<(fps * 2) {
                let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.setFillColor(CGColor(red: CGFloat(index % 3) / 2, green: CGFloat(index % 2), blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                images.append(context.makeImage()!)
            }
            let url = root.appendingPathComponent("\(fps).gif")
            try GIFEncoder.encode(images: images, fps: fps, to: url)
            let gif = CGImageSourceCreateWithURL(url as CFURL, nil)!
            var duration = 0.0
            for index in 0..<CGImageSourceGetCount(gif) {
                let props = CGImageSourceCopyPropertiesAtIndex(gif, index, nil)! as NSDictionary
                let dictionary = props[kCGImagePropertyGIFDictionary] as! NSDictionary
                let delay = (dictionary[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                    ?? (dictionary[kCGImagePropertyGIFDelayTime] as! Double)
                precondition(delay >= 0.02, "Player-Mindestverzögerung unterschritten")
                duration += delay
            }
            precondition(abs(duration - 2) < 0.001, "\(fps) FPS speichern \(duration) statt 2 Sekunden")
            precondition(CGImageSourceGetCount(gif) == min(fps * 2, 100))
        }
        for fps in [1, 25, 30, 60, 120] {
            let count = Int(ceil(241.0 * Double(fps) / 120))
            let timing = GIFEncoder.plan(frameCount: count, fps: fps, duration: 241.0 / 120)
            precondition(timing.reduce(0) { $0 + $1.ticks } == 201)
            precondition(timing.allSatisfy { $0.ticks >= 2 })
            precondition(timing.allSatisfy { $0.sourceIndex < count })
            if fps == 120 { precondition(timing.count == 100, "Überflüssige Renderbilder geplant") }
            if fps == 1 { precondition(timing.map(\.ticks) == [100, 101]) }
        }
        print("gif-timing: OK (gespeicherte Dauer bei 24/25/30/60/120 FPS)")
    }
}
