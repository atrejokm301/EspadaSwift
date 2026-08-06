# Espada (SwiftUI) — Handover

**Date:** 2026-08-05  
**Projects:** `~/EspadaSwift` (iOS/iPadOS native) · `~/Espada3.7` (macOS Tauri)  
**Bundle ID (device):** `com.asignaciondelcielo.espada37swift`  
**Team:** `RV23UF9649` (Kevin Trejo — free Personal Team)  
**Signing identity:** Apple Development · `aktrejo301@gmail.com`

---

## What this app is

Offline Spanish Bible study for **iPhone + iPad** (SwiftUI + GRDB).  
Modules: e-Sword style `.bbli` / `.cmti` / `.dcti` / `.lexi`.  
Related: `~/Espada3.7` (Tauri Mac reference), `~/EspadaMobile` (older Capacitor).

---

## Session work (2026-08-06) — True Liquid Glass

Replaced legacy `UIBlurEffect` / `.ultraThinMaterial` chrome with **system Liquid Glass**:

- SwiftUI: `.glassEffect`, `GlassEffectContainer`, interactive chips
- UIKit: `UIGlassEffect` for custom full-bleed surfaces (iPad sheets/bars)
- System nav/tab: `configureWithDefaultBackground()` + soft theme tint — **do not** set `UIBlurEffect` (it kills Liquid Glass; `UIBarAppearance.backgroundEffect` is blur-only)
- Reduce Transparency → solid/opaque fallbacks
- Tests: `EspadaSwiftTests/EspadaGlassTests.swift`

Key file: `EspadaSwift/Core/Theme/EspadaGlass.swift`

---

## Session work (2026-08-04 → 2026-08-05)

### 1. Signing / sideload (device installs)

- Free **7-day** provisioning profiles expire often → re-sign needs Xcode **Accounts** signed in.
- Scripts:
  - `./build-release.sh` — xcodegen → Release fat LTO → strip → codesign → install **iPhone + iPad**
  - `./sideload-devices.sh` — install existing `build-release/.../Espada.app` only
- Device IDs (CoreDevice):
  - iPhone 17 Pro Max: `35F96986-E00F-5B52-94C1-659989BC4781`
  - iPad Pro 12.9 (5th gen): `91C290C1-3077-5D31-97FB-A3B6B84D3F05`
- Env: always set  
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`  
  (default `xcode-select` may point at Command Line Tools).
- Xcode GUI may fail `open -a Xcode` (LaunchServices); launch via  
  `/Applications/Xcode.app/Contents/MacOS/Xcode` if needed.
- **Do not** change bundle ID for “quick re-sign” — that creates a second Espada icon (happened once with `espadaswift` workaround; user deleted the duplicate).

### 2. Warm Paper + High Contrast themes (reading comfort)

**iOS:** `EspadaSwift/Core/Theme/AppTheme.swift`, glass in `EspadaGlass.swift`, picker in `ThemePickerView.swift`.

| Theme | Role |
|-------|------|
| `warmPaper` | Cream paper `#F4EDE4`, warm ink — indoor reading (not banana sepia) |
| `highContrast` | Pure white + black, strong hairlines |
| Existing | True Dark, Plain White, pastels, Muted Lila — **unchanged** |

- Preference: `UserDefaults` key `espada.theme` (rawValue).
- Subtle paper atmosphere: `WarmPaperAtmosphere` (radial cream, only for Warm Paper).
- **No** global `filter: sepia()` — real color tokens only.

**macOS Tauri:** `~/Espada3.7/ui/`

- Themes: `warm-paper`, `high-contrast` in `styles.css` / `styles.v7.css`
- Lists: `index.html` `ESPADA_THEMES`, `app.js` / `app.v7.js`
- Helper: `ui/reading-theme.js` (optional apply/persist)

### 3. True Tone (system) — app-wide, does not recolor themes

```xml
<!-- Info.plist + project.yml -->
<key>UIWhitePointAdaptivityStyle</key>
<string>UIWhitePointAdaptivityStyleReading</string>
```

- Only helps if user has **Settings → Display → True Tone ON**.
- Cannot force True Tone or mark *other* apps as reading apps.
- Warm Paper colors stay cream with True Tone off; system may warm the *display* when True Tone is on.

### 4. ProMotion frame-rate policy (reading scroll)

**Files:**

- `EspadaSwift/Core/UI/ProMotionScroll.swift`
- Info.plist: `CADisableMinimumFrameDurationOnPhone = true`
- Applied via `.espadaProMotionScroll()` on Bible, Lexicon, Dictionary, Commentary

**Policy (current):**

```swift
// Scrolling / fling
static let high = CAFrameRateRange(minimum: 1, maximum: 120, preferred: 120)

// Foreground idle (still reading)
static let low  = CAFrameRateRange(minimum: 1, maximum: 20, preferred: 1)
```

| Mode | min | max | preferred | When |
|------|-----|-----|-----------|------|
| **high** | 1 | 120 | **120** | pan / decelerating |
| **low** | 1 | 20 | **1** | content still |

