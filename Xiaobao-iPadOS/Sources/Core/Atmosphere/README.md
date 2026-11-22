# Atmosphere core

- **Responsibility:** describe weather effects and sky light, not weather observations or school scheduling.
- **Input:** selected `Weather`, Shanghai civil date/minute, and optional elapsed animation seconds. No network, location, app permissions or backend state.
- **Output / interface:** `Weather` (stable ID/title/SF Symbol), `WeatherCategory.conditions`, `Weather.style.frame(at:)`, `SkyTime` (phase and light), `SkyPalette.at` and `Festival.automatic(on:)`. Normalized effect controls are unitless.
- **Dependencies / consumers:** uses Foundation and `SchoolClock`; used by the city-code mapping, AppModel, the environment picker and the SwiftUI Atmosphere module. See [Reusable modules](../../../../REUSABLE_MODULES.md) for call sites. The core never fetches or schedules weather.
- **Files:** `Weather.swift` contains picker metadata, `WeatherStyle.swift` contains appearance/strength ranges, `SkyTime.swift` maps dates and times to light, `SkyPlaybackClock.swift` advances or freezes animation independently of the civil clock, `SkyPalette.swift` applies color tokens, and `Atmosphere.swift` contains day phase and festival rules. `SolarTermCalendar.swift` contains offline [Hong Kong Observatory published UTC+8 dates](https://www.hko.gov.hk/en/gts/time/conversion.htm) for 2011–2050 (960 dates). Outside that range automatic mode does not invent a solar term; all term IDs remain valid as saved choices; the app currently pauses their presentation. `SeasonalMotion.swift` separates flight, present release and transient touch responses. Its visit seed maps a lane, event and channel to a stable sample; no frame-count-based randomness. A visible Halloween lamp accepts one tap per ignition and evaluates its bounce, subsequent turn and light from elapsed time. Lunar observances skip leap repetitions; the day before the next Spring Festival determines Lunar New Year’s Eve. A coinciding festival takes precedence over the solar term.
- **Tests:** from `Xiaobao-iPadOS`, run `swift test --filter 'EnvironmentTests|WeatherTests|SkyPlaybackClockTests|SeasonalSceneTests'`. Tests cover storage compatibility, intensity, midnight continuity, paused/resumed motion, movable dates, and independent flight, gift and brush responses.
- **Limits:** light times are artistic approximations, not astronomical events. Weather titles do not imply measured intensity or a warning. Stationary ranges display their midpoint.

## Change History

### 2026-11-22 — canonical-bells / named-school-cards / seasonal-pause
Model: OpenAI Codex. The shipping build applies `Festival.displayed(on:automatic:manual:)` before presentation. It returns none for automatic and saved manual selections while artwork is paused. Calendar lookup, stored values and ordinary weather remain independent.


### 2026-11-22 — Clocked print interactions
Model: OpenAI Codex · Keywords: visit-seed / independent-bursts / three-arc-ignition
Changed: Added seeded event samples and a separate Halloween ignition timeline; pausing a frame cannot reshuffle events. An active lamp ignores repeat taps; a stopped surface can explicitly request another feedback pose.
Reason: Independently varied events need to survive redraws and time jumps. The lantern sequence must land before turning. Rabbit descent and the gift bag remain independent of the sleigh pose.
Affected interfaces: native-only `SeasonalMotion.init(seed:)`, `sample(_:_:_:)`, `haunt(_:)` and optional `stillFrame` on `touch`. No holiday IDs, storage or service changes.

### 2026-11-21
Model: OpenAI Codex · Keywords: seasonal-calendar / solar terms / touch-state
Changed: Added offline date resolution, compatible manual IDs, actor paths and separate typed reaction state. Reason: select one authentic scene per Shanghai date and keep an interaction local to that scene. Affected interfaces: extended `Festival` catalog and internal motion contract; existing preference values still decode.


### 2026-11-19 · City weather consumer
Model: OpenAI Codex · Keywords: city-weather / illustration-contract  
Changed: Documented the WMO mapping as a new consumer of the same `Weather` cases.  
Reason: A city report may select an illustration without moving HTTP into the atmosphere core.  
Affected interfaces: None; raw IDs, profile count and lighting are unchanged.

### 2026-11-19 · Volumetric renderer
Model: OpenAI Codex  
Conversation Keywords: cloud density / civil clock / pause  
Changed: Added a scoped monotonic playback clock; the dates, palette, weather catalog and preferences are unchanged.  
Reason: Geometry must be able to continue changing at a fixed scene time and freeze without advancing when not visible.  
Affected interfaces: Internal `SkyPlaybackClock` used by `SkySurface`; no network or persisted contract changes.

### 2026-11-19
Model: OpenAI Codex  
Conversation Keywords: atmospheric-sky / seasonal-light / weather-catalog  
Changed: Expanded the local catalog and made visual clock and palette season-aware.  
Reason: Readably distinguish atmospheric conditions at multiple times of day without remote data.  
Affected interfaces: SwiftUI-facing weather and sky APIs only; old `rain` / `snow` preference keys still decode. No HTTP impact.

### 2026-11-21 — bilingual UI / verbatim school data
Model: Codex. Festival, solar-term, time-of-day and weather titles are localized. Solar terms have distinct keys from the weather conditions with the same Chinese spelling. Raw IDs, seasonal scenes and weather behavior are unchanged. [Language boundary and regression tests](../Localization/README.md).
