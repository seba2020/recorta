import SwiftUI
import AppKit

struct CropCanvas: NSViewRepresentable {
    let photo: Photo
    @Binding var selection: CGRect
    var enabled = true
    var speed: CGFloat = 0.25
    var ratio: CGFloat?
    var original: CGImage?
    func makeNSView(context: Context) -> CropView { CropView() }
    func updateNSView(_ view: CropView, context: Context) {
        if view.image !== photo.image { view.stopKeys() }
        view.speed = speed
        view.ratio = ratio
        view.original = original
        view.keyboardEnabled = enabled
        view.image = photo.image
        view.selection = selection
        view.onChange = { selection = $0 }
        view.needsDisplay = true
    }
}
final class CropView: NSView {
    var image: CGImage?
    var selection = CGRect(x: 0, y: 0, width: 1, height: 1)
    var onChange: ((CGRect) -> Void)?
    var keyboardEnabled = true { didSet { if !keyboardEnabled { stopKeys() } } }
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var timer: Timer?
    private var heldKeys = Set<UInt16>()
    private var lastTick: TimeInterval = 0
    private var fast = false
    private var expanding = false
    private var comparing = false
    var speed: CGFloat = 0.25
    var ratio: CGFloat?
    var original: CGImage?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopKeys()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.stopKeys() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, self.window?.attachedSheet == nil, self.keyboardEnabled else { return event }
            self.fast = event.modifierFlags.contains(.shift)
            self.expanding = event.modifierFlags.contains(.option)
            if event.keyCode == 11, event.type != .flagsChanged, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                self.stopKeys()
                self.comparing = event.type == .keyDown
                self.needsDisplay = true
                return nil
            }
            if self.comparing { return nil }
            guard [123, 124, 125, 126].contains(event.keyCode), event.type != .flagsChanged else { return event }
            if event.type == .keyUp {
                self.heldKeys.remove(event.keyCode)
                if self.heldKeys.isEmpty { self.stopKeys() }
                return nil
            }
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return event }
            if !event.isARepeat, self.heldKeys.insert(event.keyCode).inserted {
                self.trim(key: event.keyCode, amount: 0.005)
                if self.timer == nil {
                    self.lastTick = ProcessInfo.processInfo.systemUptime
                    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
                    self.timer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
            return nil
        }
    }
    func stopKeys() { timer?.invalidate(); timer = nil; heldKeys.removeAll(); comparing = false; needsDisplay = true }
    private func tick() {
        guard keyboardEnabled, window?.isKeyWindow == true, window?.attachedSheet == nil else { stopKeys(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let amount = CGFloat(min(now - lastTick, 0.05)) * speed * (fast ? 2.4 : 1)
        lastTick = now
        for key in heldKeys.sorted() { trim(key: key, amount: amount) }
    }
    private func trim(key: UInt16, amount: CGFloat) {
        guard let image else { return }
        let r = CropGeometry.trim(selection, key: key, amount: amount, expand: expanding,
                                  minimum: CGSize(width: 2 / CGFloat(image.width), height: 2 / CGFloat(image.height)), ratio: ratio)
        selection = r; onChange?(r); needsDisplay = true
    }
    deinit {
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
    private var anchor = CGPoint.zero
    private var initial = CGRect.zero
    private var mode = -1 // -1 new, 0 move, 1...4 corners
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var imageFrame: CGRect {
        guard let image else { return .zero }
        let area = bounds.insetBy(dx: 28, dy: 22)
        let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    func displayRect(_ r: CGRect) -> CGRect {
        let f = imageFrame
        return CGRect(x: f.minX + r.minX * f.width, y: f.minY + r.minY * f.height, width: r.width * f.width, height: r.height * f.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        if comparing {
            let before = original ?? image
            let area = bounds.insetBy(dx: 28, dy: 22)
            let scale = min(area.width/CGFloat(before.width), area.height/CGFloat(before.height))
            let size = CGSize(width: CGFloat(before.width)*scale, height: CGFloat(before.height)*scale)
            NSImage(cgImage: before, size: size).draw(in: CGRect(x: bounds.midX-size.width/2, y: bounds.midY-size.height/2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            ("ORIGINAL · suelta B para volver" as NSString).draw(at: CGPoint(x: 36, y: 28), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7)])
            return
        }
        let f = imageFrame, r = displayRect(selection)
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: f, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: f)
        shade.append(NSBezierPath(rect: r)); shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.58).setFill(); shade.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let outline = NSBezierPath(rect: r); outline.lineWidth = 1.5; outline.stroke()
        let grid = NSBezierPath()
        for step in 1...2 {
            let t = CGFloat(step) / 3
            grid.move(to: CGPoint(x: r.minX + r.width*t, y: r.minY)); grid.line(to: CGPoint(x: r.minX + r.width*t, y: r.maxY))
            grid.move(to: CGPoint(x: r.minX, y: r.minY+r.height*t)); grid.line(to: CGPoint(x: r.maxX, y: r.minY+r.height*t))
        }
        NSColor.white.withAlphaComponent(0.3).setStroke(); grid.lineWidth = 0.5; grid.stroke()
        for p in corners(r) {
            NSColor.white.setFill(); NSBezierPath(roundedRect: CGRect(x: p.x-4, y: p.y-4, width: 8, height: 8), xRadius: 2, yRadius: 2).fill()
        }
    }
    func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x:r.minX,y:r.minY), CGPoint(x:r.maxX,y:r.minY), CGPoint(x:r.maxX,y:r.maxY), CGPoint(x:r.minX,y:r.maxY)]
    }
    func normalized(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), f = imageFrame
        return CGPoint(x: min(1,max(0,(p.x-f.minX)/f.width)), y: min(1,max(0,(p.y-f.minY)/f.height)))
    }
    override func resetCursorRects() { addCursorRect(imageFrame, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        stopKeys()
        let p = convert(event.locationInWindow, from: nil)
        guard imageFrame.insetBy(dx: -8, dy: -8).contains(p) else { return }
        anchor = normalized(event); initial = selection; mode = -1
        let r = displayRect(selection)
        if let i = corners(r).firstIndex(where: { hypot($0.x-p.x,$0.y-p.y) < 14 }) { mode = i+1 }
        else if selection != CGRect(x:0,y:0,width:1,height:1) && r.contains(p) && !event.modifierFlags.contains(.option) { mode = 0 }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = normalized(event)
        var r: CGRect
        if mode == 0 {
            r = initial.offsetBy(dx: p.x-anchor.x, dy: p.y-anchor.y)
            r.origin.x = min(1-r.width,max(0,r.minX)); r.origin.y = min(1-r.height,max(0,r.minY))
        } else {
            let fixed = mode > 0 ? corners(initial)[(mode-1+2)%4] : anchor
            r = CGRect(x: min(fixed.x,p.x), y: min(fixed.y,p.y), width: abs(p.x-fixed.x), height: abs(p.y-fixed.y))
        }
        if mode != 0 { r = CropGeometry.fit(r, ratio: ratio) }
        if r.width > 0.002 && r.height > 0.002 { selection = r; onChange?(r); needsDisplay = true }
    }
}
