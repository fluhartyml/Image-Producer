//
//  ImageProducer_DeveloperNotes.swift
//  Image Producer
//
//  Created by Michael Fluharty on 6/9/26.
//
//  ============================================================================
//  PLAN OF RECORD — living design doc. The app is now BUILT (document-based,
//  multiplatform) and shipping green; this file is the design history + roadmap.
//  Last updated: 2026-06-21.
//  ============================================================================
//
//  WHY THIS APP / ORIGIN
//  ---------------------
//  Conceived 2026-06-10 out of a brainstorm about Apple's Image Playground
//  framework. The "aha": an app you build can host on-device AI image
//  generation, then turn that art into a shippable app icon. "Image Producer"
//  = produce app icons, AI-first.
//
//  CURRENT STATE OF THE PROJECT (as of 2026-06-21)
//  -----------------------------------------------
//  - SHIPPED & BUILDING GREEN. Document-based multiplatform app (DocumentGroup /
//    IconDocument; SwiftData dropped). Repo github.com/fluhartyml/Image-Producer,
//    bundle id com.nightgard.Image-Producer, iCloud container
//    iCloud.com.nightgard.image-producer (Files folder "Image Producer").
//  - Built: layered editor + canvas; Move/Transform (crop now bakes a selectable
//    object the box hugs, centered, with Fit/Fill snap-to-canvas); paint bucket
//    (backgrounds); pixel pen + erase; tool strip + custom tool icons; branded
//    launch (iOS DocumentGroupLaunchScene + a Mac Welcome window); version line
//    on all platforms. Undo is OFF by design (no UndoManager; History is future).
//  - Roadmap (below): History engine, selection subsystem (Path/Magic Wand),
//    Image Playground tool, effects, print/canvas-size, the registration gate.
//
//  ----------------------------------------------------------------------------
//  VERIFIED APPLE FACTS (sourced from Apple Developer docs, 2026-06-10)
//  ----------------------------------------------------------------------------
//  Framework is `ImagePlayground` — there is NO "ImagePlaygroundKit"; you just
//  `import ImagePlayground`. System framework, available in Xcode. Supports
//  SwiftUI, UIKit, AppKit. Two integration modes:
//
//    1. USER-DRIVEN UI — `.imagePlaygroundSheet(...)` SwiftUI modifier (or the
//       UIKit/AppKit view-controller equivalent). Presents Apple's Image
//       Playground sheet inside your app; the user generates the image; you get
//       back the result URL.
//
//    2. PROGRAMMATIC — `ImageCreator` class (added iOS 18.4 / iPadOS 18.4 /
//       macOS 15.4 / visionOS 2.4). You make an `ImageCreator`, call
//       `images(for:style:limit:)` with an `ImagePlaygroundConcept`
//       (text / image / drawing) + an `ImagePlaygroundStyle`, get a stream of
//       generated images. Runs ON-DEVICE — no model to ship, no hosting.
//
//  CONSTRAINTS / HONEST LIMITS (these shape the whole design):
//    - REQUIRES an Apple-Intelligence-capable device. On unsupported hardware
//      the API isn't available -> the app needs a non-AI path + a graceful
//      "not supported here" state. AI can never be the ONLY way to make
//      something in this app.
//    - OUTPUT IS STYLIZED ART (animation / illustration / sketch looks) — aimed
//      by Apple at stickers, character art, in-app imagery. It is a MISMATCH
//      for the flat, geometric style most app icons want. Image Playground
//      gives you A PICTURE, not an icon SET.
//    - APP ICONS proper are made with Icon Composer (the layered `.icon`
//      format, Xcode 26+) — a DIFFERENT tool. Natural division of labor:
//      Image Playground (ImageCreator) GENERATES artwork; Icon Composer / a
//      layer editor TURNS artwork into a shipping icon. They can chain.
//    - No bundled audio/IP-licensing entanglement — on-device generation is
//      clean on that front (fits Michael's app rules of thumb).
//
//  ----------------------------------------------------------------------------
//  DECIDED 2026-06-10 — THE EDITOR: SQUARE LAYERED + HISTORY CANVAS
//  ----------------------------------------------------------------------------
//  Michael: "similar to the shelf app, I want Image Producer to have a square
//  canvas that is layer and history like Photoshop." So Image Producer adopts
//  the SAME editor paradigm proven in Shelf-Ready's icon editor. The reference
//  design lives in:
//    ~/Developer.complex/NightGard/Shelf-Ready/Shelf-Ready/
//        Shelf-Ready_DeveloperNotes.swift  (Half B + the IMAGE-HISTORY section)
//
//  The model being mirrored (from Shelf-Ready, designed with Michael 2026-06-08/09):
//    • SQUARE CANVAS = the icon itself. No "outside" the square; the square *is*
//      the artboard. (Shelf-Ready: 1024 doc.)
//    • ORDERED STACK OF LAYERS, NEVER flattened until export (nondestructive).
//      Layer-list order = composite order = z-order; drag to reorder.
//    • Layer kinds: SYMBOL (vector SF Symbol), IMAGE (imported/pasted/AI art),
//      PIXEL (MS-Paint grid), TEXT (click-to-add text element). PIXEL's editing
//      model differs from Shelf-Ready (see below); TEXT is net-new (confirmed
//      2026-06-10). Each TOOL drives a contextual inspector (Photoshop
//      Options-Bar model — see "TOOL INSPECTOR").
//    • Per-layer: editable name, eye visibility toggle, transform
//      (center/scale/rotation), one-at-a-time delete.
//    • HISTORY = LINEAR, Photoshop-style. Undo is NOT a separate feature (no
//      ⌘Z, no undo/redo buttons) — it's a BYPRODUCT of an IMAGE-HISTORY sheet
//      that sits BEHIND the layer list and is revealed by swiping the layer
//      list aside. Pick any history entry = step back to it (navigable down to
//      a single pixel). History is PERSISTENT from icon creation; PURGE HISTORY
//      is the only thing that clears it (keeps the current image intact).
//    • DEFAULT LAYERS / TRANSPARENCY: a new icon starts with THREE layers —
//      Light Background, Dark Background, Icon (proto). The two backgrounds are
//      SEPARATE opaque solid-fill layers (kept, like Shelf-Ready); CONTENT
//      layers are transparent/see-through. Light vs dark is controlled by the
//      LAYER EYEBALL (hide one bg to preview the other) — NOT by mode buttons
//      (the Shelf-Ready "Light | Dark" buttons are what was unintuitive).
//      Details in "DIVERGENCE: TRANSPARENT LAYERS + BACKGROUND" below.
//
//  DECIDED 2026-06-10 — LAYER COUNT + CONTENT SOURCES (Michael):
//    • INFINITE LAYERS. The user can add UNLIMITED layers (no cap). The three
//      default layers are just the starting point, not a fixed ceiling — "+"
//      adds as many as wanted.
//    • PHOTO IMPORT ON ANY LAYER, from TWO sources:
//        - FROM FILE  -> document picker (cross-platform; .fileImporter /
//          security-scoped URL).
//        - FROM PHOTO ALBUM -> the system photo library (PhotosUI PhotosPicker).
//      So an IMAGE layer can be filled by: an imported file, an imported photo,
//      OR an AI image from ImageCreator — all three are IMAGE-kind content.
//
//      IMPORT WORKFLOW (Michael, 2026-06-10 — leaning, near-locked):
//      Importing an image CREATES A NEW IMAGE LAYER, auto-named after the
//      source image's name — same pattern as the text tool, where adding text
//      creates a layer whose NAME = the text content. "Content names the layer"
//      is the convention for the whole app. (Secondary mode kept open: import
//      can also INSERT INTO a selected layer when that's what's wanted — but
//      the DEFAULT is new-named-layer.) Layer names always stay user-editable.
//
//      NAMING SOURCE — VERIFIED ASYMMETRY (Apple docs, 2026-06-10), because it
//      decides what the auto-name can be:
//        • FROM FILE (.fileImporter / document picker): you get a real URL, so
//          url.lastPathComponent gives a CLEAN filename -> layer name =
//          filename (minus extension). Clean, meaningful. Easy.
//        • FROM PHOTO ALBUM (PhotosUI PhotosPicker): privacy-preserving by
//          design. PhotosPickerItem exposes only an opaque `itemIdentifier`,
//          NOT a friendly filename. Best available name = the CAPTURE filename
//          (e.g. "IMG_1234") obtained via loadTransferable -> URL
//          .lastPathComponent, or NSItemProvider.suggestedName. That's rarely
//          meaningful, and can be missing -> FALL BACK to a generated name
//          ("Image 1", "Photo 2"). So Photos imports won't get a nice name like
//          File imports do; plan the fallback + rely on the user renaming.
//
//      "HOW THE iPHOTO WORKFLOW WORKS" (Michael's question): SwiftUI
//      `PhotosPicker` presents the system photo picker; the user taps a photo;
//      you receive a `PhotosPickerItem`; you call `loadTransferable(type:)` to
//      pull the image data (or a file URL). No full photo-library permission is
//      needed just to PICK (the picker runs out-of-process) — the
//      NSPhotoLibraryUsageDescription string is only needed if we later reach
//      into PhotoKit for richer metadata. So: pick -> load data -> new image
//      layer named from whatever name we can salvage (see asymmetry above).
//
//      TEXT TOOL / TEXT LAYER — IN SCOPE (CONFIRMED Michael 2026-06-10):
//      Layer kinds are now SYMBOL / IMAGE / PIXEL / TEXT.
//        • TEXT is a TOOL, not an import: "you don't import text, you click a
//          text tool and that adds text." Clicking the text tool ADDS a text
//          element (its own layer).
//        • The text layer is auto-named from its STRING content (the naming
//          precedent for the whole app — content names the layer).
//        • GLYPHS ARE TEXT (Michael 2026-06-10): a single glyph/character (a
//          letter, numeral, font glyph) is just TEXT in a font — handled by the
//          text tool. PRIMARY USE CASE (CONFIRMED): the user takes ONE LETTER
//          and makes it the icon (a big single glyph blown up). WORDS are
//          allowed but NOT the focus — "I don't think they'd use words, but if
//          they do that's their deal, more power to them." So: no word-count
//          limit, but design/optimize for the single-glyph icon.
//        • SYMBOL vs TEXT — RESOLVED: KEEP SEPARATE. SYMBOL layer = SF Symbols
//          (picked from Apple's library, its own picker). TEXT layer = font
//          glyphs (typed or chosen from the font-book). Two distinct input
//          methods, two pickers — not merged.
//        • MUST be wired to an INSPECTOR so the user can FORMAT the text and
//          CHOOSE A FONT. Inspector covers at least: font family (font picker),
//          size, weight/style, color, alignment; likely also tracking/leading.
//          (Michael: "it needs to be wired to an inspector so you can format
//          the text and choose a font.")
//        • FONT PICKER shows a LIVE PER-FONT PREVIEW: each font in the list is
//          rendered in ITS OWN typeface using a short sample string (a pangram-
//          style "quick sly fox" example), so you see what each font looks like
//          before choosing. (Michael: "each font has a quick sly fox example of
//          each font.")
//        • SIZE SCALES UP TO FILL THE CANVAS: text/fonts can be resized large
//          enough to take up the ENTIRE canvas when blown up (a single big glyph
//          = a full icon). No artificial size cap below canvas-filling.
//          (Michael: "the fonts can be resized to take up the entire canvas if
//          blown up.")
//        • FONT-BOOK / GLYPH-REPERTOIRE INSPECTOR (Michael 2026-06-10, proposed
//          — "may need"): beyond typing, a view that shows ALL glyphs available
//          in the selected font (like macOS Font Book's repertoire / the
//          Character Viewer) — ligatures, alternates, dingbats, ornaments,
//          symbol glyphs that aren't easily typed — so you can BROWSE and pick a
//          glyph VISUALLY and drop it as the text content. Pairs with "glyphs
//          are text": this is how you reach the non-typeable glyphs.
//          Tech (flag): enumerate a font's glyphs via Core Text
//          (CTFontCopyCharacterSet / glyph enumeration); built-in on Mac
//          (Character Viewer / NSFontPanel), custom UI on iOS. VERIFY ON X27
//          BETA. Status: PROPOSED, confirm if it's in v1 scope.
//          WORKFLOW (Michael 2026-06-10): SELECT a glyph in the font-book ->
//          PASTE it into the icon (it drops as a TEXT element, following the
//          same selection rule: no layer selected -> new layer; layer selected
//          -> into it) -> then use the FONT INSPECTOR to RESIZE/format the glyph
//          (size scales up to fill the canvas as above). So the font-book is a
//          GLYPH SOURCE that feeds a normal text element, which the font
//          inspector then sizes/styles — one consistent text pipeline.
//        • GLYPH/TEXT EFFECTS (Michael 2026-06-10: "I want to be able to add
//          effects to the glyphs"). Photoshop-style layer styles on a glyph/text
//          element. CANDIDATE effects (full vocabulary — do NOT pre-cut, confirm
//          the set with Michael): gradient fill (vs solid), STROKE/outline,
//          drop shadow, inner shadow, outer/inner GLOW, bevel/emboss, color
//          overlay, opacity/blend mode. Configured in the inspector; applied
//          NONDESTRUCTIVELY (live + re-editable, like the rest of the model) and
//          recorded in history. Render at full res (vector text stays crisp).
//          LAYER-WIDE — RESOLVED (Michael 2026-06-10): effects are NOT
//          glyph-only; they are general LAYER STYLES usable on ANY layer.
//          Michael's idea: if a user IMPORTS A SMALL IMAGE WITH ROOM AROUND IT,
//          they can open the SAME effects inspector and add a glow (or any
//          Image Producer effect) to that imported image — same inspector, same
//          effect stack, just on an image layer instead of a glyph.
//          MECHANICS NOTE: outward effects (glow, drop shadow, flame) need
//          TRANSPARENT ROOM around the content to render INTO. A small image
//          centered with empty margin is the ideal case; an image filling the
//          layer edge-to-edge leaves the glow nowhere to go. Reinforces the
//          transparent-content-layers principle (effects + alpha go together).
//          Tech (flag): SwiftUI gives shadow/gradient/stroke cheaply; inner
//          shadow / bevel / emboss need custom rendering. VERIFY ON X27 BETA.
//          PLACEMENT — RESOLVED (Michael 2026-06-10): the EFFECTS INSPECTOR is
//          a SEPARATE, SHARED, REUSABLE inspector ACCESSED VIA A BUTTON in the
//          tool inspector. Press the button in the font inspector -> the font
//          inspector SWAPS OUT and is REPLACED by the effects inspector (a
//          drill-in / push; a back action returns to the tool inspector). The
//          font inspector stays typography-only.
//          REUSE: the SAME effects inspector is opened by the SHAPE tool and any
//          future tool/layer that supports effects — build it ONCE, reuse
//          everywhere (fits the shared-engine philosophy). It operates on the
//          selected element/layer's effect stack: stackable, toggleable,
//          reorderable, nondestructive, history-recorded.
//          (So the inspector panel has two states — TOOL-OPTIONS and EFFECTS —
//          toggled by the button; effects content is identical regardless of
//          which tool launched it.)
//          SPECIFIC EFFECTS Michael named (2026-06-10):
//            - OUTER GLOW — CONFIRMED, in. Easy: blurred colored halo around the
//              glyph shape.
//            - PLASMA FLAME — DESIRED hero effect ("if possible"). Ambitious but
//              feasible via a METAL FRAGMENT SHADER on the glyph (SwiftUI
//              .colorEffect / .layerEffect, iOS 17+/macOS 14+): animated noise +
//              fire color ramp (black->red->orange->yellow->white) off the glyph
//              edges. REAL shader work, not a checkbox. NOTE: app icons are
//              STATIC -> what ships is a STATIC flame frame (a live animated
//              version could exist for preview only). Mark as a STRETCH/R&D
//              effect; VERIFY shader APIs ON X27 BETA. Maximum-quality bar: make
//              it genuinely good, not a cheap gradient.
//        • Tech (flag, not now): render text as VECTOR so it stays crisp at any
//          icon size (like the SYMBOL layer); keep it RE-EDITABLE (change the
//          string + reformat later, nondestructive). Font picker: SwiftUI font
//          APIs / UIFontPickerViewController (iOS) / NSFontPanel-style (Mac).
//          VERIFY ON X27 BETA. The text inspector is one instance of the
//          app-wide TOOL INSPECTOR model — see next.
//
//  DECIDED 2026-06-10 — TOOL INSPECTOR (Photoshop Options-Bar model, Michael):
//    "All tools may need to be wired to a tool inspector — I think Photoshop
//    does it that way." So the inspector is TOOL-CONTEXTUAL: a single inspector
//    surface that RE-POPULATES with the ACTIVE TOOL's options (like Photoshop's
//    Options Bar), NOT a fixed per-layer panel.
//      • What each tool shows when active (examples):
//          - TEXT tool   -> font picker, size, weight/style, color, alignment.
//          - PIXEL tools -> pencil/brush size, color, opacity; fill tolerance;
//                           shape stroke/fill; grid density (128/256/512/1024);
//                           mirror/symmetry toggle.
//          - SYMBOL tool -> SF Symbol picker, weight/scale, tint.
//          - IMAGE/import-> source (File / Photo / paste) + transform/opacity.
//          - MOVE/TRANSFORM -> position, scale, rotation, alignment.
//      • COMPLEMENTS the layer list (the stack) and the live thumbnail.
//        Photoshop pairs a tool-contextual Options Bar WITH layer/Properties
//        panels; we may end up with both, but the PRIMARY inspector follows the
//        active TOOL.
//      • Supersedes the earlier "each layer KIND has its own inspector" wording
//        — it's TOOL-driven, not layer-driven.
//
//  DECIDED 2026-06-11 — UI LAYOUT / COMPONENT PLACEMENT (Michael):
//    How the four surfaces (canvas, toolbox, tool inspector, layers/history)
//    are arranged. Reasoning: the TOOLBOX + its INSPECTOR are coupled and used
//    constantly (pick a tool -> tune it); LAYERS + HISTORY are a separate,
//    lower-frequency "managing" surface. So they must not fight for the same
//    always-visible space.
//      • LAYOUT adapts by GEOMETRY, not size class (iPhone landscape is still
//        "compact" width). Locked 2026-06-11, incl. iPad (Michael: "lock the
//        iPad in"):
//          - PORTRAIT (taller than wide — iPhone AND iPad portrait): canvas =
//            TOP half; everything else in the BOTTOM half (see compact model).
//          - LANDSCAPE / WIDE (Mac, iPad landscape, iPhone landscape): the
//            original side-by-side; room to show tools + inspector + layers all
//            at once, NO swiping.
//      • COMPACT (portrait) model — bottom half under the canvas:
//          - A thin TOOL STRIP pinned right under the canvas, ALWAYS VISIBLE
//            (tap to switch tools — high-frequency, never hidden behind a swipe).
//          - Below it, a SWIPE / SEGMENTED panel (Michael's "sheet that swipes
//            between the components") with three pages:
//                TOOL (the active tool's inspector — repopulates per the strip
//                      selection; the EFFECTS inspector is a drill-in BUTTON
//                      here, not its own page) · LAYERS (the list) · HISTORY.
//          - Only the three lower-frequency panels swipe; the tool strip never
//            moves. This also fills the empty space below the layers list.
//      • FUTURE — SCROLLABLE TOOLBOX (Michael 2026-06-11): when there are more
//        tools than fit the strip's first screenful, the strip SCROLLS
//        (horizontal) to reveal the overflow tools — no redesign needed as the
//        toolbox grows. (Not needed yet; only the layout shell + layers exist.)
//      • FUTURE — KEYBOARD SHORTCUTS (Michael 2026-06-11): Michael runs the iPad
//        landscape-locked in a Magic Keyboard AND drives it via Universal Control
//        (MacBook trackpad + keyboard). So a hardware keyboard is present on the
//        iPad too -> add Photoshop-style SINGLE-KEY tool shortcuts (V=move, etc.)
//        for power users. Pointer is also present -> hover tooltips work on iPad.
//        Not now; noted as a real win once tools are live.
//      • FUTURE — PRINT + NON-ICON CANVAS SIZES + DPI (Michael 2026-06-16): grow the
//        app beyond square app-icons into print/document output. Three pieces:
//          (1) PRINT THE CANVAS — send to a physical printer OR export as PDF.
//          (2) CANVAS-SIZE PICKER with presets (inches): 8.5x11 (letter),
//              11x17 (tabloid/ledger), 3x5 (index card), 2x3 (business card),
//              PLUS a CUSTOM override — user types exact dimensions "nnnnn x nnnn".
//              [implies non-square canvases — today's model is a square 1024 master,
//               so this needs a width/height canvas, not just `canvasSize: Int`.]
//          (3) RESOLUTION (DPI) PICKER: 72 dpi (web), 300 dpi (laser/thermal),
//              and a print-shop tier — Michael said "400 or whatever printer shops
//              standard dpis are." Common print-shop standards to confirm with him:
//              300 (standard), 600 (high-quality laser / line art), 1200 (fine).
//              PLUS a CUSTOM override — user types an exact "nnn dpi".
//          Both pickers = preset list + a "Custom…" entry for an explicit value
//          (Michael 2026-06-16). Presets are shortcuts, never a ceiling.
//        NOTE (no scope cut — capture in full): this pushes Image Producer toward a
//        general print-design tool, not only an app-icon maker. Worth a product-
//        positioning decision later (icon maker that ALSO prints, vs. broaden the
//        app's identity). Recorded as Michael's vision; do not trim.
//        REBRAND (Michael 2026-06-16): as the app broadened beyond app-icons
//        (print, canvas sizes, general graphics), the original narrow name "Icon
//        Producer" (it says "icons") became a MODE, not the product — per Michael's
//        standing rule, prefer an umbrella noun with room to grow over a narrow name.
//        FINAL NAME (Michael 2026-06-20): **IMAGE PRODUCER.**
//          - FULL LINEAGE (kept as history): Icon Producer -> Praelum -> Pictorial
//            Studio -> Pictorial Producer -> Image Producer. Praelum retired (too
//            abstract/Latin); "Studio" dropped (off Michael's naming voice);
//            "Pictorial" dropped 2026-06-20 — the "-al" tail reads weak, and
//            "Picture" reads as motion/video. "Image" is clean and still.
//          - "Producer" = Michael's house MAKER-SUFFIX voice: [output] + agentive
//            role-noun — Image Producer, Icon/Typeface Producer (cf. Contact/
//            Transcription Keeper, Cryo Playlist Manager, CryoTunes Player, NightGard
//            Library Commander). "Image Producer" = "makes images," on-voice and
//            App-Store-clear. Method: Workshop/Naming-Brainstorm-Method-2026-06-17.md
//          - PRIORITY: clarity/familiar/pleasant OVER ownability (Michael
//            de-prioritized owning/defending the mark).
//          - Availability (checked 2026-06-20): no exact App Store match for "Image
//            Producer" (nor the prior "Pictorial Producer"). The only HARD gate is
//            App Store Connect at reservation (it blocks identical names).
//          - ⚠️ BUNDLE ID CHANGED (2026-06-20): this is now a FRESH project with a
//            clean bundle id **com.nightgard.Image-Producer** + iCloud container
//            iCloud.com.nightgard.image-producer (Files folder "Image Producer").
//            The OLD "Icon Producer" project (com.nightgard.Icon-Producer) is kept
//            intact as a backup; its existing iCloud docs do NOT auto-migrate.
//            (SUPERSEDES the earlier "rename is display-name only, do NOT touch the
//            bundle ID" plan — that in-place rename was NOT the path taken.)
//          - "Graphic Arts" descriptor kept (spans graphic design AND printmaking).
//          - Gauntlet rejects (kept for history): Praelum/Stampa (Latin/abstract),
//            Inkstone (collides w/ Inkstone Software), Pictographic Studio (Pictogram
//            Studio TM), Markwright/Tilesmith (maker-coinage), Pictorial Studio
//            (off-voice "Studio"), Glyph (reads as font), Tessera, plus Pixel Press /
//            Imprint / Seal Press / Vellum / Calque / Signum.
//      • STATUS / HINT BAR (Michael 2026-06-11): a text bar BELOW THE CANVAS (both
//        orientations) = the app's single VOICE to the user. PRIMARY PURPOSE: it
//        solves the NO-HOVER problem on touch — desktop rollover/hover hints have
//        nowhere to go on touch, so this bar SHOWS the hint when you touch/focus a
//        tool or element. Shows: (1) TOOL HINTS — e.g. Move -> "drag a layer to
//        reposition; handles to scale/rotate"; Pen -> "tap to paint, two fingers
//        to pan"; (2) LIVE STATUS/PROMPTS — "Tap a layer to select", "Generating…",
//        "Background filled", action confirmations. One consistent place instead
//        of scattered alerts. BUILDS ON the ActiveToolLabel already shipped (that
//        strip is the seed). Impl: give each Tool a one-line `hint`; show the
//        active tool's hint + let the app push status text to the same bar.
//
//  TOOL VOCABULARY / CANDIDATE TOOLBOX SET (Michael brainstorm 2026-06-11):
//    The full set of tools the toolbox should hold. Captured so none is lost;
//    the EXACT arrangement (which are top-level toolbox icons vs sub-tools that
//    live in another tool's inspector) is a BUILD-TIME detail settled per tool,
//    NOT pre-cut here. The scrollable strip (above) handles the length.
//      • MOVE / TRANSFORM — ONE tool (Michael 2026-06-11, chose combined not
//        split). TRANSFORM is the umbrella: MOVE (reposition) · SCALE · ROTATE ·
//        SKEW (slant/shear) · DISTORT (free corner drag) · FLIP. The inspector
//        offers a MODE TOGGLE between the two behaviours Michael recalls as the
//        ARROW and the FINGER/HAND:
//          - ARROW (pointer) = select + grab the HANDLES to scale/rotate/skew/
//            transform.
//          - FINGER / HAND = grab the object's BODY and MOVE the whole thing.
//        Both are MODES inside the one Move/Transform inspector — NOT two toolbox
//        tools. Acts on the active layer (per-element later). NOTE: Move can also
//        reposition the SELECTION outline itself (the marching ants), not just
//        content — that rides with the selection subsystem.
//      • PAINT BUCKET — fill a layer with a solid color (fills backgrounds).
//      • PEN — PIXEL editing (the raster painter; "pixel" not "vector"). See the
//        PAINT BUCKET + PEN section below.
//      • ERASER — erase pixels (naturally a PIXEL sub-tool of the pen).
//      • EYEDROPPER — sample a color off the canvas to paint with (lean: GLOBAL,
//        usable with any tool; already noted under the pixel tools).
//      • SHAPE — line / rectangle / oval / polygon, stroke + fill. ABSORBS the
//        "line tool" (a line is just the simplest shape).
//      • PATH (a.k.a. "Vector Pen") — a vector path of ANCHOR POINTS. PRIMARY
//        MODE = ANCHOR-TO-ANCHOR STRAIGHT SEGMENTS (Michael 2026-06-11: he never
//        uses Bezier — he zooms in until the image is PIXELATED, blurs his eyes
//        to read the average color variance at the edge, and drops straight-line
//        points around it; many short segments approximate any curve). BEZIER
//        curve handles = OPTIONAL LATER enhancement, NOT needed for his workflow.
//        NAMING: this is the Photoshop/Illustrator "Pen"; we keep "PEN" for
//        PIXELS and call this "PATH" so the two never blur. THREE JOBS:
//          (a) DRAW a crisp, infinitely-scalable vector SHAPE (fill/stroke).
//          (b) MAKE A SELECTION — Michael's primary use (2026-06-11). His real
//              workflow: zoom in to pixel level -> drop anchor points to trace an
//              object -> convert the PATH to a SELECTION ("marching ants") ->
//              INVERT the selection (now the background is selected) -> DELETE ->
//              the background pixels clear to TRANSPARENT, revealing the layer
//              beneath. A clean cutout. Fits our model BETTER than Photoshop:
//              content layers are already transparent, so the deleted area shows
//              straight through (no white backing to fight).
//          (c) STROKE PATH (Michael 2026-06-11) — ink ALONG the path with the
//              active drawing tool (pen/brush/pencil), rasterizing the stroke
//              onto the current layer. The TRACING move: put a transparent layer
//              on top (clear "onion paper" — you see the layer beneath through
//              it), trace its shape with a path, then Stroke Path to draw that
//              outline onto the clear top layer -> the underlying image is now
//              traced onto its own independent transparent layer.
//        IMPLICATION — this needs a SELECTION SUBSYSTEM, not just the path tool:
//          a SELECTION (mask region) that ops respect · path -> selection ·
//          INVERT (later add/subtract) · DELETE-WITHIN-SELECTION (clear to alpha).
//          Path is ONE source of a selection (magic-wand / rectangle etc. later).
//          Marching ants = animated dashed stroke (Core Animation dash phase).
//        Effort: the path tool ITSELF is SIMPLER than first framed — straight
//        anchor-to-anchor segments need NO Bezier handle UI (just tap-to-drop
//        points + close the path). The weight is the SELECTION SUBSYSTEM it
//        feeds. Apple frameworks only (CGPath + CGImage masking; Metal optional).
//        Still a LATER increment (toolbox slot 7 + needs selection), but lighter
//        than a full Bezier editor.
//      • MAGIC WAND / MAGIC SELECTION — tap to select a contiguous color region.
//        A SECONDARY selection source: Michael used it briefly but it "didn't
//        select what I wanted all the time," so the PATH tool is the PRIMARY /
//        workhorse selection method. BUT it's RELIABLE on CLEAN UNIFORM regions
//        (a transparent background, a solid fill) and weak only on noisy image
//        content — see "REGENERATE A SELECTION FROM A LAYER'S ALPHA" below.
//      • TEXT — TYPE characters/words in a font (single-letter-as-icon primary).
//      • GLYPH — browse a font's FULL repertoire (font-book: dingbats, ornaments,
//        non-typeable characters) and place one. WHY IT'S SEPARATE FROM TEXT
//        (Michael 2026-06-11): fonts hold glyphs you can't meaningfully type —
//        e.g. WINGDINGS / dingbat fonts are entirely symbol-glyphs — so you must
//        browse the repertoire visually, not type. This PROMOTES the earlier
//        "font-book glyph picker" (which had been nested inside the Text tool)
//        to its OWN tool. So: TEXT = type · GLYPH = browse-and-pick · SYMBOL =
//        SF Symbols — three distinct "place a pre-made mark" tools.
//      • SYMBOL — pick an SF Symbol from Apple's library.
//      • IMAGE — import artwork: File / Photo / paste / drag / AI (ImageCreator).
//      • IMAGE PLAYGROUND (CANDIDATE, Michael 2026-06-11) — promote AI from just
//        an Image-import source to its OWN tool and/or a LAYER FILTER. Two uses:
//          (tool)   text/concept -> generate AI art straight onto a layer.
//          (filter) feed an EXISTING layer's content in as the concept ->
//                   ImageCreator RESTYLES it (ImagePlaygroundConcept accepts an
//                   image/drawing input, not just text). "Run a layer through AI."
//        Rides the existing AI gating (Apple-Intelligence HW + iOS 18.4 / macOS
//        15.4); graceful-absent on older devices. GLYPH VERIFIED IN SDK 2026-06-11
//        via NSImage(systemSymbolName:): `apple.image.playground` and `.fill`
//        EXIST (alternates: wand.and.sparkles / wand.and.stars). NOT committed —
//        candidate; one tool at a time, this is a later add.
//        GLYPH-AS-STATE-LIGHT (Michael 2026-06-11): use the OUTLINE/FILL pair as a
//        status indicator on the toolbox icon — IDLE = outline `…playground`;
//        SELECTED = the usual accent highlight (like every tool); WORKING = the
//        `.fill` variant + a color (a "lightbulb on"). Especially valuable because
//        generation is ASYNC (a few seconds) -> the lit glyph IS the "working,
//        hang on" feedback (no separate spinner). SwiftUI: `.symbolEffect(.pulse)`
//        + the .fill variant + a tint while generating. Options still live in the
//        TOOL INSPECTOR; the toolbox glyph reflects state.
//        INSPECTOR LAYOUT (Michael 2026-06-11): the tool inspector DIFFERENTIATES
//        the two modes, each with its OWN TEXT INPUT, distinguished by TARGET:
//          - IMAGE MAKER box  -> prompt -> generate + drop the product image on a
//            NEW layer (text-only concept).
//          - IMAGE FILTER box -> describe the change -> modify the ACTIVE layer:
//            feed that layer's CURRENT content + the text into ImageCreator so the
//            AI restyles what's already there (image + text concept).
//        Same framework, both concept inputs; only the OUTPUT TARGET differs
//        (new layer vs active layer).
//      • ZOOM (magnifying glass) — zoom the canvas for precise editing, and PAN
//        FOLDS IN HERE (Michael 2026-06-11): pan = scroll the VIEW when zoomed in
//        (two-finger drag / Photoshop Hand-tool style) = NAVIGATION; the content
//        does NOT move (distinct from MOVE, which relocates content). Zoom + pan
//        are the get-around pair (zoom to pixel level, pan to drop path anchors).
//        A NAVIGATION tool: does NOT log to history (consistent with pulling the
//        magnifying glass out of the history parents 2026-06-10).
//        GESTURE MODEL = PROCREATE-STYLE, ALWAYS-ON (Michael 2026-06-11, locked):
//        native iOS gestures, available REGARDLESS of the active tool — you do
//        NOT switch to a zoom tool to navigate. 1 FINGER = the active tool · 2
//        FINGERS DRAG = pan · PINCH = zoom · (optional double-tap = fit / 100%).
//        Impl: wrap the canvas in a scroll view (UIScrollView via a representable;
//        its pan minimumNumberOfTouches = 2 so single-finger passes through to the
//        tool) -> free native pinch-zoom + two-finger pan. This is INFRASTRUCTURE
//        that benefits every tool (you'll want to draw zoomed-in early, e.g. path-
//        tracing), so it may be worth building BEFORE toolbox slot 12, not after.
//        The ZOOM TOOL icon's residual role: near-redundant on iPhone/iPad (just
//        pinch) -> a convenience (tap-to-zoom + Fit/100%/Fit-Selection buttons in
//        its inspector); on MAC it earns its keep (no pinch -> click/scroll zoom).
//
//  WORKFLOW — SELECTION -> COPY/PASTE/DUPLICATE -> ARRANGE (Michael 2026-06-11):
//    Validates the layers + selection + move + paste pieces working together.
//    His real Photoshop pattern, e.g. building a constellation of stars:
//      1. PATH-tool around the star on an image layer -> make a SELECTION.
//      2. Select that image layer; CMD+C copies just the SELECTED REGION (the
//         star), NOT the whole layer.
//      3. CMD+V pastes it onto a NEW layer AUTOMATICALLY (our paste->new-layer
//         rule). Repeat to drop MANY stars, each as its OWN layer.
//      4. MOVE/TRANSFORM tool: move each star, RESIZE it per layer, and BRING
//         FORWARD / SEND BACK = z-order = the layer-list DRAG-REORDER (already
//         built). Arrange them into a constellation.
//    Already decided/built: paste->new layer · per-layer move/scale · reorder.
//    NEW capability it needs: COPY A SELECTION's pixels off a layer (not the
//    whole layer) — part of the selection subsystem (see PATH). Also note paste
//    has TWO sources: EXTERNAL clipboard image (File/Photo/web) AND INTERNAL
//    copied selection/layer — both Cmd+V, both follow the selection rule.
//
//  KEYSTONE — PATHS/SELECTIONS ARE LAYER-INDEPENDENT (Michael 2026-06-11):
//    A path (and the selection made from it) is NOT owned by the layer it was
//    drawn on — it lives at the DOCUMENT/CANVAS level and floats free of layers
//    (Photoshop "Paths" panel model: drawn once, persists, REUSABLE). COPY acts
//    on the ACTIVE layer THROUGH the current selection — so the SHAPE stays
//    fixed while WHICH LAYER IS ACTIVE decides what gets harvested. => a path is
//    a reusable COOKIE-CUTTER: draw a flower path once, stamp it on a texture
//    layer (Cmd+C/V) for a textured flower, re-activate the SAME path on a
//    gradient layer for a gradient flower, etc. One shape, any layer's content.
//    Impl: store paths/selections on the IconDocument (not on a layer); copy =
//    clip the active layer's CGImage to the selection CGPath -> new layer.
//
//  REGENERATE A SELECTION FROM A LAYER'S ALPHA (Michael 2026-06-11):
//    You never truly lose a cookie-cutter while a layer still HAS that shape.
//    Even after the original path is gone, take a shaped layer (the flower on a
//    clear background) -> MAGIC WAND the empty TRANSPARENT background (reliable
//    here — uniform region) -> INVERT -> the flower shape is selected again, an
//    exact fresh cookie-cutter. The principle: a LAYER'S OWN ALPHA IS A
//    SELECTION SOURCE. One-tap shortcut worth adding = "load layer transparency
//    as selection" (Photoshop Cmd-click the layer thumbnail) = select that
//    layer's opaque pixels directly, no wand+invert dance.
//
//  DECIDED 2026-06-10 — TOOLS: PAINT BUCKET + PEN (Michael):
//
//    PAINT BUCKET TOOL — fills a layer with a solid color. This is how the
//      BACKGROUND layers get filled (white for Light, black/dark for Dark, etc).
//      Its COLOR PICKER lives in the TOOL INSPECTOR (when paint bucket is the
//      active tool). Select bucket -> pick color in inspector -> fill the layer.
//      TWO FILL MODES — what STOPS the flood (Michael 2026-06-11, confirmed):
//        1. SELECTION ACTIVE -> the SELECTION EDGE is the wall. Tap whichever
//           side you want; it floods that region edge-to-edge, OVERWRITING any
//           existing colors (the boundary stops it, not color-matching). Tap
//           inside = fill inside, tap outside = fill outside. Flower cookie-
//           cutter example: red + tap inside -> red flower; black + tap outside
//           -> black bg -> one layer = a red flower on a black background.
//        2. NO SELECTION -> the COLOR EDGES are the walls. Tap a region and it
//           floods the CONTIGUOUS same-color area from the tap point until it
//           hits a different color (with a TOLERANCE). Different-colored pixels
//           act as DAMS; IF THERE ARE NO PIXELS TO DAM IT, THE FLOOD CONTINUES
//           across the whole layer (Michael 2026-06-11). So: uniform/blank layer
//           = whole layer fills; flower-on-clear = tap the clear area fills
//           around the flower (the flower edge dams it), tap the flower fills it.
//           OOZE ON REPEATED TAP (Michael 2026-06-11): each tap fills within the
//           TOLERANCE of the tapped pixel. On SOFT/gradient/anti-aliased edges,
//           the first tap fills to where the gradient leaves tolerance; those
//           edge pixels are now the fill color, so the NEXT tap finds the next
//           ring within tolerance and CREEPS one band further. Keep tapping and
//           it OOZES outward ring by ring until the whole layer is one color. A
//           HARD edge dams it cold. This falls out FREE of tolerance flood-fill
//           (re-sample current pixels each tap); the TOLERANCE slider tunes the
//           creep (low = tiny per tap, high = big jumps / one-tap fill). KEEP IT.
//      PER LAYER TYPE: a BACKGROUND layer is uniform (no internal edges) so the
//        bucket fills the whole layer = just SET ITS FILL (no raster needed). A
//        CONTENT layer's flood-fill is a real RASTER op (pixel buffer + tolerance)
//        -> rides with the pixel tooling.
//      STAGING: v1 bucket (BUILD FIRST) = whole-layer fill on a BACKGROUND (set
//        its fill) — Light/Dark backgrounds, makes the canvas change today. v2 =
//        mode-2 raster flood-fill (content layers) + mode-1 selection-bounded
//        fills (needs the SELECTION SUBSYSTEM, see PATH).
//      PREREQUISITE for v1: an ACTIVE/SELECTED layer must exist (we removed layer
//        selection when the list became always-reorderable) -> tap a row = active
//        layer, distinct from the drag handle. APPLY = tap the canvas to pour
//        (not auto-fill on colour change). History logging deferred (no engine yet).
//      PATTERN FILL — PARKED / UNCERTAIN (Michael 2026-06-11): Photoshop's bucket
//        could fill with a tiled PATTERN instead of a solid color. Michael has
//        never used it himself ("i dont know"); recalls a friend tiling a tiny
//        (~4-6px) line texture to fake a CRT SCANLINE / line-sweep effect. NOT
//        committed — parked as a candidate. If wanted later it's a clean add
//        (bucket source = Color | Pattern). NOTE: that CRT-scanline look might be
//        cleaner as a GENERATIVE EFFECT (procedural scanlines w/ spacing/thickness
//        sliders in the Effects inspector — scales with the icon) than a hand-made
//        tiled pattern. Decide later.
//
//    PEN TOOL = THE PIXEL-EDITING TOOL (this is how pixels are drawn; "pixel
//      tools" above = the pen and its friends). When the PEN is active:
//      • Its TOOL INSPECTOR shows the ICON PREVIEW at SCREEN RESOLUTION with a
//        SCALED GRID overlaying it, updating in REAL TIME as you draw. (So the
//        live production thumbnail from R2 lives IN the pen's inspector and
//        carries a grid overlay.)
//      • On the MAIN CANVAS you ZOOM IN and PAN; the pixels you draw appear on
//        the canvas AND generate in real time on the inspector preview.
//      • The CANVAS has a GRID VIEW that SCALES WITH THE CANVAS (zoom in -> grid
//        cells grow with it; zoom out -> they shrink). Grid is drawn on the
//        canvas, scaling — NOT nested fixed guide-lines.
//      • ✨ CHECKERBOARD + GRID (Michael 2026-06-10, "nifty easter egg"; refined):
//        - The CHECKERBOARD is the transparency background — shown wherever the
//          layers are transparent (the blank state). Its box size tracks the
//          pixel density so the checker cells align with the pixel cells.
//        - The PIXEL GRID LINES are a SEPARATE overlay drawn OVER the
//          checkerboard, and they appear ONLY WHEN THE PIXEL PEN TOOL IS
//          SELECTED for use (tool-contextual — gone when the pen isn't active).
//          Grid lines are at the current pen density (128/256/512/1024).
//        So: checkerboard = always-on transparency indicator; grid lines = pen-
//        tool-active overlay marking the cells to paint. (Shell stub currently
//        uses a fixed checker size + no grid; wire both to pen density + zoom
//        when the pixel pen tool is built.)
//      • PEN SIZE determines the PIXEL DIVISIONS: 128 / 256 / 512 / 1024. The
//        same canvas is divided into more or fewer cells -> MORE divisions =
//        SMALLER cells. So (confirmed Michael 2026-06-10): a 128 grid = fewer,
//        BIGGER squares = a 128 pen lays down a LARGER square; a 1024 grid =
//        many, TINY squares = a 1024 pen lays down a small square. Pen size IS
//        the density control, inverse to cell size.
//      • MIX DENSITIES IN ONE LAYER = CONFIRMED (Michael 2026-06-10, user-facing
//        behavior): the user can use multiple pixel densities / block sizes on
//        the SAME pixel layer (switch pen size mid-drawing — big 128 blocks AND
//        fine 1024 detail coexist).
//      • IMPLEMENTATION DETAIL (Claude's call at build time — NOT a user-facing
//        concept; Michael rightly noted "storage" isn't a design factor): keep
//        the pixel layer on ONE fine 1024 master grid internally and treat PEN
//        SIZE as STAMP SIZE (a 128 pen stamps an 8x8 block of the 1024 master, a
//        1024 pen stamps one cell). That's just how the code makes the mixing
//        "just work" — "draw small, render master big." Nothing the user sees or
//        decides.
//
//    This RESOLVES the earlier grid question (R1/R3): density is SELECTABLE via
//    PEN SIZE, drawn as a canvas-scaling grid (not nested guide-lines).
//
//  DECIDED 2026-06-10 — HISTORY (per-stroke lives here; SAME engine as
//  Shelf-Ready's IMAGE-HISTORY, designed with Michael 2026-06-09). Source of
//  truth for the full model: Shelf-Ready_DeveloperNotes.swift, "ICON EDITOR —
//  IMAGE HISTORY, UNDO & LAYER INTERACTIONS". Image Producer reuses it (shared
//  source engine, Q1). Michael 2026-06-10: "the per-stroke is in a reveal >
//  Pixels > where each pixel is a stroke but nested within the tool-history
//  parent. paint bucket > Pen > ... kept unless purged." (Michael noted the
//  "magnifying glass" he mentioned was off-the-cuff — NOT a history parent and
//  not a logged tool; zoom is a plain canvas behavior, not history.)
//    • UNDO IS NOT A SEPARATE FEATURE — no Cmd+Z, no undo/redo buttons. Undo is
//      a BYPRODUCT of the history list (a panel behind the layer list).
//      ⚠️ WHY (Michael 2026-06-10): the Cmd+Z UNDO IS WHAT KEPT CRASHING
//      SHELF-READY yesterday. The app-wide SwiftData UndoManager snapshotted
//      the WHOLE store on every change and blew up on deletes. It was REMOVED
//      2026-06-09. => HARD RULE for Image Producer's shared engine: DO NOT wire
//      an app-wide SwiftData UndoManager (or any whole-store snapshot undo).
//      The custom linear tool-history below IS the undo, and it sidesteps that
//      entire crash class. (cf. Chat-History 2026-06-09 delete-crash fix.)
//    • GROUPED BY TOOL, each a REVEAL CARAT ">": paint bucket, Pen (its group =
//      "Pixels"), and the other EDITING tools (eraser, eyedropper, shapes...).
//      Only DESTRUCTIVE/edit tools are history parents — NOT zoom/pan. Expand a
//      tool's ">" to see its individual actions nested under it — under Pen/
//      "Pixels", EACH PIXEL/STROKE is one nested entry (keeps the list tidy vs
//      one row per dot).
//      => THIS is where per-stroke granularity lives: every pen stroke (at
//         whatever pen size 128..1024) is its own nested, step-back-able entry,
//         so mixing block sizes on one layer is naturally recorded + reversible.
//    • LINEAR step-back: PICK any entry (a tool group OR a nested stroke) ->
//      EVERYTHING FORWARD OF IT IS DROPPED, resume from there. NO surgical
//      mid-delete (can't pull one stroke from the middle and keep later ones) —
//      rejected for the dependent-edit problem. Picking an entry = the step-back.
//    • PERSISTENT from icon creation, across close/reopen; never auto-resets.
//    • PURGE HISTORY = the ONLY thing that clears it; KEEPS the current image,
//      drops only the trail. Tuck behind a menu + confirm, not a prominent
//      button (icon edits are tiny; storage is a non-issue).
//    • Zoom/pan is NOT history (Michael: the "magnifying glass" was off-the-cuff
//      — not a tool he's committing to, not a history parent). History logs only
//      destructive edits.
//
//      VERIFY ON X27 BETA: PhotosPicker + ImageCreator API specifics against
//      the actual Xcode 27 SDK before coding.
//
//      PASTE / CLIPBOARD WORKFLOW (Michael, 2026-06-10) — the SELECTION-DRIVEN
//      rule that resolves "insert vs new layer":
//        • Cmd+V (paste an image onto the canvas):
//            - NO layer selected  -> paste creates a NEW layer (auto-named).
//            - A layer IS selected -> paste INTO that layer, COMPOSITED with
//              whatever image content is already in it.
//        • IMPLICATION (model): an IMAGE layer is a RASTER sub-canvas that can
//          hold MULTIPLE pasted/imported images composited together — NOT
//          strictly one-image-per-layer. (Michael: "pastes in with any other
//          image in the layer.")
//        • CONFIRMED (Michael 2026-06-10): the SAME selection rule governs the
//          FROM FILE / FROM PHOTO import buttons (and drag-and-drop) too —
//          NO layer selected -> NEW layer; a layer selected -> paste/import INTO
//          that selected layer, alongside whatever other elements it already
//          holds. So paste, import, and drag all share one rule; selection
//          state is the decider for ALL image ingest. (Reaffirms: a layer is a
//          raster sub-canvas that can hold MULTIPLE composited elements.)
//
//      CLIPBOARD-AWARE NAMING (Michael likes Xcode's pattern: it pre-names a
//      new Swift file from the TEXT on the clipboard). Apply the same spirit:
//      when a paste creates a NEW layer, name it from whatever the PASTEBOARD
//      provides — if a filename rode along (e.g. a file copied in Finder/Files,
//      NSPasteboard/ UIPasteboard carries the name), use it; otherwise fall
//      back to a generated name. (A raw photo/web image often carries no name ->
//      fallback, same asymmetry as the Photos import above.)
//        Tech: macOS NSPasteboard, iOS/iPadOS UIPasteboard; read image data
//        (public.png / public.tiff / NSImage|UIImage) + any string/filename.
//        VERIFY ON X27 BETA.
//
//      EMPIRICAL FINDINGS — IMAGE METADATA (tested live 2026-06-10):
//        • WEB image (real Amazon product image, fetched + inspected via sips):
//          - URL ended ".png" but the BYTES WERE JPEG. => NEVER trust the file
//            extension; sniff the real format from the data in the import/paste
//            pipeline. (Correctness rule.)
//          - Server-transformed derivative: delivered 679x690 though the URL
//            referenced a 2140x2000 source (Amazon resized on the fly).
//          - NO useful metadata: just dimensions + 72dpi + sRGB profile, no
//            alpha. NO EXIF / title / camera / date / GPS / IPTC (stripped).
//          => Web/Safari images give essentially NOTHING to auto-name from ->
//             generic fallback name.
//        • PHOTOS-app DRAG-AND-DROP (TESTED LIVE 2026-06-10 — dragged the Xcode
//          icon out of Photos; NOTE: this was DRAG-AND-DROP, not Cmd+C copy —
//          the clipboard-copy path is STILL UNTESTED and may differ):
//          - Photos exports a THROWAWAY TEMP FILE named with a raw UUID:
//            .../com.apple.Photos/Data/tmp/TemporaryItems/PasteboardItemExports/
//            <UUID>.jpeg  => NO usable name at all (not even IMG_1234) ->
//            generic fallback name, confirmed.
//          - ⚠️ ALPHA FLATTENED: Photos exported a natively-transparent PNG as
//            JPEG with hasAlpha:no. A Photos *paste* can DESTROY transparency.
//            => for an ICON app (transparency is the whole point) PREFER the
//            "From Photo Album" PhotosPicker import (loadTransferable original
//            data) OVER clipboard paste when alpha must survive.
//          - EXIF: minimal here (orientation + resolution) because the icon is
//            a saved graphic, not a camera capture. A real CAMERA photo would
//            carry date/camera/often-GPS in the same EXIF block.
//          - 512x512, sRGB, 72dpi.
//          - TAKEAWAY: DRAG-AND-DROP is itself a 4th import vector worth
//            supporting (alongside paste, File import, Photo picker, AI gen) —
//            same selection-driven rule (drop onto empty canvas = new layer;
//            drop onto a selected layer = into it). But the alpha-flatten +
//            UUID-name caveats apply to the Photos drag path too.
//        • PHOTOS-app Cmd+C COPY (TESTED LIVE 2026-06-10 via NSPasteboard):
//          - The copy is a LAZY, PROVIDER-BACKED PROMISE. Clipboard holds ONE
//            concrete item: com.apple.photos.object-reference.asset (346 bytes,
//            an ASSET REFERENCE) + ADVERTISED promised types public.png /
//            public.tiff / file-url whose bytes materialize ONLY when a real
//            app pulls them via a normal paste. A lightweight tool process
//            CANNOT force fulfillment (raw data(forType:) -> nil; NSImage
//            readObjects -> nil; AppleScript «PNGf» coercion -> error -25133).
//            A real app DOES fulfill it — the pixels just aren't sitting on the
//            clipboard in readable form.
//          - COPY advertises public.png (ALPHA-CAPABLE) -> copy likely
//            PRESERVES TRANSPARENCY, unlike the drag path's eager flattened
//            JPEG. (Not provable from CLI; the advertised PNG type is the
//            evidence.)
//          - The asset-reference is the KEY to metadata: resolve it via
//            PhotoKit (PHAsset) to get the ORIGINAL asset (true format, alpha,
//            full res) AND real metadata — creation date, GPS, camera, and the
//            user's Title/Caption/Keywords. Needs photo-library authorization.
//
//        FIDELITY LADDER for pulling an image OUT of Photos (best -> worst):
//          1. PhotoKit PHAsset resolution  -> original bytes + full metadata.
//          2. PhotosPicker import (loadTransferable) -> original data, alpha-safe.
//          3. Cmd+C COPY -> lazy PNG promise, alpha-capable, no loose metadata.
//          4. DRAG-AND-DROP -> eager flattened JPEG, ALPHA LOST, UUID name.
//        DESIGN: prefer 1/2 for real imports; treat paste/drag as convenience
//        paths and ALWAYS sniff format + alpha after ingest.
//        ANSWER to "does a Photos copy have a title/metadata?": not on the
//        clipboard itself (just an asset reference + promised pixels), but YES
//        reachable via PhotoKit from that reference.
//        NOTE (privacy, ties to feedback_photo_location_privacy): imported
//        photos may carry GPS in EXIF. Icon art has no location relevance ->
//        do NOT propagate/persist EXIF GPS; read only what we need (pixels),
//        and never write location back. Flag for the import pipeline.
//    • TECH TO WIRE (not now — flag): photo-library import needs an Info.plist
//      NSPhotoLibraryUsageDescription string; file import is entitlement-light
//      (document picker / security-scoped bookmark). No EXIF writes; icon art
//      has no location relevance (cf. feedback_photo_location_privacy).
//
//  DIVERGENCE FROM SHELF-READY — PIXEL LAYER EDITS IN-PLACE, NOT IN A SEPARATE
//  EDITOR (Michael, 2026-06-10):
//    Michael KEEPS the pixel-art layer — what he dislikes is HOW Shelf-Ready's
//    pixel layer is set up: it opens in a SEPARATE editor surface. For Icon
//    Producer he wants the pixel grid edited IN CONTEXT, ON THE MAIN CANVAS,
//    inside the layer itself — never popped out.
//
//    KEY BEHAVIOR — ONION-SKINNING ("onionpapers"): while editing the pixel
//    layer, the layers BELOW it stay VISIBLE underneath the grid (showing
//    through, like onion-skin / tracing paper), so the pixel art can be drawn
//    in alignment with whatever sits beneath it. You draw the pixel layer
//    registered to the real composite, not blind in an isolated window.
//      • Edit happens on the same square canvas, in z-order position.
//      • Layers below = visible reference under the active pixel grid.
//      • RESOLVED (Michael 2026-06-10): the onion-skin overlay itself is
//        TRANSPARENT and NOT visibly rendered — the ONLY thing drawn on the
//        editing overlay is the GRID LINES. Through that transparency you see
//        the real layer content below (and the pixels you place). There is NO
//        dimmed render of other layers, NO special above/below dimming — it's
//        just transparent + grid lines. (Michael: "the onion skin is
//        transparent and not visible, all you would see are the grid lines.")
//
//  DIVERGENCE FROM SHELF-READY — TRANSPARENT LAYERS + BACKGROUND (Michael,
//  2026-06-10):
//    Michael's clarification (2026-06-10), refining two earlier complaints:
//      (1) CONTENT LAYERS are opaque in Shelf-Ready, so you can't see through
//          a layer to what's below it. WRONG — they should be transparent.
//      (2) He DID want a background layer he can FILL WITH A SOLID COLOR, and
//          he DID want THREE default layers on a new icon. Shelf-Ready did
//          "something weird, similar but didn't work like I wanted": it added
//          an extra Light-mode / Dark-mode background. He LIKES the light/dark
//          background idea — but the implementation "doesn't work intuitively."
//
//    TWO SEPARATE RULES (do not conflate them again):
//
//    A) CONTENT LAYERS = TRANSPARENT. Every non-background layer (symbol,
//       image, pixel) carries real alpha — clear where unpainted — so you can
//       ALWAYS see through it to the layers below. Same onion-skin philosophy
//       as the pixel layer, extended to the whole content stack. No content
//       layer has an opaque fill that blocks what's beneath it.
//
//    B) BACKGROUND = TWO SEPARATE LAYERS (RESOLVED Michael 2026-06-10 — my
//       earlier "merge into one" lean was WRONG):
//       Keep TWO distinct background layers — Light Background + Dark Background
//       — as real entries in the layer list, each a solid-color fill (opaque;
//       that's their job as the floor).
//       WHAT WAS ACTUALLY UNINTUITIVE in Shelf-Ready was NOT the two layers —
//       it was the separate Light/Dark TOGGLE BUTTONS (the "Light | Dark"
//       control under the canvas). Michael does NOT want mode buttons.
//       THE FIX: control light vs dark with the STANDARD LAYER EYEBALL. To see
//       the light version, click the Dark Background's eye to hide it (and vice
//       versa). The eyeball you already use on every layer IS the light/dark
//       control — no special buttons, no mode swap UI. Consistent + intuitive.
//       (Michael: "I want two layers because I can hide the layer by clicking
//       the eyeball.")
//       FILL = THE OPACITY GUARANTEE (Michael 2026-06-10): each background layer
//       is filled with a solid color — Light Background typically WHITE, Dark
//       Background BLACK or any dark color the user picks (color is user-
//       chosen, not fixed). PURPOSE: the opaque fill "gets rid of clear
//       backgrounds" — it's what ensures the SHIPPED icon has a solid backing
//       instead of transparency (app icons must not be clear). So the
//       transparent CONTENT layers ride on top, and the opaque background is
//       the floor that removes any clear background from the final icon. (This
//       resolves the "HARD CONSTRAINT" opacity question below by DESIGN: the
//       user-filled background is the opacity source.)
//
//    DEFAULT NEW-ICON STACK = THREE LAYERS (RESOLVED):
//       1. Light Background  (solid fill, opaque)
//       2. Dark Background   (solid fill, opaque)
//       3. Icon              (the "proto icon" content layer, transparent)
//       ...and the user adds more layers as needed (infinite).
//
//    EXPORT-ROLE FLAG (don't assume — confirm later): the two backgrounds carry
//    an APPEARANCE ROLE by identity (Light vs Dark) used to render the icon's
//    light/dark appearance variants (.icon / Icon Composer). The eyeball is an
//    EDITING-PREVIEW convenience; export should map by the layer's role, not by
//    whatever eye state happens to be set at export time. >>> confirm the export
//    mapping when we get to the export pipeline. <<<
//
//    THREE OUTPUT PATHS (Michael 2026-06-10):
//
//    1. SAVE — the ICON PACKAGE (working file) with the HISTORY EMBEDDED. Full
//       layers + history, nondestructive, for future editing. The editable doc.
//
//    2. EXPORT AS ICON SET (in-app action) — the real production deliverable.
//       RESOLVED (Michael 2026-06-10): NOT the .icon / Icon Composer format.
//       Export a SET OF IMAGE FILES that the user DRAGS-AND-DROPS into Xcode's
//       AppIcon asset catalog (= Shelf-Ready's "Generate Icon Set" approach),
//       filed/named by appearance (light / dark / tinted).
//       ⚠️ FILE FORMAT = PNG, NOT JPG (Claude flag, quality): icons must be
//       LOSSLESS — JPG adds compression artifacts (fuzzy edges, banding) and
//       can't carry alpha. Apple's icons are PNG. CONFIRMED PNG (Michael
//       2026-06-10: "png is okay, I pulled jpg out of the air"). Export = PNG.
//       SIZES — VERIFY ON X27 BETA: modern Xcode often needs only a SINGLE 1024
//       per appearance (auto-generates the rest), so a full explicit size set
//       may be more than needed. Decide the exact size list once we see what the
//       Xcode 27 AppIcon asset catalog actually wants; can produce the full
//       classic set if Michael prefers explicit files.
//
//    3. SHARE SHEET (quick share) — DECIDED, simple: exports ONLY a single
//       1024x1024, FLAT, ONE appearance (light OR dark), where the appearance =
//       whichever mode the user has chosen JUST BEFORE invoking the share sheet
//       (i.e. the currently-previewed composite — which background eye is on;
//       ties to the eyeball-controls-light/dark decision). No sizes, no tinted,
//       no set — just one flattened 1024 PNG of the current look. (Michael: "if
//       you share it via the share sheet it is only 1024x1024 and only flat with
//       only one light or dark mode chosen by the user just before share sheet
//       was initiated.")
//
//    HARD CONSTRAINT TO RECONCILE (flag, do not assert): the SHIPPED icon's
//    opacity rules are an Apple fact, and with the layered .icon / Icon
//    Composer + Liquid Glass model in OS 26/27 the old "app icons must be fully
//    opaque" rule may have changed (layered icons carry managed alpha). So:
//    transparent layers are unambiguously right for the EDITING experience;
//    the EXPORT step must still produce whatever the current Icon Composer /
//    App Store rules require. VERIFY ON X27 BETA against Apple's Icon Composer
//    docs before locking the export contract — do NOT assert the opacity rule
//    from memory.
//      MICHAEL'S RECOLLECTION (2026-06-11): "Xcode didn't like clear pixels" —
//      matches the classic rule: iOS app icons must be OPAQUE (no alpha); Xcode/
//      ASC reject a transparent app icon. This is EXACTLY why the Background
//      layers are opaque: editing can be fully transparent (onion-paper, cutouts,
//      a flower on clear), but EXPORT FLATTENS onto the opaque background -> the
//      shipped PNG has ZERO clear pixels. So clear pixels are fine WHILE editing,
//      never in the FINAL icon. Nuances to verify: that's the iOS rule; macOS
//      icons historically ALLOW transparency (free-form); and the layered .icon
//      path manages alpha differently — but we export FLAT PNGs, so the classic
//      opaque rule governs and the opaque background covers it.
//      EXPORT FLATTEN BACKSTOP (Michael 2026-06-11, chose B): at flatten, any
//      pixel STILL transparent (unfilled background, a gap) is written as an
//      OPAQUE pixel so a clear pixel NEVER ships. The backstop FOLLOWS THE
//      APPEARANCE being exported: Light variant -> WHITE, Dark variant -> BLACK
//      (or the Dark Background's chosen color) — so the fill blends into either
//      icon instead of leaving a white speck on the dark one. A safety net on
//      top of the opaque Background layers; the no-clear-pixel guarantee holds
//      regardless of what the user did or didn't fill.
//
//    EVERYTHING ELSE about the pixel tooling carries over from Shelf-Ready's
//    PIXEL-ART EDITOR design (art-cell decoupled from hardware pixel; draw-small
//    / render-master-big nearest-neighbor; pencil/fill/eraser/eyedropper/
//    line/rect/ellipse/swatches; grid toggle, mirror/symmetry; hard pencil +
//    nearest-neighbor = blur-off). The EDITING SURFACE is RESOLVED: IN-PLACE on
//    the icon canvas with a live production thumbnail (see RESOLVED section
//    below) — no popout.
//
//  ============================================================================
//  RESOLVED (2026-06-10) — PIXEL EDITING SURFACE + RESOLUTION + NAVIGATOR
//  DECISION: PATH A. The pixel editor lives ON THE ICON CANVAS (in-place,
//  in z-order, live onion-skin of the real layers) — NOT a popout. A REAL-TIME
//  PRODUCTION-ICON THUMBNAIL shows the finished icon, updating live as pixels
//  are drawn. (Michael: "I want the pixel editor to be on the icon canvas and
//  not a popout editor, but I want a thumbnail of the production icon while the
//  pixels are being added in real time.") Paths B (popout) and C (focused
//  overlay) are REJECTED — editing is directly on the main canvas.
//  R1 (resolution ladder) and R2 (zoom + the now-live thumbnail) still apply.
//  ============================================================================
//
//  NEW REQUIREMENTS Michael added (all apply regardless of which path wins):
//
//  (R1) RESOLUTION LADDER = 128 / 256 / 512 / 1024 (RESOLVED 2026-06-10).
//       Shelf-Ready offered only 64 / 128. Image Producer's grid densities are
//       the four powers Michael named: 128, 256, 512, 1024. (No coarse retro
//       16/32/64 rung — this app's pixel grids run fine-to-full-res.) The
//       "pixel" is a CHOSEN ART-CELL: 128 = chunkier; 1024 = 1 cell = 1 device
//       pixel at the 1024 master = effectively full-res raster paint.
//       GRID OVERLAY: these densities are shown as GRIDS on the canvas
//       ("grids representing the 128/256/512/1024 pixel densities").
//       RESOLVED: density is SELECTABLE (not nested guides), and it's chosen by
//       the PEN SIZE (see "TOOLS: PAINT BUCKET + PEN"). Grid is drawn on the
//       canvas and SCALES with zoom.
//
//  (R2) ZOOM-IN/ZOOM-OUT CANVAS + FIXED-RESOLUTION THUMBNAIL (RESOLVED).
//       Two independent viewports:
//        • THE CANVAS itself ZOOMS IN AND OUT freely, so you can work pixel-by-
//          pixel up close (esp. at 512/1024 where cells are tiny) or pull back
//          to see the whole grid. The pixel-edit surface is an ONION-SKIN
//          TRANSLUCENT overlay — you see THROUGH the active grid to the real
//          layers below while drawing.
//        • THE PREVIEW THUMBNAIL stays at ACTUAL SCREEN RESOLUTION (1:1 device
//          pixels, true final size) and does NOT follow the canvas zoom — it
//          updates LIVE as each pixel is drawn so you always see the real,
//          shipping-size icon take shape while the canvas is zoomed in. It
//          renders the full layer composite, not just the pixel layer.
//       (Michael: "a zoom in / zoom out canvas while the preview thumbnail
//       remains actual screen resolution.")
//
//  (R3) MOOT NOW (popout rejected). Was: a popout would need a flattened
//       composite backdrop. Since editing is in-place on the live canvas, the
//       real layers below ARE the backdrop — no flatten/snapshot needed. Kept
//       here only as the rationale for why in-place won (the Shelf-Ready popout
//       showed a solid BLACK canvas = zero context; in-place fixes that
//       inherently).
//
//  THE TWO OPPOSITE PATHS (this is the fork to resolve):
//
//   PATH A — IN-PLACE / INTEGRATED. Edit the pixel layer directly on the MAIN
//     canvas, in z-order, with LIVE onion-skin of the REAL layers above/below.
//     Zoom the canvas to pixel-edit; the navigator (R2) shows the whole icon.
//     + True WYSIWYG: the backdrop is the actual live composite, never a stale
//       snapshot; layer changes below are reflected instantly.
//     + Matches Michael's stated preference (no popout, see-through context).
//     - Heavier single surface: pixel tools + palette + zoom + the layer list
//       all have to coexist on one view. Most UI complexity of the two.
//
//   PATH B — POPOUT, FIXED. Keep a dedicated pixel-editor surface (focused, its
//     own full tool palette + navigator), but replace the black canvas with a
//     FLATTENED COMPOSITE backdrop of the layers below (R3).
//     + Simplest main canvas; roomy dedicated tooling; clean separation.
//     - The backdrop is a SNAPSHOT, not live — re-flatten if lower layers
//       change; a step removed from true WYSIWYG. The disconnect Michael
//       dislikes is reduced but not gone.
//
//   PATH C — HYBRID (Claude's note, dissolves the dichotomy): a FOCUSED MODE /
//     full-screen overlay that is still driven by the LIVE composite (not a
//     static flatten) — i.e. Path A's truth with Path B's roomy dedicated
//     tooling. The "popout" becomes a zoom/focus state of the real editor, not
//     a separate snapshot world. Worth weighing before committing to A or B.
//
//  WHY THE NAVIGATOR MATTERS TO THE FORK: once a navigator + flattened/live
//  backdrop exists, the ORIGINAL reason in-place felt mandatory (seeing the
//  layers below) is satisfied by BOTH paths. So the decision narrows to:
//  LIVE composite (A/C) vs SNAPSHOT composite (B), and ONE crowded surface (A)
//  vs a roomy dedicated one (B/C). [RESOLVED: Path A — in-place on the canvas.
//  See the RESOLVED header at the top of this section.]
//
//  HOW IMAGE PLAYGROUND FITS THIS EDITOR (the new ingredient vs. Shelf-Ready):
//    An AI-generated image from `ImageCreator` lands as an IMAGE LAYER on this
//    same canvas — i.e. AI is a FEEDER into the layered editor, not a separate
//    output path. You generate a starting image, drop it in as a layer, then
//    refine/compose with the other layers and ship via the flatten-to-icon
//    path. (This is the "AI gives a rough start; the editor does the real
//    work" posture — see Q3, now largely answered by this decision.)
//
//  SHARED-PARADIGM NOTE: the editor is "the same as Shelf-Ready." RESOLVED
//  (see Q1): two INDEPENDENT apps sharing the editor ENGINE at the SOURCE level
//  (own copy in each), NO custom kit/package, Apple frameworks only; engine
//  improvements synced by hand.
//
//  ----------------------------------------------------------------------------
//  OPEN DESIGN QUESTIONS — UNRESOLVED, do NOT assume (Michael decides)
//  ----------------------------------------------------------------------------
//  Q1. RELATIONSHIP TO SHELF-READY — RESOLVED (Michael 2026-06-10):
//      "Separate apps that share an editor engine — two unique apps,
//      independent, with NO KITS other than Apple kits."
//      MEANING (important nuance):
//        • TWO INDEPENDENT SHIPPING APPS. Image Producer and Shelf-Ready are
//          separate products; neither depends on the other.
//        • SHARED ENGINE AT THE SOURCE LEVEL, NOT AS A PACKAGE. The editor
//          "engine" is a clean, self-contained set of Swift source files that
//          BOTH apps include their OWN COPY of. It is NOT a Swift package /
//          framework / custom "kit" that the apps link against.
//        • NO CUSTOM KITS. "No kits other than Apple kits" = only Apple
//          frameworks (SwiftUI, AppKit/UIKit, PhotosUI, ImagePlayground, etc.).
//          Do NOT build an EditorKit/IconEngineKit package, and NO third-party
//          dependencies. (Consistent with Michael's independence philosophy —
//          cf. apps ship decoupled, CryoKit-style "diamond" stays internal.)
//        • TRADE-OFF ACCEPTED: source-copy sharing means engine improvements
//          must be MANUALLY synced into both apps (no single linked source of
//          truth). Michael chose independence over the package's auto-sync.
//      PRACTICE: build the engine ONCE as a tidy, dependency-free Swift source
//      module-by-convention; copy it into each app; keep the two copies in sync
//      by hand. Each app stays a standalone, Apple-frameworks-only product.
//
//      *** UPDATE 2026-06-10 — POSITIONING REVISED (resolves the App-Review 4.3
//      duplicate-functionality risk; see VIABILITY below): SHELF-READY DROPS ITS
//      ICON-EDITING PARTS and becomes the SCREENSHOT / submission-asset PACKAGER;
//      ICON PRODUCER OWNS the icon-creation studio. Shelf-Ready is NOT yet in the
//      App Store, so removing its icon editor costs nothing (no users to
//      migrate). CONSEQUENCE: the "shared engine" is now largely MOOT — if
//      Shelf-Ready has no icon editor, the engine just LIVES IN ICON PRODUCER
//      (no copy, no manual sync). (Only revisit sharing if Shelf-Ready keeps a
//      MINIMAL icon-assembly step.) The two apps are COMPLEMENTARY (create icon
//      in Image Producer; package screenshots in Shelf-Ready) and can ship as an
//      APP BUNDLE. ***
//
//  GIT / GITHUB WORKFLOW: repo = github.com/fluhartyml/Image-Producer (origin
//  wired, gh authed; the legacy Icon-Producer repo is the backup). PUSH ON EACH
//  SUCCESSFUL BUILD
//  (standing rule — BUILD SUCCEEDED = commit + stage + push, don't ask). GitHub
//  is ALSO the MacBook<->minis bridge: write/commit/push on the MacBook (dev),
//  the minis PULL + build/submit on RELEASE Xcode 26. Repos default PUBLIC; no
//  secrets in repo.
//
//  VIABILITY / APP-REVIEW RISK (analyzed w/ Michael 2026-06-10, web-verified):
//    • NAME "Image Producer" (FINAL 2026-06-20): no exact App Store match
//      (confirm in App Store Connect at reservation). Broadened up from the
//      narrow "Icon Producer" per the naming-strategy memory (umbrella noun,
//      room to grow). Generic/descriptive — chosen for clarity over ownability.
//    • vs Apple's ICON COMPOSER: complementary, not competing (Icon Composer
//      ASSEMBLES the layered .icon; Image Producer CREATES artwork -> PNG). Low
//      risk on this axis.
//    • 4.2 minimum functionality: SAFE — deep editor (layers/pixel/effects/
//      fonts) is substantial.
//    • ORIGINALITY: the icon-maker category is CROWDED and AI icon generation is
//      already TABLE STAKES (AppIcon AI etc.). So AI is NOT the differentiator;
//      the EDITOR DEPTH (pixel art, layered compositing, font glyphs, effects
//      like the plasma flame) is. Position as a "design STUDIO, not a one-shot
//      generator."
//    • 4.3 SPAM — was the real risk: Shelf-Ready ALSO had a layered icon editor
//      -> two same-developer apps with duplicate functionality. RESOLVED by the
//      positioning update above (Shelf drops icon editing). No overlap now.
//    • SUBSCRIPTION FRAMING (CORRECTED — Michael 2026-06-10): the paid +
//      recurring "$99/mo subscription" framing is a STANDARD INTERNAL ASSUMPTION
//      (Claude's-eyes-only calibration, feedback_assume_paid_app_premium_pricing)
//      — NOT an open question. The ONGOING VALUE is already settled by Michael's
//      model: his flagship apps are REGULARLY UPDATED so they don't go stale.
//      Regular updates = the recurring justification. Do not re-flag this.
//    • APP BUNDLE caveat — VERIFY: classic App Store Bundles are for
//      ONE-TIME-PURCHASE paid apps; subscription apps bundle differently.
//      Confirm the mechanism with Apple at pricing time. Not now.
//    • NO "LIGHT" vs "DELUXE" SEPARATE APPS (decided Michael 2026-06-11): the
//      idea of a free/Light app + a Deluxe app whose only diff is USER-DEFINED
//      CANVAS SIZE would be a 4.3 DUPLICATE-SPAM risk — two ~95%-identical
//      binaries differing by one feature is exactly the lite/full pattern Apple
//      steers away from (use ONE app + IAP, not duplicate apps). INSTEAD: ONE
//      Image Producer, with user-defined canvas size as the premium feature.
//      PRICING — FREE, NOT PAID (Michael 2026-06-11, OVERRIDES the usual paid/
//      premium internal default for THIS app): Michael does NOT want money here.
//      The premium feature is unlocked by a FREE REGISTRATION that EXPIRES
//      ANNUALLY — to keep it the user RE-REGISTERS once a year, and that renewal
//      screen SHOWCASES Michael's OTHER APPS (portfolio cross-promo = the "value
//      exchange" in place of dollars). NOT a StoreKit subscription (those are
//      paid) — it's a free account/entitlement with a 1-year expiry + a feature
//      flag. Core app works WITHOUT registering (only the extra feature is gated
//      -> 5.1.1-safe). Lapse = premium relocks, rest still works. Apple-OK:
//      promoting your OWN apps (links to their App Store pages) is allowed; the
//      rule only bites on gating CORE function or hosting OTHER devs' apps.
//      OPEN FORK: (A) lightweight DEVICE-LOCAL annual "see our apps to renew"
//      tap — no accounts / no PII -> minimal compliance; or (B) a REAL account
//      (Sign in with Apple) to count/contact users -> adds privacy policy +
//      in-app account deletion (5.1.1(v)). Decide by the goal: portfolio exposure
//      (lean A) vs building a user list (B).
//      SIGN IN WITH APPLE DETAIL (Michael leaning B 2026-06-11 — wants a welcome
//      email): SIWA is a FULLY IN-APP flow (Face/Touch ID) — NO website. Data it
//      returns: a STABLE unique user ID (team-scoped -> count/recognize users);
//      an EMAIL (user picks real OR Hide My Email relay — either is deliverable);
//      and NAME (only if requested, only on FIRST sign-in). ⚠️ EMAIL + NAME come
//      back ONLY on the FIRST sign-in — capture+store them then. WELCOME EMAIL:
//      works to real or relay, BUT to email a Hide-My-Email relay you must first
//      REGISTER YOUR SENDER domain/email with Apple ("Sign in with Apple for
//      Email Communication") or relay mail BOUNCES. COST of B: needs a small
//      BACKEND (server + DB to store registrations) + an EMAIL SERVICE to send
//      (SIWA gives the address, not the sending) + privacy policy + in-app
//      account deletion. A avoids all that but learns nothing about who registered.
//      DECISION + STAGING (Michael 2026-06-11): Sign in with Apple = the GATE TO
//      FULL ACCESS. Built in TWO STAGES:
//        • STAGE 1 — LOCAL (now, no backend): SIWA is an ON-DEVICE flow; on a
//          successful sign-in, store the credential/user-id LOCALLY (Keychain)
//          and unlock the app. No server needed -> we can build the gate today,
//          before any infrastructure exists. "Full access" for now = the whole
//          app (premium tiers not built yet).
//        • STAGE 2 — BACKEND (later): wire the registration to the WordPress DB
//          (record the user, send the welcome email, run the annual renewal +
//          app-catalog cross-promo) once the host exists.
//        ⚠️ ETHICS + 5.1.1 (Michael 2026-06-11) — CORRECTION: do NOT justify the
//        gate with cloud sync. The user ALREADY PAYS APPLE for iCloud, so locking
//        sync behind OUR registration = charging twice for what's already theirs
//        = unethical. So: the local editor core AND any iCloud sync stay FREE/
//        UNGATED (no registration). Registration unlocks only what's GENUINELY
//        OURS to give — the premium user-defined canvas, future server-side
//        features we host, the membership/catalog. This is BOTH ethical AND what
//        5.1.1 wants (don't force login for core function). So "gate to full
//        access" -> "registration unlocks OUR premium layer," not a wall in front
//        of the whole app. (Stage-1 local SIWA still fine to build now.)
//      APP SHELL — SETTINGS + FEEDBACK (Michael 2026-06-11): match his EXISTING
//        app pattern — a Settings/About area with FEEDBACK ("like they have
//        been"); MIRROR a sibling app (Shelf-Ready / CryoTunes) rather than
//        invent a new style; portfolio-link / mailto feedback is fine (see
//        feedback_apps_may_link_to_portfolio_for_feedback). Include the BLANKET
//        privacy.html and the Sign-in-with-Apple registration gate (Stage 1
//        local). FLOW/COMPLIANCE: since SIWA gates FULL access, Feedback / About /
//        Privacy must be reachable FROM THE SIGN-IN SCREEN too (App Review +
//        users need support + privacy without an account).
//      BACKEND OPTIONS for B (Michael 2026-06-11): the registration DB + welcome
//      email needs a DYNAMIC backend.
//        • WORDPRESS / MySQL — leans best: app POSTs the SIWA user-id+email to a
//          WordPress REST endpoint -> stored in its MySQL DB; WordPress also SENDS
//          the welcome email (wp_mail + an SMTP plugin). ONE box = DB + mailer.
//          Secure the endpoint (HTTPS + verify the Apple identity token server-
//          side) and register the WP From-address with Apple's relay service.
//        • Firebase / Supabase — serverless DB+functions, free tiers, if not WP.
//        • CloudKit — native/no-server but weak for a visible user list + email.
//        • ❌ GitHub is NOT a backend — it stores CODE, not a live DB; GitHub Pages
//          is static (no DB writes / no endpoint). The API-commit hack needs an
//          embedded write-token (extractable) + isn't concurrency-safe. RULED OUT.
//          GitHub stays the CODE bridge (MacBook<->minis) only.
//        DOMAIN STATUS (checked 2026-06-11): fluharty.me currently resolves to
//        GITHUB PAGES (A records 185.199.108-111.153, server: GitHub.com) = a
//        STATIC site; NO MX (no email), NOT WordPress (wp-login 404). So the
//        domain as-pointed can't be the backend. TODO Michael: check GoDaddy "My
//        Products" for a Web Hosting / Managed-WordPress / cPanel / VPS plan — if
//        one exists, point a SUBDOMAIN (e.g. api.fluharty.me) at it for the
//        backend; if domain-only, add hosting or use a BaaS.
//        DIRECTION (Michael 2026-06-11): leaning toward BUYING a hosting plan
//        (poss. a 5-yr term) + maybe a CUSTOM DOMAIN. Good call — one Linux/
//        cPanel or Managed-WordPress host + domain covers ALL launch infra at
//        once: registration backend (MySQL + REST), welcome-email sender, the
//        App-Store-REQUIRED privacy-policy + support URLs, and a marketing
//        landing page. Make sure the plan is Linux/WordPress (MySQL+PHP+email),
//        not domain-only/static. Term length = pure cost choice (his lane). All
//        PRE-LAUNCH — does not block building the app's tools.
//        HOMELAB SELF-HOST OPTION (Michael 2026-06-11): he may have a parallel
//        GoDaddy MySQL/Linux plan (confirm in My Products) AND/OR could self-host
//        MySQL on the HOMELAB via the NightGard DDNS. Assessment: self-host is
//        IDEAL FOR DEV/TESTING (free, build the whole flow against his box; API/
//        PHP in front of MySQL — never expose MySQL directly; DDNS hostname +
//        Let's Encrypt TLS for ATS). For PRODUCTION (public users + their emails
//        on home hardware) flag: internet exposure/attack surface, residential
//        uptime + ISP often blocks inbound 80/443 & bans servers, scale limits,
//        PII liability. RECOMMENDATION: homelab for DEV, managed host (the
//        GoDaddy plan or a cheap VPS) for PRODUCTION. Best of both.
//        DOMAIN/HOSTING INVENTORY (checked 2026-06-11): owns fluharty.me (-> GitHub
//        Pages, static) + mybrainconnections in MULTIPLE TLDs (.com -> GoDaddy
//        registrar-forwarding, catch-all 200, no real WP, no MX; .org/.net don't
//        resolve). NONE is a live server. Michael thinks he "probably let the
//        hosting subscriptions EXPIRE" -> assume NO active hosting; just domain
//        names (verify even those haven't lapsed). So production backend = BUY a
//        fresh Linux/WordPress plan when we reach the registration feature
//        (PRE-LAUNCH, long after the app's tools). Homelab-DDNS covers dev. Not
//        urgent — nothing lost; spin up hosting at launch time.
//        WHOIS (2026-06-11): mybrainconnections.COM REGISTERED via GoDaddy thru
//        2034-06-08 (long-term lock — solid asset). .INFO + .APP also show
//        registered but are NOT Michael's (he confirmed he NEVER registered a
//        .app; both are third parties). So the ONLY mybrainconnections name he
//        owns is .COM. .net/.org/.me/.co/.us/.io LAPSED. fluharty.me still active
//        (GitHub Pages, static).
//        UMBRELLA DOMAIN — INTENDED: fluharty.app (Michael 2026-06-11). Verified
//        AVAILABLE (GoDaddy ~$19.99 first yr / ~$27.99 renew; corrected via
//        whois.nic.google after a bad first lookup falsely said "taken"). Matches
//        the fluharty.me brand; .app is HTTPS-only (we want that); same GoDaddy
//        account as the .com. Would host the app-portfolio landing + the free-
//        registration "see our apps" catalog + privacy/support pages + backend.
//        fluharty.com is OWNED BY TUCOWS — it's part of their SURNAME VANITY-EMAIL
//        service (NetIdentity/Mailbank lineage): Tucows holds last-name domains and
//        leases vanity addresses by subscription. MICHAEL SUBSCRIBES -> he has
//        mike@fluharty.com + michael@fluharty.com (personal email). That's why the
//        domain is locked since 1996 and never drops — it's Tucows' product, not
//        for sale. He does NOT control its DNS, so it CAN'T host the app site/
//        backend or be a Sign-in-with-Apple relay sender. Keep the personal
//        addresses; the APP uses fluharty.app (fully owned/controlled).
//        NOT yet purchased — Michael's call.
//        nightgard.app / iconproducer.app also available if a studio/per-app
//        brand is preferred later.
//        fluharty.NET — LIKELY ALREADY OWNED by Michael (WHOIS 2026-06-11: GoDaddy
//        registrar + "Domains By Proxy" = GoDaddy privacy proxy, AZ; created 2017,
//        RENEWED April 2026, on GoDaddy default nameservers/parked). All signs =
//        his (his registrar + privacy + fresh renewal, likely auto-renew). Confirm
//        in GoDaddy My Products. IF his, it's a domain he ALREADY OWNS + FULLY
//        CONTROLS (DNS/MX/zone) — unlike .com (Tucows) — so it could host the app
//        site/email/backend NOW, free, no purchase. Tradeoff: .net is older/generic
//        vs .app's modern app-branding. Could use BOTH (.app public brand, .net
//        infra) or start on .net.
//        BRAND FORK (open, Michael 2026-06-11): umbrella = PERSONAL name
//        (fluharty.app/.net) vs STUDIO brand (NightGard — already his folder/DDNS
//        identity; nightgard.app available) vs a coined name. Undecided.
//
//  DEPLOYMENT TARGET (Michael 2026-06-10): plan = ship targeting iOS 26-or-LOWER
//  first, then a fast iOS-27 upgrade pass right after submitting (fits the
//  regularly-updated-flagship model). Feature floors: SwiftData 17 · SwiftUI
//  shader effects 17 · PhotosPicker 16 · ImageCreator (AI) 18.4 + Apple-
//  Intelligence hardware. => iOS 15 is TOO LOW; iOS 27 is NOT required.
//  LOCKED (Michael 2026-06-10): FLOOR = iOS 17 / macOS 14, AI GATED.
//  - Full editor runs on iOS 17 / macOS 14. AI generation (ImageCreator) is
//    gated to iOS 18.4 / macOS 15.4 + Apple-Intelligence hardware (iPhone 15
//    Pro/16+; Apple-Silicon Mac) via #available + a runtime capability check.
//    Non-AI / older devices install and use the whole app minus the AI button.
//  - Project currently set to iOS 26 (Xcode-26 template leftover, pre-beta) ->
//    lower to iOS 17 / macOS 14 (build setting; Michael or Claude-with-okay).
//  - BUILD/SUBMIT: low floor is NOT a problem for App Store Connect. The BETA
//    XCODE is — ASC rejects binaries built with a BETA Xcode/SDK. The shipping
//    binary MUST be built on a RELEASE Xcode (Mac minis' Xcode 26). KEY INSIGHT:
//    Image Producer uses only APIs through iOS 18.4 / macOS 15.4, ALL of which
//    are in the RELEASE iOS-26 / macOS-26 SDK -> the app can be developed AND
//    shipped ENTIRELY on the minis' Xcode 26; the Xcode 27 BETA is NOT needed
//    for this app (it's for the book + the later iOS-27 upgrade pass). Avoid
//    letting the Xcode 27 beta "upgrade"/save the .xcodeproj (project-format
//    bump can make Xcode 26 grumble). iOS-27 upgrade pass ships later on release
//    Xcode 27.
//
//  Q2. WHAT "PRODUCE" MEANS — LARGELY ANSWERED by the editor decision: the
//      LAYERED EDITOR is the centerpiece; Image Playground is a FEEDER (AI image
//      -> IMAGE layer). Still to pin down: the exact EXPORT target(s) —
//      `AppIcon.appiconset`, the layered `.icon` (Icon Composer), or both — and
//      whether non-AI inputs (SF Symbol / imported art / pixel) are first-class
//      from day one or phased in (Shelf-Ready has symbol+image built,
//      pixel planned).
//
//  Q3. STYLE POSTURE — LARGELY ANSWERED: AI = "rough starting image, the editor
//      does the real refinement," consistent with the layered-editor decision
//      and the stylized-output limit. Remaining nuance: do we still SURFACE the
//      playful Image-Playground styles as an intentional aesthetic option, or
//      treat AI output as raw material only?
//
//  ----------------------------------------------------------------------------
//  PARKED / TO REVISIT
//  ----------------------------------------------------------------------------
//  - Default template carries CloudKit + push entitlements + SwiftData `Item`.
//    None of that is a decision yet — revisit once the concept is set (may not
//    need CloudKit/push at all for a local icon tool).
//  - VERIFY ON X27 BETA: the ImagePlayground API signatures above are from the
//    shipping iOS 18.4 / macOS 15.4 framework. Confirm against the Xcode 27
//    beta before any of it is treated as final (esp. for the book).
//  - Business framing (if it ships): per Michael's app rules — PAID, premium,
//    recurring; English-only / Americas-only. Not decided, just the default.
//

