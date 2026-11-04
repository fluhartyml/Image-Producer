# Image Producer shakedown

| Build | Result | Check |
|---|---|---|
Run: 2026-11-04 21:30:19 +0000  ·  Mac  ·  -ImageProducerUITest (temporary image; his files untouched)

| — | ✅ PASS | A new image opens (in the test's temporary folder) |
| 356 | ✅ PASS | Palette swatches are named buttons — 11 found |
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
