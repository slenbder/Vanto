# Repository Guidelines

## Project Structure & Module Organization

`Vanto/` contains the Swift 5 application code. `VantoApp.swift` owns the menu-bar lifecycle, `PasteStack.swift` manages the FIFO clipboard queue, and `HotkeyManager.swift` registers global shortcuts and resolves live vs. user-overridden bindings (`HotkeySpec.swift` holds the shortcut/recording types, `ShortcutStoring.swift` persists per-action overrides to `UserDefaults`).

The popover has queue and Settings screens, split across `PopoverRootView.swift` (screen selection, dynamic width, shared divider, locale), `PopoverStatusRow.swift` (recording state, queue count, gear/close button), `PasteStackMenu.swift` (queue list, drag-to-reorder, actions, scrolling geometry), `SettingsMenu.swift` (shortcuts, language, Launch at Login, website/version), and `ShortcutRecorderField.swift` (one shortcut row). `PasteAllTextView.swift` is the queue screen's confirmation view for combining text; `TextJoinPreferences.swift` defines its separators and persisted choice. `LanguagePreferenceStore.swift` holds the language override and 7 supported locales; translated strings live in `Vanto/Localizable.xcstrings`.

Licensing lives in four files. `TrialAccessController.swift` holds the local 14-day trial clock stored in Keychain. `LicenseAccessController.swift` holds the access state, activation, weekly validation, deactivation, trial warnings, and the Keychain credential store. `LemonSqueezyLicenseClient.swift` holds the product configuration read from Info.plist and the public License API client. `LicenseActivationView.swift` holds the expired-trial gate, the Settings license section, and the trial warning banner. `AppUpdateController.swift` starts Sparkle only when a valid feed URL and EdDSA public key are embedded. See `CLAUDE.md` → "Licensing and trial" and "Updates (Sparkle)" for the rules to keep, especially that Keychain storage failures must grant access rather than lock out a paying user.

Clipboard value types and test seams live in `ClipboardItem.swift` and `PasteboardProviding.swift`. Assets are under `Vanto/Assets.xcassets` and `Vanto/VantoIcon.icon`. `menuBarIcon` (idle) and `menuBarIconFrame` (collecting) share the same outer silhouette so the status item does not jump when its state changes.

Unit tests live in `VantoTests/`; keep mocks beside the tests that use them — `MockPasteboard.swift` now also holds `MockShortcutStore`, `MockLanguagePreferenceStore`, `MockLaunchAtLoginService`, and the paste/cleanup-scheduler recorders used across the suite. Accessibility evidence belongs in `a11y-test-artifacts/`. `project.yml` is the source of truth for project settings and for `Vanto/Info.plist` (via `info.properties`); regenerate with XcodeGen instead of editing `Vanto.xcodeproj` or the plist by hand. CI fails if the generated files differ from what is committed. `appcast.xml` at the repository root is the production Sparkle feed.

## Build, Test, and Development Commands

- `xcodegen generate` regenerates the Xcode project after changes to `project.yml`.
- `xcodebuild -scheme Vanto -configuration Debug build` builds the app from Terminal.
- `xcodebuild test -scheme Vanto -destination 'platform=macOS,arch=arm64' -only-testing:VantoTests -derivedDataPath /private/tmp/VantoDerivedData CODE_SIGNING_ALLOWED=NO` runs the isolated XCTest target locally; this setting is never a release signing choice.
- Open `Vanto.xcodeproj` and use Cmd-R for interactive development or Cmd-U for tests.

The app must remain unsandboxed: global event monitoring and synthetic paste events do not work with App Sandbox enabled. Running hotkey flows also requires macOS Accessibility permission.

The first release targets direct website download for Apple Silicon. `project.yml` sets version 0.1/build 1, arm64-only Release and Hardened Runtime on for Release while keeping Debug off. Lemon Squeezy IDs and the checkout URL are per-configuration `LEMON_SQUEEZY_*` build settings: Debug uses the test-mode product, Release uses the live one, and `archive` fails if any value is empty. This host currently has no valid code-signing identity, including no Developer ID Application identity. Do not describe an unsigned test build, a Debug build, or the historical `dist/` image as distributable. Use `docs/RELEASE_HANDOFF.md` for the remaining gate and validate the exact candidate artifact before publication.

Never add an `<item>` to `appcast.xml` on `main` before the signed, notarized artifact is uploaded and verified: installed copies update from that feed automatically.

## Coding Style & Naming Conventions

Follow standard Swift conventions and Xcode formatting: four-space indentation, braces on the declaration line, `UpperCamelCase` for types, and `lowerCamelCase` for methods and properties. Prefer focused files named after their primary type. Keep model state changes in `PasteStack`; UI-specific behavior belongs in SwiftUI/AppKit views. When extending clipboard formats, update capture, paste, and row-display branches together, and preserve file detection before image detection.

For combined text paste, require at least two text items in the UI, preserve the previewed queue IDs until confirmation, and drain the queue only after a paste command is posted. Back, leaving the confirmation view, and popover closure cancel a pending recipient-activation wait. The completion callback must show failures in the popover. Keep ordinary sequential Paste behavior independent of these changes.

## Testing Guidelines

Tests use XCTest and should be named `testBehaviorUnderCondition`. All clipboard tests use `MockPasteboard`, including image and file cases; they must not touch `NSPasteboard.general`. Add regression coverage for queue ordering, capacity, cleanup, and state transitions. `PasteStackTests` and `TextJoinPreferenceTests` cover combined paste and separator persistence; `HotkeyManagerTests`/`HotkeySpecTests` cover shortcut matching and recording with an injected test layout; `LanguagePreferenceStoreTests` covers locale override and translations, including plural forms. `TrialAccessControllerTests`, `LicenseAccessControllerTests`, `LemonSqueezyLicenseClientTests`, and `AppUpdateControllerTests` cover trial, license, API, and Sparkle configuration with in-memory stores, a fixed clock, and a mock URL session. They never touch the real Keychain or network. Construct managers and stores through their designated DI initializers, never through `.shared`. Complete the manual checklist in `README.md` on the final artifact, including cancellation/errors in combined paste and both popover screens.

## Commit & Pull Request Guidelines

Recent commits use short, imperative subjects such as `Fix multi-image pasteboard copies losing all but the first item`. Keep each commit focused. Pull requests should explain user-visible behavior, identify affected clipboard types, include test results, and note manual checks. Add screenshots or accessibility artifacts for popover, icon, or VoiceOver changes, and link the relevant issue when one exists. CI (`.github/workflows/ci.yml`) runs on PRs to and pushes of `main`; work on a branch and merge only after CI passes.
