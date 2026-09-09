## TODO

Format & Standard Compatibility:
[x] Composite Glyphs: The library currently crashes (`CompositeUnsupported`) if `n_contours < 0`. Implementing composite glyph resolution would vastly increase TrueType compatibility, as most fonts use composites for accented characters and structural reuse.
[x] Ignore Hinting: Instead of throwing `HintingUnsupported`, you can safely parse the hinting byte length and advance the `Reader` past them to render the unhinted outlines.
[x] Cubic Bézier (CFF/OTF) Support: The `Path` module only handles quadratic Béziers. Adding parsing for OpenType CFF (Type 2 charstrings) and cubic flattening would allow the library to support `.otf` files alongside `.ttf`.
[ ] Variable Fonts (`gvar` table): Support for OpenType Font Variations. Interpolating coordinates based on user-defined axes (weight, width, optical size) is the modern standard for flexible typography.

Rendering & Geometry:
[ ] Signed Distance Fields (SDF/MSDF): Instead of only generating rasterized bitmaps via `Fill.coverage`, add an option to generate Multi-channel Signed Distance Fields. This would allow hardware-accelerated, infinitely scalable rendering of the glyphs on the GPU in external graphics engines.
[ ] Gamma-Correct Blending: The current `Bitmap#blend` performs alpha compositing in sRGB space. Converting colors to linear space before blending, then re-applying the gamma curve, prevents dark halos and makes `COLRv1` gradients much more physically accurate.
[ ] Subpixel Anti-Aliasing (LCD Subpixel Rendering): The current rasterizer uses 4x vertical sub-sampling for grayscale coverage. LCD subpixel rendering (treating R, G, and B as separate horizontal subpixels) would drastically improve sharpness on traditional monitors.

Performance & Optimization:
[ ] SIMD Acceleration: The nested loops in `Bitmap#blend` and `Fill#coverage` are prime candidates for explicit SIMD intrinsics (via Crystal's experimental SIMD support or C bindings) to process multiple pixels or coverage spans simultaneously.
[ ] Parallel Rasterization: Rendering complex `COLRv1` layers or bulk-rendering the `Glossary` could be dispatched to a worker pool (Crystal's `spawn` with `Channel`), scaling rasterization across multiple CPU cores.

Architecture & Scope:
[ ] Relaxing PUA Restriction: The library strictly enforces `Glyph.pua?(cp)`. If the goal is a general-purpose font engine, abstracting the PUA check into a strict "Icon Mode" vs. a general "Font Mode" would allow users to render standard alphanumeric characters.