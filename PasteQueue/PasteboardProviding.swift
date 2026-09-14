import AppKit

/// The complete pasteboard surface used by PasteStack. Keeping AppKit's object-reading
/// APIs in the production implementation preserves its native type negotiation while
/// allowing tests to remain entirely in memory.
protocol PasteboardProviding: AnyObject {
    var changeCount: Int { get }
    func readFileURLs() -> [URL]
    func readImages() -> [NSImage]
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func replaceContents(with item: ClipboardItem)
}

extension NSPasteboard: PasteboardProviding {
    func readFileURLs() -> [URL] {
        (readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
    }

    func readImages() -> [NSImage] {
        (readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]) ?? []
    }

    func replaceContents(with item: ClipboardItem) {
        clearContents()
        switch item {
        case .text(let string):
            setString(string, forType: .string)
        case .image(let image):
            writeObjects([image])
        case .file(let url, _):
            writeObjects([url as NSURL])
        }
    }
}
