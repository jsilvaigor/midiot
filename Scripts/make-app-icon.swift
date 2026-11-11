import AppKit
// Draws the Midiot app icon: a charcoal tile, piano keys, and the amber filament line.
// Usage: swift Scripts/make-app-icon.swift <output.png>, then resize into
// App/Assets.xcassets/AppIcon.appiconset (16 to 512 pt, 1x and 2x).
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
// macOS icon grid: an 824 pt rounded square centered in 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(tilePath); ctx.clip()
ctx.setFillColor(color(0x0C0D10)); ctx.fill(tile)
// Warm light rising from the keys.
let glow = CGGradient(colorsSpace: nil, colors: [color(0xF2A649, 0.38), color(0xF2A649, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0, endCenter: CGPoint(x: 512, y: 470), endRadius: 520, options: [])
// Falling notes.
for (x, y, h, hex) in [(262.0, 640.0, 150.0, 0x86A0DD), (467.0, 560.0, 250.0, 0xF2A649), (672.0, 700.0, 110.0, 0xF2A649)] as [(CGFloat, CGFloat, CGFloat, UInt32)] {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 90, height: h), cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.setFillColor(color(hex)); ctx.fillPath()
}
// Keys along the bottom.
let keyTop: CGFloat = 470, keyWidth = tile.width / 4
for i in 0..<4 {
    let key = CGRect(x: tile.minX + CGFloat(i) * keyWidth + 5, y: tile.minY - 40, width: keyWidth - 10, height: keyTop - tile.minY + 40)
    ctx.addPath(CGPath(roundedRect: key, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setFillColor(color(0xF4F1EA)); ctx.fillPath()
}
for i in [1, 3] {
    let black = CGRect(x: tile.minX + CGFloat(i) * keyWidth - 60, y: 250, width: 120, height: keyTop - 250)
    ctx.addPath(CGPath(roundedRect: black, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.setFillColor(color(0x121316)); ctx.fillPath()
}
// The filament.
ctx.setShadow(offset: .zero, blur: 46, color: color(0xF2A649, 0.95))
ctx.setFillColor(color(0xF2A649)); ctx.fill(CGRect(x: tile.minX, y: keyTop, width: tile.width, height: 16))
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
