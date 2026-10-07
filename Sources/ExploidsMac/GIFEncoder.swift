import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum GIFEncoder {
    enum EncodingError: Error { case destinationFailed }

    static func encode(images: [CGImage], fps: Int, to url: URL) throws {
        guard !images.isEmpty, fps > 0 else { throw EncodingError.destinationFailed }
        // GIF speichert ganze Hundertstelsekunden. Unter 2 cs ersetzen viele Player
        // die Verzögerung durch einen eigenen Mindestwert; hohe Raten daher zusammenfassen.
        let ticks = max(2, Int((Double(images.count) * 100 / Double(fps)).rounded()))
        let count = min(images.count, max(1, ticks / 2))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw EncodingError.destinationFailed
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var previousTick = 0
        for index in 0..<count {
            let endTick = (index + 1) * ticks / count
            let delay = Double(endTick - previousTick) / 100
            previousTick = endTick
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(destination, images[index * images.count / count], properties)
        }
        guard CGImageDestinationFinalize(destination) else { throw EncodingError.destinationFailed }
    }
}
