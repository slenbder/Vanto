# Vanto

A minimal menu-bar utility for collecting text, images, and files, then pasting
them back in queue order. Text items can also be combined into one paste.

## ⌨️ Hotkeys — read this before you buy

Vanto uses two global hotkeys. These are the defaults; you can change
either shortcut in Settings:

- **⌃⌘C** (Control + Command + C) — start/stop collecting
- **⌃⌘V** (Control + Command + V) — paste the next item in the queue

Check these against any hotkey tools you already have running (Raycast,
Ice, Rectangle, BetterTouchTool, etc.). The shortcuts are observed globally
without blocking other apps, so a combination already used elsewhere can
trigger both Vanto and that app's action. Rebind it in Settings if there
is a conflict.

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon only — Intel Macs are not supported and have not been tested

## Installing

The first release is planned as a direct download from the Vanto website
for Apple Silicon Macs. The package format has not been finalized. If you
receive a `Vanto.app`, move it to `/Applications` before enabling Launch
at Login. See `SETUP.md` to build the app from source.

## Trial and license

- **14-day free trial.** Every feature is available for 14 days (exactly
  14 × 24 hours) from the first launch. No account or internet connection is
  needed. Settings shows the days left, and a one-time reminder appears in the
  menu 7, 3, and 1 day before the end.
- **After the trial.** Once the trial ends, the menu shows a license screen
  and the hotkeys open it instead of collecting or pasting. Your queue is kept.
- **License.** One purchase is a perpetual license for up to **3 Macs**, with
  all future updates included. Enter the key from the purchase email in the
  license screen, or earlier via Settings → **Activate License**. Access
  unlocks immediately, with no relaunch.
- **Moving to another Mac.** Settings → **Deactivate This Mac** frees one of
  the three device slots. It needs an internet connection.
- **Offline use.** A licensed copy keeps working offline. Vanto re-checks
  the license about once a week and simply retries later if the check fails.
  Only an explicit "invalid license" answer from the license server (for
  example, after a refund) removes the activation.
- **What leaves the Mac.** Activation sends the license key and the Mac's
  displayed device name to Lemon Squeezy. Weekly validation and deactivation
  send the license key and Lemon Squeezy instance ID. Copied content never
  leaves your Mac.

## Updates

Vanto updates itself automatically in the background (Sparkle). There is
no update button or setting, and you never need to pay for an update. Each
update is signed, and Vanto installs only updates that pass that check.

## Uninstalling

Vanto has no installer and no uninstaller — like most macOS utilities
distributed outside the App Store, removing it is just dragging
`Vanto.app` to the Trash. That leaves a few small things behind on disk,
none of which are dangerous, but worth knowing about if you want a fully
clean system:

- **`~/Library/Application Support/Vanto/ClipboardFiles/`** — temporary
  copies of files you've queued. Vanto removes owned copies when you use
  Clear or delete an item, about two seconds after that item is pasted, and on
  the next launch if an orphan remains. An ordinary Quit with files still
  queued does not perform a separate exit cleanup, so copies can remain until
  the next launch. Safe to delete manually while Vanto is not running.
- **`~/Library/Preferences/com.slenbder.vanto.plist`** — your Launch at
  Login choice, shortcut overrides, language choice, last-used text
  separator, which trial reminders were shown, and Sparkle's update-check
  timestamps. Safe to delete; `defaults delete com.slenbder.vanto` also
  works from Terminal.
- **Keychain items** `com.slenbder.vanto.trial` and
  `com.slenbder.vanto.license` — the trial start date and, if activated,
  your license key and device activation. Deactivate the Mac in Settings
  *before* deleting the app if you want to free its device slot. Keeping
  these items means a reinstall remembers both the trial and the license.
- **`~/Library/Caches/com.slenbder.vanto/`** — Sparkle's temporary update
  downloads. Safe to delete.
- **Launch at Login entry** — macOS does *not* clean this up when you delete
  the app. If you had "Launch at Login" enabled, go to **System Settings →
  General → Login Items & Extensions** after deleting the app and remove
  Vanto from that list — it'll otherwise sit there pointing at a Trashed
  app indefinitely.

