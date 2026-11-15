import Foundation
import ImageIO
import Vision

struct Candidate: Codable {
    let text: String
    let confidence: Float
}

struct Region: Codable {
    let id: String
    let boundingBox: [String: Double]
    let candidates: [Candidate]
    let status: String
}

struct Document: Codable {
    let schemaVersion: String
    let sourceImage: String
    let width: Int
    let height: Int
    let regions: [Region]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: vision-ocr INPUT_IMAGE OUTPUT_JSON")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fail("Could not read the input image.")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.automaticallyDetectsLanguage = true
request.minimumTextHeight = 0.006

do {
    try VNImageRequestHandler(cgImage: image).perform([request])
} catch {
    fail("Text recognition failed: \(error.localizedDescription)")
}

let observations = request.results ?? []
let regions = observations.enumerated().compactMap { index, observation -> Region? in
    let candidates = observation.topCandidates(3).map {
        Candidate(text: $0.string, confidence: $0.confidence)
    }
    guard let best = candidates.first else { return nil }
    let box = observation.boundingBox
    let status = best.confidence >= 0.75 ? "recognized" : "uncertain"
    return Region(
        id: "line-\(index + 1)",
        boundingBox: [
            "x": box.origin.x,
            "y": box.origin.y,
            "width": box.size.width,
            "height": box.size.height,
        ],
        candidates: candidates,
        status: status
    )
}

let document = Document(
    schemaVersion: "paper-ingest/0.1",
    sourceImage: inputURL.path,
    width: image.width,
    height: image.height,
    regions: regions
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

do {
    try encoder.encode(document).write(to: outputURL, options: .atomic)
} catch {
    fail("Could not write structured OCR: \(error.localizedDescription)")
}

print(outputURL.path)
