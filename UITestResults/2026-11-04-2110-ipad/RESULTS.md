# Image Producer iPad shakedown

| Build | Result | Check |
|---|---|---|
Run: 2026-11-05 03:05:27 +0000  ·  iPad simulator  ·  -ImageProducerUITest (simulator only; his iPad untouched)

| — | ✅ PASS | A new image opens |
| 356 | ✅ PASS | Palette swatches are named buttons — 8 found |
| 356 | ✅ PASS | Pressing a swatch picks that color — pressed Color 2, #FFFFFF; selected now: Color 2, #FFFFFF |
| 364 | ✅ PASS | Key M picks Move |
| 364 | ✅ PASS | Key B picks Paint Drop Bucket |
| 364 | ✅ PASS | Key C picks Canvas Tool |
| — | ✅ PASS | A layer is active in Move — Layer 6 |
| 364 | ✅ PASS | Arrow keys: Down ×5 + Shift-Down = 15 px down, none sideways — moved 15.0 px down, 0.0 px sideways |
| 358 | ✅ PASS | Straight-line buttons are there by their spoken names |
| 358 | ✅ PASS | Up down only shows as selected when on |
| 358 | ✅ PASS | Up down only: a diagonal drag moves only up/down — 0.0 px sideways, 62.5 px down |
| 358 | ✅ PASS | Tapping Up down only again turns it off |
| 358 | ✅ PASS | Left right only: a diagonal drag moves only sideways — 93.7 px sideways, 0.0 px down |
| 358 | ✅ PASS | Left right only turns off again |
| 366 | ✅ PASS | Position X, Position Y and Rotation degrees fields are there by name |
| 366 | ✅ PASS | Typing X 100, Y 200 puts the layer's center there — center 100.0, 200.0 px |
| 013 | ✅ PASS | The canvas is one element named Canvas |
| 014 | ✅ PASS | Arrows + Space paint by keyboard: one stroke, one new pixel layer — layers 9 → 10, active Layer 6 (Move 3) (Pixel 1) |
| 015 | ✅ PASS | Every tool picked by its spoken name shows as selected (19 tools) — all 19 |
| 015a | ✅ PASS | Text grows with the system text size (Accessibility Large) — "Active color" 21.5 pt tall → 39.0 pt |
