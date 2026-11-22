import simd

/// Geometry guards independent of sky color. A sky-only frame, a repainted ellipsoid
/// or a growing bird with sliding feet can all pass a simple image-difference test.
enum SeasonalSparrowProbe {
    static func check(aspect:Float,motion:SeasonalMotion) throws {
        typealias Fail=SeasonalProbe.Failure
        let still=SkyDetails.scene(.lesserCold,aspect:aspect,time:2.35,motion:.init())
        let reacted=SkyDetails.scene(.lesserCold,aspect:aspect,time:2.35,motion:motion)
        guard let still, let reacted else {throw Fail("Missing perch scene")}
        for shape:SeasonalShape in [.sparrowFoot,.sparrowPerch] {
            let a=still.instances[shape.rawValue],b=reacted.instances[shape.rawValue]
            guard a.count==1,b.count==1,a[0].center==b[0].center,a[0].x==b[0].x,a[0].y==b[0].y,
                  a[0].z==b[0].z,a[0].curve==b[0].curve else {throw Fail("Sliding foot or moving support")}
        }
        guard still.instances[SeasonalShape.sparrowPerch.rawValue][0].extras.x==Float(SeasonalTarget.none.rawValue),
              still.instances[SeasonalShape.sparrowFoot.rawValue][0].extras.x==Float(SeasonalTarget.subject.rawValue),
              let coat=reacted.instances[SeasonalShape.sparrowContour.rawValue].first,coat.curve.w < -0.1,
              let wing=reacted.instances[SeasonalShape.sparrowWing.rawValue].first,wing.curve.w==coat.curve.w
        else {throw Fail("Invalid perch ownership or no distal web displacement")}

        var foot=SeasonalMeshAtlas.Mesh();foot.sparrowFoot()
        var claws:[SkyPoint]=[]
        for v in foot.vertices where abs(v.normalV.w-5)<0.0001 {
            let p=SkyPoint(v.positionU.x,v.positionU.y,v.positionU.z)
            if !claws.contains(where:{simd_length_squared($0-p)<0.000002}) {claws.append(p)}
        }
        let sample=(-400...400).map { Float($0)/1000 }
        for claw in claws {
            let nearest=sample.map { simd_length(SeasonalSparrow.twig($0)-claw)-SeasonalSparrow.radius($0) }.min()!
            guard abs(nearest)<0.0025 else {throw Fail("A terminal claw misses the bark: \(nearest)")}
        }
        guard claws.count==8 else {throw Fail("Found \(claws.count) distinct terminal claws")}

        var groom=SeasonalMeshAtlas.Mesh();groom.sparrowContour()
        var wingMesh=SeasonalMeshAtlas.Mesh();wingMesh.sparrowWing()
        func valid(_ mesh:SeasonalMeshAtlas.Mesh)->Bool {
            mesh.vertices.allSatisfy { v in
                let n=SkyPoint(v.normalV.x,v.normalV.y,v.normalV.z)
                return v.positionU.x.isFinite && v.positionU.y.isFinite && v.positionU.z.isFinite &&
                       v.positionU.w.isFinite && v.normalV.w.isFinite && (0.96...1.04).contains(simd_length_squared(n))
            } && mesh.indices.allSatisfy { Int($0)<mesh.vertices.count }
        }
        var bill=SeasonalMeshAtlas.Mesh();bill.sparrowBill()
        guard valid(bill) else {throw Fail("Invalid bill or orbital mesh")}
        // Mirroring an orbital frame reverses its vertical basis. Check the
        // openings in anatomical space; a side-view image can hide an inverted lid.
        for sign:Float in [-1,1] {
            let orbit=SeasonalSparrow.orbit(sign)
            func lid(_ role:Int)->Float? {
                guard let v=bill.vertices.first(where:{
                    abs($0.normalV.w-Float(2*role))<0.0001 && abs($0.positionU.w-0.5)<0.0001 &&
                        $0.positionU.z*sign>0
                }) else {return nil}
                let p=SkyPoint(v.positionU.x,v.positionU.y,v.positionU.z)-orbit.center
                return simd_dot(p,orbit.axes.columns.1)*sign
            }
            guard let upper=lid(3),let lower=lid(4),upper>0,lower<0,upper-lower<0.052
            else {throw Fail("Upper/lower eyelids inverted or leaving the whole cornea exposed")}
        }
        let follicles=Set(groom.vertices.map {Int($0.positionU.w/4)})
        let tract:Set<Int>=Set(1...8)
        for side:Float in [-1,1] {
            let visible=Set(wingMesh.vertices.lazy.filter {$0.positionU.z*side>0.01}.map {Int($0.normalV.w/2)})
            guard visible.isSuperset(of:tract) else {throw Fail("Missing feather tract on flank \(side)")}
        }
        guard follicles.count>600,valid(foot),valid(groom),valid(wingMesh) else {throw Fail("Broken feather mesh or normals")}
        print("PASS: \(follicles.count) body follicles; both folded wings and rectrices; eight claws on unchanged bark")
    }
}
