// Renders the synthetic OCR fixtures from text written for this project
// (plan phase 5): Fixtures/ocr-two-column.png, ocr-table.png, ocr-terms.png,
// ocr-open-table.png and ocr-questions.png.
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

// Terms beside definitions, without rules. Each term is read with its definition.
do {
    let width = 1500, height = 700
    let context = canvas(width, height)
    let terms = [
        ("Quay", "The stone edge where the ferry ties up and the carts wait for the crates."),
        ("Valve", "A glass part of an old radio. It glows when the set is warm."),
        ("Stall", "A table with a roof, rented by the week from the town."),
    ]
    for (index, term) in terms.enumerated() {
        draw(term.0, in: CGRect(x: 80, y: 80 + index * 180, width: 260, height: 60), size: 30, bold: true, context: context, imageHeight: height)
        draw(term.1, in: CGRect(x: 400, y: 80 + index * 180, width: 1000, height: 150), size: 30, context: context, imageHeight: height)
    }
    save(context, "ocr-terms.png")
}

// A table with sentences in its cells and no rules. It is read row by row.
do {
    let width = 1500, height = 800
    let context = canvas(width, height)
    let rows = [
        ["Ferry", "Times", "Payment"],
        ["North", "Alpha. Boats leave at six and return at noon with the catch.", "Delta. Bring cash, because the kiosk takes no cards at all."],
        ["South", "Bravo. Boats leave at nine and carry only passengers and post.", "Echo. Buy the ticket online and show the code at the gate."],
    ]
    for (row, cells) in rows.enumerated() {
        for (column, text) in cells.enumerated() {
            draw(text, in: CGRect(x: [100, 420, 920][column], y: row == 0 ? 105 : 200 + (row - 1) * 220, width: 450, height: 190),
                 size: row == 0 ? 32 : 28, bold: row == 0, context: context, imageHeight: height)
        }
    }
    save(context, "ocr-open-table.png")
}

// A ruled table of questions and answers without a header. Each question is read with its answer.
do {
    let width = 1500, height = 800
    let context = canvas(width, height)
    let rows = [
        ["Can I bring a bicycle on the ferry in the summer?", "Yes, if there is room on deck after the cars."],
        ["Where do I buy a ticket when the kiosk is closed?", "Pay the crew on board, in cash or by card."],
        ["How long does the crossing to the island usually take?", "About forty minutes, or an hour when the sea is rough."],
    ]
    context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setLineWidth(3)
    for y in [80, 280, 480, 680] {
        context.move(to: CGPoint(x: 80, y: height - y))
        context.addLine(to: CGPoint(x: 1400, y: height - y))
    }
    for x in [80, 740, 1400] {
        context.move(to: CGPoint(x: x, y: height - 80))
        context.addLine(to: CGPoint(x: x, y: height - 680))
    }
    context.strokePath()
    for (row, cells) in rows.enumerated() {
        for (column, text) in cells.enumerated() {
            draw(text, in: CGRect(x: 110 + column * 660, y: 120 + row * 200, width: 560, height: 140), size: 30, context: context, imageHeight: height)
        }
    }
    save(context, "ocr-questions.png")
}
