# Image Producer shakedown

| Build | Result | Check |
|---|---|---|
Run: 2026-11-04 20:15:54 +0000  ·  Mac  ·  -ImageProducerUITest (temporary image; his files untouched)

| — | ✅ PASS | A new image opens (in the test's temporary folder) |
| 356 | ✅ PASS | Palette swatches are named buttons — 11 found |
| — | ✅ PASS | A layer is active in Move — Layer 6 |
| 357 | ✅ PASS | Arrow keys: Down ×5 + Shift-Down = 15 px down, none sideways — moved 15.0 px down, 0.0 px sideways |
| 357 | ✅ PASS | Leaving Move keeps the nudge as one Move step (hidden original kept) — Layer 6 (Move), hidden 1 |
| 358 | ✅ PASS | Straight-line buttons are there by their spoken names |
| 358 | ❌ FAIL | Up down only shows as selected when on |
| 358 | ❌ FAIL | Up down only: a diagonal drag moves only up/down — 0.0 px sideways, 0.0 px down |
| 358 | ❌ FAIL | Tapping Up down only again turns it off |
| 358 | ❌ FAIL | Left right only: a diagonal drag moves only sideways — 0.0 px sideways, 0.0 px down |
| 358 | ✅ PASS | Left right only turns off again |
| 358 | ❌ FAIL | Shift-drag locks to the starting direction (mostly sideways → sideways only) — 0.0 px sideways, 0.0 px down |
| 359 | ❌ FAIL | Option-drag makes one new layer and selects it as "(copy)" — Layer 6 (Move), layers 7→7 |
| 359 | ❌ FAIL | The copy moved — 0.0 px |
| 359 | ✅ PASS | Committing the copy adds no hidden fork — hidden 1→1 |
| 359 | ⚠️ NOT CHECKED | Original's position — its row wasn't found by name 'Layer 6 (Move)' |
| 359 | ❌ FAIL | Option-Shift-drag copy stays in a straight line — 0.0 px down |
