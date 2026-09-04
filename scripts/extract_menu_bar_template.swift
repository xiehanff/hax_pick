import AppKit

guard CommandLine.arguments.count == 3 else {
    fatalError("usage: extract_menu_bar_template.swift <source.png> <output.png>")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let sourceData = try? Data(contentsOf: sourceURL),
      let source = NSBitmapImageRep(data: sourceData) else {
    fatalError("unable to load source icon")
}

let width = source.pixelsWide
let height = source.pixelsHigh
var alphaMask = [CGFloat](repeating: 0, count: width * height)

var minX = width
var minY = height
var maxX = 0
var maxY = 0

for y in 0..<height {
    for x in 0..<width {
        guard let sourceColor = source.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.deviceRGB) else {
            continue
        }

        let orangeDistance = sourceColor.redComponent
            - max(sourceColor.greenComponent, sourceColor.blueComponent)
        let alpha = min(max((orangeDistance - 0.18) * 3.6, 0), 1)
            * sourceColor.alphaComponent

        guard alpha > 0 else { continue }
        alphaMask[y * width + x] = alpha

        if alpha > 0.03 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

guard minX <= maxX, minY <= maxY else {
    fatalError("orange brand mark was not found")
}

let outputPixels = 256
let padding = 24
guard let output = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: outputPixels,
    pixelsHigh: outputPixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: .alphaNonpremultiplied,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else {
    fatalError("unable to create output image")
}
output.size = NSSize(width: outputPixels, height: outputPixels)

let markWidth = CGFloat(maxX - minX + 1)
let markHeight = CGFloat(maxY - minY + 1)
let available = CGFloat(outputPixels - padding * 2)
let scale = min(available / markWidth, available / markHeight)
let destinationSize = CGSize(width: markWidth * scale, height: markHeight * scale)
let destination = CGRect(
    x: (CGFloat(outputPixels) - destinationSize.width) / 2,
    y: (CGFloat(outputPixels) - destinationSize.height) / 2,
    width: destinationSize.width,
    height: destinationSize.height
)

guard let bitmap = output.bitmapData else {
    fatalError("unable to access output bitmap")
}

func sourceAlpha(x: Int, y: Int) -> CGFloat {
    guard x >= 0, x < width, y >= 0, y < height else { return 0 }
    return alphaMask[y * width + x]
}

// NSBitmapImageRep.setColor silently drops pixels written into an
// alphaNonpremultiplied deviceRGB buffer, so fill the RGBA bytes directly.
for y in 0..<outputPixels {
    for x in 0..<outputPixels {
        let outputPoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
        guard destination.contains(outputPoint) else { continue }

        let sourceX = CGFloat(minX) + (outputPoint.x - destination.minX) / scale - 0.5
        let sourceY = CGFloat(minY) + (outputPoint.y - destination.minY) / scale - 0.5
        let x0 = Int(floor(sourceX))
        let y0 = Int(floor(sourceY))
        let xMix = sourceX - CGFloat(x0)
        let yMix = sourceY - CGFloat(y0)

        let top = sourceAlpha(x: x0, y: y0) * (1 - xMix)
            + sourceAlpha(x: x0 + 1, y: y0) * xMix
        let bottom = sourceAlpha(x: x0, y: y0 + 1) * (1 - xMix)
            + sourceAlpha(x: x0 + 1, y: y0 + 1) * xMix
        let alpha = top * (1 - yMix) + bottom * yMix

        if alpha > 0 {
            let offset = y * output.bytesPerRow + x * 4
            bitmap[offset] = 0
            bitmap[offset + 1] = 0
            bitmap[offset + 2] = 0
            bitmap[offset + 3] = UInt8((alpha * 255).rounded())
        }
    }
}

guard let png = output.representation(using: .png, properties: [:]) else {
    fatalError("unable to encode output image")
}
try png.write(to: outputURL, options: .atomic)
