# Murmur

**Local-first AI voice dictation for macOS.** Hold a hotkey, speak, and polished
text appears in whatever app you're focused on — system-wide. An open-source,
notarized alternative to Wispr Flow that can run entirely on your machine.

<p>
  <img alt="Platform: macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<!-- Add screenshots / a short demo GIF of the notch HUD here before launch. -->

## Highlights

- **Push-to-talk dictation anywhere** — hold **Right ⌘** (or tap **⌃⌥D**), speak,
  and the text is inserted at your cursor in any app. Plus a hands-free mode with
  silence auto-stop.
- **Your choice of transcription engine:**
  - **Local Parakeet** via [FluidAudio](https://github.com/FluidInference/FluidAudio) — fast, on-device, the default (no API key)
  - **Local Whisper** via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML / Apple Neural Engine)
  - **Cloud APIs** — OpenAI, Groq, Deepgram, AssemblyAI, ElevenLabs
- **AI "Polish"** that strips filler words, fixes punctuation, and formats —
  powered by a **local LLM** (LM Studio / Ollama) or a cloud model (OpenAI,
  Anthropic, Groq). Context-aware tone per focused app.
- **Transforms** — hotkey-bound rewrites of the selection (concise, formal, …).
- **Command Mode** — select text, speak an instruction, and Murmur edits it.
- **Custom Dictionary** (vocab + replacements) and **Snippets** (voice text-expansion).
- **History** of past dictations and a **Scratchpad** for quick voice notes.
- **Beautiful, minimal, monochrome** native SwiftUI with macOS Liquid Glass and an
  optional MacBook-notch HUD.
- **Private by default** — with a local engine your voice never leaves the Mac.
- **Shortcuts/Spotlight** integration via App Intents, and **Sparkle** auto-update.

## Install

**Download:** grab the latest notarized `.dmg` from the
[Releases](https://github.com/robzilla1738/Murmur/releases) page, drag Murmur to
Applications, and launch it. It lives in the menu bar (no Dock icon).

On first run, grant the permissions Murmur asks for:

| Permission | Why | Required? |
|---|---|---|
| **Microphone** | Record your voice | Yes |
| **Accessibility** | Paste transcribed text into the focused app | Yes |
| **Input Monitoring** | Detect the **Right ⌘** hold-to-talk key globally | For the hold key (⌃⌥D works without it) |

> If a permission is toggled on but doesn't take effect, quit and reopen Murmur —
> macOS applies some grants only on a fresh launch.

Then click into any text field, **tap ⌃⌥D** to start/stop, or **hold Right ⌘**
and speak. The offline model downloads once on first use.

## Build from source

Requirements: **macOS 26 (Tahoe)+**, **Xcode 26+**, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/robzilla1738/Murmur.git
cd Murmur
xcodegen generate          # generate Murmur.xcodeproj from project.yml
open Murmur.xcodeproj       # build & run the Murmur scheme
```

The Debug config signs ad-hoc (no Apple Developer account needed), so it builds
and runs out of the box. From the command line:

```bash
xcodegen generate
xcodebuild -scheme Murmur -configuration Debug build
cd MurmurKit && swift test   # the engine package builds & tests independently
```

## Architecture

- **`MurmurKit/`** — a SwiftPM package with the engine-agnostic pipeline:
  transcription engines, LLM "Polish" providers, audio capture, settings, and
  data models. UI-framework-free and unit-tested (`swift test`).
- **`Murmur/`** — the thin SwiftUI/AppKit app shell: menu-bar agent, floating
  notch/pill HUD, global hotkey tap, text insertion, permissions, and Settings UI.

Murmur is **not sandboxed** — a global event tap and synthesized ⌘V are
impossible under App Sandbox — so it ships via Developer ID + notarization, not
the Mac App Store.

## Release & notarization (maintainers)

```bash
# One-time: create a notarytool keychain profile.
xcrun notarytool store-credentials AC_PASSWORD \
    --apple-id "you@example.com" --team-id "YOURTEAMID" \
    --password "<app-specific-password>"

# Per release:
./scripts/build-release.sh   # archive + export a Developer ID, hardened-runtime app
./scripts/notarize.sh        # submit to Apple, staple, verify with Gatekeeper
./scripts/make-dmg.sh        # package + staple a distributable DMG
```

Signing identity, team id, and entitlements live in `project.yml`,
`ExportOptions.plist`, and `Murmur/Resources/Murmur.entitlements`. Auto-update
setup is documented in [docs/SPARKLE_SETUP.md](docs/SPARKLE_SETUP.md). Forking?
Set your own `DEVELOPMENT_TEAM` for Release builds and generate your own Sparkle
key.

## Contributing

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). In short: edit
`project.yml` (not the generated `.xcodeproj`), keep `swift test` green, and run
the Debug build before opening a PR.

## License

[MIT](LICENSE)
