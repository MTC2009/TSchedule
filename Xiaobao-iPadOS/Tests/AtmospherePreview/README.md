# Metal appearance probe

- **Purpose / boundary:** developer-only shader rendering on macOS and sidebar sky lifecycle checks on a separate iPad simulator. Neither tool ships in the student app or measures physical iPad performance.
- **Input / output:** a new output folder, optional width and height in pixels, and `pair` or `catalog` mode. The script builds the shader with the installed Xcode toolchain and writes PNGs and per-render GPU timings. No preview data enters the application.
- **Entry:** `scripts/render_sky_probe.sh /tmp/xiaobao-sky-visuals` from the native project. `pair` compares a held night clock at three elapsed motion times and checks a repeated frame is bit-identical. `catalog` samples the 35 cloud presets but does not draw the SwiftUI foreground rain or snow. For actual UI composition, run the native app on the iPad simulator.
- **Dependencies / consumers:** Xcode, local Metal GPU, and the same Swift state, encoder and Metal sources as `SkySurface`. Used by developers only.
- **Files:** `RenderSky.swift` renders, reads back and verifies frames; the script builds it without introducing new dependencies.

**Sidebar regression:** from the iPad project run `python3 Tests/AtmospherePreview/sidebar-sky-smoke.py <booted-QA-iPad-UUID> <dedicated-scratch-dir>`. Use a simulator without Reduce Motion or Low Power Mode to test pause/resume. Reuse the same scratch directory. The Python launcher builds the checked-in sources with a locally verified synthetic owner, entry and SwiftUI destination from `SidebarSkySmoke.swift` under a fixture-only bundle ID (through the shared project setting, so the embedded extension retains the matching prefix); it never installs the production identifier. The probe checks actual Metal view identity across six sidebar selections, push/pop, switching away from a detail, and invalidating the school session while a detail is open. It emits only a pass/fail summary. No account or imported grades are needed. A manual fixture launch with `--inspect-sky` briefly holds the synthetic GPA screen for a compositor check.

## Change History

### 2026-11-21 — Verified sidebar scope
Model: Codex · Keywords: sidebar-scope / school-only-build
Changed: Test the standard Release routes with an injected memory-only identity read. Verify an owner before testing that invalidation removes the protected destination. The fixture never opens a school website. Interfaces: existing simulator probe only.

### 2026-11-21 — Sidebar lifecycle regression
Model: Codex · Keywords: simulator-sky / scoped-destination  
Changed: Added a simulator probe of the production view tree, separate from the existing headless shader test. Reason: an offscreen image test cannot detect a tab change replacing the Metal view or a system navigation controller retaining a stale destination. Affected interfaces: developer test command only.

### 2026-11-19
Model: OpenAI Codex  
Conversation Keywords: volumetric sky / fixed-time comparison  
Changed: Added a reproducible, code-only test render of the production pipeline.  
Affected interfaces: None in the app or Rust service.
