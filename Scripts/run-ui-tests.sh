#!/bin/sh
# run-ui-tests.sh — Image Producer shakedown (Legend's pattern), Mac. His ask 2026-11-04.
# Checks builds 356–359 by accessibility name + keyboard, inventories each screen, runs Apple's
# accessibility audit. Launches with -ImageProducerUITest: the test image lives in the app's temp
# folder; his iCloud files, recents and project number are untouched. Takes over the screen ~3 min.
# Output: UITestResults/<date-time>/RESULTS.md, ACCESSIBILITY.md, *.txt (screens seen).
cd "$(dirname "$0")/.." || exit 1
D="$HOME/Library/Containers/com.nightgard.Image-ProducerUITests.xctrunner/Data/tmp/ImageProducerUITestResults"
rm -rf "$D"
caffeinate -dimsu xcodebuild test -scheme "Image Producer" -destination 'platform=macOS' \
  -allowProvisioningUpdates -only-testing:"Image ProducerUITests/Image_ProducerUITests/testShakedown" \
  > /tmp/imageproducer-uitests.log 2>&1
OUT="UITestResults/$(date +%Y-%m-%d-%H%M)"
mkdir -p "$OUT" && cp "$D"/* "$OUT"/ 2>/dev/null
tail -3 /tmp/imageproducer-uitests.log
echo "PASS: $(grep -c 'PASS' "$OUT/RESULTS.md")  FAIL: $(grep -c 'FAIL' "$OUT/RESULTS.md")  → $OUT"
grep -E 'FAIL|NOT CHECKED' "$OUT/RESULTS.md"
