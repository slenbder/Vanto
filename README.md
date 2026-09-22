# PasteQueue

A minimal menu-bar utility for collecting text, images, and files, then pasting
them back in queue order. Text items can also be combined into one paste.

## ⌨️ Hotkeys — read this before you buy

PasteQueue uses two global hotkeys. These are the defaults; you can change
either shortcut in Settings:

- **⌃⌘C** (Control + Command + C) — start/stop collecting
- **⌃⌘V** (Control + Command + V) — paste the next item in the queue

Check these against any hotkey tools you already have running (Raycast,
Ice, Rectangle, BetterTouchTool, etc.). The shortcuts are observed globally
without blocking other apps, so a combination already used elsewhere can
trigger both PasteQueue and that app's action. Rebind it in Settings if there
is a conflict.

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon only — Intel Macs are not supported and have not been tested

## Installing

The first release is planned as a direct download from the PasteQueue website
for Apple Silicon Macs. The package format has not been finalized. If you
receive a `PasteQueue.app`, move it to `/Applications` before enabling Launch
at Login. See `SETUP.md` to build the app from source.

## Uninstalling

PasteQueue has no installer and no uninstaller — like most macOS utilities
distributed outside the App Store, removing it is just dragging
`PasteQueue.app` to the Trash. That leaves a few small things behind on disk,
none of which are dangerous, but worth knowing about if you want a fully
clean system:

- **`~/Library/Application Support/PasteQueue/ClipboardFiles/`** — temporary
  copies of files you've queued. PasteQueue removes owned copies when you use
  Clear or delete an item, about two seconds after that item is pasted, and on
  the next launch if an orphan remains. An ordinary Quit with files still
  queued does not perform a separate exit cleanup, so copies can remain until
  the next launch. Safe to delete manually while PasteQueue is not running.
- **`~/Library/Preferences/com.slenbder.pastequeue.plist`** — your Launch at
  Login choice, shortcut overrides, language choice, and last-used text
  separator. Safe to delete; `defaults delete com.slenbder.pastequeue` also
  works from Terminal.
- **Launch at Login entry** — macOS does *not* clean this up when you delete
  the app. If you had "Launch at Login" enabled, go to **System Settings →
  General → Login Items & Extensions** after deleting the app and remove
  PasteQueue from that list — it'll otherwise sit there pointing at a Trashed
  app indefinitely.

To remove everything in one pass:
```
rm -rf ~/Library/Application\ Support/PasteQueue
rm -f ~/Library/Preferences/com.slenbder.pastequeue.plist
```
(then check Login Items as above, and empty the Trash).

## Opening a downloaded build

macOS opening behavior depends on how the specific artifact was signed,
notarized, and distributed. Follow the instructions shipped with that build and
do not bypass a security warning unless you trust its source. Developer ID,
notarization, and the final release package still need verification; enabling
Hardened Runtime in Release settings alone does not establish a Gatekeeper
outcome.

## First run

1. Launch PasteQueue — a 📋 icon appears in the menu bar (no Dock icon, this
   is a menu-bar-only utility).
2. macOS will prompt for Accessibility permission the first time it tries to
   register the global hotkeys. Approve it in
   **System Settings → Privacy & Security → Accessibility**.
3. If you skip or deny the prompt, the menu bar dropdown shows an
   **⚠️ Accessibility required** item — click it to jump straight to the
   right System Settings pane. The hotkeys silently do nothing until this is
   granted; there is no crash, just no effect.
4. During development, a rebuilt app may need to be removed and re-added in
   Accessibility settings. Make sure the permission belongs to the exact app
   copy you are running.

## Using it

1. Press ⌃⌘C once to start collecting. Press it again whenever you want to
   stop collecting.
2. While collection is on, copy text, images, or files with the normal ⌘C in
   the order you want them pasted.
3. Switch to the destination and press ⌃⌘V, or open the menu and click
   **Paste**, to paste the first item.
4. Repeat ⌃⌘V or **Paste** for the remaining items.
   Once the last item is pasted, collecting mode turns itself off
   automatically — no need to remember to hit "Stop collecting."
