import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 76, y: 76, width: 872, height: 872)
let shape = NSBezierPath(roundedRect: rect, xRadius: 195, yRadius: 195)
NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.27, alpha: 1), ending: NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.12, alpha: 1))!.draw(in: shape, angle: -80)
NSColor.white.withAlphaComponent(0.12).setStroke()
shape.lineWidth = 3
shape.stroke()
let orange = NSColor(calibratedRed: 1, green: 0.59, blue: 0.24, alpha: 1)
orange.setStroke()
let path = NSBezierPath()
path.lineWidth = 47
path.lineCapStyle = .round
path.lineJoinStyle = .round
for x in [CGFloat(330), 694] {
    let direction: CGFloat = x < 512 ? 1 : -1
    path.move(to: NSPoint(x: x + direction * 64, y: 670))
    path.line(to: NSPoint(x: x, y: 670))
    path.line(to: NSPoint(x: x, y: 354))
    path.line(to: NSPoint(x: x + direction * 64, y: 354))
}
path.move(to: NSPoint(x: 445, y: 512))
path.line(to: NSPoint(x: 579, y: 512))
path.stroke()
NSColor(calibratedRed: 0.35, green: 0.91, blue: 0.62, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 727, y: 712, width: 77, height: 77)).fill()
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
