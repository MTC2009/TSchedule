#ifndef XIAOBAO_SKY_FIELD_H
#define XIAOBAO_SKY_FIELD_H
#include <metal_stdlib>
using namespace metal;

constant float3 fieldMin = float3(-28.0, 0.72, 1.0);
constant float3 fieldSpan = float3(56.0, 8.7, 55.0);
constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler noiseSampler(coord::normalized, address::repeat, filter::linear);

struct SkyUniforms {
    float4 viewport; // aspect, steps, width, height
    float4 clock;    // daylight, twilight, elapsed motion seconds, cloud optical strength
    float4 weather;  // cover, dimming, veil, signed wind
    float4 sun;      // direction and intensity
    float4 moon;     // direction and angular radius
    float4 skyTop;
    float4 skyMiddle;
    float4 skyBottom;
    float4 sunlight;
    float4 moonlight;
    float4 cloudAmbient; // rgb at noon; colder fill at night is derived from the sky
    float4 camera;       // test camera origin; the shipping camera stays still
    float4 pointLight;   // local seasonal source, xyz world location + radiant strength
    float4 pointColor;
    float4 waveContact;  // world-space water contact + age; -1 when inactive
};

inline uint skyHash(uint3 p) {
    uint n = p.x * 0x9e3779b9u + p.y * 0x85ebca6bu + p.z * 0xc2b2ae35u;
    n = (n ^ (n >> 16)) * 0x7feb352du;
    n = (n ^ (n >> 15)) * 0x846ca68bu;
    return n ^ (n >> 16);
}

inline float skyRandom(uint3 p) {
    return float(skyHash(p) >> 8) * (1.0f / 16777216.0f);
}

inline float valueNoise(float3 p, uint frequency) {
    uint3 cell = uint3(floor(p));
    float3 f = fract(p);
    f = f * f * (3.0f - f * 2.0f);
    uint m = frequency - 1u;
    float4 a, b;
    for (uint y = 0; y < 2; ++y) {
        for (uint x = 0; x < 2; ++x) {
            uint i = y * 2 + x;
            a[i] = skyRandom((cell + uint3(x,y,0)) & m);
            b[i] = skyRandom((cell + uint3(x,y,1)) & m);
        }
    }
    float4 v = mix(a,b,f.z);
    return mix(mix(v.x,v.y,f.x), mix(v.z,v.w,f.x), f.y);
}

inline float cellNoise(float3 p, int cells) {
    int3 baseCell = int3(floor(p));
    float3 f = fract(p);
    float nearest = 2.0f;
    for (int z = -1; z <= 1; ++z) {
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                int3 q = int3(x,y,z);
                uint3 cell = uint3((baseCell + q + cells) & (cells - 1));
                uint h = skyHash(cell);
                float3 feature = float3(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u) / 255.0f;
                float3 delta = float3(q) + feature - f;
                nearest = min(nearest, dot(delta, delta));
            }
        }
    }
    return 1.0f - saturate(sqrt(nearest) * 0.92f);
}

