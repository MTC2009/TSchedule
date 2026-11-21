#ifndef XIAOBAO_SKY_LIGHTING_H
#define XIAOBAO_SKY_LIGHTING_H
#include "SkyField.h"

inline float stars(float3 ray) {
    const float2 p = (ray.xy / max(0.6f, ray.z)) * 86.0f + 234.0f;
    float2 cell = floor(p);
    uint seed = skyHash(uint3(uint2(cell), 692u));
    float intensity = float((seed >> 16) & 255u) / 255.0f;
    if (intensity < 0.945f) return 0.0f;
    float2 point = 0.22f + float2(seed & 255u, (seed >> 8) & 255u) * (0.57f / 255.0f);
    float radius = 0.020f + 0.057f * smoothstep(0.965f,1.0f,intensity);
    float d = length(fract(p) - point);
    return (1.0f - smoothstep(radius, radius + 0.090f, d)) * smoothstep(0.938f,1.0f,intensity) * 0.60f;
}

inline float moonDisk(float3 ray, float3 light, float radius) {
    float3 tangent = normalize(cross(float3(0,1,0), light));
    float3 bitangent = cross(light, tangent);
    float2 uv = float2(dot(ray, tangent), dot(ray, bitangent)) / radius;
    float radius2 = dot(uv, uv);
    float edge = 1.0f - smoothstep(0.93f,1.04f,radius2);
    if (edge <= 0.0f || dot(ray,light) < 0.0f) return 0.0f;
    float gn = valueNoise(float3(uv * 4.2f + 8.0f, 2.7f), 16);
    float fine = valueNoise(float3(uv * 15.0f + 22.0f, 8.9f), 32);
    const float2 mareP = uv + float2(0.31f,-0.08f);
    const float2 mareQ = uv - float2(0.32f,0.30f);
    float mare = (0.28f * exp(-dot(mareP,mareP) * 4.6f) + 0.27f * exp(-dot(mareQ,mareQ) * 6.0f))
                 * smoothstep(0.21f,0.66f,gn);
    return edge * (0.79f + 0.21f * sqrt(saturate(1.0f - radius2))) * (0.69f + gn * 0.20f + fine * 0.11f - mare);
}

inline float3 backgroundLight(float3 ray, constant SkyUniforms &u) {
    float horizon = saturate(pow(saturate(ray.y * 1.48f),0.91f));
    float3 color = mix(u.skyBottom.rgb, u.skyMiddle.rgb, smoothstep(0.0f,0.57f,horizon));
    color = mix(color, u.skyTop.rgb, smoothstep(0.19f,0.98f,horizon));
    float daylight = u.clock.x;
    float sunDot = saturate(dot(ray,u.sun.xyz));
    color += u.sunlight.rgb * (pow(sunDot,12.0f) * 0.14f + pow(sunDot,80.0f) * 0.23f)
               * daylight * (1.0f - u.weather.y);
    if (daylight < 0.44f) {
        float night = 1.0f - smoothstep(0.015f,0.44f,daylight);
        float moonDot = saturate(dot(ray,u.moon.xyz));
        color += u.moonlight.rgb * (0.044f * pow(moonDot,23.0f) + 0.12f * pow(moonDot,680.0f)
                + 1.27f * moonDisk(ray,u.moon.xyz,u.moon.w)) * night * (1.0f - u.weather.z * 0.76f);
        color += stars(ray) * u.moonlight.rgb * night * (1.0f - u.weather.z) * 0.62f;
    }
    return color;
}

inline float shadowDepth(float3 p, float3 light, CloudField f, texture3d<half> field, texture3d<half> noise) {
    // Integrate toward the rising light. Thin edges transmit strongly; thick cores stay shadowed.
    const float4 offsets = float4(0.35f,0.94f,1.86f,3.24f);
    const float4 lengths = float4(0.48f,0.78f,1.10f,1.67f);
    float depth = 0;
    for (uint i = 0; i < 4; ++i) {
        depth += cloudDensity(p + light * offsets[i], f, field, noise, false) * lengths[i];
    }
    return depth;
}
#endif
