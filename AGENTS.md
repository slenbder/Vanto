# Repository Guidelines

## Project Structure & Module Organization

`PasteQueue/` contains the Swift 5 application code. `PasteQueueApp.swift` owns the menu-bar lifecycle, `PasteStack.swift` manages the FIFO clipboard queue, `HotkeyManager.swift` registers global shortcuts, and `PasteStackMenu.swift` renders the SwiftUI popover. Clipboard value types and test seams live in `ClipboardItem.swift` and `PasteboardProviding.swift`. Assets are under `PasteQueue/Assets.xcassets` and `PasteQueue/PasteQueueIcon.icon`.

Unit tests live in `PasteQueueTests/`; keep mocks beside the tests that use them. Accessibility evidence belongs in `a11y-test-artifacts/`. `project.yml` is the source of truth for project settings; regenerate `PasteQueue.xcodeproj` instead of editing it by hand.

## Build, Test, and Development Commands

- `xcodegen generate` regenerates the Xcode project after changes to `project.yml`.
- `xcodebuild -scheme PasteQueue -configuration Debug build` builds the app from Terminal.
- `xcodebuild test -scheme PasteQueue -destination 'platform=macOS'` runs all XCTest tests.
- Open `PasteQueue.xcodeproj` and use Cmd-R for interactive development or Cmd-U for tests.

The app must remain unsandboxed: global event monitoring and synthetic paste events do not work with App Sandbox enabled. Running hotkey flows also requires macOS Accessibility permission.

## Coding Style & Naming Conventions

Follow standard Swift conventions and Xcode formatting: four-space indentation, braces on the declaration line, `UpperCamelCase` for types, and `lowerCamelCase` for methods and properties. Prefer focused files named after their primary type. Keep model state changes in `PasteStack`; UI-specific behavior belongs in SwiftUI/AppKit views. When extending clipboard formats, update capture, paste, and row-display branches together, and preserve file detection before image detection.

## Testing Guidelines

Tests use XCTest and should be named `testBehaviorUnderCondition`. Use `MockPasteboard` for text-oriented unit tests; image and file tests intentionally touch `NSPasteboard.general`, so clear it during setup. Add regression coverage for queue ordering, capacity, cleanup, and state transitions. Complete the manual checklist in `README.md` for hotkeys, files/images, VoiceOver, Launch at Login, and menu-bar appearance.

## Commit & Pull Request Guidelines

Recent commits use short, imperative subjects such as `Fix multi-image pasteboard copies losing all but the first item`. Keep each commit focused. Pull requests should explain user-visible behavior, identify affected clipboard types, include test results, and note manual checks. Add screenshots or accessibility artifacts for popover, icon, or VoiceOver changes, and link the relevant issue when one exists.