// Spherical growth cells, not silhouettes. The scalar field starts below the lower deck
// and extends well behind the main cloud banks, so view rays see thickness and occlusion.
struct GrowthCell { float3 center; float3 radius; };
constant GrowthCell growthCells[] = {
    {float3(-10.0, 2.15, 19.1), float3(7.8, 1.62, 5.2)},
    {float3(-7.55, 3.68, 19.9), float3(3.8, 2.00, 3.8)},
    {float3(-5.20, 4.63, 18.1), float3(2.10, 1.98, 2.50)},
    {float3(-3.30, 3.96, 20.4), float3(2.25, 1.89, 2.95)},
    {float3(-1.15, 2.45, 23.2), float3(5.55, 1.50, 5.5)},
    {float3(-1.30, 4.90, 19.0), float3(2.85, 2.08, 3.35)},
    {float3( 0.75, 5.28, 19.8), float3(2.45, 1.98, 3.21)},
    {float3(-1.22, 3.17, 13.1), float3(2.90, 1.36, 3.27)},
    {float3(-1.08, 4.82, 13.7), float3(1.87, 1.97, 2.28)},
    {float3(-2.57, 4.31, 14.9), float3(1.75, 1.36, 2.05)},
    {float3( 2.65, 3.28, 21.8), float3(3.30, 2.08, 4.15)},
    {float3( 4.80, 2.12, 14.3), float3(6.4, 1.46, 5.7)},
    {float3( 5.20, 3.76, 14.1), float3(3.75, 2.32, 4.85)},
    {float3( 7.35, 4.78, 13.3), float3(3.28, 2.28, 3.60)},
    {float3( 7.95, 5.80, 12.55),float3(1.80, 1.76, 2.20)},
    {float3( 6.99, 5.63, 13.95),float3(2.20, 1.75, 2.20)},
    {float3( 9.80, 3.85, 11.2), float3(3.90, 2.25, 3.20)},
    {float3( 6.60, 5.02, 15.7), float3(1.95, 1.85, 2.35)},
    {float3( 5.65, 4.98, 17.1), float3(2.47, 1.30, 2.85)},
    {float3(14.00, 3.36, 22.0), float3(7.9, 2.35, 6.8)},
    {float3(-19.0, 2.20, 24.3), float3(8.8, 2.0, 6.7)},
    {float3(-13.0, 3.40, 30.9), float3(7.0, 2.3, 6.7)},
    {float3( 1.20, 2.30, 41.0), float3(12.7,1.67,7.6)},
    {float3(11.10, 3.09, 34.0), float3(8.2,2.05,6.1)}
};

kernel void buildSkyField(texture3d<half, access::write> output [[texture(0)]],
                          uint3 gid [[thread_position_in_grid]]) {
    uint3 size = uint3(output.get_width(), output.get_height(), output.get_depth());
    if (any(gid >= size)) return;
    float3 p = fieldMin + (float3(gid) + 0.5f) / float3(size) * fieldSpan;
    float shape = -1.0f;
    for (uint i = 0; i < sizeof(growthCells) / sizeof(GrowthCell); ++i) {
        float3 v = (p * float3(1.22f,1.0f,1.0f) - growthCells[i].center) / growthCells[i].radius;
        float s = (1.0f - length(v));
        // Smooth union avoids spherical overlap seams while retaining separate updraft lobes.
        const float smoothness = 0.17f;
        float overlap = max(smoothness - abs(s - shape), 0.0f) / smoothness;
        shape = max(shape,s) + overlap * overlap * (0.25f * smoothness);
    }
    output.write(half4(half(clamp(shape,-1.0f,1.0f)),0,0,0), gid);
}

kernel void buildSkyNoise(texture3d<half, access::write> output [[texture(0)]],
                          uint3 gid [[thread_position_in_grid]]) {
    uint3 size = uint3(output.get_width(), output.get_height(), output.get_depth());
    if (any(gid >= size)) return;
    float3 p = (float3(gid) + 0.5f) / float3(size);
    float puffy = 0.71f * cellNoise(p * 8.0f, 8) + 0.29f * cellNoise(p * 16.0f, 16);
    float erosion = 0.58f * cellNoise(p * 16.0f + 5.0f, 16) + 0.42f * valueNoise(p * 32.0f, 32);
    float billow = 0.55f * valueNoise(p * 4.0f, 4) + 0.30f * valueNoise(p * 8.0f, 8)
                 + 0.15f * valueNoise(p * 16.0f, 16);
    float grit = valueNoise(p * 32.0f + 11.0f, 32);
    output.write(half4(puffy, erosion, billow, grit), gid);
}

struct CloudField {
    float cover;
    float weight;
    float sheet;
    float gust;
    float seconds;
    float briefGrowth;
};
inline CloudField cloudField(constant SkyUniforms &u) {
    float cover = u.weather.x;
    return CloudField{cover, smoothstep(0.08f,0.59f,cover), smoothstep(0.53f,0.96f,cover),
                      u.weather.w, u.clock.z, u.clock.w};
}

