import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum GIFEncoder {
    enum EncodingError: Error { case destinationFailed }

    struct FrameTiming {
        let sourceIndex: Int
        let ticks: Int
    }

    /// Plant Bilder und Hundertstelsekunden vor dem teuren Rendern. Ein kurzer
    /// Schlussrest verlängert das vorherige Bild, statt von Playern gedehnt zu werden.
    static func plan(frameCount: Int, fps: Int, duration: TimeInterval? = nil) -> [FrameTiming] {
        guard frameCount > 0, fps > 0 else { return [] }
        let seconds = duration ?? Double(frameCount) / Double(fps)
        guard seconds.isFinite, seconds > 0, seconds < Double(Int.max / 100) else { return [] }
        let totalTicks = max(2, Int((seconds * 100).rounded()))
        if fps > 50 {
            let count = min(frameCount, max(1, totalTicks / 2))
            return (0..<count).map { index in
                let start = index * totalTicks / count
                let end = (index + 1) * totalTicks / count
                return FrameTiming(sourceIndex: min(frameCount - 1, start * fps / 100), ticks: end - start)
            }
        }
        var starts: [(index: Int, tick: Int)] = [(0, 0)]
        for index in 1..<frameCount {
            let tick = Int((Double(index) * 100 / Double(fps)).rounded())
            if tick >= totalTicks - 1 { break }
            starts.append((index, tick))
        }
        return starts.enumerated().map { index, item in
            let end = index + 1 < starts.count ? starts[index + 1].tick : totalTicks
            return FrameTiming(sourceIndex: item.index, ticks: end - item.tick)
        }
    }

    static func encode(images: [CGImage], fps: Int, to url: URL) throws {
        let timing = plan(frameCount: images.count, fps: fps)
        try encode(images: timing.map { images[$0.sourceIndex] }, timing: timing, to: url)
    }

    static func encode(images: [CGImage], timing: [FrameTiming], to url: URL) throws {
        guard !images.isEmpty, images.count == timing.count else { throw EncodingError.destinationFailed }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil) else {
            throw EncodingError.destinationFailed
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, frame) in zip(images, timing) {
            let properties = [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime: Double(frame.ticks) / 100]] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }
        guard CGImageDestinationFinalize(destination) else { throw EncodingError.destinationFailed }
    }
}
