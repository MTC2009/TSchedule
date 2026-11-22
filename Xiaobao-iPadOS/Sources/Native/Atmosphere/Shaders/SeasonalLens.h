#ifndef TSCHEDULE_SEASONAL_LENS_H
#define TSCHEDULE_SEASONAL_LENS_H
// Thin-lens circle of confusion in pixels. Rendering and selection keep separate
// notions of depth: the photograph may bloom, but neither blur nor glow is pickable.
struct LensSample {float4 surface;float coverage;float3 halo;};
inline LensSample seasonalLens(texture2d<half> scene,uint2 pixel,float4 center,float2 uv,float aspect,float2 lens) {
    int2 extent=int2(scene.get_width(),scene.get_height())-1,p=int2(pixel);
    float yaw=0.118*(1-smoothstep(0.6f,1.32f,aspect));
    float rayZ=rsqrt(1+pow((uv.x-0.5)*0.86*aspect+yaw,2.0f)+pow(0.102+(1-uv.y)*0.86,2.0f));
    float factor=49.0f*float(extent.y+1)/675.0f;
    float radius=center.w>0 ? clamp(factor*abs(1/(center.w*rayZ)-1/lens.x),0.0f,6.4f) : 0;
    LensSample out={center,center.w>0 ? 1.0f : 0.0f,float3(0)};
    const float2 disk[12]={float2(0.26,0.10),float2(-0.29,0.21),float2(0.05,-0.40),float2(0.35,0.47),
        float2(-0.56,-0.17),float2(0.61,-0.33),float2(-0.19,0.70),float2(-0.34,-0.70),
        float2(0.80,0.21),float2(-0.77,0.45),float2(0.36,-0.87),float2(0.21,0.95)};
    float reference=center.w;
    // Sky pixels only gather if geometry abuts them; never blur the existing sky or moon.
    if(center.w==0) {
        for(uint j=0;j<4;j++) {
            int2 q=clamp(p+int2(disk[j+8]*5.4),int2(0),extent);
            float r=float(scene.read(uint2(q)).w);
            if(r>0) {radius=max(radius,min(6.4f,factor*abs(1/(r*rayZ)-1/lens.x)));reference=max(reference,r);}
        }
    }
    if(radius>0.7) {
        float3 sum=center.rgb;float total=center.w>0 ? 1 : 0, count=1, covered=total,nearest=center.w;
        constexpr sampler lensSampler(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 texel=1.0f/float2(extent+1);
        for(uint j=0;j<24;++j) {
            float2 aperture=disk[j%12];
            if(j>=12) aperture=float2(-aperture.y,aperture.x)*0.88;
            float4 s=float4(scene.sample(lensSampler,uv+aperture*radius*texel));
            // Continuous aperture coverage at a backlit twig; rounding each sample to
            // a pixel produces displaced copies of the twig rather than a defocused edge.
            if(s.w>0.65*reference && s.w+0.12<reference && factor*abs(1/(s.w*rayZ)-1/lens.x)<radius*0.42) continue;
            count+=1;
            if(s.w>0) {
                covered+=1;
                float weight=saturate(s.w/max(0.1f,reference));
                sum+=s.rgb;total+=weight;
                nearest=nearest>0 ? min(nearest,max(reference*0.65,s.w)) : max(reference*0.65,s.w);
            }
        }
        if(total>0) {out.surface=float4(sum/total,center.w>0 ? center.w : nearest);out.coverage=covered/count;}
    }
    if(lens.y>0) {
        float3 glare=0;
        for(uint j=0;j<12;++j) {
            int2 q=clamp(p+int2(round(disk[j]*6.3*float(extent.y+1)/675.0)),int2(0),extent);
            float3 s=float3(scene.read(uint2(q)).rgb);float peak=max(s.x,max(s.y,s.z));
            glare+=s*(max(peak-0.85f,0.0f)/(1.0f+peak));
        }
        out.halo=glare*0.023;
    }
    return out;
}
#endif
