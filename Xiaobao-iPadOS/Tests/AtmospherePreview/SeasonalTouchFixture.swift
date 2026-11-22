import SwiftUI
import MetalKit

// Installed only under a fixture identifier. Inspect the production renderer from outside;
// no test buttons, state observers or readback hooks are compiled into the shipping target.
@main @MainActor struct SeasonalTouchFixture:App {
    @State private var model:AppModel
    let theme:Festival
    let wanted:SeasonalTarget
    let cover:Bool
    init() {
        let args=ProcessInfo.processInfo.arguments
        theme=args.compactMap(Festival.init(rawValue:)).first ?? .coldDew
        wanted=args.contains("--water") ? .water : (theme == .midautumn ? .rabbit : (theme == .christmas ? .sleigh : .subject))
        cover=args.contains("--cover")
        let model=AppModel()
        model.preferences.automaticFestival=false; model.preferences.festival=theme
        model.preferences.liveBackground=false; model.preferences.sceneMinute=theme == .christmas || theme == .midautumn ? 1260 : 760
        model.preferences.ambientMotion=false; model.previewWeather(.sunny)
        _model=State(initialValue:model)
    }
    var body:some Scene { WindowGroup {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--environment") { EnvironmentView() }
            else { FixturePage(wanted:wanted,cover:cover) }
        }.environment(model)
    } }
}

@MainActor private struct FixturePage:View {
    let wanted:SeasonalTarget, cover:Bool
    @State private var aim:CGPoint?
    @State private var evidence="waiting"
    @State private var clicks=0
    @State private var scrolled=false
    var body:some View {
        GeometryReader { box in
            ZStack(alignment:.topLeading) {
                AtmosphereView()
                ScrollView {
                    Color.clear.frame(height:box.size.height*2)
                        .onGeometryChange(for:CGFloat.self) { $0.frame(in:.scrollView).minY } action: { y in
                            if y < -25 { scrolled=true }
                        }
                }
                if cover,let aim {
                    Button("前景控件") {clicks+=1}
                        .buttonStyle(.borderedProminent).frame(width:150,height:55)
                        .position(x:aim.x*box.size.width,y:aim.y*box.size.height)
                        .accessibilityIdentifier("foreground")
                }
                Text("验证").accessibilityIdentifier("seasonal-state")
                    .accessibilityValue("\(evidence);\(clicks);\(scrolled)")
                    .padding(8).position(x:65,y:60)
            }.task {
                for _ in 0..<1800 {
                    if let (v,c)=surface() {
                        if aim == nil { aim=point(v,c,box.size) }
                        if let aim,let motion=value(c,"motion") as? SeasonalMotion {
                            let id=motion.gesture?.target.rawValue ?? (motion.ignition == nil ? 0 : SeasonalTarget.subject.rawValue)
                            evidence="\(aim.x),\(aim.y);\(motion.landing != nil);\(motion.present != nil);\(id);\(motion.gesture?.pull ?? 0);\(motion.gesture?.held ?? false)"
                        }
                    }
                    try? await Task.sleep(for:.milliseconds(100))
                    if Task.isCancelled {break}
                }
            }
        }.ignoresSafeArea()
    }
    private func value(_ c:SkySurface.Coordinator,_ key:String) -> Any? {
        Mirror(reflecting:c).children.first{ $0.label == key }?.value
    }
    private func surface() -> (MTKView,SkySurface.Coordinator)? {
        guard let window=(UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow else {return nil}
        func find(_ v:UIView)->MTKView? {if let m=v as? MTKView {return m};for child in v.subviews {if let m=find(child){return m}};return nil}
        guard let view=find(window),let c=view.delegate as? SkySurface.Coordinator else{return nil}
        return (view,c)
    }
    private func point(_ v:MTKView,_ c:SkySurface.Coordinator,_ viewport:CGSize) -> CGPoint? {
        guard (value(c,"hasPickFrame") as? Bool)==true,let tex=(value(c,"targets") as? SeasonalTargets)?.picks,
              let queue=v.device?.makeCommandQueue(),let cmd=queue.makeCommandBuffer(),
              let blit=cmd.makeBlitCommandEncoder() else{return nil}
        let w=tex.width,h=tex.height,row=(w*4+255)/256*256
        guard w>0,h>0,let buf=queue.device.makeBuffer(length:row*h,options:.storageModeShared) else{return nil}
        blit.copy(from:tex,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:w,height:h,depth:1),
                  to:buf,destinationOffset:0,destinationBytesPerRow:row,destinationBytesPerImage:row*h)
        blit.endEncoding();cmd.commit();cmd.waitUntilCompleted()
        guard cmd.status == .completed, let window=v.window else{return nil}
        let data=buf.contents().assumingMemoryBound(to:UInt16.self), id=Float16(wanted.rawValue).bitPattern
        var best=0, chosen:CGPoint?
        for y in stride(from:h/8,to:h*9/10,by:3) {
            var x=0
            while x<w {
                if data[y*row/2+x*2] != id {x+=1;continue}
                let a=x
                while x<w && data[y*row/2+x*2]==id {x+=1}
                let score=min(80,x-a)
                if score>best {
                    best=score
                    let local=CGPoint(x:(CGFloat(x+a)*0.5+0.5)*v.bounds.width/CGFloat(w),y:(CGFloat(y)+0.5)*v.bounds.height/CGFloat(h))
                    let screen=v.convert(local,to:window)
                    chosen=CGPoint(x:screen.x/window.bounds.width,y:screen.y/window.bounds.height)
                }
            }
        }
        return chosen
    }
}
