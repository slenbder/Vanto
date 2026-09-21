# CLAUDE.md

This file provides compact working guidance for coding agents in this
repository.

## What this is

PasteQueue is a macOS menu-bar-only utility. ⌃⌘C toggles collection; while
collection is active, ordinary ⌘C copies text, images, or files into a FIFO
queue. ⌃⌘V or the Paste button sends the next item. Minimum target: macOS
13.0; Apple Silicon only.

The popover has two screens: the queue (default) and Settings, reached via
the gear button in the shared header. Settings holds shortcut rebinding for
both actions, an in-app language override (7 locales), and Launch at Login.

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

Thirteen source files, including three protocols:

| File | Role |
|------|------|
| `PasteQueueApp.swift` | `@main` entry point + `AppDelegate` owning status UI, popover lifecycle, recipient focus restoration, and paste routing |
| `PasteStack.swift` | Singleton model: FIFO queue, clipboard polling, synthetic paste, Launch at Login |
| `HotkeyManager.swift` | Registers global + local `NSEvent` monitors for ⌃⌘C / ⌃⌘V, resolves live vs. overridden bindings, owns recording-pause state |
| `HotkeySpec.swift` | `ShortcutAction` enum, `HotkeySpec` (keyCode + modifiers), and `ShortcutRecording`'s pure classification/validation logic for capturing a new combo |
| `ShortcutStoring.swift` | `UserDefaults`-backed persistence for per-action shortcut overrides |
| `LanguagePreferenceStore.swift` | `SupportedLanguage` (the 7 shipped locales) + persisted in-app language override, independent of system locale |
| `PopoverRootView.swift` | True root of the popover content: owns which of the two screens is showing, the shared status row, outer padding/width, and the `.environment(\.locale:)` override |
| `PopoverStatusRow.swift` | Shared header across both screens — recording indicator, queue count, and the gear/close button that switches screens |
| `PasteStackMenu.swift` | Queue screen: item list with hand-rolled drag-to-reorder, Start/Paste/Clear/Quit |
| `SettingsMenu.swift` | Settings screen: shortcut recorder rows, language picker, Launch at Login, website/version row |
| `ShortcutRecorderField.swift` | One rebindable-shortcut row — owns the recording-mode local `NSEvent` monitor, delegates classification to `HotkeySpec.swift`, persists through `HotkeyManager` |
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
fresh hosting controller wrapping `PopoverRootView` is created at each opening
— `screen` always starts back at `.queue` on reopen, matching every other
piece of popover state (drag state, recording state, …) already resetting.
That opening's initial list height is passed as `PopoverRootView`'s minimum
(capped by `PasteStackMenu` at 230 pt), keeping controls stable while a queue
is consumed; reopening recalculates a compact height. During sequential paste
the popover remains available while items remain and closes after the final
item.

### Status item ownership

`AppDelegate` uses AppKit `NSStatusItem`, not `MenuBarExtra`, so the template icon
tracks the status-bar button's effective appearance. The count is a separate
`CenteredLabelView`; keep its frame calculation in the queue subscription after
AppKit has established the button bounds.

`menuBarIcon` (idle) and `menuBarIconFrame` (collecting — same outer contour,
hollow, so the count label has room inside it) are meant to be a matched pair.
Their current SVGs share the same outer path. Keep those paths aligned when
changing either icon so collecting-state toggles do not shift the silhouette.

### Hotkey matching

`HotkeyManager` uses `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` + `UCKeyTranslate` to map the physical keyCode to a character under the ASCII-capable hardware layout. This keeps ⌃⌘C/⌃⌘V tracking the physical key under Dvorak/AZERTY while being unaffected by non-Latin input sources (Cyrillic, Japanese, etc.).

Both a global and a local `NSEvent` monitor are registered — the global monitor
misses events when PasteQueue itself is active, and the local monitor covers
that case. Caps Lock and non-shortcut device flags do not prevent matching;
Shift and Option do. Key-repeat events are ignored.

An un-overridden action's default binding is resolved live against the
current keyboard layout in **both** directions — `matchingAction()` (keyCode
→ character, unmodified state) and `effectiveSpec()` (character → keyCode,
same unmodified state via `KeyboardLayoutTranslator.asciiCapableKeyCode`).
These two must stay on the same modifier-state table: `effectiveSpec()` used
to go through the Command-modified table instead (`commandKeyCode`), which on
a layout where that table disagrees with the unmodified one made Settings
display/dedupe-check a different physical key than the one that actually
fires. `commandKeyCode`/`commandVKeyCode` still exist and are still correct
for their one real use — synthesizing an actual ⌘V keypress in
`PasteStack.simulateCommandV()`, which genuinely needs the Command-modified
table. Don't reuse them for anything in the matching/display path.

