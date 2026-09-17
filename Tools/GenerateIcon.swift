import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ pixels: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
    NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.14, alpha: 1).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.26, blue: 0.28, alpha: 1), ending: NSColor(calibratedRed: 0.065, green: 0.085, blue: 0.11, alpha: 1))!.draw(in: tile, angle: -70)
    NSColor.white.withAlphaComponent(0.13).setStroke(); tile.lineWidth = 2; tile.stroke()
    let mint = NSColor(calibratedRed: 0.65, green: 0.94, blue: 0.77, alpha: 1)
    let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .medium).applying(NSImage.SymbolConfiguration(paletteColors: [mint]))
    let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Recorta")!.withSymbolConfiguration(config)!
    let size = symbol.size
    let ratio = min(570 / size.width, 570 / size.height)
    let width = size.width * ratio, height = size.height * ratio
    symbol.draw(in: NSRect(x: (1024-width)/2, y: (1024-height)/2, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size*2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to: output.appendingPathComponent("Recorta-icon.png"))
