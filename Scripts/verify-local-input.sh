#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x MacAutoKey >/dev/null; then
    echo 'Quit Mac AutoKey before starting its isolated live verification command.' >&2
    exit 1
fi
Scripts/build-input-receiver.sh
mkdir -p docs/evidence
REPORT_DIR="$(mktemp -d /tmp/macautokey-verify.XXXXXX)"
REPORT="$REPORT_DIR/report.json"
DESTINATION="$PWD/docs/evidence/local-input.json"
if [[ "${1:-}" == "--physical-hotkeys" ]]; then
    DESTINATION="$PWD/docs/evidence/physical-hotkeys.json"
fi
# Launch Services exercises this app's own permission identity, not the terminal's.
open -W -n "$PWD/dist/Mac AutoKey.app" --args \
    --verify-local-input "$PWD/.build/Input Receiver.app" \
    "$REPORT" "$@"
cp "$REPORT" "$DESTINATION"
cat "$REPORT"
swift Scripts/CheckVerification.swift "$REPORT"