`matchingAction()` checks persisted physical overrides first, then translates
only keydowns with the exact default modifiers when an action still uses its
default. The global monitor sees every system-wide keydown, so the underlying
TIS/Carbon lookup must stay off the path for unrelated keys. If a layout
change puts a live default on a saved override, the override wins and Settings
shows the conflict on the default row.

### Rebindable shortcuts (Settings screen)

Each `ShortcutAction` (`startStopCollecting`, `pasteNext`) has a factory
default (`defaultCharacter`, live-translated as above) and an optional
persisted override (`HotkeySpec`: raw keyCode + modifiers, matched exactly,
not layout-translated — required regardless, since function keys have no
ASCII character). `HotkeyManager.effectiveSpec(for:)` returns the override if
set, else the live default; `ShortcutRecorderField` uses it for both display
and duplicate-checking a freshly recorded combo against every *other*
`ShortcutAction` (loop over `.allCases`, not a hardcoded pair — extending the
enum should not require touching this check).

Recording is single-flight across rows: `HotkeyManager.recordingAction`
(`ShortcutAction?`) is the one place that state lives — both
`ShortcutRecorderField` rows read it directly via `@ObservedObject
hotkeyManager`, so starting to record one row is automatically visible to the
other without a separately-threaded `@State`/`@Binding` to keep in sync.
While non-nil, `matchingAction()` suppresses **both** actions, not just the
one being rebound — intentional (see `testPausingSuppressesAllMatchingUntilResumed`),
not something to "fix" into per-action suppression.

Escape while recording is owned entirely by `AppDelegate`'s existing
Escape-closes-popover local monitor via `HotkeyManager.cancelRecordingHandler`
— not by `ShortcutRecorderField`'s own recording monitor, which explicitly
lets Escape (`ShortcutRecording.escapeKeyCode`, the one definition three
call sites share) pass through unswallowed. That pass-through guard matters
regardless of which monitor AppKit happens to call first for a given event —
without it, the recording monitor's default "swallow everything" behavior
would eat Escape itself if it were ever invoked before AppDelegate's monitor.

Persistence (`ShortcutStoring` / `UserDefaultsShortcutStore`, key
`shortcutOverride.<action>`) logs on encode/decode failure instead of
silently discarding — a custom binding that fails to persist should look
like a logged error, not a binding that quietly reverted to default on next
launch.

### Localization

`Localizable.xcstrings` covers 7 locales (`SupportedLanguage`: en, ru,
zh-Hans, es, ja, de, pt-BR). `LanguagePreferenceStore` persists an optional
in-app override (nil = follow system); `PopoverRootView` applies it via
`.environment(\.locale:)` to the whole popover subtree. Strings built outside
SwiftUI `Text` need `AppLocalization.bundle(for:)` as well as a locale: the
locale argument alone formats values but does not select another `.lproj`.
This applies to the status-item accessibility labels and shortcut captions.

The popover's fixed width (`PopoverRootView`, 270pt) is sized to the longest
string that actually ships across all 7 locales — verified by measuring
`NSFont`-rendered widths, not by eyeballing screenshots. If a new locale is
added or a string is lengthened, re-measure before assuming 270 still holds;
the previous 240pt regressed silently to visible truncation/wrapping in ru/es/de
before this was caught.

### Drag-to-reorder in PasteStackMenu

Reordering is a hand-rolled `DragGesture`, not `List(onMove:)`. Keep its named
coordinate space on the stable rows container; moving it to the offset row
reintroduces translation drift.

## Test isolation

Tests inject `MockPasteboard`, the ⌘V sender, cleanup scheduler,
Accessibility state, Launch at Login service, a shortcut store
(`MockShortcutStore`), a language preference store
(`MockLanguagePreferenceStore`), and a unique temporary storage directory;
automatic polling is disabled. Image and file tests remain in memory except
for files created under those temporary directories. The test host must
return before production singletons, polling, Accessibility prompts,
login-item state, or production storage are touched. Tests must never use
`NSPasteboard.general`.

`HotkeyManagerTests` constructs `HotkeyManager` directly through its DI init,
with a fixed key-to-character test layout. `HotkeySpecTests` injects the same
kind of mapping into its classification checks. Neither uses `.shared` or the
host's selected keyboard layout. The zero-arg production init remains private
so tests cannot accidentally create a second instance with real monitors.

## Extending content types

To add a new pasteboard type, add a case to `ClipboardItem`, then add a detection branch in `PasteStack.checkPasteboard()` (keeping file detection first), a paste branch in `pasteNext()`, and a display branch in `QueueRowView.body`.
