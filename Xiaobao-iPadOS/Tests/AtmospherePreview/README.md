# Metal appearance probe

- **Purpose / boundary:** developer-only shader rendering on macOS and sidebar sky lifecycle checks on a separate iPad simulator. Neither tool ships in the student app or measures physical iPad performance.
- **Input / output:** a new output folder, optional width and height in pixels, and the mode described below (`pair`, `catalog`, `seasonal`, `study`, `lighting`, `sparrow`, `festive`, `prints`, `reel` or `contact-reel`). The script builds the shader with the installed Xcode toolchain and writes images, invariant checks or GPU timings depending on the mode. No preview data enters the application.
- **Entry:** `scripts/render_sky_probe.sh /tmp/xiaobao-sky-visuals` from the native project. `pair` compares a held night clock at three elapsed motion times and checks a repeated frame is bit-identical. `catalog` samples the 35 cloud presets but does not draw the SwiftUI foreground rain or snow. For actual UI composition, run the native app on the iPad simulator.
- **Dependencies / consumers:** Xcode, local Metal GPU, and the same Swift state, encoder and Metal sources as `SkySurface`. Used by developers only.
- **Files:** `RenderSky.swift` renders, reads back and verifies frames; the script builds it without introducing new dependencies.

**Sidebar regression:** from the iPad project run `python3 Tests/AtmospherePreview/sidebar-sky-smoke.py <booted-QA-iPad-UUID> <dedicated-scratch-dir>`. Use a simulator without Reduce Motion or Low Power Mode to test pause/resume. Reuse the same scratch directory. The Python launcher builds the checked-in sources with a locally verified synthetic owner, entry and SwiftUI destination from `SidebarSkySmoke.swift` under a fixture-only bundle ID (through the shared project setting, so the embedded extension retains the matching prefix); it never installs the production identifier. The probe checks actual Metal view identity across six sidebar selections, push/pop, switching away from a detail, and invalidating the school session while a detail is open. It emits only a pass/fail summary. No account or imported grades are needed. A manual fixture launch with `--inspect-sky` briefly holds the synthetic GPA screen for a compositor check.

**Seasonal rendering:** `scripts/render_sky_probe.sh <new-output-folder> 768 576 seasonal`. Uses the production mesh and material, cloud and picking passes. Check the 37 manual scenes against their own sky-only controls and each other's image fingerprints; for each solar term compare the same scene and clock with/without an explicit touch. Test ripples at two separated surface hits against their untouched surroundings. Also checks gift independence (a parcel may temporarily obscure, not displace, a sleigh pixel), rabbit descent, fixed-time replay and a second camera. The overcast check compares the *visible IDs*, not just a different sky color. Screenshots are evidence, not assets.

**Festival motion and geometry:** `scripts/render_sky_probe.sh <new-output-folder> 768 576 festive`. Repeat at `576 768` to check rotation. Compares same-clock replay and two visit seeds, tests that clocks advance the events, requires actual remote burst trails behind the Lantern Festival’s near and far paper lights, counts green pixels in the lamp ID, measures rabbit width against the actual moon in a sky-only control, and compares solid walls with their own opaque radiance readback under an overcast deck. Optical antialiasing at a real edge is not a hole through a wall.

**Art and motion plates:** `prints` saves ungraded, standard-camera frames for all 37 scenes at different choices from the existing environment panel; it does not set the App’s weather. `reel` records five festival sequences (128 frames each, 16 fps). `contact-reel` records 64 consecutive frames each for all 24 terms, the rabbit and the two sleighs. At frame 13 it finds a real visible hit; a brush is released at frame 27, and the Rain Water demonstration includes a second contact on the actual water surface. The recorder deliberately exercises the successful gift branch, while the core suite also checks the no-gift branch. The sequences contain actual geometry and move both clocks; no pointer glyph, compositing grade or video ships in the App. They are scripted Metal captures, not recordings of a physical iPad.

**Four-plate motion proof:** `scripts/render_sky_probe.sh <new-output-folder> 800 600 impression-reel` saves 96 consecutive GPU frames at 18 fps for the regatta, the magpie bridge, the lotus and the dew web. Both clocks advance; the latter two receive a surface pick at frame 20. Standard `seasonal` also invokes `SeasonalImpressionProbe.swift`: it checks the assembled hull and each blade against the real mirror, verifies flight in both directions and offscreen wrapping in a wide window, checks the projecting bow and stern in two narrow windows, compares dew positions under two different contacts with a fixed wood frame, and measures each petal's change after removing the stalk's rigid tilt. These are structural checks, not a numerical measure of artistic quality.

