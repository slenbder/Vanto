# CLAUDE.md

This file provides compact working guidance for coding agents in this
repository.

## What this is

PasteQueue is a macOS menu-bar-only utility. ⌃⌘C toggles collection; while
collection is active, ordinary ⌘C copies text, images, or files into a FIFO
queue. ⌃⌘V or the Paste button sends the next item. Minimum target: macOS
13.0; Apple Silicon only.

## Build & test

The project file (`PasteQueue.xcodeproj`) is generated from `project.yml` via XcodeGen — edit `project.yml`, not the `.xcodeproj` directly.

```bash
# Regenerate .xcodeproj after editing project.yml
xcodegen generate

# Build
xcodebuild -scheme PasteQueue -configuration Debug build

# Run the isolated unit-test target
xcodebuild test -scheme PasteQueue -destination 'platform=macOS' \
  -only-testing:PasteQueueTests \
  -derivedDataPath /private/tmp/PasteQueueDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` applies to the test invocation, not to release builds.
Do not claim tests passed unless they were run successfully on the current HEAD.
Use README.md for the final manual release checklist.

**App Sandbox must be OFF.** A sandboxed app cannot post synthetic keyboard events or register global key monitors — this is a hard requirement, not optional.

## Architecture

Six source files, including one protocol:

| File | Role |
|------|------|
| `PasteQueueApp.swift` | `@main` entry point + `AppDelegate` owning status UI, popover lifecycle, recipient focus restoration, and paste routing |
| `PasteStack.swift` | Singleton model: FIFO queue, clipboard polling, synthetic paste, Launch at Login |
| `HotkeyManager.swift` | Registers global + local `NSEvent` monitors for ⌃⌘C / ⌃⌘V |
| `PasteStackMenu.swift` | SwiftUI popover content with hand-rolled drag-to-reorder |
| `ClipboardItem.swift` | `ClipboardItem` enum (`.text`, `.image`, `.file`) + `QueuedClipboardItem` wrapper |
| `PasteboardProviding.swift` | Complete pasteboard seam for change count, text, image/file reads, and content replacement |

### Data flow

`PasteStack` owns queue state, pasteboard capture/replacement, file storage, and
synthetic ⌘V. `AppDelegate` owns window/application concerns: it remembers the
external frontmost app before opening the menu, restores that recipient for a
paste requested from the popover, and calls `PasteStack.pasteNext()` only after
focus restoration succeeds. Hotkey requests are routed through `AppDelegate`.

Clipboard polling runs every 0.25 seconds while collection is active.
`pasteNext()` first captures a pending pasteboard change when collection is on,
then consumes the FIFO head. It does not capture external clipboard content
when collection is off.

### Critical ordering in `checkPasteboard()`

File detection (`NSURL` with `.urlReadingFileURLsOnly`) **must run before** image detection (`NSImage`). Copying a file in Finder puts a `public.file-url` on the pasteboard; `NSImage` will "succeed" against it, but returns the generic file-type icon instead of the file's actual content. Catching the URL first avoids this.

The required detection order is **files → images → text**. All reads and
writes go through `PasteboardProviding`; do not bypass it with
`NSPasteboard.general`.

### File copy-on-capture

When a file is queued, it is copied to
`ClipboardFiles/<item UUID>/<original filename>`. The UUID directory prevents
same-name collisions while preserving the receiver-visible filename. Cleanup
is scoped to storage owned by that queue item. Current cleanup points are
startup orphan cleanup, Clear/remove, and delayed cleanup about two seconds
after paste; do not claim a separate ordinary-Quit cleanup.

### Popover lifecycle

The popover uses `.applicationDefined` with explicit closing for the status
item, outside click, and a drained queue. Escape is handled by a local key
monitor while PasteQueue is receiving keyboard events; its behavior after
focus returns to the external application has not been separately confirmed. A
fresh hosting controller is created at each opening. That opening's initial
list height is passed as its minimum (capped by the view at 230 pt), keeping
controls stable while a queue is consumed; reopening recalculates a compact
height. During sequential paste the popover remains available while items
remain and closes after the final item.

### Status item ownership

`AppDelegate` uses AppKit `NSStatusItem`, not `MenuBarExtra`, so the template icon
tracks the status-bar button's effective appearance. The count is a separate
`CenteredLabelView`; keep its frame calculation in the queue subscription after
AppKit has established the button bounds.

### Hotkey matching

`HotkeyManager` uses `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` + `UCKeyTranslate` to map the physical keyCode to a character under the ASCII-capable hardware layout. This keeps ⌃⌘C/⌃⌘V tracking the physical key under Dvorak/AZERTY while being unaffected by non-Latin input sources (Cyrillic, Japanese, etc.).

Both a global and a local `NSEvent` monitor are registered — the global monitor
misses events when PasteQueue itself is active, and the local monitor covers
that case. Caps Lock and non-shortcut device flags do not prevent matching;
Shift and Option do. Key-repeat events are ignored.

### Drag-to-reorder in PasteStackMenu

Reordering is a hand-rolled `DragGesture`, not `List(onMove:)`. Keep its named
coordinate space on the stable rows container; moving it to the offset row
reintroduces translation drift.

## Test isolation

Tests inject `MockPasteboard`, the ⌘V sender, cleanup scheduler,
Accessibility state, Launch at Login service, and a unique temporary storage
directory; automatic polling is disabled. Image and file tests remain in
memory except for files created under those temporary directories. The test
host must return before production singletons, polling, Accessibility prompts,
login-item state, or production storage are touched. Tests must never use
`NSPasteboard.general`.

## Extending content types

To add a new pasteboard type, add a case to `ClipboardItem`, then add a detection branch in `PasteStack.checkPasteboard()` (keeping file detection first), a paste branch in `pasteNext()`, and a display branch in `QueueRowView.body`.
