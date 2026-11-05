#!/bin/sh
# run-ipad-ui-tests.sh — Image Producer iPad shakedown in the iPad SIMULATOR. His ask 2026-11-04.
# Headless: xcodebuild boots the simulator without the Simulator window, so his screen,
# mouse and keyboard stay his. His real iPad is never touched.
# Output: UITestResults/<date-time>-ipad/RESULTS.md, ACCESSIBILITY.md, *.txt (screens seen).
cd "$(dirname "$0")/.." || exit 1
SIM="${SIM:-iPad Pro 13-inch (M5)}"
LOG=/tmp/imageproducer-ipad-uitests.log
UDID0=$(xcrun simctl list devices | grep "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
# The runner's data container has no fixed bundle ID to ask simctl for, so find it by folder name.
find "$HOME/Library/Developer/CoreSimulator/Devices/$UDID0/data/Containers/Data/Application" -maxdepth 3 -type d -name ImageProducerUITestResults -exec rm -rf {} + 2>/dev/null
caffeinate -dimsu xcodebuild test -scheme "Image Producer" -destination "platform=iOS Simulator,name=$SIM" \
  -parallel-testing-enabled NO -only-testing:"Image ProducerUITests/Image_ProducerUITests_iPad/testShakedownIPad" -only-testing:"Image ProducerUITests/Image_ProducerUITests_iPad/testTextSizeIPad" \
  -resultBundlePath "/tmp/imageproducer-ipad-$(date +%H%M%S).xcresult" \
  > "$LOG" 2>&1
OUT="UITestResults/$(date +%Y-%m-%d-%H%M)-ipad"
mkdir -p "$OUT"
# The runner's tmp folder lives inside the simulator's container for the runner app.
D=$(find "$HOME/Library/Developer/CoreSimulator/Devices/$UDID0/data/Containers/Data/Application" -maxdepth 3 -type d -name ImageProducerUITestResults | head -1)
cp "$D"/* "$OUT"/ 2>/dev/null
grep -E "Test case .* (passed|failed)|\*\* TEST" "$LOG" | tail -3
echo "PASS: $(grep -c 'PASS' "$OUT/RESULTS.md" 2>/dev/null)  FAIL: $(grep -c 'FAIL' "$OUT/RESULTS.md" 2>/dev/null)  → $OUT"
grep -E 'FAIL|NOT CHECKED' "$OUT/RESULTS.md" 2>/dev/null
