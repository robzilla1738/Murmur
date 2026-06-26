# Murmur

**Local-first AI voice dictation for macOS.** Hold a hotkey, speak, and polished
text appears in whatever app you're focused on — system-wide. An open-source,
notarized alternative to Wispr Flow that runs entirely on your machine if you
want it to.

> Status: feature-complete and building. The full dictation loop, both local
> engines, cloud providers, Polish, Transforms, Command Mode, Dictionary,
> Snippets, History, Scratchpad, and the notch/pill HUD are implemented.

## Highlights

- **Push-to-talk dictation anywhere** — hold a key, speak, release; the text is
  inserted at your cursor in any app. Plus hands-free mode with silence auto-stop.
- **Your choice of transcription engine:**
  - **Local Whisper** via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML / Apple Neural Engine)
  - **Local Parakeet** via [FluidAudio](https://github.com/FluidInference/FluidAudio) (NVIDIA Parakeet, ~190× realtime)
  - **Cloud APIs** — OpenAI, Groq, Deepgram, AssemblyAI, ElevenLabs
- **AI "Polish"** that strips filler words, fixes punctuation, and formats —
  powered by a **local LLM** (LM Studio / Ollama) or a cloud model (OpenAI,
  Anthropic, Groq). Context-aware tone per focused app.
- **Transforms** — hotkey-bound rewrites of the selection (concise, formal, …).
- **Command Mode** — select text, speak an instruction, and Murmur edits it.
- **Custom Dictionary** (spelling/vocab + replacements) and **Snippets** (voice
  text-expansion).
- **History** of past dictations and a **Scratchpad** for quick voice notes.
- **Beautiful, minimal, monochromatic** native SwiftUI with macOS Liquid Glass
  and an optional MacBook-notch HUD.
- **Private by default** — local engines mean your voice never leaves the Mac.
- **Shortcuts/Spotlight** integration via App Intents, and **Sparkle** auto-update.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
xcodegen generate          # generate Murmur.xcodeproj from project.yml
open Murmur.xcodeproj       # build & run the Murmur scheme
```

Or from the command line:

```bash
xcodegen generate
xcodebuild -scheme Murmur -configuration Debug build
```

The engine package builds and tests independently:

```bash
cd MurmurKit && swift test
```

## Release & notarization

Murmur is **not sandboxed** (a global event tap + synthesized ⌘V are impossible
under App Sandbox), so it ships via Developer ID + notarization, not the App Store.

One-time: create a notarytool keychain profile.

```bash
xcrun notarytool store-credentials AC_PASSWORD \
    --apple-id "you@example.com" --team-id "YOURTEAMID" \
    --password "<app-specific-password>"
```

Then per release:

```bash
./scripts/build-release.sh   # archive + export a Developer ID, hardened-runtime app
./scripts/notarize.sh        # submit to Apple, staple, verify with Gatekeeper
./scripts/make-dmg.sh        # package + staple a distributable DMG
```

Signing identity, team id, and entitlements live in `project.yml`,
`ExportOptions.plist`, and `Murmur/Resources/Murmur.entitlements`.

## Architecture

- **`MurmurKit/`** — a SwiftPM package with the engine-agnostic pipeline:
  transcription engines, LLM "Polish" providers, audio capture, settings, and
  data models. UI-framework-free and unit-testable.
- **`Murmur/`** — the thin SwiftUI/AppKit app shell: menu-bar agent, floating
  HUD panels, global hotkey tap, text insertion, permissions, and Settings UI.

The app is **not sandboxed** (a global event tap and synthesized keystrokes are
impossible under App Sandbox) and ships via Developer ID + notarization.

## License

[MIT](LICENSE)
