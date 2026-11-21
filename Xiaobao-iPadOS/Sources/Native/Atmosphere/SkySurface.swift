import SwiftUI
@preconcurrency import MetalKit

/// Sky quality is capped by pixel area, not by the number of physical iPad display pixels.
private enum SkyQuality: Int {
    case small, balanced, detailed

    var pixels: Double {
        switch self {
        case .small: 400_000
        case .balanced: 710_000
        case .detailed: 1_040_000
        }
    }

    var steps: Int {
        switch self {
        case .small: 66
        case .balanced: 88
        case .detailed: 112
        }
    }

    func size(for bounds: CGSize) -> CGSize {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 1, bounds.height > 1 else { return .zero }
        let scale = min(2, sqrt(pixels / (bounds.width * bounds.height)))
        return CGSize(width: floor(bounds.width * scale), height: floor(bounds.height * scale))
    }
}

@MainActor
struct SkySurface: UIViewRepresentable {
    let state: VolumetricSkyState
    let size: CGSize
    let moving: Bool

    private static let sharedSky: Task<VolumetricSky?, Never> = Task.detached(priority: .userInitiated) {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary()
        else { return nil }
        return try? VolumetricSky(device: device, library: library)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = false
        view.framebufferOnly = true
        view.colorPixelFormat = VolumetricSky.pixelFormat
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.preferredFramesPerSecond = 24
        view.delegate = context.coordinator
        context.coordinator.attach(view, to: Self.sharedSky)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(state: state, size: size, moving: moving, view: view)
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.stop(view)
    }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        private var startup: Task<Void, Never>?
        private var sky: VolumetricSky?
        private var state: VolumetricSkyState?
        private var boundsSize = CGSize.zero
        private var clock = SkyPlaybackClock()
        private var wantsMotion = false
        private var quality = SkyQuality.balanced
        private var busy = false
        private var needsFrame = true
        private var ema = 0.0
        private var count = 0

        func attach(_ view: MTKView, to pipeline: Task<VolumetricSky?, Never>) {
            startup = Task { [weak self, weak view] in
                guard let result = await pipeline.value, !Task.isCancelled, let self, let view else { return }
                sky = result
                view.device = result.device
                configure(view)
            }
        }

        func update(state: VolumetricSkyState, size: CGSize, moving: Bool, view: MTKView) {
            guard self.state != state || boundsSize != size || wantsMotion != moving else { return }
            self.state = state
            boundsSize = size
            wantsMotion = moving
            configure(view)
        }

        func stop(_ view: MTKView) {
            startup?.cancel()
            wantsMotion = false
            clock.setRunning(false, at: CACurrentMediaTime())
            view.isPaused = true
            view.delegate = nil
        }

        private func configure(_ view: MTKView) {
            guard sky != nil else { return }
            let target = (wantsMotion ? quality : .detailed).size(for: boundsSize)
            let runnable = wantsMotion && target != .zero
            clock.setRunning(runnable, at: CACurrentMediaTime())
            if target != .zero, view.drawableSize != target { view.drawableSize = target }
            if runnable {
                view.enableSetNeedsDisplay = false
                view.isPaused = false
            } else {
                view.isPaused = true
                view.enableSetNeedsDisplay = true
            }
            needsFrame = true
            if !runnable { view.setNeedsDisplay() }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // A resize while paused still needs a frame; the display loop will handle active draws.
            needsFrame = true
            if view.isPaused { view.setNeedsDisplay() }
        }

        func draw(in view: MTKView) {
            guard !busy, let sky, let state, boundsSize != .zero,
                  wantsMotion || needsFrame,
                  let buffer = sky.queue.makeCommandBuffer(),
                  let pass = view.currentRenderPassDescriptor, let target = view.currentDrawable
            else { return }
            let moving = wantsMotion
            let selectedQuality = moving ? quality : .detailed
            let size = target.texture
            let uniforms = state.uniforms(width: size.width, height: size.height, steps: selectedQuality.steps,
                                          elapsed: clock.elapsed(at: CACurrentMediaTime()), moving: moving)
            guard sky.encode(uniforms, in: buffer, to: pass) else { return }
            busy = true
            needsFrame = false
            let finish: @MainActor @Sendable (Bool, Double) -> Void = { [weak self, weak view] succeeded, milliseconds in
                guard let self, let view, view.delegate === self else { return }
                self.busy = false
                if !succeeded {
                    self.stop(view)
                    view.isHidden = true
                } else if moving && self.wantsMotion {
                    self.sample(milliseconds, view: view)
                } else if self.needsFrame {
                    view.setNeedsDisplay()
                }
            }
            buffer.addCompletedHandler { result in
                let milliseconds = (result.gpuEndTime - result.gpuStartTime) * 1000
                let succeeded = result.status == .completed
                Task { @MainActor in finish(succeeded, milliseconds) }
            }
            buffer.present(target)
            buffer.commit()
        }

        private func sample(_ milliseconds: Double, view: MTKView) {
            guard milliseconds.isFinite, milliseconds > 0 else { return }
            ema = count == 0 ? milliseconds : ema * 0.90 + milliseconds * 0.10
            count += 1
            guard count >= 36 else { return }
            let next: SkyQuality?
            if ema > 27 {
                next = SkyQuality(rawValue: quality.rawValue - 1)
            } else if ema < 13, count >= 80 {
                next = SkyQuality(rawValue: quality.rawValue + 1)
            } else {
                next = nil
            }
            if let next {
                quality = next
                count = 0
                configure(view)
            }
        }
    }
}
