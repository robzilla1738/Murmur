# Sparkle auto-update

Murmur ships with [Sparkle](https://sparkle-project.org) fully wired in: a
"Check for Updates…" menu item, automatic background checks, and EdDSA-signed
update verification.

## Already configured

- **`SUPublicEDKey`** (in `Murmur/Resources/Info.plist`) is set to the project's
  EdDSA **public** key. The matching **private** key lives only in the
  maintainer's login Keychain — it is never committed and is required to sign
  releases.
- **`SUFeedURL`** points at the appcast attached to GitHub Releases:
  `https://github.com/robzilla1738/Murmur/releases/latest/download/appcast.xml`
- **`SUEnableAutomaticChecks`** is `YES`.

> Forking? Generate your own key pair and replace `SUPublicEDKey` + `SUFeedURL`:
> ```bash
> ~/Library/Developer/Xcode/DerivedData/Murmur-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
> ```
> It stores a private key in your Keychain and prints the public key to paste in.

## Cutting a release

1. Build, notarize, and package:
   ```bash
   ./scripts/build-release.sh   # Developer ID, hardened-runtime app
   ./scripts/notarize.sh        # submit to Apple, staple, verify
   ./scripts/make-dmg.sh        # stapled, distributable DMG
   ```
2. Sign the DMG for Sparkle:
   ```bash
   ~/Library/Developer/Xcode/DerivedData/Murmur-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
       build/Murmur-<version>.dmg
   # → sparkle:edSignature="…" length="…"
   ```
3. Update [`appcast.xml`](../appcast.xml): add an `<item>` with the new
   `<sparkle:version>` (build number), `<sparkle:shortVersionString>`, the DMG
   download URL, and the `edSignature`/`length` from step 2.
4. Create a GitHub Release for the new tag and attach **both** the DMG and the
   updated `appcast.xml`. Sparkle handles discovery, download, and verification.

The bundled `appcast.xml` is a template/seed; the live feed is the copy attached
to the latest GitHub Release (per `SUFeedURL`).
