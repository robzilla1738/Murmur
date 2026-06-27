# Contributing to Murmur

Thanks for your interest in improving Murmur! This is a native macOS app, so a
recent Mac is required.

## Setup

Requirements: **macOS 26 (Tahoe)+**, **Xcode 26+**, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/robzilla1738/Murmur.git
cd Murmur
xcodegen generate
open Murmur.xcodeproj
```

The Debug configuration signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`, no team), so it
builds and runs without an Apple Developer account.

## Project layout

- **`project.yml`** is the source of truth for the Xcode project. The `.xcodeproj`
  is **generated and git-ignored** — never edit or commit it. After adding/removing
  files, run `xcodegen generate` (files not in the regenerated project are silently
  excluded from the build).
- **`MurmurKit/`** — UI-free engine package (transcription, LLM, audio, settings,
  models). Prefer putting logic here; it's unit-testable with `swift test`.
- **`Murmur/`** — the app shell (menu bar, HUD, hotkeys, text insertion, Settings).

## Before opening a PR

- `cd MurmurKit && swift test` is green (add tests for new logic where practical).
- `xcodegen generate && xcodebuild -scheme Murmur -configuration Debug build`
  succeeds with no new warnings.
- Match the surrounding style: small types, clear names, comments that explain
  *why*. The codebase uses Swift 6 strict concurrency — keep it clean.
- Keep changes focused; describe the user-facing effect in the PR.

## Good to know

- The app is **not sandboxed** by design (global event tap + synthesized ⌘V).
- Local transcription downloads models to
  `~/Library/Application Support/Murmur/models` (WhisperKit) and FluidAudio's
  cache (Parakeet) — never `~/Documents`.
- Forking for your own distribution? Set your own `DEVELOPMENT_TEAM` for the
  Release config and generate your own Sparkle key (see
  [docs/SPARKLE_SETUP.md](docs/SPARKLE_SETUP.md)).

## Reporting bugs

Open an issue with your macOS version, the engine/provider in use, and steps to
reproduce. For dictation issues, the unified log helps:

```bash
/usr/bin/log show --predicate 'subsystem == "com.murmur.app"' --last 5m --info --debug
```

By contributing you agree your contributions are licensed under the project's
[MIT License](LICENSE).
