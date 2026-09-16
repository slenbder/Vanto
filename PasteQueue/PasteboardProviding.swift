import AppKit

/// The complete pasteboard surface used by PasteStack. Keeping AppKit's object-reading
/// APIs in the production implementation preserves its native type negotiation while
/// allowing tests to remain entirely in memory.
protocol PasteboardProviding: AnyObject {
    var changeCount: Int { get }
    func readFileURLs() -> [URL]
    func readImages() -> [NSImage]
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func replaceContents(with item: ClipboardItem) -> Bool
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

    func replaceContents(with item: ClipboardItem) -> Bool {
        clearContents()
        switch item {
        case .text(let string):
            return setString(string, forType: .string)
        case .image(let image):
            return writeObjects([image])
        case .file(let url, _):
            return writeObjects([url as NSURL])
        }
    }
}
