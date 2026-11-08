import AppKit

let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: 0.975, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let blue = NSColor(calibratedRed: 0.16, green: 0.33, blue: 0.88, alpha: 1)
let transform = NSAffineTransform()
transform.scale(by: 12)
transform.concat()
NSGraphicsContext.current?.imageInterpolation = .high
let path = NSBezierPath()
path.move(to: NSPoint(x: 28, y: 62))
path.curve(to: NSPoint(x: 60, y: 53), controlPoint1: NSPoint(x: 30, y: 77), controlPoint2: NSPoint(x: 64, y: 72))
path.curve(to: NSPoint(x: 58, y: 30), controlPoint1: NSPoint(x: 69, y: 42), controlPoint2: NSPoint(x: 67, y: 27))
path.curve(to: NSPoint(x: 26, y: 32), controlPoint1: NSPoint(x: 46, y: 23), controlPoint2: NSPoint(x: 18, y: 26))
path.curve(to: NSPoint(x: 28, y: 62), controlPoint1: NSPoint(x: 16, y: 45), controlPoint2: NSPoint(x: 22, y: 57))
blue.withAlphaComponent(0.09).setFill()
path.fill()
blue.setStroke()
path.lineWidth = 2.8
path.lineCapStyle = .round
path.stroke()
func line(_ points: [NSPoint]) {
    let p = NSBezierPath()
    p.move(to: points[0])
    for point in points.dropFirst() { p.line(to: point) }
    p.lineWidth = 2.5
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    blue.setStroke()
    p.stroke()
}
line([.init(x: 24, y: 48), .init(x: 14, y: 39), .init(x: 11, y: 43)])
line([.init(x: 63, y: 48), .init(x: 73, y: 60), .init(x: 77, y: 57)])
line([.init(x: 34, y: 28), .init(x: 31, y: 18), .init(x: 26, y: 18)])
line([.init(x: 51, y: 28), .init(x: 54, y: 18), .init(x: 59, y: 18)])
blue.setFill()
for x in [35.0, 48.0] { NSBezierPath(ovalIn: NSRect(x: x, y: 49, width: 3.5, height: 4.2)).fill() }
line([.init(x: 38, y: 41), .init(x: 43, y: 38), .init(x: 48, y: 41)])
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: "Blue/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
