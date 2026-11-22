#ifndef TSCHEDULE_SEASONAL_SURFACE_H
#define TSCHEDULE_SEASONAL_SURFACE_H

// Matches SeasonalFinish. Coordinates are attached to the specimen, not the screen.
enum Finish : uint { Matte, Foliage, Dew, Gourd, Paper, Water, Soil, Bark, Alloy, Fur, Plumage, Petal,
    Shell, Feather, Cloth, Stone, Glaze, Glass, Snow, Hide, Skin, Awn, Tile, Pinna, Membrane, Wax, FeatherBody, Caribou, Hair, LeafPad, Ember, Canopy, Timber, Masonry, Squash, Magpie, Paddler,
    SparrowDown, SparrowVane, SparrowHorn, SparrowTarsus, Cornea, WinterTwig, CutInk, LotusSilk, CarvedInk, BambooFibre };

struct SeasonalBRDF { float3 base; float rough, metal, through, fuzz, height, emission; };
inline float band(float phase,float width) {
    float footprint=max(0.001f,fwidth(phase)), d=abs(fract(phase+0.5f)-0.5f);
    return (1-smoothstep(width*0.45f,width+footprint,d))*(1-smoothstep(0.32f,0.83f,footprint));
}
inline float4 grain(texture3d<half> volume,float3 p) { return float4(volume.sample(noiseSampler,p,level(0))); }
inline float poreNoise(texture3d<half> volume,float3 p) { return grain(volume,p).a; }
#include "SeasonalPlumage.h"

