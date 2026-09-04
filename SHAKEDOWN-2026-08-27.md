# 🔧 Image Producer — shakedown, 2026-08-27

**Paused deliberately, not abandoned.** His call, and the reason matters:

> *"the only reason i am worried about image producer is if i cant reproduce your generated
> previews then image producer failed the shakedown - please document and we will concentrate
> more on fixing it tomorrow."*

---

## 🎯 THE ACCEPTANCE TEST — this is the bar, not "are there bugs"

**Image Producer must be able to reproduce this, unaided:**

`~/Desktop/Shell Citadel/Shell-Citadel-splash-1024.png`

Built outside the app with ImageMagick from two of his own files:

| Input | Size | Role |
|---|---|---|
| `IMG_0414.jpeg` | 1024×1024 | the seashell, black background removed |
| `ImageProducer0019.jpeg` | 562×562 | the circuit plate underneath |

**Steps the app has to be able to perform:**

1. **Remove the background from the shell.** It is **NOT black** — it is `srgb(20,17,33)` ≈ `#141121`,
   and a flat corner patch holds **21 distinct colours** because of JPEG noise. So it needs a
   colour target *and* a tolerance around **12%**. A hard "remove black" does nothing at all here.
2. **Keep the result square and transparent** — 1024×1024, alpha preserved.
3. **Place it centred over the circuit plate** at about 80% of the canvas.
4. **Export** without reintroducing a background.

**If it cannot do those four things, it failed the shakedown.** That is his standard and it is the
right one — the app exists to make images, and this is an image he wants.

**A reference to grade against** (so a failure can be told apart from a hard source image):
`~/Desktop/Shell Citadel/Seashell-cutout-REFERENCE.png`

---

## ✅ FIXED TODAY — all three build clean on macOS

### 1. Square crop drew a rectangle
**His report:** *"i chose square aspect ratio and it stayed rectangle and didnt automatically snap
to square with the shaded ask previewing a square crop."*

`cropRect` is stored in **normalised canvas coordinates (0…1)**, and `ratioRect` never divided out
the canvas aspect. So Square at 80% produced `0.8 × 0.8` — a square *in fractions of the canvas*,
which on his 2:1 canvas drew as a 2:1 rectangle.

**Measured off his screen, which is what confirmed it:** canvas ≈ 506×254 (2.0:1), crop drawn
≈ 404×205 (1.97:1) — exactly 80% of width by 80% of height.

**Fix:** `let aspect = (w / h) / canvasAspect` in `ratioRect`. On a 2:1 canvas, Square@80% now
computes `0.40 × 0.80` → 320×320 px → genuinely 1:1.

The old comment above that function claimed it *"always fits inside the square"* — it had assumed a
square canvas, and that assumption **was** the bug.

### 2. The crop never computed when a document opened
`applyCrop()` was only ever called from six `.onChange` handlers. Nothing called it on appear. So a
document opening with an aspect already selected computed no rect at all, drew no overlay, and
**re-choosing the value already showing did nothing** — because it was not a change.

**Fix:** `.onAppear { if cropAspect != .original { applyCrop() } }`

*(He confirmed this one immediately: "now i just opened image producer and didn't touch anything and
it looks 99% right.")*

### 3. "No grabbers" — the transform handles were painted over
**Caused by fix 2, and the z-order was always wrong.** `TransformBox` drew first, then `CropOverlay`
painted its dimming scrim on top. The handles still worked — `CropOverlay` is
`.allowsHitTesting(false)` — but were washed out and looked absent. It only became visible once a
crop started existing on open.

**Fix:** draw the scrim first, the box second. **A selection box belongs above a dimming layer.**

---

## ❌ OPEN — for tomorrow

### A. White bars inside the crop *(his: "the white bars shouldn't be there but it is close enough")*
Almost certainly the padding he noticed when the layer was made — the image not filling the canvas,
so empty canvas shows through. **A layer transform/scale question, not a crop one.** Not yet
investigated.

### B. The crop rectangle cannot be dragged, and the pointer never changes
*"the pointer doesn't change to arrow pointing in and out based on its angle with relation to side
of the crops ants marching"*

**Not broken — never built.** `CropOverlay` is four dimming rectangles with hit-testing off. There
is nothing under the pointer to react to. The crop is driven entirely by the aspect picker and the
size slider.

Cursor handling exists but is **per tool** (`pointerStyle(Self.style(for: tool))` — a bucket for
Fill, a pencil for Pen), never per hover target.

> **The pattern already exists in his own codebase.** `MaskBox` has grabbable corners with
> free/ratio/rectangle modes. Crop simply never got the same treatment. The work is to give the crop
> rect what the mask already has, plus `.pointerStyle(.frameResize(position:))` per handle.

**This is a feature, not a regression.**

---

## 📝 Notes for whoever picks this up

- **Build for macOS, not the iOS Simulator.** `ContentView.swift:108` uses `.modifiers`, which is
  macOS-only, so an iOS-Simulator build fails with errors that have nothing to do with your change.
  `-destination 'platform=macOS'`.
- Backup of the pre-fix file: `ContentView.swift.bak-2026-08-27`.
- `importImageAsLayer` **resizes the canvas to the imported image**. Whichever image goes in last
  sets the canvas size — worth choosing deliberately when combining the 1024 shell with the 562 plate.