To remove everything in one pass:
```
rm -rf ~/Library/Application\ Support/Vanto
rm -f ~/Library/Preferences/com.slenbder.vanto.plist
rm -rf ~/Library/Caches/com.slenbder.vanto
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

1. Launch Vanto — its icon appears in the menu bar (no Dock icon, this
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
   queue and brings the error back into view. Once Vanto posts the paste
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
  German addresses the user as "du" throughout, including the license screens.
- **Trial and license** — on a clean Mac (no `com.slenbder.vanto.*`
  Keychain items), confirm the trial starts with 14 days and survives a
  relaunch. Check the 7/3/1-day reminders appear once each, in English
  singular form for "1 day left". Let the trial end with the menu open and
  closed: collection stops, the hotkeys open the license screen, and the queue
  is kept. Buy with the live checkout, confirm the key email arrives, and
  activate. Check a wrong key, no network, and a 4th Mac each show their own
  message. Then deactivate this Mac and confirm the slot is freed. Confirm a
  refund revokes access at the next weekly check.
- **Updates** — install the previous signed build, publish a test feed, and
  confirm a silent update to the candidate keeps the trial/license state, the
  shortcuts, and the language.
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
  be distributed. Confirm its Info.plist carries the live `LemonSqueezy*`
  values, and that Settings → website opens `https://vanto.slenbder.com`.
- **Website** — on the production site, open every language (`/`, `/de/`,
  `/es/`, `/pt-br/`, `/ru/`, `/ja/`, `/zh-hans/`) on a phone and a desktop.
  Switch languages from the header menu and confirm the section anchor is
  kept; confirm a first visit to `/` in a private window follows the browser
  language once. Play the demo to the end, open the cookie banner, and check
  a localized 404 (for example `/ru/nope`). Confirm the Download and Buy links
  point at the signed artifact and the live checkout once they exist.

## Known limitations (v1)

- **Shortcut conflicts.** A custom shortcut can also trigger another app's
  action because Vanto's keyboard monitor does not block that app.
- **VoiceOver support is basic.** You can tell what state the app is in and
  perform the core actions, but:
  - Reordering the queue by dragging has no VoiceOver equivalent yet.
  - After deleting an item, VoiceOver focus drops to the scroll-area
    container rather than moving to the next row — you'll need to
    re-enter Interact mode before deleting the next one.
- **Secure input fields.** macOS or the focused application may suppress the
  global shortcut, the synthesized ⌘V, or both while secure input is active.
  Behavior can differ between password fields, system prompts, terminals, and
  third-party apps, so do not rely on Vanto for secure-entry workflows.
- **Intel Macs are unsupported and untested** (Apple Silicon only).

## Where to go from here

- Text, images, and files are all supported (`ClipboardItem.text` / `.image`
  / `.file`). Images are detected via `NSPasteboard.readObjects(forClasses:
  [NSImage.self], ...)`, which covers PNG/JPEG/TIFF/GIF/HEIC without listing
  UTIs by hand; files (single or Finder/Photos multi-select) are copied into
  Vanto's own storage at capture time so they can still be pasted even
  if the source app's sandbox only grants a read handle for the instant of
  the copy. Rich/styled text (e.g. from Pages or Word) is captured as its
  plain-text fallback — formatting is dropped, since `ClipboardItem` has no
  attributed-string case. Extending further (RTF with formatting, or any
  other pasteboard type) means adding another case to `ClipboardItem` and
  another branch in `PasteStack.checkPasteboard()`.
- No persistence — the queue lives in memory and resets when you quit. That's
  intentional for this use case; add it later if you ever want the queue to
  survive a relaunch.
- Release builds target Apple Silicon, enable Hardened Runtime, and carry the
  live Lemon Squeezy product. Developer ID signing, notarization, packaging,
  the first appcast entry, and the live purchase flow still need completion
  and verification on the final downloadable artifact.

See `SETUP.md` for building from source.
