# Sparkle auto-update setup

Murmur ships with [Sparkle](https://sparkle-project.org) wired in (a "Check for
Updates…" menu item and the updater framework). Two things must be configured
before updates work, both one-time.

## 1. Generate an EdDSA signing key

```bash
# Path depends on where SwiftPM cached Sparkle's tools:
~/Library/Developer/Xcode/DerivedData/Murmur-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

This stores a private key in your login Keychain and prints the **public** key.
Paste the public key into `Murmur/Resources/Info.plist` under `SUPublicEDKey`,
then flip `SUEnableAutomaticChecks` to `<true/>`.

## 2. Host an appcast

`SUFeedURL` in Info.plist points at `appcast.xml`. The default uses the GitHub
Releases convention:

```
https://github.com/robzilla1738/whisper-local/releases/latest/download/appcast.xml
```

Per release, after `scripts/build-release.sh` + `scripts/notarize.sh` +
`scripts/make-dmg.sh`:

```bash
# Sign the DMG/zip for Sparkle:
~/Library/Developer/Xcode/DerivedData/Murmur-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
    build/Murmur-<version>.dmg
# Prints sparkle:edSignature="…" length="…"
```

Add an `<item>` to `appcast.xml` with the new version, the download URL, and that
signature, then upload `appcast.xml` + the DMG to the release. Sparkle handles
the rest.

See Apple's notarization flow in [`../scripts/notarize.sh`](../scripts/notarize.sh).
