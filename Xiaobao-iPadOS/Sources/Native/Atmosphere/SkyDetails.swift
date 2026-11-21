import SwiftUI

/// Existing small seasonal details. Celestial light belongs behind the clouds in Metal.
struct SkyDetails: View {
    let festival: Festival

    var body: some View {
        if festival == .spring || festival == .christmas || festival == .newyear {
            Canvas { context, size in
                drawFestival(in: context, size: size)
            }
        }
    }

    private func drawFestival(in context: GraphicsContext, size: CGSize) {
        switch festival {
        case .spring:
            for edge in [0.05, 0.94] {
                let x = size.width * edge
                let y = size.height * (edge < 0.5 ? 0.25 : 0.18)
                var string = Path()
                string.move(to: CGPoint(x: x, y: 0))
                string.addLine(to: CGPoint(x: x, y: y + 58))
                context.stroke(string, with: .color(AtmosphereColors.festiveLight.opacity(0.55)), lineWidth: 1)
                let lamp = CGRect(x: x - 16, y: y, width: 32, height: 44)
                context.fill(Path(ellipseIn: lamp), with: .linearGradient(
                    Gradient(colors: [AtmosphereColors.lanternLight, AtmosphereColors.lanternShadow]),
                    startPoint: lamp.origin, endPoint: CGPoint(x: lamp.midX, y: lamp.maxY)))
            }
        case .christmas, .newyear:
            var lights = Path()
            for index in 0..<18 {
                let x = CGFloat(index) * size.width / 17
                let y = 17 + sin(Double(index) * 0.5) * 8
                lights.addEllipse(in: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6))
            }
            context.fill(lights, with: .color(AtmosphereColors.festiveLight.opacity(0.72)))
        case .none, .midautumn:
            break
        }
    }

}
