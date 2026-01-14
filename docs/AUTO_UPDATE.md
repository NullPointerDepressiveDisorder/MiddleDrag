# Auto-Update Setup (Sparkle)

MiddleDrag uses [Sparkle 2](https://sparkle-project.org/) for auto-updates. Updates are **offline by default** — users must explicitly opt-in to automatic update checks.

## User Experience

- **"Check for Updates…"** menu item — always available for manual checks
- **"Automatically Check for Updates"** toggle — opt-in for automatic checks (disabled by default)

## Setup Instructions

### 1. Generate EdDSA Key Pair

Sparkle 2 uses EdDSA (Ed25519) signatures. Generate a key pair:

```bash
# Download Sparkle
curl -L -o Sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz"
mkdir -p Sparkle && tar -xf Sparkle.tar.xz -C Sparkle

# Generate key pair
./Sparkle/bin/generate_keys
```

This outputs:
- **Private key** — store securely, add to GitHub secrets as `SPARKLE_EDDSA_PRIVATE_KEY`
- **Public key** — add to Xcode build settings as `SPARKLE_PUBLIC_KEY`

### 2. Add GitHub Secret

Add the private key to your repository secrets:
1. Go to Settings → Secrets and variables → Actions
2. Add new secret: `SPARKLE_EDDSA_PRIVATE_KEY`
3. Paste the private key (the long base64 string)

### 3. Add Xcode Build Setting

Add the public key to your Xcode project:

1. Open project in Xcode
2. Select the target → Build Settings
3. Add User-Defined Setting: `SPARKLE_PUBLIC_KEY`
4. Set value to your public key

Alternatively, add to `Frameworks/Release.xcconfig`:
```
SPARKLE_PUBLIC_KEY = your_public_key_here
```

### 4. Add Sparkle Package to Xcode

1. In Xcode: File → Add Package Dependencies
2. Enter URL: `https://github.com/sparkle-project/Sparkle.git`
3. Set version rule: Up to Next Major (from 2.6.0)
4. Add `Sparkle` library to your target

### 5. Test Locally

```bash
# Build and run the app
# Check menu for "Check for Updates…" option
# Toggle "Automatically Check for Updates" and verify it persists
```

## How It Works

1. **On release**: GitHub Actions generates appcast entry with EdDSA signature
2. **appcast.xml**: Updated in repo with new version info
3. **User checks for updates**: Sparkle downloads appcast, verifies signature
4. **Update available**: User prompted to download and install .pkg

## Files Modified

- `MiddleDrag/Utilities/UpdateManager.swift` — Sparkle integration
- `MiddleDrag/UI/MenuBarController.swift` — Menu items
- `MiddleDrag/Info.plist` — Feed URL and public key
- `.github/workflows/update-appcast.yml` — Appcast generation
- `.github/workflows/_publish-release.yml` — Trigger appcast update
- `appcast.xml` — Update feed (auto-generated)

## Troubleshooting

### "No updates available" when there should be

1. Check appcast.xml was updated after release
2. Verify version in appcast is higher than installed version
3. Check console for Sparkle errors

### Signature verification failed

1. Ensure `SPARKLE_PUBLIC_KEY` in Info.plist matches the key used to sign
2. Verify `SPARKLE_EDDSA_PRIVATE_KEY` secret is correct
3. Re-run appcast workflow to regenerate signature

### Updates not working in development

Sparkle may behave differently in debug builds. Test with Release builds.
