// Renders the synthetic OCR fixtures from text written for this project
// (plan phase 5): Fixtures/ocr-two-column.png and Fixtures/ocr-table.png.
// Usage: xcrun swift Scripts/make-ocr-fixtures.swift <output directory>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Fixtures")

func canvas(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context
}

func attributed(_ text: String, size: CGFloat, bold: Bool = false) -> NSAttributedString {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    return NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    ])
}

/// Draws wrapped text in `rect` (top-left y measured from the top of the image).
func draw(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool = false, context: CGContext, imageHeight: Int) {
    let frameRect = CGRect(x: rect.minX, y: CGFloat(imageHeight) - rect.maxY, width: rect.width, height: rect.height)
    let setter = CTFramesetterCreateWithAttributedString(attributed(text, size: size, bold: bold))
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: frameRect, transform: nil), nil)
    CTFrameDraw(frame, context)
}

func save(_ context: CGContext, _ name: String) {
    let url = output.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print(url.path)
}

// Two columns under a full-width title. The left column must be read first.
do {
    let width = 1700, height = 1100
    let context = canvas(width, height)
    draw("Notes from the harbour market", in: CGRect(x: 80, y: 60, width: 1540, height: 70), size: 44, bold: true,
         context: context, imageHeight: height)
    let left = [
        "Alpha. The market opens at six, an hour before the first ferry leaves the quay and the bakers arrive with their carts.",
        "Bravo. Marta has run the vegetable stall for nineteen years and keeps a small notebook in her apron pocket.",
        "Charlie. By noon the square is crowded, and the fishmonger tells the same joke to everyone who will listen.",
    ]
    let right = [
        "Delta. Behind the market two friends repair old radios on a bench covered with valves, screws and wire.",
        "Echo. The last ferry leaves at six in the evening, and the captain still enjoys the slow turn into the harbour.",
    ]
    for (index, text) in left.enumerated() {
        draw(text, in: CGRect(x: 80, y: 190 + index * 280, width: 700, height: 240), size: 30, context: context, imageHeight: height)
    }
    for (index, text) in right.enumerated() {
        draw(text, in: CGRect(x: 920, y: 190 + index * 280, width: 700, height: 240), size: 30, context: context, imageHeight: height)
    }
    save(context, "ocr-two-column.png")
}

// A ruled table under a heading, then a closing paragraph.
do {
    let width = 1400, height = 900
    let context = canvas(width, height)
    draw("Ferry timetable", in: CGRect(x: 80, y: 50, width: 1240, height: 70), size: 44, bold: true, context: context, imageHeight: height)
    let rows = [["Route", "Departure", "Price"], ["Island", "07:10", "6.50"], ["Lighthouse", "09:40", "4.25"], ["Old town", "12:15", "3.00"]]
    let left = 80, top = 170, columnWidth = 400, rowHeight = 110
    context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setLineWidth(3)
    for row in 0...rows.count {
        let y = height - (top + row * rowHeight)
        context.move(to: CGPoint(x: left, y: y))
        context.addLine(to: CGPoint(x: left + columnWidth * 3, y: y))
    }
    for column in 0...3 {
        let x = left + column * columnWidth
        context.move(to: CGPoint(x: x, y: height - top))
        context.addLine(to: CGPoint(x: x, y: height - (top + rows.count * rowHeight)))
    }
    context.strokePath()
    for (rowIndex, row) in rows.enumerated() {
        for (columnIndex, cell) in row.enumerated() {
            draw(cell, in: CGRect(x: left + columnIndex * columnWidth + 24, y: top + rowIndex * rowHeight + 30, width: columnWidth - 40, height: 60),
                 size: 34, bold: rowIndex == 0, context: context, imageHeight: height)
        }
    }
    draw("Tickets are sold at the office beside the quay.", in: CGRect(x: 80, y: 700, width: 1240, height: 80), size: 30,
         context: context, imageHeight: height)
    save(context, "ocr-table.png")
}
