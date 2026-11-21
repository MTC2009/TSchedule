import SwiftUI

struct AtmosphereView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var onScreen = false

    var inEnvironmentPanel = false
    var isCovered = false

    private var moving: Bool {
        let unobscured = inEnvironmentPanel || (!model.environmentPresented && !model.portalPresented && model.selectedLesson == nil)
        return onScreen && !isCovered && model.preferences.ambientMotion && !reduceMotion && !lowPower && scenePhase == .active && unobscured
    }

    var body: some View {
        let time = model.skyTime
        let weather = model.weatherDisplay.weather
        let style = weather.style
        let palette = SkyPalette.at(time: time, style: style)
        let frame = style.frame()

        ZStack {
            SkyBackdrop(state: VolumetricSkyState(time: time, style: style, festival: model.festival),
                        fallback: palette, moving: moving)

            if frame.hasParticles || frame.veil > 0 || style.lightning {
                WeatherOverlay(weather: weather, style: style, daylight: time.daylight, moving: moving)
            }
            SkyDetails(festival: model.festival)
            readability(at: time, frame: frame)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func readability(at time: SkyTime, frame: WeatherFrame) -> some View {
        let dark = colorScheme == .dark
        let shade = dark ? 0.16 + 0.26 * time.daylight : 0.29 + 0.33 * (1 - time.daylight) + 0.20 * frame.dimming
        let tone = dark ? AtmosphereColors.darkReadability : AtmosphereColors.lightReadability
        return LinearGradient(
            stops: [
                .init(color: tone.opacity(shade), location: 0),
                .init(color: tone.opacity(shade * 0.55), location: 0.56),
                .init(color: tone.opacity(shade * 0.72), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
