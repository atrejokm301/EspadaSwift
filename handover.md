# Espada — Handoff

**Date:** 2026-08-10  
**Author context:** Grok Build session with Kevin (atrejokm301 / aktrejo301@gmail.com)  
**Primary workspace for agent skills:** `~/Downloads/grok-dev-team-2` (AGENTS.md + eight skills)  
**Product code (iOS):** `~/EspadaSwift`  
**Product code (macOS):** `~/Espada3.7`

---

## What Espada is

Offline **Spanish Bible study** — e-Sword-style modules (`.bbli` / `.cmti` / `.dcti` / `.lexi`), no cloud AI.

| Project | Path | Stack | Role |
|---------|------|--------|------|
| **EspadaSwift** | `~/EspadaSwift` | SwiftUI + GRDB, iOS 17+ target (devices on **iOS/iPadOS 27 beta**) | **Active native iPhone + iPad app** |
| **Espada3.7** | `~/Espada3.7` | Tauri 2 + Rust + vanilla UI | **macOS** reference / shipping Mac app |
| EspadaMobile | `~/EspadaMobile` | Capacitor + sql.js | **Legacy** WebView iOS — do not extend unless asked |

**iOS bundle ID:** `com.asignaciondelcielo.espada37swift`  
**Apple Team:** `RV23UF9649` (free Personal Team)  
**Signing:** Apple Development · `aktrejo301@gmail.com`

---

## GitHub (public)

| Repo | URL | Contents |
|------|-----|----------|
| **iOS/iPadOS** | https://github.com/atrejokm301/EspadaSwift | Source, tests, fonts, scripts |
| **macOS** | https://github.com/atrejokm301/Espada3.7 | Release + DMG (not full Tauri source dump necessarily) |
| **Mac DMG download** | https://github.com/atrejokm301/Espada3.7/releases/tag/v3.7.0 | `Espada3.7_3.7.0_aarch64.dmg` (~3.3 MB, **Apple Silicon only**) |

Direct DMG:  
https://github.com/atrejokm301/Espada3.7/releases/download/v3.7.0/Espada3.7_3.7.0_aarch64.dmg

**Note (2026-08-10):** Working tree on EspadaSwift may have **uncommitted pastel highlight** edits (see below). Check `git status` before next push.

```bash
cd ~/EspadaSwift && git status -sb && git log -1 --oneline
```

---

## Devices

| Device | CoreDevice ID | Notes |
|--------|---------------|--------|
| Kevin’s Ayfon 17 PM (iPhone 17 Pro Max) | `35F96986-E00F-5B52-94C1-659989BC4781` | Primary; often available |
| La aipad de Kevin (iPad Pro 12.9 5th gen) | `91C290C1-3077-5D31-97FB-A3B6B84D3F05` | May show locked / unavailable until unlocked |

Both were last successfully Release-installed with pastel highlights (~2026-08-06 evening session). Re-check with:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun devicectl list devices
```

**OS on devices (when last checked):** iOS / iPadOS **27.0 beta** (build `24A5390f`).  
**Xcode on Mac:** 26.6 · SDK **iPhoneOS 26.5** — deployment target in project may be **27.0** (warns that supported DT range tops at 26.5.99; still builds/installs).

---

## How to build & install (iOS)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:/opt/homebrew/bin:$PATH"
cd ~/EspadaSwift

# Full ship: xcodegen → Release fat LTO → strip → codesign → iPhone + iPad
./build-release.sh

# Install only (app already built)
./sideload-devices.sh
```

**Release recipe (user “goodies” binary):**

- `LLVM_LTO=YES` (**full/fat LTO**, not thin)  
- `-O` / wholemodule · `GCC_OPTIMIZATION_LEVEL=3`  
- arm64 · strip **app binary only** (never SPM `.o`)  

**Not used on iOS:** PGO (that’s optional on **Mac** Espada3.7 via `./build-release.sh --pgo`).

**Gotchas:**

