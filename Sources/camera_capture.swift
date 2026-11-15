import AVFoundation
import CoreImage
import Foundation

final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let outputURL: URL
    let notBefore: Date
    let finished = DispatchSemaphore(value: 0)
    var failure: Error?
    private var saved = false
    private let imageContext = CIContext()

    init(outputURL: URL, warmupSeconds: TimeInterval) {
        self.outputURL = outputURL
        self.notBefore = Date().addingTimeInterval(warmupSeconds)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !saved, Date() >= notBefore else { return }
        saved = true
        defer { finished.signal() }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            failure = NSError(
                domain: "IPEVOCapture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The camera returned no video frame."]
            )
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        do {
            let data: Data?
            if outputURL.pathExtension.lowercased() == "png" {
                data = imageContext.pngRepresentation(
                    of: image,
                    format: .RGBA8,
                    colorSpace: colorSpace
                )
            } else {
                data = imageContext.jpegRepresentation(
                    of: image,
                    colorSpace: colorSpace,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.98]
                )
            }
            guard let data else {
                throw NSError(
                    domain: "IPEVOCapture",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not encode the camera frame."]
                )
            }
            try data.write(to: outputURL, options: .atomic)
        } catch {
            failure = error
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard (2...4).contains(arguments.count) else {
    fail("Usage: camera-capture OUTPUT.(png|jpg) [warmup-seconds] [camera-name]")
}
let warmupSeconds = arguments.count >= 3 ? (Double(arguments[2]) ?? 3.5) : 3.5
let cameraName = arguments.count >= 4 ? arguments[3] : "IPEVO V4K"

if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
    let decided = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .video) { _ in decided.signal() }
    _ = decided.wait(timeout: .now() + 30)
}

if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
    fail("Camera access is not authorized for the capture backend.")
}

let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external],
    mediaType: .video,
    position: .unspecified
)

guard let camera = discovery.devices.first(where: {
    $0.localizedName.localizedCaseInsensitiveContains(cameraName)
}) else {
    let names = discovery.devices.map(\.localizedName).joined(separator: ", ")
    fail("Camera matching '\(cameraName)' not found. Available cameras: \(names)")
}

if arguments[1] == "--list-formats" {
    var seen = Set<String>()
    for format in camera.formats {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let mediaSubtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let codec = String(format: "%c%c%c%c",
            (mediaSubtype >> 24) & 0xff,
            (mediaSubtype >> 16) & 0xff,
            (mediaSubtype >> 8) & 0xff,
            mediaSubtype & 0xff
        )
        let rates = format.videoSupportedFrameRateRanges
            .map { String(format: "%.0f-%.0f fps", $0.minFrameRate, $0.maxFrameRate) }
            .joined(separator: ", ")
        let photoSizes = format.supportedMaxPhotoDimensions
            .map { "\($0.width)x\($0.height)" }
            .joined(separator: ",")
        let description = "\(dimensions.width)x\(dimensions.height) \(codec) \(rates) photos=\(photoSizes)"
        if seen.insert(description).inserted {
            print(description)
        }
    }
    exit(0)
}

guard let bestFormat = camera.formats.max(by: { lhs, rhs in
    let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
    let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
    let leftPixels = Int(left.width) * Int(left.height)
    let rightPixels = Int(right.width) * Int(right.height)
    if leftPixels != rightPixels { return leftPixels < rightPixels }
    let leftSubtype = CMFormatDescriptionGetMediaSubType(lhs.formatDescription)
    let rightSubtype = CMFormatDescriptionGetMediaSubType(rhs.formatDescription)
    let leftIs422 = leftSubtype == kCVPixelFormatType_422YpCbCr8_yuvs
    let rightIs422 = rightSubtype == kCVPixelFormatType_422YpCbCr8_yuvs
    if leftIs422 != rightIs422 { return !leftIs422 && rightIs422 }
    let leftRate = lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
    let rightRate = rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
    return leftRate < rightRate
}) else {
    fail("The IPEVO camera did not advertise any capture formats.")
}

let session = AVCaptureSession()
session.beginConfiguration()

do {
    let input = try AVCaptureDeviceInput(device: camera)
    guard session.canAddInput(input) else { fail("Could not attach the IPEVO camera.") }
    session.addInput(input)
} catch {
    fail("Could not open the IPEVO camera: \(error.localizedDescription)")
}

let videoOutput = AVCaptureVideoDataOutput()
videoOutput.alwaysDiscardsLateVideoFrames = true
let targetDimensions = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
let targetPixelFormat = CMFormatDescriptionGetMediaSubType(bestFormat.formatDescription)
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: targetPixelFormat,
    kCVPixelBufferWidthKey as String: targetDimensions.width,
    kCVPixelBufferHeightKey as String: targetDimensions.height,
]
guard session.canAddOutput(videoOutput) else { fail("Could not create a video output.") }
session.addOutput(videoOutput)

do {
    try camera.lockForConfiguration()
    camera.activeFormat = bestFormat
    camera.unlockForConfiguration()
} catch {
    fail("Could not select the IPEVO camera's maximum resolution: \(error.localizedDescription)")
}

session.commitConfiguration()

do {
    try camera.lockForConfiguration()
    camera.activeFormat = bestFormat
    camera.unlockForConfiguration()
} catch {
    fail("Could not preserve the IPEVO camera's maximum resolution: \(error.localizedDescription)")
}

let destination = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let delegate = FrameDelegate(outputURL: destination, warmupSeconds: warmupSeconds)
let frameQueue = DispatchQueue(label: "com.argrig.ipevo-capture.frames")
videoOutput.setSampleBufferDelegate(delegate, queue: frameQueue)
session.startRunning()

guard delegate.finished.wait(timeout: .now() + 15) == .success else {
    session.stopRunning()
    fail("Timed out while waiting for the IPEVO camera.")
}

session.stopRunning()
if let failure = delegate.failure {
    fail("Capture failed: \(failure.localizedDescription)")
}

print(destination.path)
