#include "SkyField.h"
#include "SkyLighting.h"
#include "SeasonalMaterials.h"
#include "SeasonalLens.h"

struct SkyVertex {
    float4 position [[position]];
    float2 uv;
};

vertex SkyVertex skyVertex(uint index [[vertex_id]]) {
    float2 clip = (index == 0 ? float2(-1,-1) : (index == 1 ? float2(3,-1) : float2(-1,3)));
    return SkyVertex{ float4(clip,0,1), float2((clip.x + 1.0f) * 0.5f, (1.0f - clip.y) * 0.5f) };
}

struct IntegratedSky { float3 rgb; float trans; };
inline float3 skyShoulder(float3 hdr) {
    return hdr/(1+0.68f*max(max(hdr.r,max(hdr.g,hdr.b))-0.78f,0.0f));
}

inline IntegratedSky integrateSky(SkyVertex in, constant SkyUniforms &u,
                                  texture3d<half> field,texture3d<half> noise,float4 surface,float coverage=1) {
    const float span = 0.86f;
    float horizontal = span * u.viewport.x;
    float cameraYaw = 0.118f * (1.0f - smoothstep(0.6f,1.32f,u.viewport.x));
    float3 ray = normalize(float3((in.uv.x - 0.5f) * horizontal + cameraYaw, 0.102f + (1.0f - in.uv.y) * span, 1.0f));
    float3 sky = backgroundLight(ray,u);
    CloudField cloud = cloudField(u);
    float start = max(0.0f,(0.91f-u.camera.y)/ray.y);
    float end = min(44.5f, (9.15f-u.camera.y)/ray.y);
    float step = (end - start) / u.viewport.y;
    if (surface.w>0) end = min(end,surface.w);
    // Most jitter is spatially smooth; a small fixed per-pixel term breaks visible integration
    // planes without letting static backgrounds glitter or creating visible daylight grain.
    float phase = 0.25f + 0.32f * valueNoise(float3(in.uv * 58.0f,6.2f),64)
                         + 0.18f * skyRandom(uint3(uint2(in.position.xy),97u));
    float arrival = start + step * phase;
    float day = u.clock.x;
    float mixLight = smoothstep(0.10f, 0.78f, day);
    float3 lamp = normalize(mix(u.moon.xyz,u.sun.xyz,mixLight));
    float cosAngle = max(0.0f, dot(ray,lamp));
    float rim = 0.85f + 0.62f * pow(cosAngle,5.0f);
    float3 ambient = mix(u.skyMiddle.rgb * float3(0.92f,1.10f,1.29f),u.cloudAmbient.rgb * 0.77f,day);
    ambient *= 1.0f - 0.47f * u.weather.y;
    float3 lampTint = mix(u.moonlight.rgb * float3(0.075f,0.110f,0.173f),u.sunlight.rgb * u.sun.w,day);
    lampTint *= 1.0f - 0.89f * u.weather.y;
    float3 scattered = 0;
    float transmittance = 1.0f;
    float cirrus = cirrusDensity(ray,cloud,noise);
    sky = mix(sky, ambient * 0.64f + lampTint * (0.82f + 0.36f * cosAngle), cirrus);

    for (uint i = 0, budget = uint(u.viewport.y); i < budget && arrival < end; ++i, arrival += step) {
        float3 p = u.camera.xyz + ray * arrival;
        float density;
        if (budget >= 80 && step > 0.19f) {
            // Integrate both sides of longer intervals to avoid striping where the camera
            // looks nearly along the underside of a deck. Shadowing still runs once here.
            float3 substep = ray * step * 0.235f;
            density = 0.5f * (cloudDensity(p - substep, cloud, field, noise, true)
                          + cloudDensity(p + substep, cloud, field, noise, true));
        } else {
            density = cloudDensity(p, cloud, field, noise, true);
        }
        if (u.pointColor.w>0.001) {
            // The spent burst illuminates a short-lived volume in the same integration
            // domain as the clouds. Only the firework scene supplies a smoke density.
            float3 q=(p-u.pointLight.xyz)/2.4; float r2=dot(q,q);
            if(r2<1.65) {
                float4 filaments=grain(noise,q*0.38+float3(0.33,0.18-u.clock.z*0.009,0.62));
                density+=exp(-2.3*r2)*smoothstep(0.31f,0.77f,filaments.b+0.21*filaments.r)*0.22*u.pointColor.w;
            }
        }
        if (density < 0.009f) continue;
        float alpha = 1.0f - exp(-density * (surface.w>0 ? min(step,end-arrival) : step) * 1.64f);
        float depth = shadowDepth(p,lamp,cloud,field,noise) * 1.57f;
        float direct = exp(-depth) * rim + 0.28f * exp(-0.36f * depth);
        float height = smoothstep(1.15f, 7.3f,p.y);
        float3 light = ambient * mix(0.52f,1.05f,height) + direct * lampTint;
        float distanceHaze = (1.0f - exp(-arrival * (0.010f + 0.017f * u.weather.z)));
        light = mix(light,sky,distanceHaze * (0.44f + 0.13f * day));
        if (u.pointLight.w>0) {
            float3 delta=p-u.pointLight.xyz;
            light+=u.pointColor.rgb*(u.pointLight.w/(0.48f+dot(delta,delta)));
        }
        scattered += light * alpha * transmittance;
        transmittance *= (1.0f - alpha);
        if (transmittance < 0.014f) break;
    }

    float3 hdr = scattered + (surface.w>0 ? mix(sky,surface.rgb,coverage) : sky) * transmittance;
    // Keep form in sunlit cloud rims and in the moon rather than hard-clipping highlights.
    return {skyShoulder(hdr),transmittance};
}