1. Free Apple ID: ~7-day profiles, max ~3 apps — re-sign weekly; keep Xcode → Settings → Accounts signed in.  
2. **Never** change bundle ID for a quick re-sign (creates a second Espada icon).  
3. iPad often fails install if **locked** — unlock, trust developer, same Wi‑Fi/USB.  
4. Closing the Mac lid **sleeps** the machine — agent builds stop.  
5. `open -a Xcode` may fail LaunchServices; use  
   `/Applications/Xcode.app/Contents/MacOS/Xcode &`  
6. Simulator named **EspadaBuild**; with DT 27, **iOS 26.5 simulators may not be valid destinations** until a 27 runtime exists.

---

## Session history (what shipped)

### 2026-08-06 (major Grok session)

#### A. Deployment target
- Aim: target **iOS/iPadOS 27** (user on betas).  
- Files: `project.yml` → `IPHONEOS_DEPLOYMENT_TARGET` / `deploymentTarget` **27.0**.  
- Caveat: Xcode SDK still 26.5 → warning; device builds OK.

#### B. True Liquid Glass
- Replaced legacy stacked `UIBlurEffect` / ultraThinMaterial chrome with **Liquid Glass**.  
- **Key file:** `EspadaSwift/Core/Theme/EspadaGlass.swift`  
- System nav/tab: `configureWithDefaultBackground()` + soft theme tint — **do not** assign `UIBlurEffect` to `UIBarAppearance.backgroundEffect` (typed as blur-only; **kills** system Liquid Glass).  
- Custom chrome: `.glassEffect` / `UIGlassEffect` for sheets/wide bars.  
- **Reduce Transparency** → solid fallbacks.  
- Tests: `EspadaSwiftTests/EspadaGlassTests.swift`

#### C. Header / button regressions (fixed)
- Too many hairlines + fused header; Recientes + cross-ref **broken** (interactive glass + `GlassEffectContainer` ate hits).  
- **Fix:** one hairline under whole top chrome; context banner = soft card strip only; tools strip = continuous glass bar; chips = **solid elevated** on glass (not interactive liquid glass).  
- Files: `BibleView.swift`, `RecentVersesMenu.swift`, `CrossReferenceSheet.swift`, `ModulePickerMenu.swift` (ContextBanner), `EspadaGlass.swift`

#### D. Chapter swipe morph
- **File:** `EspadaSwift/Features/Bible/ChapterSwipeMorph.swift`  
- **Direction (final):**  
  - Swipe **right → left** (finger left) → **next** chapter  
  - Swipe **left → right** (finger right) → **previous** chapter  
- Animation: soft spring **morph dissolve** (scale/fade/blur + peek labels) — **not** UIPageView fling.  
- Threshold ~72 pt; vertical scroll still wins when dominant.  
- Tests: `EspadaSwiftTests/ChapterSwipeMorphTests.swift`

#### E. Pastel verse highlights
- Same six rawValues (`yellow`…`purple`) so **saved highlights keep working**.  
- Soft pastel RGB swatches + wash behind text.  
- Labels: Amarillo, Verde, Azul, Rosa, Melocotón, Lila.  
- Files: `AppTheme.swift` (`HighlightColor`), `HighlightSheet.swift`, `AppThemeTests.swift`  
- **Installed on iPhone + iPad** Release.  
- **May still be uncommitted** on disk — commit + `git push` if `git status` shows dirty.

#### F. GitHub
- Initialized `~/EspadaSwift` git, pushed **public** `atrejokm301/EspadaSwift`.  
- Created public `atrejokm301/Espada3.7` + release **v3.7.0** with Mac DMG uploaded.

### Earlier (2026-08-04 → 08-05) — still in product
- **Warm Paper** + **High Contrast** themes (keep other palettes pure).  
- **True Tone** reading style: `UIWhitePointAdaptivityStyleReading` in Info.plist / project.yml.  
- **ProMotion:** prefer **120** while scrolling, prefer **~1 Hz** when idle (`ProMotionScroll.swift`).  
- User loves Warm Paper + True Tone indoors; do **not** warp all themes for True Tone.

---

## Key paths (iOS)

