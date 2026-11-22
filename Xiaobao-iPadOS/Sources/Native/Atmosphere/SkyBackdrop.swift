import SwiftUI

struct SkyBackdrop: View {
    let state: VolumetricSkyState
    let fallback: SkyPalette
    let moving: Bool
    let exposed: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The underlying code-generated gradient keeps text readable until Metal has
                // initialized, or on a device where the GPU pipeline cannot be created.
                LinearGradient(colors: [fallback.top.color, fallback.middle.color, fallback.bottom.color],
                               startPoint: .top, endPoint: .bottom)
                SkySurface(state: state, size: geometry.size, moving: moving, exposed: exposed)
            }
            .clipped()
        }
    }
}