fragment float4 skyFragment(SkyVertex in [[stage_in]], constant SkyUniforms &u [[buffer(0)]],
                            texture3d<half> field [[texture(0)]], texture3d<half> noise [[texture(1)]]) {
    return float4(integrateSky(in,u,field,noise,float4(0)).rgb,1);
}

struct SeasonalComposite { float4 color [[color(0)]]; half2 pick [[color(1)]]; };
fragment SeasonalComposite seasonalSkyFragment(SkyVertex in [[stage_in]],constant SkyUniforms &u [[buffer(0)]],
                             texture3d<half> field [[texture(0)]],texture3d<half> noise [[texture(1)]],
                             texture2d<half> geometry [[texture(2)]],
                             texture2d<uint,access::read> ids [[texture(3)]],constant float2 &lens [[buffer(1)]]) {
    uint2 px=uint2(in.position.xy);
    float4 surface; LensSample sample; uint object;float pickRange=0;
    if(geometry.get_width()==uint(u.viewport.z)*2u) {
        uint2 base=px*2u;float4 sum=0;float count=0;uint tag[4];float ranges[4];
        for(uint j=0;j<4;j++) {
            uint2 q=base+uint2(j&1u,j>>1);float4 s=float4(geometry.read(q));
            tag[j]=s.w>0 ? ids.read(q).r : 0u;ranges[j]=s.w;
            if(s.w>0){sum+=s;count+=1;}
        }
        surface=sum/max(1.0f,count);
        sample=seasonalLens(geometry,base+1u,surface,in.uv,u.viewport.x,lens);
        // Never mix clear-sky zero distance into a feather's optical range.
        if(count>0) sample.coverage*=count*0.25f;
        // An insect or droplet against water has two different IDs and ranges.
        // Resolve the majority surface; ties belong to the nearer visible object.
        object=0;uint best=1;
        for(uint j=0;j<4;j++) if(tag[j]!=0u) {
            uint n=0;float d=0;
            for(uint k=0;k<4;k++) if(tag[j]==tag[k]) {n++;d+=ranges[k];}
            if(n>=2u && (n>best || (n==best && d/float(n)<pickRange))) {best=n;object=tag[j];pickRange=d/float(n);}
        }
    } else {
        surface=float4(geometry.read(px));object=ids.read(px).r;
        sample=seasonalLens(geometry,px,surface,in.uv,u.viewport.x,lens);
    }
    if(object==0 || pickRange<=0) pickRange=surface.w;
    // Grounded illustration is in front of the atmospheric deck. Lighting may
    // still depend on clouds; scattering must never fill an opaque wall. Genuine
    // openings continue the complete sky ray. Airborne actors keep volumetric depth.
    bool foreground=sample.surface.w>0 && sample.surface.w<=u.camera.w;
    if(foreground && surface.w>0 && sample.coverage>=0.999f)
        return {float4(skyShoulder(sample.surface.rgb)+sample.halo,1),half2(half(object),half(pickRange))};
    IntegratedSky sky;
    if(foreground) {
        sky=integrateSky(in,u,field,noise,float4(0));
        sky.rgb=mix(sky.rgb,skyShoulder(sample.surface.rgb),sample.coverage);
        if(surface.w>0) sky.trans=1;
    } else {sky=integrateSky(in,u,field,noise,sample.surface,sample.coverage);}
    sky.rgb+=sample.halo*sky.trans;
    uint visible=(surface.w>0 && sky.trans>0.20f) ? object : 0u;
    return {float4(sky.rgb,1),half2(half(visible),half(pickRange))};
}
