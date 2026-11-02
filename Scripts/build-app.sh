#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${MACAUTOKEY_OUTPUT_APP:-$PWD/dist/Mac AutoKey.app}"
# Pass --universal to build both Apple Silicon and Intel with the installed SDK.
if [[ "${1:-}" == "--universal" ]]; then
    # SwiftPM's multi-arch builder requires full Xcode. Separate builds plus lipo
    # also work with Command Line Tools alone.
    swift build -c release --arch arm64
    ARM_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
    swift build -c release --arch x86_64
    INTEL_DIR="$(swift build -c release --arch x86_64 --show-bin-path)"
    BIN_DIR="$PWD/.build/universal-release"
    mkdir -p "$BIN_DIR"
    lipo -create "$ARM_DIR/MacAutoKey" "$INTEL_DIR/MacAutoKey" -output "$BIN_DIR/MacAutoKey"
else
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacAutoKey" "$APP/Contents/MacOS/MacAutoKey"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Optional stable local signing identity; ad hoc signing needs no developer account.
codesign --force --sign "${MACAUTOKEY_SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
