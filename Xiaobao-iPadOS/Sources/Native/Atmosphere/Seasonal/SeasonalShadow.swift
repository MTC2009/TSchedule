import simd

/// A texel-snapped orthographic camera looking *from* the sun/moon. The lake and far hills
/// receive this map but do not expand its footprint to the entire horizon.
struct SeasonalShadow {
    var x,y,z: SIMD4<Float>
    static let resolution = 768

    init(_ scene:SeasonalScene,_ u:SkyUniforms) {
        let daylight = min(1,max(0,(u.clock.x-0.10)/0.68))
        let f=daylight*daylight*(3-2*daylight)
        let sun=SkyPoint(u.sun.x,u.sun.y,u.sun.z),moon=SkyPoint(u.moon.x,u.moon.y,u.moon.z)
        let l=simd_normalize(moon+(sun-moon)*f), right=simd_normalize(simd_cross(SkyPoint(0,1,0),l)), up=simd_cross(l,right)
        var lo=SkyPoint(repeating:.infinity), hi = -lo
        for shape in SeasonalShape.allCases where shape != .lake && shape != .bank && shape != .crown && shape != .floor && shape != .hillside {
            for item in scene.instances[shape.rawValue] {
                let p=SkyPoint(item.center.x,item.center.y,item.center.z)
                let c=SkyPoint(simd_dot(p,right),simd_dot(p,up),simd_dot(p,l))
                let r=min(6,max(simd_length(item.x),max(simd_length(item.y),simd_length(item.z))))*1.22
                lo=simd_min(lo,c-SkyPoint(repeating:r)); hi=simd_max(hi,c+SkyPoint(repeating:r))
            }
        }
        if !lo.x.isFinite { lo = .init(-7,-3,0); hi = .init(7,9,20) }
        let half=max(0.9,max(hi.x-lo.x,hi.y-lo.y)*0.62), pix=2*half/Float(Self.resolution)
        let cx=(((lo.x+hi.x)*0.5)/pix).rounded()*pix, cy=(((lo.y+hi.y)*0.5)/pix).rounded()*pix
        let near=hi.z+6, span=max(12,near-lo.z+8)
        x = .init(right/half,-cx/half); y = .init(up/half,-cy/half); z = .init(-l/span,near/span)
    }
}
