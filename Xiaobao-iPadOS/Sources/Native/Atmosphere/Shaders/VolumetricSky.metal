#include "SkyField.h"
#include "SkyLighting.h"

struct SkyVertex {
    float4 position [[position]];
    float2 uv;
};

vertex SkyVertex skyVertex(uint index [[vertex_id]]) {
    float2 clip = (index == 0 ? float2(-1,-1) : (index == 1 ? float2(3,-1) : float2(-1,3)));
    return SkyVertex{ float4(clip,0,1), float2((clip.x + 1.0f) * 0.5f, (1.0f - clip.y) * 0.5f) };
}

fragment float4 skyFragment(SkyVertex in [[stage_in]],
                           constant SkyUniforms &u [[buffer(0)]],
                           texture3d<half> field [[texture(0)]],
                           texture3d<half> noise [[texture(1)]]) {
    const float span = 0.86f;
    float horizontal = span * u.viewport.x;
    float cameraYaw = 0.118f * (1.0f - smoothstep(0.6f,1.32f,u.viewport.x));
    float3 ray = normalize(float3((in.uv.x - 0.5f) * horizontal + cameraYaw, 0.102f + (1.0f - in.uv.y) * span, 1.0f));
    float3 sky = backgroundLight(ray,u);
    CloudField cloud = cloudField(u);
    float start = 0.91f / ray.y;
    float end = min(44.5f, 9.15f / ray.y);
    float step = (end - start) / u.viewport.y;
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
        float3 p = ray * arrival;
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
        if (density < 0.009f) continue;
        float alpha = 1.0f - exp(-density * step * 1.64f);
        float depth = shadowDepth(p,lamp,cloud,field,noise) * 1.57f;
        float direct = exp(-depth) * rim + 0.28f * exp(-0.36f * depth);
        float height = smoothstep(1.15f, 7.3f,p.y);
        float3 light = ambient * mix(0.52f,1.05f,height) + direct * lampTint;
        float distanceHaze = (1.0f - exp(-arrival * (0.010f + 0.017f * u.weather.z)));
        light = mix(light,sky,distanceHaze * (0.44f + 0.13f * day));
        scattered += light * alpha * transmittance;
        transmittance *= (1.0f - alpha);
        if (transmittance < 0.014f) break;
    }

    float3 hdr = scattered + sky * transmittance;
    // Keep form in sunlit cloud rims and in the moon rather than hard-clipping highlights.
    float shoulder = max(max(hdr.r,max(hdr.g,hdr.b)) - 0.78f, 0.0f);
    return float4(hdr / (1.0f + 0.68f * shoulder),1.0f);
}
