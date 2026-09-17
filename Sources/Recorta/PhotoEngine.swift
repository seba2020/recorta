import Foundation
import CoreImage
import ImageIO
import CryptoKit

struct Photo: @unchecked Sendable {
    let url: URL
    let data: Data
    let image: CGImage
    let type: CFString
    let properties: [String: Any]
}
struct CropRecord: Sendable {
    let url: URL
    let backup: URL
    let savedDigest: Data
}
enum PhotoError: LocalizedError {
    case invalid, unsupported, empty, changed, encode
    var errorDescription: String? {
        switch self {
        case .invalid: return "No se pudo leer esta imagen. Puedes saltarla con Espacio."
        case .unsupported: return "Este archivo contiene varias imágenes y no se modificará. Puedes saltarlo con Espacio."
        case .empty: return "Selecciona un área más grande."
        case .changed: return "El archivo cambió fuera de Recorta. Vuelve a abrir la carpeta antes de editarlo."
        case .encode: return "No se pudo guardar el recorte. La foto original sigue intacta."
        }
    }
}
enum PhotoEngine {
    static func load(_ url: URL) throws -> Photo {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PhotoError.invalid }
        guard CGImageSourceGetCount(source) == 1 else { throw PhotoError.unsupported }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        let ci = CIImage(cgImage: raw).oriented(forExifOrientation: orientation)
        guard let image = CIContext().createCGImage(ci, from: ci.extent) else { throw PhotoError.invalid }
        return Photo(url: url, data: data, image: image, type: type, properties: props)
    }
    static func pixelRect(_ selection: CGRect, width: Int, height: Int) throws -> CGRect {
        let bounded = selection.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !bounded.isNull, bounded.width.isFinite, bounded.height.isFinite else { throw PhotoError.empty }
        let rect = CGRect(x: bounded.minX * CGFloat(width), y: bounded.minY * CGFloat(height), width: bounded.width * CGFloat(width), height: bounded.height * CGFloat(height)).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width >= 2, rect.height >= 2 else { throw PhotoError.empty }
        return rect
    }
    static func crop(_ photo: Photo, selection: CGRect) throws -> CropRecord {
        let rect = try pixelRect(selection, width: photo.image.width, height: photo.image.height)
        guard let cropped = photo.image.cropping(to: rect) else { throw PhotoError.empty }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, photo.type, 1, nil) else { throw PhotoError.encode }
        var props = photo.properties
        props[kCGImagePropertyOrientation as String] = 1
        props[kCGImagePropertyPixelWidth as String] = cropped.width
        props[kCGImagePropertyPixelHeight as String] = cropped.height
        props[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        if var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = cropped.width
            exif[kCGImagePropertyExifPixelYDimension as String] = cropped.height
            props[kCGImagePropertyExifDictionary as String] = exif
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            props[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        CGImageDestinationAddImage(destination, cropped, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.encode }
        guard try Data(contentsOf: photo.url) == photo.data else { throw PhotoError.changed }
        let backupDir = photo.url.deletingLastPathComponent().appendingPathComponent(".recorta-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backup = backupDir.appendingPathComponent(UUID().uuidString + "--" + photo.url.lastPathComponent)
        try photo.data.write(to: backup, options: .withoutOverwriting)
        let saved = output as Data
        try saved.write(to: photo.url, options: .atomic)
        return CropRecord(url: photo.url, backup: backup, savedDigest: Data(SHA256.hash(data: saved)))
    }
    static func undo(_ record: CropRecord) throws {
        guard Data(SHA256.hash(data: try Data(contentsOf: record.url))) == record.savedDigest else { throw PhotoError.changed }
        try Data(contentsOf: record.backup).write(to: record.url, options: .atomic)
    }
}
