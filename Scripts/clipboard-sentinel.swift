// Debug helper for the capture matrix (make clipboard-sentinel).
// Writes plain text, RTF, a custom type and a file URL to the GENERAL
// pasteboard, replacing what is there, so the probe can check that every
// representation survives a Copy-layer capture. Synthetic content only.
import AppKit

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
let item = NSPasteboardItem()
item.setString("Cáptalo clipboard sentinel", forType: .string)
item.setData(Data("{\\rtf1\\ansi Cáptalo clipboard sentinel}".utf8), forType: .rtf)
item.setData(Data([0xCA, 0xB7, 0xA1, 0x0]), forType: NSPasteboard.PasteboardType("com.thecreativetoken.captalo.sentinel"))
let file = NSPasteboardItem()
file.setString(URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist").absoluteString, forType: .fileURL)
let ok = pasteboard.writeObjects([item, file])
print(ok ? "sentinel written: 2 items, 4 types, change count \(pasteboard.changeCount)" : "sentinel write failed")
exit(ok ? 0 : 1)
