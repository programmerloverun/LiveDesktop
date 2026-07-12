# XiaoLeiWallpaper (小雷壁纸)

Set MP4 videos as your Mac desktop wallpaper. Supports multiple displays.

## Features

- Select any MP4 video as desktop wallpaper
- Looped playback, auto-muted
- Multi-display support
- Auto-resume after sleep/unlock
- Remembers last video across sessions
- Clean SwiftUI interface

## Build

```bash
# Build only (no signing)
make app

# Output: .build/小雷壁纸.app
```

## Release (Independent Distribution)

### Prerequisites

1. **Apple Developer Program** ($99/year) — [developer.apple.com](https://developer.apple.com)
2. **Developer ID Application certificate** — create in Xcode → Settings → Accounts → Manage Certificates
3. **App-specific password** — [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords
4. **Team ID** — find in [developer.apple.com/account](https://developer.apple.com/account) under Membership

### One-command release

```bash
make release \
    DEV_ID='Developer ID Application: Your Name (XXXXXXXXXX)' \
    APPLE_ID='you@example.com' \
    TEAM_ID='XXXXXXXXXX' \
    APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'
```

This runs: **build → sign → notarize → staple → DMG**

### Or step by step

```bash
make build                              # Compile
make sign DEV_ID='Developer ID...'      # Code sign
make notarize APPLE_ID=... TEAM_ID=... APP_PASSWORD=...  # Notarize
make staple                             # Staple ticket
make dmg                                # Create DMG
```

### Output

```
.build/小雷壁纸-1.0.0.dmg
```

Distribute via GitHub Releases.

## Before Publishing

- [ ] Replace `XiaoLeiWallpaper.icns` with your own icon (current one is from a video frame — may have copyright issues)
- [ ] Test on both Apple Silicon and Intel Macs
- [ ] Verify notarization: `spctl -a -v .build/小雷壁纸.app`
- [ ] Set up GitHub Release with the DMG

## Requirements

- macOS 13+
- Swift 5.9