inline SeasonalBRDF specimenSurface(uint k,float3 p,float2 uv,float seed,float3 albedo,float emission,
                                    float3 view,float3 normal,texture3d<half> noise) {
    if(k>=SparrowDown && k<=WinterTwig) return sparrowSurface(k,p,uv,albedo,noise);
    float3 coord=p+float3(seed*3.72,seed*1.87,seed*5.23);
    float4 patch=grain(noise,coord*0.46), fine=grain(noise,coord*2.6+0.19);
    float broad=patch.b-0.50, grit=fine.a-0.50;
    SeasonalBRDF m={albedo*(0.95+0.18*broad),0.66,0,0,0,0.002*grit,emission};
    float w=cos(uv.x*6.2831853), a=abs(w), t=uv.y;
    if(k==Foliage || k==LeafPad) {
        float crossVein=band(9.9*t-1.78*pow(a+0.002,0.62f)+0.33*w+0.15*broad,0.036);
        float mid=exp(-31*a), edge=pow(a,12.0f);
        float links=band(26*t+1.31*w+0.31*sin(8*w+15*t)+0.52*fine.b,0.043)
                   *band(11.7*w-5.7*t+0.48*patch.r,0.25);
        if(k==LeafPad) {mid=band(uv.x*16+0.13*sin(26*t),0.035);crossVein=band(uv.x*62+3*t+0.22*patch.r,0.05);edge=smoothstep(0.85f,1.0f,length(p.xz));}
        float veins=saturate(mid+0.63*crossVein*(1-mid)+0.27*links);
        float speck=smoothstep(0.68f,0.79f,patch.a+0.17*grit);
        m.base*=float3(0.81,0.84,0.75)+float3(0.65,0.42,0.38)*patch.b;
        m.base=mix(m.base,m.base*float3(1.84,1.21,0.66),saturate(edge*0.38+speck*0.34));
        m.base=mix(m.base,m.base*1.35+float3(0.063,0.049,0.014),0.66*veins);
        m.rough=0.34+0.25*patch.r+0.09*veins; m.through=0.61-0.28*veins;
        m.height=0.027*mid+0.009*crossVein+0.009*broad+0.0027*grit;
    } else if(k==BambooFibre) {
        // The reverse of a folded wrapper still has *lengthwise* veins. Filter
        // the fine fibres away at a distance; keep the keel and broad washes.
        float x=2.0f*uv.x-1.0f, v=uv.y;
        float ribs=band(8.3f*x+0.37f*sin(v*3.1f+1.6f*x)+0.11f*broad,0.062f);
        float keel=exp(-32.0f*abs(x-0.052f*sin(3*v))), lip=pow(min(1.0f,abs(x)),8.0f);
        m.base*=0.83f+0.17f*smoothstep(0.1f,0.86f,v)+0.12f*broad;
        m.base=mix(m.base,m.base*float3(1.39f,1.22f,0.91f)+float3(0.014f,0.012f,0.003f),
                   0.78f*keel+0.34f*ribs+0.24f*lip);
        m.height=0.006f*keel+0.001f*ribs;m.rough=0.56f+0.13f*patch.b;m.through=0.27f;
    } else if(k==LotusSilk) {
        // Ink collects at the upper lip; the broad inner field stays milky.
        // A handful of branching veins disappear below a pixel instead of moiré.
        float rim=smoothstep(0.62f,0.98f,t+0.11f*a+0.05f*broad);
        float vein=band(w*(2.0f+2.8f*t)+0.23f*sin(3.8f*t+2.4f*w)+0.28f*broad,0.038f);
        m.base=mix(albedo*float3(1.06,1.025,0.97),albedo*float3(1.14,0.68,0.79),rim*0.87);
        m.base*=0.985f+0.035f*broad-0.061f*vein*smoothstep(0.13f,0.69f,t);
        m.height=0.00045f*vein+0.00034f*grit;m.rough=0.62f;m.through=0.43f;
    } else if(k==Petal || k==Pinna || k==Membrane) {
        float veins=band((k==Membrane ? 11.0f : 7.0f)*w+0.91*sin(3.7*t+w)+0.16*fine.b,0.05);
        m.base*=0.85+0.19*t+0.17*broad+0.16*veins;
        if(k==Pinna) {
            float bowl=(1-smoothstep(0.48f,0.85f,a))*smoothstep(0.07f,0.33f,t)*(1-smoothstep(0.87f,1.0f,t));
            float front=smoothstep(0.28f,0.65f,-normal.z);
            m.base=mix(m.base,float3(0.51,0.245,0.218)*(1-0.22*veins),bowl*front);
            m.base*=1-0.52*smoothstep(0.84f,1.0f,t);
        } else if(k==Petal) {
            m.base=mix(m.base*float3(0.81,0.67,0.55),m.base*(1+0.20*veins),smoothstep(0.04f,0.77f,t));
        } else {
            m.base=mix(float3(0.29,0.34,0.29),float3(0.09,0.077,0.049),veins*0.82);
        }
        m.height=veins*0.002+0.0015*grit; m.rough=k==Membrane ? 0.21 : 0.51; m.through=k==Membrane ? 0.76 : 0.52;
    } else if(k==Bark || k==Hide || k==Awn) {
        float theta=atan2(p.z,p.x)/6.2831853;
        float cracks=poreNoise(noise,float3(theta*3.4+0.09*patch.b,p.y*0.074+seed,seed));
        float lenticel=smoothstep(0.66f,0.79f,poreNoise(noise,float3(theta*1.9,p.y*2.2,seed*2.7)));
        m.base*=0.61+0.69*patch.b+0.33*cracks+0.13*grit;
        m.base=mix(m.base,m.base*1.36+0.042,lenticel*0.62);
        m.rough=k==Hide ? 0.39 : 0.77; m.height=0.039*(cracks-0.5)+0.018*broad+0.008*lenticel;
        if(k==Awn) { m.fuzz=0.40; m.through=0.32; m.rough=0.64; }
    } else if(k==Fur || k==Hair || k==Caribou || k==FeatherBody || k==Magpie || k==Plumage) {
        float bend=0.31*sin(4.1*p.x+1.9*p.z)+0.23*broad;
        float comb=poreNoise(noise,float3(0.37*p.x+seed,3.9*(p.y+bend),4.3*p.z+0.18*p.x));
        float tufts=poreNoise(noise,float3(p.x*0.22+seed,p.y*1.29+bend,p.z*1.6));
        if(k==Magpie) {
            float belly=(1-smoothstep(-0.07f,0.025f,p.y))*smoothstep(-0.31f,-0.18f,p.x)*(1-smoothstep(0.04f,0.14f,p.x));
            m.base=mix(albedo*float3(0.74,1.04,1.12),float3(0.68,0.69,0.65),belly);
        } else if(k==FeatherBody) {
            float cap=smoothstep(-0.035f,0.106f,p.y+0.016*tufts);
            float bib=smoothstep(0.14f,0.32f,p.x)*(1-smoothstep(0.085f,0.157f,p.y));
            m.base=mix(float3(0.63,0.53,0.40),albedo,cap);m.base=mix(m.base,float3(0.40,0.145,0.060),bib*0.84);
        } else if(k==Caribou) {
            float bib=smoothstep(0.17f,0.27f,p.x)*(1-smoothstep(0.32f,0.42f,p.x));
            m.base=mix(albedo,float3(0.44,0.36,0.25),0.47*bib+0.26*(1-smoothstep(-0.10f,0.04f,p.y)));
        } else if(k==Fur || k==Hair) {
            float saddle=smoothstep(-0.10f,0.23f,p.y+0.10*tufts);
            m.base*=mix(float3(1.03,1.01,0.98),float3(0.73,0.72,0.67),saddle);
        }
        m.base*=0.62+0.46*tufts+0.40*comb; m.rough=0.73; m.fuzz=0.68; m.height=0.005*comb+0.006*tufts;
    } else if(k==Feather) {
        float shaft=exp(-28*a), barbs=band(52*t-11*a+0.41*sin(6*t+w),0.135);
        m.base*=0.67+0.15*patch.b+0.22*barbs+0.31*shaft+0.12*t;
        m.base=mix(m.base,m.base+float3(0.16,0.13,0.08),shaft*0.67);
        m.height=0.025*shaft+0.008*barbs; m.rough=0.47; m.fuzz=0.36;
    } else if(k==Shell || k==Gourd || k==Squash) {
        if(k==Shell) {
            float seam=1-smoothstep(0.001f,0.011f,abs(p.y));
            float line=band(p.y*45+0.54*sin(12*p.x),0.055);
            float edge=1-saturate(dot(normal,view)),hood=smoothstep(0.083f,0.119f,p.x);
            m.base=mix(albedo*float3(0.92,1.23,0.70),float3(0.14,0.17,0.07),edge);
            m.base*=1-0.57*seam*(1-hood);m.base=mix(m.base,float3(0.025,0.043,0.032),0.77*hood);
            m.rough=0.22+0.10*fine.r; m.metal=0.43; m.height=(line*0.003-seam*0.013)*(1-hood)+0.003*grit;
        } else {
            float angle=atan2(p.z,p.x),rib=0.5+0.5*cos(11*angle+0.24*sin(4*p.y));
            m.base*=0.71+0.31*pow(rib,0.67f)+0.27*patch.b+0.13*grit;
            m.rough=0.52+0.17*patch.b; m.height=0.018*patch.r+0.012*grit;
        }
    } else if(k==Alloy || k==Glaze || k==Glass || k==Dew) {
        m.rough=(k==Alloy ? 0.27+0.19*patch.r : (k==Glaze ? 0.19 : 0.061));
        m.metal=k==Alloy ? 0.87 : 0; m.height=k==Dew ? 0 : 0.003*grit;
        if(k==Alloy) { float tarnish=smoothstep(0.52f,0.78f,patch.a); m.base*=1-0.37*tarnish; }
    } else if(k==Paper || k==Cloth) {
        float2 weave=k==Paper ? float2(atan2(p.z,p.x)/6.2831853,p.y*0.5) : uv;
        float warp=band(79*weave.x+0.32*patch.b,0.17),weft=band(87*weave.y+0.22*patch.b,0.16);
        float fibre=poreNoise(noise,coord*float3(2.2,0.26,2.0));
        m.base*=0.78+0.27*patch.b+0.14*fibre+0.10*(warp+weft);
        m.height=0.010*(warp+weft)+0.013*fibre; m.through=k==Paper ? 0.63 : 0.09; m.fuzz=k==Cloth ? 0.58 : 0.23;
        if(k==Paper) {
            float radial=atan2(p.z,p.x)/6.2831853;
            float ribs=band(radial*8-0.5,0.054);
            float hot=exp(-2.32*(p.y+0.33)*(p.y+0.33))*(0.78+0.23*cos(6.2831853*(radial*8)))*(1-0.30*ribs);
            m.emission*=(0.36+0.53*patch.b+0.17*fibre)*(0.35+1.72*hot);
            m.base=mix(m.base,m.base*0.70+float3(0.33,0.22,0.075),saturate(0.97*hot*emission));
        }
    } else if(k==Canopy) {
        m.base*=0.48+0.51*patch.r+0.57*fine.g+0.22*grit;
        m.through=0.22;m.rough=0.85;m.height=0.069*patch.r+0.038*fine.g;
    } else if(k==Paddler) {
        float collar=smoothstep(0.151f,0.177f,p.y+0.011*p.x),hairline=smoothstep(0.254f,0.264f,p.y-0.19*p.x);
        float3 skin=float3(0.53,0.286,0.177)*(0.87+0.23*patch.b);
        float stripe=band(p.y*80+0.22*patch.a,0.18);
        m.base=mix(albedo*(0.82+0.29*patch.b+0.11*stripe),skin,collar);
        m.base=mix(m.base,float3(0.041,0.032,0.027),hairline);
        float ribbon=smoothstep(0.255f,0.258f,p.y-0.12*p.x)*(1-smoothstep(0.265f,0.269f,p.y-0.12*p.x));
        m.base=mix(m.base,float3(0.41,0.055,0.042),ribbon);
        m.fuzz=0.37*(1-collar);m.rough=0.60+0.12*(1-collar);m.height=0.0017*grit;
    } else if(k==Timber) {
        float warp=poreNoise(noise,coord*float3(0.23,0.49,0.53));
        float ribbons=poreNoise(noise,float3(coord.x*0.054,coord.y*1.63+warp*0.39,coord.z*1.83));
        float ray=band(p.y*9+p.z*13+warp+0.33*sin(2*p.x),0.12);
        m.base*=0.68+0.54*ribbons+0.35*patch.b-0.18*ray;
        m.height=0.013*ribbons+0.004*ray; m.rough=0.46+0.15*patch.b;
    } else if(k==Masonry) {
        float course=p.y*4.8+0.077*patch.b,cell=p.x*3.8+0.5*fmod(abs(floor(course)),2.0f);
        float mortar=max(band(course,0.039),band(cell+0.068*fine.b,0.033));
        m.base=mix(albedo*(0.69+0.51*patch.b+0.16*grit),albedo*0.56,mortar);m.rough=0.81;m.height=0.021*broad-0.028*mortar;
    } else if(k==Stone || k==Soil || k==Tile) {
        float3 q=k==Soil ? coord*float3(6,1.2,4) : coord;
        float layers=grain(noise,q*0.78).g;
        m.base*=0.65+0.63*layers+0.41*broad+0.23*grit;
        if(k==Tile) {
            float ribs=cos(p.x*3.14159*22),joint=band(abs(p.z)*7+0.13*sin(p.x*31.4),0.044);
            m.base*=0.86+0.19*ribs-0.22*joint; m.height=0.053*ribs-0.019*joint;
        } else {m.height=0.046*layers+0.027*fine.r;}
        m.rough=k==Tile ? 0.46 : 0.86;
    } else if(k==Snow || k==Skin || k==Wax) {
        m.base*=0.93+0.11*patch.b+0.13*grit; m.through=k==Snow ? 0.56 : 0.34; m.rough=k==Wax ? 0.41 : 0.53;
        m.height=k==Snow ? 0.038*fine.r : 0.007*grit;
    } else if(k==Ember) {m.rough=1;}
    return m;
}
#endif
