#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
RECEIVER="$PWD/.build/Input Receiver.app"
mkdir -p "$RECEIVER/Contents/MacOS"
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx14.0" Scripts/InputReceiver.swift -o "$RECEIVER/Contents/MacOS/InputReceiver"
cat > "$RECEIVER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>InputReceiver</string>
<key>CFBundleIdentifier</key><string>com.macautokey.inputreceiver</string>
<key>CFBundleName</key><string>Input Receiver</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$RECEIVER"
echo "Built disposable input receiver: $RECEIVER"
