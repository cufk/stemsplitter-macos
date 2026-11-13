// Genererar ett .iconset med rundade hörn från en källbild.
// Användning: swift scripts/round-icon.swift <in.jpg> <ut-mapp.iconset>
import AppKit
import Foundation

let arguments = CommandLine.arguments
 guard arguments.count == 3 else {
    FileHandle.standardError.write("användning: swift round-icon.swift <in-bild> <iconset-mapp>\n".data(using: .utf8)!)
    exit(2)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let iconset = arguments[2]

guard let image = NSImage(contentsOf: inputURL) else {
    FileHandle.standardError.write("kunde inte läsa bild\n".data(using: .utf8)!)
    exit(1)
}

try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let entries: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (size, name) in entries {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let output = NSImage(size: NSSize(width: size, height: size))
    output.lockFocus()
    // ~22% hörnradie, liknande macOS squircles
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).addClip()
    image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
    output.unlockFocus()
    guard let tiff = output.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("misslyckades för \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: iconset).appendingPathComponent(name))
}
