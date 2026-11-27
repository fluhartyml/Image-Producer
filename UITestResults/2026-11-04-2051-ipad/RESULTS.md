# Image Producer iPad shakedown

| Build | Result | Check |
|---|---|---|
Run: 2026-11-05 02:39:46 +0000  ·  iPad simulator  ·  -ImageProducerUITest (simulator only; his iPad untouched)

| — | ✅ PASS | A new image opens |
| 356 | ❌ FAIL | Palette swatches are named buttons — 0 found |
| 356 | ❌ FAIL | Pressing a swatch picks that color — no unselected swatch to press |
| 364 | ❌ FAIL | Key M picks Move |
| 364 | ❌ FAIL | Key B picks Paint Drop Bucket |
| 364 | ✅ PASS | Key C picks Canvas |
| — | ✅ PASS | A layer is active in Move — Layer 6 |
| 364 | ❌ FAIL | Arrow keys: Down ×5 + Shift-Down = 15 px down, none sideways — moved 0.0 px down, 0.0 px sideways |
| 358 | ❌ FAIL | Straight-line buttons are there by their spoken names |
| 015a | ❌ FAIL | Text grows with the system text size (Accessibility Large) — "Active color" 0.0 pt tall → 0.0 pt |
