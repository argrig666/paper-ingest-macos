import CoreGraphics
import Foundation
import ImageIO

struct Metrics: Codable {
    let width: Int
    let height: Int
    let p05: Int
    let p50: Int
    let p95: Int
    let p99: Int
    let highlightClip: Double
    let shadowClip: Double
    let meanGradient: Double
    let score: Double
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: image-text-score IMAGE")
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fail("Could not read image.")
}

let sampleWidth = 512
let sampleHeight = max(1, Int(Double(image.height) * Double(sampleWidth) / Double(image.width)))
var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)

guard let context = CGContext(
    data: &pixels,
    width: sampleWidth,
    height: sampleHeight,
    bitsPerComponent: 8,
    bytesPerRow: sampleWidth,
    space: CGColorSpaceCreateDeviceGray(),
    bitmapInfo: CGImageAlphaInfo.none.rawValue
) else {
    fail("Could not create analysis buffer.")
}

context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

let x0 = sampleWidth / 10
let x1 = sampleWidth - x0
let y0 = sampleHeight / 10
let y1 = sampleHeight - y0
var histogram = [Int](repeating: 0, count: 256)
var count = 0
var gradientSum = 0.0
var gradientCount = 0

for y in y0..<y1 {
    for x in x0..<x1 {
        let value = Int(pixels[y * sampleWidth + x])
        histogram[value] += 1
        count += 1
        if x + 1 < x1, y + 1 < y1 {
            let right = Int(pixels[y * sampleWidth + x + 1])
            let down = Int(pixels[(y + 1) * sampleWidth + x])
            gradientSum += Double(abs(value - right) + abs(value - down)) / 2.0
            gradientCount += 1
        }
    }
}

func percentile(_ fraction: Double) -> Int {
    let target = Int(Double(count - 1) * fraction)
    var cumulative = 0
    for value in 0..<256 {
        cumulative += histogram[value]
        if cumulative > target { return value }
    }
    return 255
}

let highlights = histogram[250...255].reduce(0, +)
let shadows = histogram[0...5].reduce(0, +)
let p05 = percentile(0.05)
let p50 = percentile(0.50)
let p95 = percentile(0.95)
let p99 = percentile(0.99)
let highlightClip = Double(highlights) / Double(count)
let shadowClip = Double(shadows) / Double(count)
let meanGradient = gradientSum / Double(max(1, gradientCount))

// Favor a bright but unclipped sheet, retain faint strokes, and mildly reward edge detail.
let exposureTarget = -abs(Double(p95) - 238.0)
let clippingPenalty = 450.0 * highlightClip + 40.0 * shadowClip
let dynamicRangeReward = 0.04 * Double(p95 - p05)
let detailReward = 0.15 * meanGradient
let score = exposureTarget - clippingPenalty + dynamicRangeReward + detailReward

let metrics = Metrics(
    width: image.width,
    height: image.height,
    p05: p05,
    p50: p50,
    p95: p95,
    p99: p99,
    highlightClip: highlightClip,
    shadowClip: shadowClip,
    meanGradient: meanGradient,
    score: score
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
print(String(data: try encoder.encode(metrics), encoding: .utf8)!)
