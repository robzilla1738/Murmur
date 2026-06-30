# Changelog

All notable changes to Murmur are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Murmur adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-06-29

A reliability, robustness, and polish release. No new top-level features — every
README capability from 0.1.0 is intact — but the app is meaningfully harder to
break and nicer to use.

### Fixed
- **No longer crashes on a corrupt/unreadable database.** If the on-disk store
  can't be opened, Murmur falls back to an in-memory store and keeps running
  (dictation still works); the History pane explains that saving is paused for
  the session instead of the app failing to launch.
- **Local Parakeet (the default engine) now downloads into Murmur's own models
  directory** (`~/Library/Application Support/Murmur/models/parakeet`) instead of
  FluidAudio's library default, matching where Whisper models already live.
- **Audio capture survives a mid-recording input-format change** (e.g. a
  Bluetooth headset switching profiles): the sample-rate converter is rebuilt on
  the fly instead of silently dropping audio.
- **Cloud transcription no longer times out on long recordings** over a slow
  connection — uploads get a generous 10-minute resource budget.
- **Command Mode / Transforms no longer clobber the clipboard** if you copy
  something while Murmur is reading your selection.
- **HUD no longer flashes a stray idle icon** for a beat after each dictation —
  it holds the completed frame while animating out.
- **History save failures are logged** instead of silently ignored.
- **API error messages in the HUD are now compact** — provider HTML/JSON error
  pages are summarized to a single short line rather than dumped verbatim.

### Changed
- **Dictionary, Snippets, and History rows have explicit delete controls**
  (a remove button plus a right-click "Delete"), since macOS has no
  swipe-to-delete.
- **Onboarding scrolls and resizes** so large accessibility text never clips the
  action button, and the permission cards have clearer contrast.
- **Recording pill border adapts to light/dark mode** (was a fixed white hairline
  that vanished in light mode).
- **VoiceOver labels** added to icon-only buttons (show/hide API key, refresh
  models, copy) and to the recording HUD states.
- The HUD no longer hard-clips at large Dynamic Type sizes.
- "View on GitHub" in About now points at the correct repository.

## [0.1.0] - 2026-01-01

- Initial open-source release.
