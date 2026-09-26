# CLAUDE.md

This file provides compact working guidance for coding agents in this
repository.

## What this is

Vanto is a macOS menu-bar-only utility. ⌃⌘C toggles collection; while
collection is active, ordinary ⌘C copies text, images, or files into a FIFO
queue. ⌃⌘V or the Paste button sends the next item. Minimum target: macOS
13.0; Apple Silicon only.

The popover has two screens: the queue (default) and Settings, reached via
the gear button in the shared header. Settings holds shortcut rebinding for
both actions, an in-app language override (7 locales), and Launch at Login.
The queue screen also opens a short confirmation view for combining all queued
text into one paste with a chosen separator.

The app is a paid product: a local 14-day full-access trial starts at first
launch, then a Lemon Squeezy license key (3 devices, perpetual) unlocks it.
After the trial ends without a license, the popover shows an activation gate
and both hotkeys open it instead of acting. Sparkle 2 installs updates
silently in the background.

## Build & test

The project file (`Vanto.xcodeproj`) is generated from `project.yml` via XcodeGen — edit `project.yml`, not the `.xcodeproj` directly.

```bash
# Regenerate .xcodeproj after editing project.yml
xcodegen generate

# Build
xcodebuild -scheme Vanto -configuration Debug build

# Run the isolated unit-test target
xcodebuild test -scheme Vanto -destination 'platform=macOS' \
  -only-testing:VantoTests \
  -derivedDataPath /private/tmp/VantoDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` applies to the test invocation, not to release builds.
Do not claim tests passed unless they were run successfully on the current HEAD.
Use README.md for the final manual release checklist.

The first release is planned for direct website download on Apple Silicon.
`project.yml` declares version 0.1/build 1; its Release configuration targets
arm64 only and enables Hardened Runtime. The project uses automatic signing,
but this host currently has no valid code-signing identity, including no
Developer ID Application identity, so no build is distributable. Check
`docs/RELEASE_HANDOFF.md` for the current release gate before changing signing
or publishing an artifact.

`Vanto/Info.plist` is written by XcodeGen from `project.yml`'s
`info.properties`; change keys there, never in the plist or `.xcodeproj`.
Lemon Squeezy IDs and the checkout URL are per-configuration build settings
(`LEMON_SQUEEZY_STORE_ID`, `_PRODUCT_ID`, `_VARIANT_ID`, `_CHECKOUT_URL`):
Debug points at the test-mode product, Release at the live one. A pre-build
script fails `archive` if any of them is empty.

CI (`.github/workflows/ci.yml`) runs on PRs to and pushes of `main`.
The `Test and build` job regenerates the project and fails on any diff in
`Vanto.xcodeproj` or `Info.plist`, runs `VantoTests`, and compiles Release
unsigned. The `Site build is current` job reruns
`node scripts/build-site.mjs` and fails if `Site/` differs. It publishes
nothing.

`main` is protected by the repository ruleset `main`: no deletion, no force
push, changes only through a pull request (0 approvals, since a solo author
cannot approve their own PR), and both CI jobs above must pass before merge.
The Repository admin role may bypass it; use that only for a deliberate
hotfix, and work on a branch with a PR otherwise. GitHub's "AI Scan for pull
requests" is turned off (it failed every PR with an unsupported-model error).

**App Sandbox must be OFF.** A sandboxed app cannot post synthetic keyboard events or register global key monitors — this is a hard requirement, not optional.

## Architecture

Twenty Swift source files:

