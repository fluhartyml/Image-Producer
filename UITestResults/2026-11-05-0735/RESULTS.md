# Image Producer shakedown

| Build | Result | Check |
|---|---|---|
Run: 2026-11-05 13:30:08 +0000  ·  Mac  ·  -ImageProducerUITest (temporary image; his files untouched)

| — | ✅ PASS | A new image opens (in the test's temporary folder) |
| 356 | ✅ PASS | Palette swatches are named buttons — 10 found |
| 356 | ✅ PASS | Pressing a swatch picks that color — pressed Color 2, #FFFFFF; selected now: Color 2, #FFFFFF |
| — | ✅ PASS | A layer is active in Move — Layer 6 |
| 357 | ✅ PASS | Arrow keys: Down ×5 + Shift-Down = 15 px down, none sideways — moved 15.0 px down, 0.0 px sideways |
| 357 | ✅ PASS | Leaving Move keeps the nudge as one Move step (hidden original kept) — Layer 6 (Move), hidden 1 |
| 358 | ✅ PASS | Straight-line buttons are there by their spoken names |
| 358 | ✅ PASS | Up down only shows as selected when on |
| 358 | ✅ PASS | Up down only: a diagonal drag moves only up/down — 0.0 px sideways, 88.5 px down |
| 358 | ✅ PASS | Tapping Up down only again turns it off |
| 358 | ✅ PASS | Left right only: a diagonal drag moves only sideways — 132.7 px sideways, 0.0 px down |
| 358 | ✅ PASS | Left right only turns off again |
| 358 | ✅ PASS | Shift-drag locks to the starting direction (mostly sideways → sideways only) — 176.9 px sideways, 0.0 px down |
| 359 | ✅ PASS | Option-drag makes one new layer and selects it as "(copy)" — Layer 6 (Move 2) (copy), layers 8→9 |
| 359 | ✅ PASS | The copy moved — -176.9 px |
| 359 | ✅ PASS | Committing the copy adds no hidden fork — hidden 2→2 |
| 359 | ✅ PASS | The original stayed where it was — x 0.8024→0.8024 |
| 359 | ✅ PASS | Option-Shift-drag copy stays in a straight line — 0.0 px down |
| 366 | ✅ PASS | Position X, Position Y and Rotation degrees fields are there by name |
| 366 | ✅ PASS | Typing X 100, Y 200 puts the layer's center there — center 100.0, 200.0 px |
| 355 | ✅ PASS | Typing B in a number box leaves the tool alone (still Move) |
| 366 | ✅ PASS | Typing Rotation 30 turns the layer to 30 degrees — field reads 30 |
| 366 | ✅ PASS | Crop left, top, width and height fields are there by name |
| 366 | ❌ FAIL | Square crop: typing Width 400 makes Height 400 (ratio held) — width 922.0, height 922.0 |
| 366 | ✅ PASS | Typing Crop left 100, top 50 moves the crop box there — left 100.0, top 50.0 |
| 366 | ✅ PASS | Mask left, top, width and height fields are there by name |
| 366 | ✅ PASS | Typing Mask left 100, top 80 moves the mask there — left 100.0, top 80.0 |
| 366 | ✅ PASS | Typing Mask width 300 sizes the mask — width 300.0, height 819.0 |
| 013 | ✅ PASS | The canvas is one element named Canvas |
| 014 | ✅ PASS | Arrows + Space paint by keyboard: one stroke, one new pixel layer — layers 11 → 12, active Layer 6 (Move 2) (copy) (Move) (Pixel 1) |
| 015 | ✅ PASS | Every tool picked by its spoken name shows as selected (19 tools) — all 19 |
| 355 | ✅ PASS | Every tool letter picks its tool on the Mac (19 keys) — all 19 |
