import CaptaloCore
import CaptaloOCR
import CoreGraphics
import Foundation
import ImageIO

/// captalo-ocr-probe <fixture.png> <expected.json>: runs the production
/// recognition step (VisionRecognizer, then DocumentTranscript) on a
/// committed synthetic fixture and checks block kinds, order and first words.
/// `captalo-ocr-probe --cancel <fixture.png>` cancels one recognition mid-run
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

struct FixedCapturer: RegionCapturer {
    let image: CGImage
    func capture(_ selection: RegionSelection) async throws -> CGImage { image }
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments.first == "--cancel", arguments.count == 2 {
        let image = try load(arguments[1])
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
