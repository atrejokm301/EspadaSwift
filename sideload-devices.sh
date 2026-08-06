#!/usr/bin/env bash
# Install the latest Release Espada build on paired iPhone + iPad.
# Usage: ./sideload-devices.sh
# Optional: APP=/path/to/Espada.app ./sideload-devices.sh
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${APP:-$ROOT/build-release/Build/Products/Release-iphoneos/Espada.app}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.asignaciondelcielo.espada37swift}"

IPHONE_CORE="${IPHONE_CORE:-35F96986-E00F-5B52-94C1-659989BC4781}"
IPAD_CORE="${IPAD_CORE:-91C290C1-3077-5D31-97FB-A3B6B84D3F05}"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: app not found at $APP"
  echo "Build first (Release generic iOS) or set APP=..."
  exit 1
fi

install_one() {
  local name="$1"
  local device="$2"
  echo "==> $name ($device)"
  if xcrun devicectl device install app --device "$device" "$APP"; then
    xcrun devicectl device process launch --terminate-existing --device "$device" "$BUNDLE_ID" || true
    echo "    OK"
    return 0
  fi
  echo "    FAILED — unlock device, same Wi‑Fi or USB, Developer Mode on"
  return 1
}

echo "App: $APP"
xcrun devicectl list devices
echo
ok=0
install_one "iPhone" "$IPHONE_CORE" && ok=$((ok+1)) || true
install_one "iPad" "$IPAD_CORE" && ok=$((ok+1)) || true
echo
echo "Installed on $ok device(s)."
[[ $ok -ge 1 ]]
