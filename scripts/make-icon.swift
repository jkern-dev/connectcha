// Placeholder app icon: a rounded tile with a bold "C". Run: swift scripts/make-icon.swift
import AppKit

func render(background: NSColor, letter: NSColor, to path: String) {
    let size = NSSize(width: 1024, height: 1024)
    // Draw into an explicit 1024-pixel bitmap so a Retina Mac doesn't double it.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 700, weight: .bold),
        .foregroundColor: letter,
        .paragraphStyle: paragraph,
    ]
    let text = NSAttributedString(string: "C", attributes: attrs)
    let bounds = text.boundingRect(with: size, options: [.usesLineFragmentOrigin])
    text.draw(in: NSRect(x: 0, y: (1024 - bounds.height) / 2 - 20, width: 1024, height: bounds.height))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("render failed") }
    try! png.write(to: URL(fileURLWithPath: path))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
render(background: NSColor(red: 0.82, green: 0.42, blue: 0.18, alpha: 1), letter: .white, to: "\(dir)/icon-light.png")
render(background: NSColor(red: 0.09, green: 0.08, blue: 0.075, alpha: 1), letter: NSColor(red: 0.95, green: 0.56, blue: 0.34, alpha: 1), to: "\(dir)/icon-dark.png")
render(background: .black, letter: .white, to: "\(dir)/icon-tinted.png")
print("icons written to \(dir)")