- UIKit has **no** `UIScrollView.preferredFrameRateRange` on this SDK; rate is requested via a **CADisplayLink** whose `preferredFrameRateRange` is the signal (empty tick).
- After settle → switch to **low** (prefer 1 Hz), not permanent 120 Hz.
- Tests: `EspadaSwiftTests/ReadingFrameRateTests.swift`

---

## How to build & install

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:/opt/homebrew/bin:$PATH"
cd ~/EspadaSwift

# Both devices
./build-release.sh

# Install only (app already built)
./sideload-devices.sh

# iPad only example
xcrun devicectl device install app \
  --device 91C290C1-3077-5D31-97FB-A3B6B84D3F05 \
  build-release/Build/Products/Release-iphoneos/Espada.app
xcrun devicectl device process launch --terminate-existing \
  --device 91C290C1-3077-5D31-97FB-A3B6B84D3F05 \
  com.asignaciondelcielo.espada37swift
```

**If provisioning fails:** Xcode → Settings → Accounts → sign in `aktrejo301@gmail.com`.  
**If launch fails “not trusted”:** device Settings → General → VPN & Device Management → Trust.  
**If launch fails “Locked”:** unlock device and open app or re-launch via devicectl.  
**Free profile TTL:** ~7 days — expect re-sign weekly on free team.

Release flags (from `build-release.sh`): fat LTO, `-O` / wholemodule, `-O3`, arm64, strip app binary only (never SPM `.o`).

---

## How to test (user-facing)

1. **Warm Paper** — Apariencia → Warm Paper → read indoors.  
2. **True Tone** — System True Tone on/off; theme identity should not flip cream↔white.  
3. **ProMotion** — Long chapter, fling hard (prefer 120), stop and sit (prefer ~1 Hz). Low Power Mode can cap refresh.  
4. **Data** — Same bundle ID → modules/highlights preserved across re-sideloads.

---

## Key paths

```
~/EspadaSwift/
  build-release.sh
  sideload-devices.sh
  project.yml
  handover.md                 ← this file
  EspadaSwift/
    Info.plist
    Core/Theme/AppTheme.swift
    Core/Theme/EspadaGlass.swift
    Core/UI/ProMotionScroll.swift
    Features/Bible/BibleView.swift
    Features/Shared/ThemePickerView.swift
  EspadaSwiftTests/
    AppThemeTests.swift
    ReadingFrameRateTests.swift

~/Espada3.7/ui/
  styles.css / styles.v7.css
  app.js / app.v7.js
  index.html
  reading-theme.js
```

---

## User preferences (product)

- Loves **Warm Paper** + **True Tone** for indoor reading.  
- Does **not** want other theme palettes warped for True Tone.  
- ProMotion: **prefer 120 when scrolling**, **prefer 1 Hz when idle** (low band max 20).  
- Sideload often to iPhone and/or iPad separately when one device is offline.

---

## Known issues / gotchas

1. Free Apple ID: max ~3 apps, 7-day profiles, Xcode account session can clear.  
2. iPad often shows `unavailable` / locked / “trust developer” until unlocked.  
3. Post-strip re-sign in `build-release.sh` is required so install doesn’t fail integrity checks.  
4. Cannot build a third-party app that marks *other* apps as “reading apps” for True Tone.  
5. **Deployment target: iOS / iPadOS 27.0** (`project.yml`). Devices are on 27.0 beta; Mac Xcode may still ship an older SDK (e.g. 26.5) — install matching **Xcode beta** if build rejects DT > SDK.
6. Simulator name used for tests: **EspadaBuild** (needs a **27.x** runtime once available; older 26.5 simulators cannot run a 27.0-minimum app).

---

## Suggested next steps (optional)

- [ ] Paid Apple Developer Program ($99/yr) for longer-lived profiles.  
- [ ] Fine-tune Warm Paper ink/cream if user wants cooler/warmer.  
- [ ] iOS 18+ path: consider `UIUpdateLink` instead of display-link signal.  
- [ ] Instruments: Core Animation FPS while scrolling to validate ProMotion.  
- [ ] Keep Tauri Mac themes in sync if iOS theme names change.

---

## Quick commands cheatsheet

```bash
# Devices
xcrun devicectl list devices

# Full ship
cd ~/EspadaSwift && ./build-release.sh

# Open Xcode (if LaunchServices broken)
/Applications/Xcode.app/Contents/MacOS/Xcode &

# Unit tests (frame rate)
xcodebuild test -project EspadaSwift.xcodeproj -scheme EspadaSwift \
  -destination 'platform=iOS Simulator,name=EspadaBuild,OS=27.0' \
  -only-testing:EspadaSwiftTests/ReadingFrameRateTests \
  CODE_SIGNING_ALLOWED=NO
```

---

*End of handover — Espada reading comfort (Warm Paper + True Tone style + ProMotion 120/1) and device sideload workflow.*