```
~/EspadaSwift/
  build-release.sh
  sideload-devices.sh
  project.yml
  handover.md                 ← this file
  EspadaSwift/
    Info.plist
    App/EspadaApp.swift
    Core/Theme/AppTheme.swift      # themes + HighlightColor pastels
    Core/Theme/EspadaGlass.swift   # Liquid Glass
    Core/UI/ProMotionScroll.swift
    Features/Bible/BibleView.swift
    Features/Bible/ChapterSwipeMorph.swift
    Features/Bible/HighlightSheet.swift
    Features/Bible/RecentVersesMenu.swift
    Features/Bible/CrossReferenceSheet.swift
  EspadaSwiftTests/
    AppThemeTests.swift
    EspadaGlassTests.swift
    ChapterSwipeMorphTests.swift
    ReadingFrameRateTests.swift
    …
```

## Key paths (macOS)

```
~/Espada3.7/
  build-release.sh            # optional --pgo
  ui/                         # themes, app.js, styles
  src-tauri/                  # Rust e-Sword layer
  …/bundle/dmg/Espada3.7_3.7.0_aarch64.dmg
```

Modules folder often used: `~/Downloads/for mac espada`

---

## User preferences (product)

- Offline-first Spanish study; Strong’s via **interlinear map** (e.g. iRV) while reading RV1960.  
- Loves **Warm Paper** + system **True Tone**.  
- ProMotion: 120 scroll / ~1 idle.  
- Liquid Glass, but **reliable buttons** over flashy interactive glass on chips.  
- Chapter swipe like a book (left = next).  
- Pastel highlights (soft, not neon).  
- Fat LTO Release “goodies” builds for devices.  
- Sideload iPhone and/or iPad; iPad may need unlock.  
- Public GitHub for source + Mac DMG.

---

## Known issues / gotchas

1. Free provisioning TTL ~7 days.  
2. Deployment target 27 vs SDK 26.5 warning.  
3. Simulator unit **runs** may be blocked without iOS 27 runtime (tests still **compile**).  
4. Glass-on-glass and interactive glass on `Button`+popover = broken hits — avoid.  
5. PGO is **Mac-only** optional; not on iOS pipeline.  
6. Mac DMG is **aarch64 only** — not Intel.  
7. Agent cannot work if Mac lid closes (sleep).  
8. GitHub MCP cannot always create repos (403); use keychain `git credential-osxkeychain` + curl API when needed.

---

## Suggested next steps (optional — user deferred some)

- [ ] Commit + push pastel highlights if still dirty:  
  `cd ~/EspadaSwift && git add -A && git commit -m "Pastel verse highlight colors" && git push`  
- [ ] Paid Apple Developer + TestFlight (stop weekly re-sign pain).  
- [ ] Instruments pass: chapter swipe + word→Strong path.  
- [ ] iPad split study layout (Bible | dict/lex/cmt).  
- [ ] Local search / bookmarks / share verse.  
- [ ] Do **not** chase iOS PGO unless measured need.  
- [ ] Keep Mac themes in sync if iOS theme names change.

---

## Quick commands cheatsheet

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:/opt/homebrew/bin:$PATH"

# Devices
xcrun devicectl list devices

# Full iOS ship
cd ~/EspadaSwift && ./build-release.sh

# Open Xcode if LaunchServices broken
/Applications/Xcode.app/Contents/MacOS/Xcode &

# Unit tests (when a valid sim destination exists)
cd ~/EspadaSwift
xcodebuild test -project EspadaSwift.xcodeproj -scheme EspadaSwift \
  -destination 'platform=iOS Simulator,name=EspadaBuild,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO

# Mac release (+ optional PGO)
cd ~/Espada3.7 && ./build-release.sh
# ./build-release.sh --pgo
```

---

## Agent pipeline note

Product work in this org uses `~/Downloads/grok-dev-team-2/AGENTS.md`:  
trend-scout → graphic-designer → ui-ux-meticulous → safe-feature-dev → test-writer-qa → code-reviewer → security-auditor → performance-optimizer  
(with handoff skips as documented). Skills live under `.grok/skills/` and `skills/`.

---

*End of handoff — EspadaSwift (iOS Liquid Glass, chapter morph, pastel highlights, public GitHub) + Espada3.7 (macOS DMG release v3.7.0).*