**Seasonal touch:** `python3 Tests/AtmospherePreview/seasonal-touch-smoke.py <booted-QA-iPad-UUID> <dedicated-scratch-directory>`. Uses Xcode and the existing local Ruby `xcodeproj` tool. A fixture-only identifier and entry mount the production sky and real SwiftUI controls under XCUITest. Tests send actual taps and drags at the composited locations, check a button and a scroll view keep their gestures, and exercise the shipping manual selector. The fixture inspects geometry/state only in its own process; no account or live portal is needed.

**Material study:** `scripts/render_sky_probe.sh <new-output-folder> 900 675 study` renders all 37 scenes twice: standard App framing and a true camera dolly at the same sky time. For selected scenes it also renders another real environment-panel weather/clock combination with the near camera (`-sky.png`). Images are never inputs. For an old/new comparison, keep both cameras, times, weather and output size identical.

**Sparrow portrait:** `scripts/render_sky_probe.sh <new-output-folder> 1112 724 sparrow`. Saves the shipping composition, a freshly rendered 1:1 sensor crop from that same viewpoint (no enlargement, sharpener or color grade), two rotations of the shipping subject and perch, the puffed state, and a second real sky. Cropping happens only in this developer executable. `SeasonalSparrowProbe.swift` checks both flanks, the upper/lower opening of each eye, finite indices/normals, fixed foot and perch transforms and the terminal positions of all eight claws against the branch. A CPU or pixel test cannot certify resemblance to a real photograph.

**Optical bench:** `scripts/render_sky_probe.sh <new-output-folder> 768 576 lighting` runs `SeasonalLightProbe.swift` on the production pipeline. It measures non-empty caster depth and movement as the actual key changes, swaps two pigments behind clear geometry and looks inside the drop, then restricts a reflection comparison to genuine **water-ID** pixels. It reports warm median command-buffer GPU times, without texture readback in the timed frames. Neither timings nor semantic tests certify photographic quality.

## Change History

### 2026-11-22 — Four-plate articulation proof
Model: OpenAI Codex · Keywords: stroke-immersion / silk-tension / delayed-whorls / matching-prints
Changed: Added paired structural assertions to the catalog, an isolated four-plate recorder, and native paused-tap coverage for fine silk and petals.
Reason: A changing frame alone would pass floating paddles, a rigidly swaying web or a whole flower tilting as one. Affected interfaces: developer CLI gains `impression-reel`; no recording or test action enters the shipping target.

### 2026-11-22 — Almanac prints / animation proof
Model: OpenAI Codex · Keywords: independent-events / projected-ratio / overcast-wall / live-contact-reel
Changed: Added the `festive`, `prints`, `reel` and `contact-reel` developer modes; the native input fixture now distinguishes the hanging lamp from its noninteractive surroundings. Existing regression mode still uses matching weather and time for untreated vs touched scenes.
Reason: A single still cannot demonstrate random launches, the order of bounce and turn, unchanged sleigh trajectory or the shell occluding green fire edge-on.
Affected interfaces: developer CLI and fixture only.

### 2026-11-22 — Perched wildlife evidence
Model: OpenAI Codex · Keywords: sparrow-portrait / fixed-sensor / paused-feather-touch
Changed: Added the sensor crop/turntable and anatomical checks, a real tap on the paused perch in XCUITest and a Lesser Cold timing sample in the optical bench. The portrait colors come from the shipping Metal passes, not the reference.
Reason: Different backgrounds, different camera distances, or a changed pixel count can hide the exact missing detail. The staged check keeps framing and time fixed and verifies that the contact points do not slide.
Affected interfaces: developer command adds `sparrow`; no extra control or debug camera in the App.

### 2026-11-22 — Surface and lighting evidence
Model: OpenAI Codex · Keywords: paired-lookdev / optical-bench / water-mirror
Changed: Added fixed camera/context and close studies, optional weather studies and an isolated depth/transmission/reflection test plus GPU timings. Reason: separate a lighting or geometry regression from a palette change or a moving cloud. Interfaces: developer command adds `study` and `lighting` only.


### 2026-11-21 — Seasonal rendering and input
Model: OpenAI Codex · Keywords: seasonal-probe / visible-object-ids / physical-touch-routing
Changed: Added catalog-wide GPU comparisons and isolated XCTest input; refreshed the standalone probe to compile the full core source dependencies. Reason: a screenshot or a state-machine test alone cannot verify the recipient of an iPad gesture. Interfaces: existing developer script adds `seasonal`; new fixture-only touch command.


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
