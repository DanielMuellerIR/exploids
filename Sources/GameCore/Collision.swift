import Foundation

/// Helper for geometric computations and polygon collision detection.
public struct CollisionHelper {
    
    /// Checks if two polygons (defined by their world-space vertices) intersect.
    /// Polygons are defined by ordered arrays of points forming closed shapes.
    public static func polygonsIntersect(_ polyA: [CGPoint], _ polyB: [CGPoint]) -> Bool {
        guard polyA.count >= 2, polyB.count >= 2 else { return false }
        
        // 1. Check segment-segment intersections
        for i in 0..<polyA.count {
            let startA = polyA[i]
            let endA = polyA[(i + 1) % polyA.count]
            
            for j in 0..<polyB.count {
                let startB = polyB[j]
                let endB = polyB[(j + 1) % polyB.count]
                
                if segmentsIntersect(startA, endA, startB, endB) {
                    return true
                }
            }
        }
        
        // 2. Point-in-polygon containment check (handles when one shape is completely inside the other)
        if isPointInPolygon(polyA[0], polygon: polyB) || isPointInPolygon(polyB[0], polygon: polyA) {
            return true
        }
        
        return false
    }
    
    /// Checks if line segment AB intersects line segment CD.
    public static func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        let rx = b.x - a.x
        let ry = b.y - a.y
        let sx = d.x - c.x
        let sy = d.y - c.y
        
        let crossRS = rx * sy - ry * sx
        if abs(crossRS) < 1e-6 {
            return false // Parallel or collinear
        }
        
        let u = ((c.x - a.x) * sy - (c.y - a.y) * sx) / crossRS
        let v = ((c.x - a.x) * ry - (c.y - a.y) * rx) / crossRS
        
        return u >= 0 && u <= 1 && v >= 0 && v <= 1
    }
    
    /// Ray casting algorithm to check if a point is inside a polygon.
    public static func isPointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            
            // Check if ray from point to the right crosses the segment between pi and pj
            if ((pi.y > point.y) != (pj.y > point.y)) {
                let intersectX = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < intersectX {
                    inside = !inside
                }
            }
            j = i
        }
        return inside
    }
    
    /// Checks if a laser projectile intersects an asteroid polygon.
    @MainActor
    public static func laserIntersectsAsteroid(_ laser: Laser, _ asteroid: Asteroid) -> Bool {
        let (laserStart, laserEnd) = laser.getWorldSegment()
        return segmentIntersectsPolygon(laserStart, laserEnd, polygon: asteroid.getWorldVertices())
    }

    /// Prüft auch Durchquerungen, deren beide Endpunkte außerhalb der Kontur liegen.
    public static func segmentIntersectsPolygon(_ start: CGPoint, _ end: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 2 else { return false }
        for i in polygon.indices {
            if segmentsIntersect(start, end, polygon[i], polygon[(i + 1) % polygon.count]) { return true }
        }
        return isPointInPolygon(start, polygon: polygon) || isPointInPolygon(end, polygon: polygon)
    }
}

