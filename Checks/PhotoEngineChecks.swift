import Foundation
import ImageIO
import UniformTypeIdentifiers


final class PhotoEngineTests {
    var cleanups: [() -> Void] = []
    func addTeardownBlock(_ block: @escaping () -> Void) { cleanups.append(block) }
    deinit { cleanups.forEach { $0() } }
    func fixture(orientation: Int = 1) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("photo.png")
        let context = CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1)); context.fill(CGRect(x:0,y:0,width:100,height:60))
        context.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:100,height:30))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
    func testCropBackupAndUndo() throws {
        let url = try fixture(), original = try Data(contentsOf: url)
        let photo = try PhotoEngine.load(url)
        let record = try PhotoEngine.crop(photo, selection: CGRect(x:0.2,y:0.1,width:0.5,height:0.5))
        let cropped = try PhotoEngine.load(url)
        XCTAssertEqual(cropped.image.width,50); XCTAssertEqual(cropped.image.height,30)
        XCTAssertEqual(try Data(contentsOf:record.backup),original)
        try PhotoEngine.undo(record)
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
    func testProtectsExternalEdits() throws {
        let url = try fixture(), photo = try PhotoEngine.load(url)
        let changed = Data("external change".utf8)
        try changed.write(to:url)
        XCTAssertThrowsError(try PhotoEngine.crop(photo,selection:CGRect(x:0,y:0,width:0.5,height:0.5)))
        XCTAssertEqual(try Data(contentsOf:url),changed)
    }
    func testUndoProtectsExternalEdits() throws {
        let url = try fixture(), photo = try PhotoEngine.load(url)
        let record = try PhotoEngine.crop(photo,selection:CGRect(x:0,y:0,width:0.5,height:0.5))
        let changed = Data("external change".utf8); try changed.write(to:url)
        XCTAssertThrowsError(try PhotoEngine.undo(record))
        XCTAssertEqual(try Data(contentsOf:url),changed)
    }
    func testOrientationAndBounds() throws {
        let photo = try PhotoEngine.load(fixture(orientation:6))
        XCTAssertEqual(photo.image.width,60); XCTAssertEqual(photo.image.height,100)
        let record = try PhotoEngine.crop(photo,selection:CGRect(x:0,y:0,width:0.5,height:0.5))
        let cropped = try PhotoEngine.load(record.url)
        XCTAssertEqual(cropped.image.width,30); XCTAssertEqual(cropped.image.height,50)
        XCTAssertEqual((cropped.properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1,1)
        XCTAssertThrowsError(try PhotoEngine.pixelRect(.zero,width:100,height:60))
        XCTAssertEqual(try PhotoEngine.pixelRect(CGRect(x:-1,y:-1,width:3,height:3),width:100,height:60),CGRect(x:0,y:0,width:100,height:60))
    }
    func testTopCropUsesDisplayedTop() throws {
        let photo = try PhotoEngine.load(fixture())
        let record = try PhotoEngine.crop(photo,selection:CGRect(x:0,y:0,width:1,height:0.5))
        let cropped = try PhotoEngine.load(record.url)
        var bytes = [UInt8](repeating:0,count:4)
        let context = CGContext(data:&bytes,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cropped.image,in:CGRect(x:0,y:0,width:1,height:1))
        XCTAssertGreaterThan(bytes[0],240); XCTAssertLessThan(bytes[2],10)
    }
}

func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(a) == \(b)") }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T) { precondition(a > b) }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T) { precondition(a < b) }
func XCTAssertThrowsError<T>(_ operation: @autoclosure () throws -> T) {
    do { _ = try operation(); fatalError("Expected an error") } catch {}
}
@main struct RunChecks {
    static func main() throws {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let minimum = CGSize(width: 0.002, height: 0.002)
        let down = CropGeometry.trim(full, key: 125, amount: 0.2, expand: false, minimum: minimum, ratio: nil)
        precondition(abs(down.minY-0.2) < 0.000001 && abs(down.height-0.8) < 0.000001 && down.width == 1)
        XCTAssertEqual(CropGeometry.trim(down, key: 125, amount: 0.2, expand: true, minimum: minimum, ratio: nil), full)
        for ratio: CGFloat in [0.4, 0.7, 1, 1.5, 2.3] {
            var rect = CropGeometry.fit(full, ratio: ratio)
            for step in 0..<1000 {
                rect = CropGeometry.trim(rect, key: UInt16(123 + step % 4), amount: 0.017, expand: step % 7 < 3, minimum: minimum, ratio: ratio)
                precondition(rect.minX >= -0.000001 && rect.minY >= -0.000001 && rect.maxX <= 1.000001 && rect.maxY <= 1.000001)
                precondition(abs(rect.width / rect.height - ratio) < 0.000001)
                precondition(rect.width >= minimum.width-0.000001 && rect.height >= minimum.height-0.000001)
            }
        }
        print("PASS: edge expansion, anchoring, 5,000 constrained resizes across portrait and landscape ratios")
        let tests = PhotoEngineTests()
        try tests.testCropBackupAndUndo()
        try tests.testProtectsExternalEdits()
        try tests.testUndoProtectsExternalEdits()
        try tests.testOrientationAndBounds()
        try tests.testTopCropUsesDisplayedTop()
        print("PASS: 5 checks — crop, backups, undo, external edits, orientation and top coordinates")
    }
}