5. Open the menu to preview the queue, delete individual items, **Clear** it,
   drag rows to reorder them, switch collection with **Start**/**Stop**, or use
   **Paste**. During sequential pasting from an open menu, it remains available
   while items remain and closes after the last item is pasted.
6. With at least two items queued, choose **Combine and Paste…** to join text
   into one paste. Choose a new line, blank line, space, comma and space, no
   separator, or a custom separator. The preview shows a shortened sample;
   the full text is pasted in the current queue order. Every queued item must
   be text. The last successfully used separator is remembered. **Back** or
   closing the menu cancels an in-flight request; a failed request keeps the
   queue and brings the error back into view. Once PasteQueue posts the paste
   command successfully, it drains the queue. As with ordinary Paste, it
   cannot confirm that the destination app actually inserted the text.

The queue holds at most 99 items — anything copied past that is silently
ignored (no alert) until you paste some off or clear the queue. The counter
on the menu bar icon turns red once you hit the cap, as a clear signal
you're full.

## Launch at Login

The **Settings** screen has a **Launch at Login** item with a checkmark showing
current state — click it to toggle. Uses `SMAppService` (macOS 13+), so it only
works once the app is actually installed in `/Applications` (an `.app`
launched straight out of Xcode's DerivedData can fail to register — that's
expected, not a bug).

## Manual release checklist

Run this checklist against the actual final release build. Earlier targeted
checks during development are useful evidence, but are not a complete pass of
the final artifact.

- **Collection and hotkeys** — press ⌃⌘C once, copy several items with
  ordinary ⌘C, then stop with ⌃⌘C. Confirm Caps Lock does not interfere
  and holding either hotkey does not repeat its action.
- **FIFO and content types** — paste mixed text, images, a Finder file, a Finder
  multi-selection, and a Photos item. Confirm ordering, image previews, original
  filenames, and the pasted file contents.
- **Popover workflow** — verify previews, individual delete, Clear,
  drag-to-reorder, Start/Stop, and Paste. With several items queued, paste by
  both button and hotkey: focus must return to the external recipient, the menu
  must remain available while items remain, and it must close after the last
  item. Reopen it with a shorter queue and confirm its height is compact. Also
  check status-item toggle, outside click, and Escape closing. Check the
  header divider on both screens, a single divider when the queue is empty,
  and the first row's hover outline beside the scroll bar.
- **Combine and Paste** — reorder three text items, choose a preset and then a
  custom separator, and confirm the full combined text appears once in TextEdit.
  Confirm Back changes nothing, closing the menu during recipient activation
  cancels the paste, the last successful separator returns on reopening,
  mixed text/file or text/image queues cannot be combined, and the queue stays
  intact when the target app or Accessibility permission is unavailable. If
  focus moved to the target before failure, confirm the panel and error become
  visible again. Repeat in VoiceOver and German at 99 items; the German count
  intentionally takes two left-aligned lines.
- **Queue cap** — copy 99+ items, confirm additional items are ignored while
  full and the count turns red at 99.
- **Settings screen** — open it via the gear button. Rebind each shortcut to a
  new combo and confirm the new key works and the old one no longer does;
  confirm recording a combo already used by the other action shows the
  "Already used by …" caption instead of saving; confirm Reset restores the
  factory default. Confirm Escape cancels an in-progress recording without
  closing the popover, and closing the popover mid-recording (outside click)
  doesn't leave hotkeys stuck paused afterward. Switch the language picker
  through a few locales and confirm both screens' text updates immediately,
  with no truncated labels — check at least ru, es, de, and one of ja/zh-Hans.
- **Accessibility and VoiceOver** — test a fresh permission grant, status and
  queue announcements, all core buttons, and deletion focus. Re-test after any
  UI change.
- **Launch at Login** — test both enabled and disabled states across a real
  logout/login or restart with the app installed in `/Applications`.
- **Menu bar appearance** — use light and dark desktop wallpapers independently
  of system appearance; confirm the template icon and count remain legible.
- **Final artifact** — run the full automated test target, smoke-test on the
  supported macOS versions, and verify installation, first launch, permissions,
  signing, notarization, and Gatekeeper behavior on the exact artifact that will
  be distributed. Replace the Settings screen's current website placeholder
  with the real product/support destination before shipping.

## Known limitations (v1)

- **Shortcut conflicts.** A custom shortcut can also trigger another app's
  action because PasteQueue's keyboard monitor does not block that app.
- **VoiceOver support is basic.** You can tell what state the app is in and
  perform the core actions, but:
  - Reordering the queue by dragging has no VoiceOver equivalent yet.
  - After deleting an item, VoiceOver focus drops to the scroll-area
    container rather than moving to the next row — you'll need to
    re-enter Interact mode before deleting the next one.
- **Secure input fields.** macOS or the focused application may suppress the
  global shortcut, the synthesized ⌘V, or both while secure input is active.
  Behavior can differ between password fields, system prompts, terminals, and
  third-party apps, so do not rely on PasteQueue for secure-entry workflows.
- **Intel Macs are unsupported and untested** (Apple Silicon only).

## Where to go from here

- Text, images, and files are all supported (`ClipboardItem.text` / `.image`
  / `.file`). Images are detected via `NSPasteboard.readObjects(forClasses:
  [NSImage.self], ...)`, which covers PNG/JPEG/TIFF/GIF/HEIC without listing
  UTIs by hand; files (single or Finder/Photos multi-select) are copied into
  PasteQueue's own storage at capture time so they can still be pasted even
  if the source app's sandbox only grants a read handle for the instant of
  the copy. Rich/styled text (e.g. from Pages or Word) is captured as its
  plain-text fallback — formatting is dropped, since `ClipboardItem` has no
  attributed-string case. Extending further (RTF with formatting, or any
  other pasteboard type) means adding another case to `ClipboardItem` and
  another branch in `PasteStack.checkPasteboard()`.
- No persistence — the queue lives in memory and resets when you quit. That's
  intentional for this use case; add it later if you ever want the queue to
  survive a relaunch.
- Release builds now target Apple Silicon and enable Hardened Runtime.
  Developer ID signing, notarization, packaging, and paid delivery still need
  completion and verification on the final downloadable artifact.

See `SETUP.md` for building from source.
