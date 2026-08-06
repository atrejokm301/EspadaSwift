#!/usr/bin/env bash
# Espada — Release device build + install
# Full (fat) LTO · -O3 · wholemodule · arm64-only (iPhone + M1 iPad)
# Strip final app binary only — never SPM intermediates (breaks fat LTO)
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

TEAM="${DEVELOPMENT_TEAM:-RV23UF9649}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.asignaciondelcielo.espada37swift}"
IPHONE_CORE="${DEVICE_CORE:-35F96986-E00F-5B52-94C1-659989BC4781}"
IPAD_CORE="${IPAD_CORE:-91C290C1-3077-5D31-97FB-A3B6B84D3F05}"
DERIVED="${ROOT}/build-release"
LOG="${ROOT}/build-release.log"

echo "==> Regenerating project (xcodegen)"
xcodegen generate

echo "==> Release · arm64 · -O3 · wholemodule · FULL fat LTO"
echo "    Team=$TEAM  Bundle=$BUNDLE_ID"
echo "    Destination: generic/platform=iOS (iPhone + M1 iPad)"
echo "    Log: $LOG"

# generic/platform=iOS → one arm64 binary for all iOS devices (A-series + M1 iPad).
# LLVM_LTO=YES = full/fat LTO (not YES_THIN).
# Do NOT pass STRIP_INSTALLED_PRODUCT on the CLI — that strips GRDB.o and breaks LTO.
xcodebuild \
  -project EspadaSwift.xcodeproj \
  -scheme EspadaSwift \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  LLVM_LTO=YES \
  SWIFT_OPTIMIZATION_LEVEL=-O \
  SWIFT_COMPILATION_MODE=wholemodule \
  GCC_OPTIMIZATION_LEVEL=3 \
  DEAD_CODE_STRIPPING=YES \
  ENABLE_NS_ASSERTIONS=NO \
  VALIDATE_PRODUCT=YES \
  build 2>&1 | tee "$LOG"

APP="$DERIVED/Build/Products/Release-iphoneos/Espada.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: app not found at $APP"
  exit 1
fi

MAIN="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null || echo Espada)"
BIN="$APP/$MAIN"

echo "==> Binary check (expect: Mach-O arm64, not fat x86)"
file "$BIN"
lipo -info "$BIN" 2>/dev/null || true
ls -lh "$BIN"

# Extra post-link strip on final executable only (safe; not SPM .o files)
if command -v xcrun >/dev/null; then
  echo "==> Final strip (app binary only)"
  xcrun strip -x "$BIN" 2>/dev/null || xcrun strip "$BIN" 2>/dev/null || true
  CODESIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"(.+)"/\1/')
  if [[ -n "${CODESIGN_ID:-}" ]]; then
    ENT="$DERIVED/Build/Intermediates.noindex/EspadaSwift.build/Release-iphoneos/EspadaSwift.build/Espada.app.xcent"
    if [[ -f "$ENT" ]]; then
      codesign --force --sign "$CODESIGN_ID" --entitlements "$ENT" --timestamp=none --generate-entitlement-der "$APP"
    else
      codesign --force --sign "$CODESIGN_ID" --timestamp=none --generate-entitlement-der "$APP"
    fi
  fi
  ls -lh "$BIN"
fi

install_one() {
  local name="$1"
  local device="$2"
  echo "==> Install $name ($device)"
  if xcrun devicectl device install app --device "$device" "$APP"; then
    xcrun devicectl device process launch --terminate-existing --device "$device" "$BUNDLE_ID" \
      && echo "    launched" \
      || echo "    installed (unlock device to launch)"
  else
    echo "    FAILED — unlock / wake / same Wi‑Fi or USB"
  fi
}

install_one "iPhone" "$IPHONE_CORE"
install_one "iPad (M1)" "$IPAD_CORE"

echo "==> Done. Fat LTO · -O3 · arm64 Release pushed."
echo "    App: $APP"
echo "    Log: $LOG"
