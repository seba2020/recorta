import Foundation

enum CropGeometry {
    static func fit(_ rect: CGRect, ratio: CGFloat?) -> CGRect {
        guard let ratio, ratio > 0 else { return rect }
        var size = rect.size
        if size.width / max(size.height, 0.000001) > ratio { size.width = size.height * ratio }
        else { size.height = size.width / ratio }
        return CGRect(x: rect.midX-size.width/2, y: rect.midY-size.height/2, width: size.width, height: size.height)
    }
    static func trim(_ r: CGRect, key: UInt16, amount: CGFloat, expand: Bool, minimum: CGSize, ratio: CGFloat?) -> CGRect {
        let horizontal = key == 123 || key == 124
        let fromStart = key == 124 || key == 125
        guard [123,124,125,126].contains(key) else { return r }
        let current = horizontal ? r.width : r.height
        var minSize = horizontal ? minimum.width : minimum.height
        var limit: CGFloat = horizontal ? (fromStart ? r.maxX : 1-r.minX) : (fromStart ? r.maxY : 1-r.minY)
        if let ratio {
            if horizontal {
                minSize = max(minSize, minimum.height*ratio)
                limit = min(limit, 2*min(r.midY,1-r.midY)*ratio)
            } else {
                minSize = max(minSize, minimum.width/ratio)
                limit = min(limit, 2*min(r.midX,1-r.midX)/ratio)
            }
        }
        let size = max(minSize, min(limit, current + (expand ? amount : -amount)))
        var result = r
        if horizontal {
            result.size.width = size
            if fromStart { result.origin.x = r.maxX-size }
            if let ratio { result.size.height = size/ratio; result.origin.y = r.midY-result.height/2 }
        } else {
            result.size.height = size
            if fromStart { result.origin.y = r.maxY-size }
            if let ratio { result.size.width = size*ratio; result.origin.x = r.midX-result.width/2 }
        }
        return result
    }
}