inline float cloudDensity(float3 p, CloudField f, texture3d<half> field, texture3d<half> noise, bool fine) {
    // Different altitudes advect at different speeds. Two non-parallel flows plus time-changing
    // erosion split and grow individual cloud lobes; there is no screen-space image translation.
    float drift = f.seconds * (0.080f + 0.062f * abs(f.gust));
    float slope = smoothstep(1.2f,8.0f,p.y);
    float direction = f.gust < -0.05f ? -1.0f : 1.0f;
    float3 q = p + float3(
        -direction * ((0.51f + slope * 0.47f) * sin(drift * 0.26f) * 5.3f
              + 0.19f * sin(p.z * 0.30f + drift * 0.71f)),
        0.26f * sin(p.x * 0.18f + p.z * 0.14f + drift * 0.88f),
        0.61f * sin(drift * 0.23f + p.x * 0.12f));
    float3 v = (q - fieldMin) / fieldSpan;
    float signedShape = float(field.sample(fieldSampler, v).r);
    float bounds = smoothstep(0.0f, 0.065f, min(min(v.x,1.0f - v.x), min(v.z,1.0f - v.z)));
    float base = smoothstep(0.94f, 1.95f, p.y);
    float upper = 1.0f - smoothstep(7.6f,9.1f,p.y);
    const float3x3 turn = float3x3(float3(0.881f,0.331f,-0.339f),
                                   float3(-0.402f,0.900f,-0.169f),
                                   float3(0.249f,0.284f,0.926f));
    float3 uv = (turn * q) * 0.104f;
    float4 n = float4(noise.sample(noiseSampler, uv + float3(-0.061f, 0.027f, 0.033f) * drift));
    float edge = (n.r - 0.50f) * 1.04f + (n.b - 0.49f) * 0.48f;
    float inhale = 0.088f * sin(p.x * 0.68f + p.z * 0.32f - drift * 1.90f);
    float towerShape = signedShape + edge + inhale - 0.70f * (1.0f - f.weight);
    float tower = smoothstep(-0.029f,0.34f,towerShape) * (0.61f + 0.60f * n.r);
    float sheetBand = smoothstep(1.12f,2.55f,p.y) * (1.0f - smoothstep(2.98f,4.8f,p.y));
    float deck = f.sheet * sheetBand * (0.18f + smoothstep(0.32f,0.70f, n.b * 0.62f + n.r * 0.38f) * 0.82f);
    float body = max(tower, deck) * base * upper * bounds;
    if (body <= 0.003f) return 0.0f;
    if (fine) {
        float3 erodeUV = uv.yzx * 2.24f + float3(0.71f,0.05f,0.22f)
                       + float3(0.12f,-0.033f,-0.082f) * drift;
        float4 d = float4(noise.sample(noiseSampler, erodeUV));
        float edgeWeight = 1.0f - saturate(body);
        body += ((d.g - 0.52f) * 0.57f + (d.a - 0.52f) * 0.21f) * (0.51f + edgeWeight * 0.49f);
    }
    return saturate(body) * (0.15f + 0.85f * f.weight) * f.briefGrowth;
}

inline float cirrusDensity(float3 ray, CloudField f, texture3d<half> noise) {
    // A sparse field at another altitude, stretched diagonally by high-altitude shear.
    // The projection comes from the view ray, not the screen UV.
    float3 p = ray * (10.5f / max(0.2f,ray.y));
    float t = f.seconds;
    float3 v = float3(p.x * 0.048f + p.z * 0.012f, p.y * 0.055f, p.z * 0.102f - p.x * 0.032f);
    v += float3(0.086f * sin(p.z * 0.36f + p.x * 0.26f),
                0.083f * sin(p.x * 0.55f - t * 0.05f),
                0.051f * sin(p.x * 0.41f + p.z * 0.3f + t * 0.06f));
    v += t * float3(-0.0016f,0.0014f,0.00081f);
    float4 n = float4(noise.sample(noiseSampler, v));
    float coarse = float(noise.sample(noiseSampler, p * 0.058f + float3(0.26f,0.17f,0.42f)).b);
    float density = smoothstep(0.50f,0.81f,n.b * 0.47f + n.r * 0.53f) * smoothstep(0.48f,0.76f,coarse);
    return density * (0.24f + f.cover * 0.33f) * smoothstep(0.13f,0.39f,ray.y) * (1.0f - f.sheet * 0.68f);
}
#endif