| File | Role |
|------|------|
| `VantoApp.swift` | `@main` entry point + `AppDelegate` owning status UI, popover lifecycle, recipient focus restoration, paste routing, access gating of hotkeys, and trial/validation timers |
| `PasteStack.swift` | Singleton model: FIFO queue, clipboard polling, synthetic paste, Launch at Login |
| `HotkeyManager.swift` | Registers global + local `NSEvent` monitors for ⌃⌘C / ⌃⌘V, resolves live vs. overridden bindings, owns recording-pause state |
| `HotkeySpec.swift` | `ShortcutAction` enum, `HotkeySpec` (keyCode + modifiers), and `ShortcutRecording`'s pure classification/validation logic for capturing a new combo |
| `ShortcutStoring.swift` | `UserDefaults`-backed persistence for per-action shortcut overrides |
| `LanguagePreferenceStore.swift` | `SupportedLanguage` (the 7 shipped locales) + persisted in-app language override, independent of system locale |
| `PopoverRootView.swift` | True root of the popover content: shows `LicenseGateView` when access is denied, otherwise owns which of the two screens is showing, the shared status row, the trial warning banner, outer padding/width, and the `.environment(\.locale:)` override |
| `PopoverStatusRow.swift` | Shared header across both screens — recording indicator, queue count, and the gear/close button that switches screens |
| `PasteStackMenu.swift` | Queue screen: item list with hand-rolled drag-to-reorder, actions, scrolling geometry, and entry to combined paste |
| `PasteAllTextView.swift` | Combined-text confirmation, separator picker, preview, validation feedback, and cancellation on departure |
| `TextJoinPreferences.swift` | Separator values and `UserDefaults` persistence for the last successful choice |
| `SettingsMenu.swift` | Settings screen: shortcut recorder rows, language picker, Launch at Login, license section, website/version row |
| `ShortcutRecorderField.swift` | One rebindable-shortcut row — owns the recording-mode local `NSEvent` monitor, delegates classification to `HotkeySpec.swift`, persists through `HotkeyManager` |
| `ClipboardItem.swift` | `ClipboardItem` enum (`.text`, `.image`, `.file`) + `QueuedClipboardItem` wrapper |
| `PasteboardProviding.swift` | Complete pasteboard seam for change count, text, image/file reads, and content replacement |
| `TrialAccessController.swift` | Local 14-day trial clock persisted in Keychain (`KeychainTrialStateStore`); no network dependency |
| `LicenseAccessController.swift` | `@MainActor` access state (`trial` / `licensed` / `expired` / `storageUnavailable`): activation, periodic validation, deactivation, trial warnings; Keychain credential store |
| `LemonSqueezyLicenseClient.swift` | `LicenseProductConfiguration` (read from Info.plist) + public License API client for activate/validate/deactivate with store/product/variant checks |
| `LicenseActivationView.swift` | `LicenseGateView` (expired trial), `LicenseSettingsSection`, `TrialWarningView`, and the shared activation form |
| `AppUpdateController.swift` | Starts Sparkle's `SPUStandardUpdaterController` only when `SUFeedURL` (https) and a valid `SUPublicEDKey` are embedded |

### Data flow

`PasteStack` owns queue state, pasteboard capture/replacement, file storage, and
synthetic ⌘V. `AppDelegate` owns window/application concerns: it remembers the
external frontmost app before opening the menu, restores that recipient for a
paste requested from the popover, and calls `PasteStack.pasteNext()` only after
focus restoration succeeds. Combined paste follows the same focus route through
`PasteStack.pasteAllText(separator:expectedIDs:)`; hotkey requests still use
ordinary sequential paste. An unsuccessful combined request brings the popover
forward so its error is visible. Hotkey requests are routed through `AppDelegate`.

Clipboard polling runs every 0.25 seconds while collection is active.
`pasteNext()` first captures a pending pasteboard change when collection is on,
then consumes the FIFO head. It does not capture external clipboard content
when collection is off.

`pasteAllText` first checks for a pending copy, compares the current queue IDs
with the IDs shown in the confirmation view, requires every item to be text,
joins full strings without trimming, and posts one synthetic ⌘V. It drains the
queue only after `commandPosted`; that result does not prove insertion into the
target app. The separator choice is stored only after that result. Back,
leaving the confirmation view, and popover closure cancel a pending wait for
recipient activation. Keep this cancellation scoped to combined paste.

### Licensing and trial

`AppDelegate.makeAccessController()` wires `TrialAccessController`,
`KeychainLicenseCredentialStore`, the Lemon Squeezy client, and
`UserDefaultsTrialWarningStore`. Debug uses separate Keychain services and
defaults key (`.debug` suffix), so development never consumes the user's trial:
Keychain services `com.slenbder.vanto.trial[.debug]` /
`com.slenbder.vanto.license[.debug]`, defaults key
`trial-warning-thresholds-v1[.debug]`.

- **Trial.** Exactly 14 × 24 h from first launch. `latestObservedAt` only
  moves forward, so turning the clock back does not extend the trial.
  `refresh()` persists at most hourly or at expiry.
