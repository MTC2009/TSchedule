# City weather

This module turns a public city-level weather report into a condition for the existing sky. It has no school account, course, device-location, notification or rendering dependency.

| File | Responsibility |
| --- | --- |
| `CityWeather.swift` | Fixed public city configuration, normalized sample and display states, explicit WMO-to-art mapping. |
| `OpenMeteoClient.swift` | Read and decode only the **current** weather code and its UTC validity time, not a daily maximum. Ephemeral HTTPS session, no cookies, credential store, redirects or shared HTTP cache. |
| `CityWeatherStore.swift` | One foreground refresh loop; mode persistence, stale/cached/preview selection and cancellation. |

**Inputs and outputs.** `OpenMeteoClient.read(_ city:)` returns `CityWeatherSample(weather:validAt:)`. `CityWeatherStore(city:defaults:clock:read:)` accepts the city, local preferences, a real clock and the asynchronous reader; `setForeground(_:)` and `setFollowsCity(_:)` own scheduling. `display(at:preview:)` returns current, cached, manual, loading or unavailable. The fallback art is cloudy; unavailable is never labelled as a cloudy report. Only the weather core's `Weather` enum crosses into the renderer. Consumers: [native app](../../../README.md); exact call sites in the [reuse index](../../../../REUSABLE_MODULES.md).

**Origin and privacy.** The campus configuration uses the rounded city centre of Dongguan, Guangdong (WGS84 23.02° N, 113.75° E); this is the same fixed grid request on every installation. No runtime geocoding. The only outbound data selected by the app are two city coordinates, `current=weather_code` and `timeformat=unixtime`. Like other HTTPS services, the provider sees ordinary connection metadata such as the network IP. The current condition is model-derived, **not** a measurement at a school or an official warning. See the [API and WMO table](https://open-meteo.com/en/docs), [licence](https://open-meteo.com/en/licence) and [service terms](https://open-meteo.com/en/terms). The keyless endpoint is for this non-commercial prototype; review licensing and volume before a commercial release. The environment sheet attributes the source alongside the condition.

**Policy.** A fresh install follows the city. The old preferences blob stays intact; manual mode reuses the last local weather selection. While active, successful reads are spaced 30 minutes apart and failed reads retry after 10 minutes. Leaving the foreground or entering manual mode cancels the request and the timer. Pending old calls cannot overwrite a new session. Ignore reports more than 2 hours old, more than 5 minutes in the future, or older than an already usable sample. A cold cache or a failed refresh is explicitly labelled as cached and expires 24 hours after the model validity time, regardless of the fetch time. A missing/malformed/unknown report cannot independently assert any weather condition. Cache keys are versioned by source and city; school caches, keys and offline databases are untouched.

**Coverage.** 29 recognised codes map onto 15 existing illustrations. For example, drizzle shares light rain, all rain showers share the shower effect, and snow grains use light snow. No inference of typhoon, dust alerts, interval grades or rainstorm warnings from unrelated codes. All 35 illustrations remain available to manual preview even without network. The atmosphere clock is not a forecast date picker.

**Tests.** From the native project run `swift test --filter CityWeather` for isolated request, mapping, cache, time boundary, cancellation, failure and recovery checks. Tests use synthetic cities, clocks and responses; the test suite does not access the public endpoint.

**Runtime verification (2026-11-19).** On the 11-inch iPad Air (M4) simulator, iPadOS 26.4, the running app fetched Dongguan's model condition **阴**, valid at **20:15** Shanghai time. The environment sheet showed the source and timestamp. An XCUITest selected a manual rain effect, restored automatic mode, and toggled back to confirm the manual choice survived. A second launch within the refresh interval identified the saved sample as cached. On an iPad Form the accessibility switch spans the row; test the visible trailing switch rather than assuming its row midpoint toggles it. [Network result](../../../../docs/verification/city-weather/city-report.jpg) · [Restored cache](../../../../docs/verification/city-weather/cached-report.jpg) · [Manual preview](../../../../docs/verification/city-weather/manual-preview.jpg). Offline failure and an out-of-order reply were injected in core tests, not by disabling the host network. The full Swift suite passed 69/69 with the isolated Rust demo integration enabled; the public-weather read was a separate simulator check. Release built for both simulator and unsigned arm64 iPad; no physical-device installation is claimed.

## Change History

### 2026-11-19
Model: OpenAI Codex · Keywords: fixed-city-weather / manual-preview / freshness  
Changed: Added the city reader, explicit freshness states and isolated foreground scheduler.  
Reason: Use an actual city input without transmitting school information or waking the GPU to fetch data.  
Affected interfaces: Native module interfaces above and a single external HTTPS GET; no Rust API, database, deployment flag or app permission.
