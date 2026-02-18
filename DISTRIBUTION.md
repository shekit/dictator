# Dictator - Distribution Guide

How to package and distribute Dictator.

## Quick Start

```bash
cd Dictator
./package-for-distribution.sh
```

This creates two files in `dist/`:
- **Dictator-v1.0.0.dmg** — Drag-and-drop installer (recommended)
- **Dictator-v1.0.0.zip** — Direct app bundle archive

For a signed + notarized build:

```bash
export DICTATOR_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export DICTATOR_NOTARY_PROFILE="dictator-notary"
./package-for-distribution.sh
```

You can also store these in `Dictator/signing.local.env` (gitignored).

## Sharing

Share the DMG or ZIP via email, cloud storage (Dropbox, Google Drive, iCloud), file sharing services, or GitHub Releases.

If the build is unsigned, recipients will need to right-click and choose **Open** on first launch (see README for details).

## Signing + Notarization

To avoid the Gatekeeper security warning:

### 1. Get a Developer Certificate

1. Enroll in [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
2. Create a **Developer ID Application** certificate in Xcode
3. Install the certificate on your Mac

### 2. Create notary profile

```bash
xcrun notarytool store-credentials "dictator-notary" \
  --apple-id your@email.com \
  --team-id XXXXXXXXXX \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### 3. Run packaging with signing config

```bash
export DICTATOR_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export DICTATOR_NOTARY_PROFILE="dictator-notary"
./package-for-distribution.sh
```

The script will sign the app, build DMG/ZIP, submit for notarization, and staple the ticket.

## Distribution Checklist

- [ ] Test on a clean Mac (or new user account)
- [ ] Verify onboarding flow and permissions
- [ ] Include install instructions (link to README)

## Updates

1. Increment version in the script (`VERSION="1.0.1"`)
2. Rebuild and redistribute
3. Users quit old version before installing new one
4. Settings and history are preserved across updates

## Alternative: TestFlight

For easier beta distribution without Gatekeeper warnings:

1. Upload to App Store Connect
2. Add testers
3. They install via TestFlight

Requires Apple Developer Program membership.

## Reference

- [Apple Notarization docs](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