- **Access check.** Every hotkey action, Paste/Combine request, and popover
  opening calls `refreshAccess()`. Without access it stops collection and
  shows the popover (the gate) instead of acting. A timer fires at
  `expiresAt` so the trial ends while the app sits idle.
- **Storage failures grant access.** `.storageUnavailable` intentionally
  grants access. A failed credential read is retried on every `refresh()`, and
  until it succeeds the state stays `.storageUnavailable` instead of falling
  back to a possibly expired trial. Do not "fix" this into a lockout — a
  Keychain hiccup must never lock out a paying user.
- **Activation.** Trims the key, calls the API, and saves the credential
  (key + instance ID) to Keychain. If that save fails, it releases the new
  instance. The client itself releases the instance on a store/product/variant
  mismatch or a non-`active` license status.
- **Validation.** Runs every 7 days while running (timer, no relaunch needed).
  Transport, 5xx, and unparseable failures keep paid access and retry after
  6 h. Only an explicit invalid answer (`valid: false`, product mismatch, or
  HTTP 400/404/422) deletes the credential and falls back to trial state.
- **Deactivation.** Releases the instance on the server, then deletes the local
  credential. A server 400/404/422 still cleans up locally. If the Keychain
  delete fails after a server release, the retry does not call the server
  again.
- **Warnings.** One-time trial warnings appear at the 7/3/1-day thresholds,
  in-popover only.

No secret API key is embedded: the License API is public. Never log the
license key or instance ID.

### Updates (Sparkle)

Sparkle 2.10.0 comes via SwiftPM (`exactVersion` in `project.yml`). Checks,
download, and install are automatic (`SUEnableAutomaticChecks`,
`SUAutomaticallyUpdate`), with no UI or toggles in Settings — a deliberate v1
decision. The feed is `appcast.xml` at the root of public `main`, read via
`raw.githubusercontent.com`. The empty channel means "no updates". Pushing a
new `<item>` to `main` releases an update to every installed copy, so add it
only after the signed, notarized artifact is uploaded and verified. The
private EdDSA key lives only in the local Keychain.

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
monitor while Vanto is receiving keyboard events; its behavior after
focus returns to the external application has not been separately confirmed. A
fresh hosting controller wrapping `PopoverRootView` is created at each opening
— `screen` always starts back at `.queue` on reopen, matching every other
piece of popover state (drag state, recording state, …) already resetting.
That opening's initial list height is passed as `PopoverRootView`'s minimum
(capped by `PasteStackMenu` at 230 pt), keeping controls stable while a queue
is consumed; reopening recalculates a compact height. During sequential paste
the popover remains available while items remain and closes after the final
item. If the queue becomes empty while the popover is open, the empty list and
its lower divider disappear; the shared header divider remains. The row hover
background extends slightly into the inter-row gap, so ScrollView content has
top/bottom inset to keep its rounded edges from clipping.

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
misses events when Vanto itself is active, and the local monitor covers
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

`PopoverRootView` uses 270 pt as its minimum width and measures the current
localized status/count with AppKit fonts to grow only when needed. The German
visual queue count breaks before its final word and its two lines are
left-aligned; the VoiceOver announcement remains a single sentence. Keep the
same visual text and width calculation in sync when changing this layout.

When adding user-facing strings, add translations for all 7 locales in
`Localizable.xcstrings`, with plural variations for counts. German addresses
the user with informal "du" ("Versuche es erneut"), matching the website and
Apple's German copy; never "Sie". Xcode's automatic
extraction sometimes marks live keys as `stale` and adds empty `%@` variants.
Do not commit that noise, and never run "Remove stale" without checking first.

### Drag-to-reorder in PasteStackMenu

Reordering is a hand-rolled `DragGesture`, not `List(onMove:)`. Keep its named
coordinate space on the stable rows container; moving it to the offset row
reintroduces translation drift.

Three distances can be tuned separately in `PasteStackMenu.swift`:
`scrollerOutset` moves the ScrollView's right edge toward the window edge,
`rowTrailingInset` sets the gap from row highlight to scroller without moving
the left edge, and `deleteButtonTrailingInset` sets the delete button's gap
inside the row highlight. Keep the latter in `QueueRowView`.

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
`TextJoinPreferenceTests` uses a fresh in-memory `UserDefaults` subclass per
test instead of a named suite: cfprefsd writes an empty
`~/Library/Preferences/<suite>.plist` for any suite, even after
`removePersistentDomain`, and does it too late for a test to delete.

