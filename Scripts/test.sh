#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER_PATH="$(xcode-select -p)"
if [[ "$DEVELOPER_PATH" == */CommandLineTools ]]; then
    # CLT includes Swift Testing but SwiftPM does not discover its framework/rpaths.
    swift test \
        -Xswiftc -F -Xswiftc "$DEVELOPER_PATH/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEVELOPER_PATH/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEVELOPER_PATH/Library/Developer/usr/lib" "$@"
else
    swift test "$@"
fi
