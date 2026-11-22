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
    let exposed: Bool

    private static let sharedSky: Task<VolumetricSky?, Never> = Task.detached(priority: .userInitiated) {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary()
        else { return nil }
        return try? VolumetricSky(device: device, library: library)
    }
    private static let sparrowAssets=Task.detached(priority:.userInitiated) {
        let sky=await sharedSky.value
        return sky?.prepareSparrow() ?? false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = SeasonalMetalView(frame: .zero)
        view.windowDidChange = { [weak c = context.coordinator] view in c?.syncContact(view) }
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
        context.coordinator.update(state: state, size: size, moving: moving, exposed: exposed, view: view)
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.stop(view)
    }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        private var startup: Task<Void, Never>?
        private var sparrowStartup:Task<Void,Never>?
        private var sparrowReady:Bool?
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

        private let contact = SeasonalContact()
        private var exposed = false
        private var targets: SeasonalTargets?
        private var seasonOrigin = 0.0
        private var staticAdvance: Float = 0
        private var motion = SeasonalMotion()
        private var generation = 0
        private var hasPickFrame = false
        private var parcelOrigin: SkyPoint?

        func syncContact(_ view: MTKView) {
            let f = state?.festival ?? .none
            let interactive = f == .christmas || f == .christmasEve || f == .midautumn || f == .halloween || Festival.solarTerms.contains(f)
            contact.mount(view,enabled:exposed && interactive && sky?.supportsSeasonalScenes == true)
        }

        private var seasonTime: Float {
            Float(max(0,clock.elapsed(at:CACurrentMediaTime())-seasonOrigin))+staticAdvance
        }
        private func redraw(_ view: MTKView) {
            needsFrame = true
            if view.isPaused { view.setNeedsDisplay() }
        }

        func attach(_ view: MTKView, to pipeline: Task<VolumetricSky?, Never>) {
            contact.pick = { [weak self, weak view] point, reply in
                guard let self, let view, let targets=self.targets, let sky=self.sky, self.hasPickFrame,
                      view.bounds.width>0,view.bounds.height>0 else { reply(nil); return }
                let gen = self.generation
                let bag = self.parcelOrigin
                let uv = SIMD2(Float(point.x/view.bounds.width),Float(point.y/view.bounds.height))
                let radius = Int(8*CGFloat(targets.picks.width)/view.bounds.width)
                SeasonalPicking.read(uv:uv,radius:radius,texture:targets.picks,queue:sky.queue) { [weak self] hit in
                    Task { @MainActor in
                        guard let self,self.exposed,self.generation==gen else { reply(nil); return }
                        // Keep the gift attached to the bag in the sampled frame, even when
                        // a tap hits the leading reindeer or the readback completes a frame later.
                        if let hit, hit.target == .sleigh, let bag {
                            reply(.init(target:.sleigh,world:bag))
                        } else { reply(hit) }
                    }
                }
            }
            contact.interact = { [weak self,weak view] hit, held in
                guard let self, let view, self.exposed, let f=self.state?.festival else { return }
                if self.motion.touch(hit.target,scene:f,time:self.seasonTime,point:hit.world,
                                     chance:Float.random(in:0..<1),holding:held,stillFrame:!self.wantsMotion) {
                    if !self.wantsMotion { self.staticAdvance += 0.48 }
                    self.redraw(view)
                }
            }
            contact.pull = { [weak self,weak view] amount in
                guard let self, let view else { return }
                self.motion.pull(amount); self.redraw(view)
            }
            contact.release = { [weak self,weak view] in
                guard let self, let view else { return }
                self.motion.release(at:self.seasonTime)
                if !self.wantsMotion { self.staticAdvance += 0.24 }
                self.redraw(view)
            }
            startup = Task { [weak self, weak view] in
                guard let result = await pipeline.value, !Task.isCancelled, let self, let view else { return }
                sky = result
                view.device = result.device
                configure(view)
                syncContact(view)
            }
        }

        func update(state: VolumetricSkyState, size: CGSize, moving: Bool, exposed: Bool, view: MTKView) {
            guard self.state != state || boundsSize != size || wantsMotion != moving || self.exposed != exposed else { return }
            if self.state?.festival != state.festival {
                contact.invalidateContact()
                generation += 1
                motion = SeasonalMotion(seed:[Festival.spring,.lantern].contains(state.festival) ? UInt32.random(in:.min ... .max) : 0)
                hasPickFrame = false
                seasonOrigin = clock.elapsed(at:CACurrentMediaTime()); staticAdvance = 0
                if state.festival == .none { targets = nil }
            }
            if size != boundsSize || (self.exposed && !exposed) {
                generation += 1; hasPickFrame = false; contact.invalidateContact()
            }
            self.exposed = exposed
            self.state = state
            boundsSize = size
            wantsMotion = moving
            configure(view)
            syncContact(view)
        }

        func stop(_ view: MTKView) {
            contact.mount(nil,enabled:false); exposed = false; generation += 1; targets = nil
            startup?.cancel()
            sparrowStartup?.cancel()
            wantsMotion = false
            clock.setRunning(false, at: CACurrentMediaTime())
            view.isPaused = true
            view.delegate = nil
        }

        private func configure(_ view: MTKView) {
            guard sky != nil else { return }
            if state?.festival == .lesserCold, sparrowReady == nil, sparrowStartup == nil {
                let assets=SkySurface.sparrowAssets
                sparrowStartup=Task { [weak self,weak view] in
                    let ready=await assets.value
                    guard !Task.isCancelled,let self,let view else {return}
                    self.sparrowReady=ready; self.sparrowStartup=nil
                    if self.state?.festival == .lesserCold {self.redraw(view)}
                }
            }
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
            var art: SeasonalScene?
            if state.festival != .none, sky.supportsSeasonalScenes, state.festival != .lesserCold || sparrowReady == true {
                if targets?.color.width != size.width || targets?.color.height != size.height {
                    targets = SeasonalTargets(device:sky.device,width:size.width,height:size.height)
                    hasPickFrame = false
                }
                art = SkyDetails.scene(state.festival,aspect:uniforms.viewport.x,time:seasonTime,motion:motion,moon:uniforms.moon)
            }
            guard sky.encode(uniforms, in:buffer, to:pass, scene:art, targets:targets) else {
                hasPickFrame = false
                return
            }
            hasPickFrame = art != nil && targets != nil
            parcelOrigin = art?.parcelOrigin
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

/// Registration follows window attachment and scene visibility; the Metal view never takes a touch.
@MainActor private final class SeasonalMetalView: MTKView {
    var windowDidChange: ((MTKView) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); windowDidChange?(self) }
}
