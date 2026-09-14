import AppKit

enum ClipboardItem: Equatable {
    case text(String)
    case image(NSImage)
    // url points at ClipboardFiles/<item UUID>/<original filename>, not the source path.
    // originalFilename is retained separately for display.
    case file(url: URL, originalFilename: String)

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        switch (lhs, rhs) {
        case (.text(let l), .text(let r)):
            return l == r
        case (.image(let l), .image(let r)):
            return l === r
        case (.file(let lURL, _), .file(let rURL, _)):
            return lURL == rURL
        default:
            return false
        }
    }
}

/// Wraps a ClipboardItem with an identity that's stable regardless of content.
/// Needed because the queue can hold two entries with equal content (e.g. the same
/// text copied twice in a row) — identifying a specific queue slot by content match
/// would risk deleting/targeting the wrong one of a pair of duplicates.
struct QueuedClipboardItem: Identifiable, Equatable {
    let id: UUID
    let content: ClipboardItem

    init(id: UUID = UUID(), content: ClipboardItem) {
        self.id = id
        self.content = content
    }
}
