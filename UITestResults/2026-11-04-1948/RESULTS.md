# Image Producer shakedown

| Build | Result | Check |
|---|---|---|
Run: 2026-11-05 01:44:17 +0000  ·  Mac  ·  -ImageProducerUITest (temporary image; his files untouched)

| — | ✅ PASS | A new image opens (in the test's temporary folder) |
| 356 | ✅ PASS | Palette swatches are named buttons — 10 found |
| 356 | ✅ PASS | Pressing a swatch picks that color — pressed Color 2, #FFFFFF; selected now: Color 2, #FFFFFF |
| — | ✅ PASS | A layer is active in Move — Layer 6 |
| 357 | ✅ PASS | Arrow keys: Down ×5 + Shift-Down = 15 px down, none sideways — moved 15.0 px down, 0.0 px sideways |
| 357 | ❌ FAIL | Leaving Move keeps the nudge as one Move step (hidden original kept) — Layer 6, hidden 0 |
| 358 | ✅ PASS | Straight-line buttons are there by their spoken names |
| 358 | ✅ PASS | Up down only shows as selected when on |
| 358 | ✅ PASS | Up down only: a diagonal drag moves only up/down — 0.0 px sideways, 88.5 px down |
| 358 | ✅ PASS | Tapping Up down only again turns it off |
| 358 | ✅ PASS | Left right only: a diagonal drag moves only sideways — 132.7 px sideways, 0.0 px down |
| 358 | ✅ PASS | Left right only turns off again |
| 358 | ✅ PASS | Shift-drag locks to the starting direction (mostly sideways → sideways only) — 176.9 px sideways, 0.0 px down |
| 359 | ❌ FAIL | Option-drag makes one new layer and selects it as "(copy)" — Layer 6 (copy), layers 6→8 |
| 359 | ✅ PASS | The copy moved — -18.6 px |
| 359 | ❌ FAIL | Committing the copy adds no hidden fork — hidden 0→1 |
| 359 | ❌ FAIL | The original stayed where it was — x 0.8024→0.5000 |
| 359 | ✅ PASS | Option-Shift-drag copy stays in a straight line — 0.0 px down |
| 366 | ✅ PASS | Position X, Position Y and Rotation degrees fields are there by name |
| 366 | ✅ PASS | Typing X 100, Y 200 puts the layer's center there — center 100.0, 200.0 px |
| 013 | ❌ FAIL | The canvas is one element named Canvas |
| 014 | ✅ PASS | Arrows + Space paint by keyboard: one stroke, one new pixel layer — layers 9 → 10, active Layer 6 (copy) (Pixel 1) |
| 015 | ❌ FAIL | Every tool picked by its spoken name shows as selected (19 tools) — missed: Canvas |
