import CaptaloCore
import CaptaloOCR
import CoreGraphics
import Foundation
import ImageIO

/// captalo-ocr-probe <fixture.png> <expected.json>: runs the production
/// recognition step (VisionRecognizer, then DocumentTranscript) on a
/// committed synthetic fixture and checks block kinds, order and first words.
/// `captalo-ocr-probe --cancel <fixture.png>` first cancels a direct Vision
/// call mid-run (it must throw, not finish), then times out one recognition
/// through RegionReader and checks that the slot is freed within 1 s.
struct Expected: Decodable {
    struct Block: Decodable {
        let kind: String
        /// A word the block must contain (OCR may misread a leading letter).
        let contains: String
    }
    let blocks: [Block]
}

func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "captalo-ocr-probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read \(path)"])
    }
    return image
}

func kind(_ block: Block) -> (String, String) {
    switch block {
    case let .paragraph(text): ("paragraph", text)
    case let .listItem(text): ("listItem", text)
    case let .tableRow(cells): ("tableRow", cells.joined(separator: " "))
    case let .codeLine(text): ("codeLine", text)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("captalo-ocr-probe: \(message)\n".utf8))
    exit(1)
}

/// The fixture tiled 2 × 2, so a full recognition runs long enough to cancel mid-run.
func tiled(_ image: CGImage) -> CGImage {
    let context = CGContext(data: nil, width: image.width * 2, height: image.height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<2 { for y in 0..<2 {
        context.draw(image, in: CGRect(x: x * image.width, y: y * image.height, width: image.width, height: image.height))
    } }
    return context.makeImage()!
}

/// Vision must honour cancellation: cancelled at a fifth of a full run, the call throws.
func checkNativeCancellation(_ image: CGImage) async throws {
    let large = tiled(image)
    let fullStart = ContinuousClock.now
    _ = try await VisionRecognizer().recognize(large)
    let full = fullStart.duration(to: .now)
    let cancelAfter = max(full / 5, .milliseconds(10))
    let task = Task { try await VisionRecognizer().recognize(large) }
    try await Task.sleep(for: cancelAfter)
    let cancelled = ContinuousClock.now
    task.cancel()
    let result = await task.result
    let returnedMs = Double(cancelled.duration(to: .now) / .microseconds(1)) / 1000
    let fullMs = Int(full / .milliseconds(1)), afterMs = Int(cancelAfter / .milliseconds(1))
    guard case .failure = result else {
        fail("Vision finished instead of honouring a cancel \(afterMs) ms into a \(fullMs) ms run")
    }
    print("native cancel: threw \(returnedMs) ms after a cancel \(afterMs) ms into a \(fullMs) ms run")
}

struct FixedCapturer: RegionCapturer {
    let image: CGImage
    func capture(_ selection: RegionSelection) async throws -> CGImage { image }
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments.first == "--cancel", arguments.count == 2 {
        let image = try load(arguments[1])
        try await checkNativeCancellation(image)
        let slot = OCRSlot()
        let reader = RegionReader(capturer: FixedCapturer(image: image), recognizer: VisionRecognizer(), slot: slot,
                                  isCurrent: { _ in true }, timeout: .milliseconds(50))
        let selection = RegionSelection(displayID: 0, globalRect: .zero, localRect: .zero,
                                        pixelSize: CGSize(width: image.width, height: image.height))
        let token = await TokenMaker.make()
        let outcome: CaptureOutcome = await reader.read(token, selection)
        let timedOutOutcome = CaptureOutcome.failed(.ocrTimedOut)
        let timedOut = ContinuousClock.now
        while await slot.isReserved {
            if timedOut.duration(to: .now) > .seconds(1) { fail("slot still held 1 s after the caller's timeout") }
            try await Task.sleep(for: .milliseconds(1))
        }
        let freedMs = Int(timedOut.duration(to: .now) / .milliseconds(1))
        print("cancel: outcome \(outcome == timedOutOutcome ? "timedOut" : "\(outcome)"), slot freed \(freedMs) ms after the timeout")
        exit(outcome == timedOutOutcome ? 0 : 1)
    }
    guard arguments.count == 2 else { fail("usage: captalo-ocr-probe <fixture.png> <expected.json> | --cancel <fixture.png>") }
    let image = try load(arguments[0])
    let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    let started = ContinuousClock.now
    let blocks = DocumentTranscript.blocks(try await VisionRecognizer().recognize(image))
    let actual = blocks.map(kind)
    print("\(arguments[0]): \(actual.count) blocks in \(Int(started.duration(to: .now) / .milliseconds(1))) ms")
    for block in actual { print("  \(block.0): \(block.1.prefix(60))") }
    guard actual.count == expected.blocks.count else { fail("expected \(expected.blocks.count) blocks, got \(actual.count)") }
    for (index, (got, want)) in zip(actual, expected.blocks).enumerated() {
        guard got.0 == want.kind, got.1.contains(want.contains) else {
            fail("block \(index): expected \(want.kind) containing \"\(want.contains)\", got \(got.0) \"\(got.1.prefix(40))\"")
        }
    }
    print("ok")
} catch {
    fail("\(error)")
}

enum TokenMaker {
    static func make() async -> InputToken {
        let coordinator = RequestCoordinator { _, _, _ in NoSession() }
        return await coordinator.beginInput(kind: .region, source: InputSource(pid: 0, bundleID: nil, focusedElement: nil))
    }
}

struct NoSession: PlaybackSession {
    func start() async {}
    func stop() async {}
}