Licensing tests never touch the real Keychain or network:
- `TrialAccessControllerTests` injects an in-memory `TrialStateStoring` and a
  fixed clock.
- `LicenseAccessControllerTests` injects mock credential, trial, and warning
  stores plus a mock `LicenseServicing`.
- `LemonSqueezyLicenseClientTests` uses a mock `URLSessionDataLoading`.
- `AppUpdateControllerTests` checks Info.plist parsing and the bundled Sparkle
  keys.

`testDebugConfigurationUsesVerifiedTestProduct` reads the Debug build's
Info.plist through the test host. Keep it in sync with the Debug
`LEMON_SQUEEZY_*` values.

## Extending content types

To add a new pasteboard type, add a case to `ClipboardItem`, then add a detection branch in `PasteStack.checkPasteboard()` (keeping file detection first), a paste branch in `pasteNext()`, and a display branch in `QueueRowView.body`.

## Website

`Site/` is the static marketing site at `https://vanto.slenbder.com`, deployed
by Cloudflare Pages from `main` (output directory `Site`, no build step).
`functions/u/[[path]].js` at the repo root is a Pages Function that proxies
Umami (`/u/script.js`, `/u/api/send`) through the site's own domain and
forwards the visitor IP and country via Umami's `x-umami-client-*` headers.
Preview locally with the `site` configuration in `.claude/launch.json`
(`wrangler pages dev Site`, which also picks up `functions/`).

The site ships in the app's 7 languages: English at `/`, the rest under
`/de/`, `/es/`, `/pt-br/`, `/ru/`, `/ja/`, `/zh-hans/`. Every `.html` page in
`Site/` (plus `sitemap.xml`) is **generated** — edit `site-src/` and run
`node scripts/build-site.mjs`, never the output. Templates are
`site-src/pages/*.html` with shared `site-src/partials/`; text lives in
`site-src/i18n/<lang>.json`, where `en.json` is the reference shape and the
build fails on any missing, extra, or mistyped key. Output is committed
because Pages has no build step; CI rebuilds and fails on a diff. Static
assets (`*.js`, `styles.css`, images, `_headers`, `robots.txt`) stay
hand-edited in `Site/`; bump their `?v=` in the partials when they change.

- Page scripts read their text from the `#i18n-strings` JSON each page embeds
  (the `js` subtree of the dictionary) through `window.vantoI18n.t()`, with
  `Intl.PluralRules` plurals; `i18n.js` must load before them.
- The demo game's three scenarios are rewritten per language, not
  translated: each needs three words that stay grammatical in every order
  (gender, case, verb person), the same `id`s for analytics, and a
  `correctOrder` that reads as the punchline.
- Hero mock strings match `Vanto/Localizable.xcstrings`; German's queue count
  breaks onto two lines, as in the app.
- Legal pages stay English with a translated notice and chrome; their
  canonical points at the English URL, and they have no `hreflang`.
- The English home page redirects a first visit once by `navigator.languages`
  (keeping query and hash); a choice from the language menu is stored in
  `localStorage['vanto-lang']` and always wins.
- `FAQ Open` reports the English question (`data-faq`) in every language.
  `Language Switch` and `Language Redirect` are tracked too.

Analytics live in `Site/analytics.js`: elements with `data-track="Event"` and
`data-track-<key>` attributes send events, plus section reach, scroll depth,
FAQ opens, the demo funnel reported from `app.js`, and the cookie banner's
events from `consent.js` (`Consent Shown`, `Cookie Bite`, `Consent Details
Click`, `Consent Choice` with trigger, bites and shakes). Umami is cookieless
and reports only on the production host (`data-domains`); set
`localStorage['vanto-analytics-debug'] = '1'` to log events locally.
`Site/consent.js` loads Microsoft Clarity only after the visitor chooses
"Paste it" (the allow button). Never load a cookie-setting tool outside that consent gate, and keep
`Site/privacy.html` in sync with whatever the site actually collects.
