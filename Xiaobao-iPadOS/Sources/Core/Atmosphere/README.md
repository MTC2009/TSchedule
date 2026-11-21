# Atmosphere core

- **Responsibility:** describe weather effects and sky light, not weather observations or school scheduling.
- **Input:** selected `Weather`, Shanghai civil date/minute, and optional elapsed animation seconds. No network, location, app permissions or backend state.
- **Output / interface:** `Weather` (stable ID/title/SF Symbol), `WeatherCategory.conditions`, `Weather.style.frame(at:)`, `SkyTime` (phase and light), `SkyPalette.at` and `Festival.automatic(on:)`. Normalized effect controls are unitless.
- **Dependencies / consumers:** uses Foundation and `SchoolClock`; used by the city-code mapping, AppModel, the environment picker and the SwiftUI Atmosphere module. See [Reusable modules](../../../../REUSABLE_MODULES.md) for call sites. The core never fetches or schedules weather.
- **Files:** `Weather.swift` contains picker metadata, `WeatherStyle.swift` contains appearance/strength ranges, `SkyTime.swift` maps dates and times to light, `SkyPlaybackClock.swift` advances or freezes animation independently of the civil clock, `SkyPalette.swift` applies color tokens, and `Atmosphere.swift` contains day phase and festival rules.
- **Tests:** from `Xiaobao-iPadOS`, run `swift test --filter 'EnvironmentTests|WeatherTests|SkyPlaybackClockTests'`. Tests cover coverage, storage compatibility, intensity, season changes, midnight continuity, and paused or resumed motion.
- **Limits:** light times are artistic approximations, not astronomical events. Weather titles do not imply measured intensity or a warning. Stationary ranges display their midpoint.

## Change History

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
