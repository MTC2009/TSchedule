#ifndef TSCHEDULE_SEASONAL_PLUMAGE_H
#define TSCHEDULE_SEASONAL_PLUMAGE_H

// Linear pigment reflectances, not lit colors. These only mix the strata of this
// specimen; temperature, exposure, shadow, cloud color and reflections remain the sky's.
constant float3 quillUmber = float3(0.074,0.043,0.028);
constant float3 quillSoot = float3(0.029,0.021,0.018);
constant float3 quillRusset = float3(0.430,0.165,0.063);
constant float3 quillWheat = float3(0.635,0.382,0.180);
constant float3 quillIvory = float3(0.69,0.603,0.459);
constant float3 quillAsh = float3(0.549,0.515,0.451);

inline float sparrowRand(float x) { return fract(sin(fmod(x,4091.0f)*47.113f+3.7f)*1873.835f); }
// Each barb has a different pigment and width. Average unresolved barbules to their
// mean instead of letting a high-frequency hatch shimmer at normal iPad scale.
inline float barbTone(float x,float seed) {
    float i=floor(x),f=fract(x);
    float value=mix(sparrowRand(i+seed),sparrowRand(i+1+seed),smoothstep(0.05f,0.93f,f));
    return mix(value,0.5f,smoothstep(0.55f,1.65f,fwidth(x)));
}
inline float sparrowLobe(float2 p,float2 center,float2 axes) {
    float2 q=(p-center)/axes;return 1-smoothstep(0.65f,1.10f,dot(q,q));
}
inline float3 sparrowTracts(float3 p,float coarse,float grain) {
    float x=p.x,y=p.y, edge=(coarse-0.5)*0.040+(grain-0.5)*0.021;
    float capLine=0.481-0.095*(x+0.39)-0.065*smoothstep(-0.35f,-0.20f,x);
    float crown=smoothstep(-0.008f,0.009f,y-capLine+edge);
    float mantle=smoothstep(-0.290f,-0.187f,x+0.36*(y-0.39))*
        smoothstep(0.304f,0.352f,y+0.42*(x+0.22)+edge);
    float cheek=sparrowLobe(p.xy,float2(-0.357,0.399),float2(0.142,0.087));
    float chin=sparrowLobe(p.xy,float2(-0.480,0.398),float2(0.042,0.031))*(1-smoothstep(0.036f,0.124f,abs(p.z)));
    float bridge=saturate((x+0.48)/0.091);
    float lore=(1-smoothstep(0.006f+0.010*bridge,0.013f+0.018*bridge,abs(y-(0.455+0.021*bridge)+edge*0.60)))*
               (1-smoothstep(-0.394f,-0.361f,x));
    float collar=smoothstep(-0.31f,-0.267f,x)*(1-smoothstep(-0.158f,-0.105f,x))*
                 (1-smoothstep(0.009f,0.043f,abs(y-0.358-0.91*(x+0.267)+edge)));
    float3 gray=mix(quillAsh*float3(0.26,0.23,0.18),quillAsh*1.13,smoothstep(-0.177f,0.25f,y)+0.07*(grain-0.50));
    gray=mix(gray,float3(0.83,0.757,0.649),0.85*cheek);
    float3 chestnut=mix(quillRusset*float3(0.63,0.58,0.58),quillRusset*1.27,coarse);
    float forecap=(1-smoothstep(-0.376f,-0.238f,x));
    chestnut*=mix(float3(1.15,1.10,0.98),float3(0.35,0.28,0.23),forecap);
    float patch=valueNoise(61+p*float3(36,63,43),64u);
    float stripe=valueNoise(17+float3(19*x,83*y+47*x,47*abs(p.z)+14*x),64u);
    chestnut=mix(chestnut,quillSoot,smoothstep(0.44f,0.76f,stripe)*(0.51+0.15*forecap));
    chestnut=mix(chestnut,quillWheat*1.14,smoothstep(0.55f,0.88f,patch)*(0.25+0.37*grain));
    chestnut*=mix(float3(1.0),float3(0.83,0.62,0.60),crown*(1-0.52*mantle));
    float3 color=mix(gray,chestnut,max(crown,mantle));
    float orbit=sparrowLobe(p.xy+float2(edge*0.16,edge*0.40),float2(-0.375,0.479),float2(0.049,0.034));
    color=mix(color,mix(quillSoot,quillRusset,0.09+0.14*grain),orbit*0.94);
    // A dark brow continues behind the exposed eye, then breaks into short
    // chestnut malar feathers before reaching the pale nape.
    float brow=sparrowLobe(float2(x,y-0.12*(x+0.369))+edge*0.51,float2(-0.365,0.477),float2(0.079,0.023));
    float malar=sparrowLobe(float2(x+0.47*(y-0.444),y)+edge*0.67,float2(-0.283,0.444),float2(0.016,0.042));
    color=mix(color,mix(quillSoot*0.65,quillRusset*0.52,0.15+0.18*grain),max(0.87*brow,0.79*malar));
    float shoulder=sparrowLobe(float2(x,y+0.31*(x+0.23)),float2(-0.23,0.199),float2(0.174,0.107));
    color=mix(color,chestnut,0.68*shoulder);
    color=mix(color,float3(0.77,0.706,0.60),0.87*collar);
    return mix(color,quillSoot*0.81,saturate(0.96*lore+0.83*chin));
}

// Tangent-space grooves and mottled tips of overlapping down follicles. This field
// shades the gaps between the actual 3-D fans; it has no image, screen or camera UV.
inline float3 sparrowNap(float3 p,float coarse) {
    float cheek=smoothstep(0.27f,0.50f,p.y);
    float breast=(1-smoothstep(-0.45f,-0.22f,p.x))*(1-smoothstep(0.26f,0.44f,p.y));
    float2 dir=normalize(float2(0.91-0.55*breast,-0.42-0.4*breast+0.36*cheek));
    float auricular=sparrowLobe(p.xy,float2(-0.352,0.400),float2(0.14,0.083));
    dir=normalize(mix(dir,normalize(p.xy-float2(-0.391,0.481)+0.0001f),0.56*auricular));
    float across=dot(p.xy,float2(-dir.y,dir.x))+0.56*abs(p.z);
    float along=dot(p.xy,dir)+0.14*abs(p.z);
    float2 tract=float2(across/(0.027-0.011*cheek),along/(0.053-0.024*cheek));
    float3 space=p*float3(17,21,16)+13;
    tract+=float2(valueNoise(space,64u)-0.5,valueNoise(space+7.32,64u)-0.5)*1.35;
    float row=floor(tract.y), t=fract(tract.y);
    float col=tract.x+0.50*fmod(abs(row),2.0f)+0.28*sin(6*row+0.7*tract.x);
    float cell=floor(col), a=fract(col)-0.5,seed=skyRandom(uint3(uint2(cell+256,row+256),31u))*699;
    float r=sparrowRand(seed+4), wire=(t+0.23*abs(a)*abs(a))*(19+7*r)-(6.3+3*r)*abs(a)+0.67*sin(t*3+seed);
    float fil=barbTone(wire,seed),clump=barbTone(wire*0.29,seed+41);
    float reveal=smoothstep(0.05f,0.35f,t)*(1-smoothstep(0.76f,1.0f,t))*(1-smoothstep(0.31f,0.50f,abs(a)));
    // Uninterrupted fine strands cross cell boundaries, keeping the surface soft
    // rather than outlining every short feather as a scale.
    float strand=barbTone(across*(398+118*cheek)+1.11*sin(along*45+across*13)+0.62*coarse,18);
    float nib=smoothstep(0.57f,0.92f,t+0.37*a*a+0.13*(fil-0.5))*(1-smoothstep(0.28f,0.52f,abs(a)));
    return float3(0.5+(fil-0.5)*reveal*0.72+(strand-0.5)*0.62,
                  0.5+(r-0.5)*reveal*0.78+(clump-0.5)*reveal*0.43,
                  nib*r*smoothstep(0.36f,0.49f,p.y+0.33*(p.x+0.25)));
}

inline SeasonalBRDF sparrowSurface(uint k,float3 p,float2 uv,float3 albedo,texture3d<half> noise) {
    float4 patch=grain(noise,p*0.74+0.183), fine=grain(noise,p*4.4+0.317);
    SeasonalBRDF m={albedo,0.68,0,0,0,0,0};
    if(k==SparrowDown || k==SparrowVane) {
        bool vane=k==SparrowVane;
        float id=floor(uv.x*0.25), a=uv.x-(4*id+2);
        float type=floor(uv.y*0.5), t=uv.y-2*type;
        bool filament=type>=12;
        float tract=filament ? type-12 : type;
        float r=sparrowRand(id), s=sparrowRand(id+317);
        if(!vane || tract<0.5) {
            float3 anchor=vane ? p+float3((r-0.5)*0.020,(s-0.5)*0.014,0) : p;
            float3 coat=sparrowTracts(anchor,patch.b,fine.a);
            float3 nap=sparrowNap(p,patch.r);
            coat=mix(coat,quillWheat*1.12,nap.z*0.29);
            float facial=sparrowLobe(p.xy,float2(-0.355,0.414),float2(0.149,0.082));
            float downClump=valueNoise(23+float3(47*p.x+19*p.y,94*p.y-31*p.x,58*abs(p.z)),128u);
            float scatter=(0.43+0.59*facial)*(nap.y-0.5)+(0.44+0.32*facial)*(nap.x-0.5);
            coat*=1+scatter+(0.22+0.87*facial)*(downClump-0.5);
            // A fine undercoat remains between follicles. Its grain follows the
            // change of tract from crown to pendent throat to swept flanks.
            float face=smoothstep(0.28f,0.49f,p.y);
            float2 flow=normalize(mix(float2(0.74,-0.67),float2(1.0,-0.09),face));
            float len=dot(p.xy,flow), crossflow=dot(p.xy,float2(-flow.y,flow.x));
            float nest=poreNoise(noise,float3(1.1*len,6.7*crossflow+0.17*patch.g,p.z*4.1));
            float fineCoat=band(crossflow*281+p.z*109+0.62*fine.b+0.37*sin(44*len),0.145);
            float bloom=0.5,slip=0,rib=0,filaments=0.5,tuft=0.5;
            if(vane) {
                float side=abs(a);
                float phase=t*(19+6*s)-side*(7.4+2.4*r)+0.94*side*side+0.57*sin(4.2*t+6*r);
                slip=band(phase,0.12);
                filaments=barbTone(phase*1.22,635*r+(a>0 ? 19 : 0));
                tuft=barbTone(phase*0.33,371*s);
                rib=exp(-31*side)*(0.62-0.42*t);
                bloom=(0.76*r+0.24*s);
                // Light buff terminal fringes on crown/mantle; down on the breast
                // has a much less legible perimeter than a stiff wing covert.
                float terminal=smoothstep(0.55f,0.99f,t+0.13*sin(a*8+6*r)+0.12*(filaments-0.5));
                float dorsal=smoothstep(0.32f,0.51f,p.y+0.53*(p.x+0.25));
                coat=mix(coat,quillIvory*(0.49+0.34*r),terminal*dorsal*(0.13+0.45*s));
                float featherShade=(r-0.42)*0.30*(0.50+0.50*dorsal);
                coat*=0.87+0.16*t+0.17*slip+0.11*rib+featherShade;
            }
            m.base=coat*(0.85+0.24*nest+0.12*patch.b+0.08*fineCoat+0.14*(bloom-0.40)
                +0.33*(filaments-0.5)+0.30*(tuft-0.5));
            m.height=0.00028*fineCoat+0.00052*nest+0.00047*slip+0.00062*rib+0.00042*tuft;
            m.through=0.20;m.fuzz=0.33;m.rough=0.83;
        } else if(tract>8.5) {
            m.base=mix(quillUmber,quillRusset,0.18+0.19*patch.b);
            m.rough=0.78;m.fuzz=0.21;
        } else {
            float v=abs(a),tonal=0.82+0.32*r;
            float hem=smoothstep(0.62f+0.08*s,0.97f,v+0.045*sin(8*t+7*r)+0.027*(fine.a-0.5));
            float shaft=exp(-v*(31+28*t))*(0.87-0.51*t);
            float phase=(48+32*s)*t-(9+7*r)*v+1.32*v*v+0.78*sin(5*t+3*r)+0.66*v*sin(11*t+s);
            float barbs=band(phase,0.14), barb=barbTone(phase*1.6,r*78+(a>0 ? 63 : 0));
            float bundles=barbTone(phase*0.21,51*s);
            float3 ink=quillUmber,edge=quillWheat;
            if(tract<1.5) {
                ink=mix(quillUmber,quillAsh*0.68,0.43+0.31*r);edge=mix(quillAsh,quillWheat,0.13)*0.91;
                hem*=0.25+0.36*s;shaft*=0.32;
                ink*=0.90+0.17*t+0.14*barb;
            } else if(tract<2.5) {
                ink=mix(quillSoot,quillUmber,0.33+0.52*r);edge=quillWheat*(0.71+0.27*s);hem*=0.80;
                ink=mix(ink,quillWheat*0.74,smoothstep(-0.21f,0.77f,a+0.09*sin(4*t))*(0.40+0.19*r));
            } else if(tract<3.5) {
                ink=mix(quillUmber,quillRusset,0.24+0.28*s);edge=quillWheat;hem*=0.91;
                ink=mix(ink,quillWheat,smoothstep(-0.12f,0.74f,a)*(0.26+0.17*s));
            } else if(tract<4.5) {
                ink=mix(quillSoot*1.21,quillRusset,0.08+0.10*s);edge=mix(quillWheat,quillIvory,0.41+0.26*r);
                hem=max(hem,smoothstep(0.40f,0.84f,v+0.11*a)*(0.60+0.22*s));
                ink=mix(ink,quillSoot,smoothstep(0.39f,0.78f,t)*0.65);
            } else if(tract<5.5) {
                ink=mix(quillRusset,quillUmber,0.11+0.24*s);edge=mix(quillRusset,quillWheat,0.81);
                ink=mix(ink,quillSoot*0.89,smoothstep(0.38f,0.73f,t)*(0.65+0.21*s));
                float bar=smoothstep(0.764f+0.085*r,0.936f,t+0.105*a+0.033*v+0.055*(bundles-0.5));
                ink=mix(ink,mix(quillIvory,quillWheat,0.37)*(0.85+0.26*r),bar*(0.67+0.24*s));
                ink=mix(ink,quillWheat*(0.77+0.22*r),smoothstep(-0.27f,0.59f,a+0.19*sin(3.7*t))*(1-bar)*(0.48+0.15*s));
                edge=mix(edge,quillIvory,bar*0.84);
            } else if(tract<6.5) {
                ink=mix(quillRusset*(0.87+0.48*r),quillWheat,smoothstep(-0.30f,0.76f,a)*0.53);edge=mix(quillRusset,quillWheat,0.69);
                float subterminal=smoothstep(0.48f,0.76f,t)*(1-smoothstep(0.76f,0.91f,t));
                ink=mix(ink,quillUmber*0.68,subterminal*(0.30+0.33*r));
                float bar=smoothstep(0.62f+0.13*r,0.865f,t+0.11*a+0.079*v+0.086*(bundles-0.5));
                ink=mix(ink,quillIvory*(0.97+0.24*s),bar*(0.80+0.19*r));
                edge=mix(edge,quillIvory,bar*0.77);
            } else {
                ink=quillRusset*(0.79+0.53*s);edge=quillWheat*(0.80+0.20*r);
                float streak=(1-smoothstep(0.13f,0.56f,v+0.14*sin(5*t+6*r))) * smoothstep(0.12f,0.50f,t);
                ink=mix(ink,quillSoot*1.16,streak*(tract>7.5 ? 0.93 : 0.75));
                hem*=0.68;
            }
            float web=smoothstep(-0.5f,0.6f,a+0.23*sin(2*t));
            ink=mix(ink,edge,0.09*web+0.09*bundles);
            m.base=mix(ink,edge,hem)*tonal;
            m.base=mix(m.base,edge*0.84,shaft*0.72);
            if(filament) m.base=mix(m.base,edge,0.06+0.14*bundles)*(0.91+0.19*barb);
            m.base*=0.91+0.17*barbs+0.13*fine.b+0.10*(patch.r-0.5)+0.45*(barb-0.5)+0.36*(bundles-0.5);
            // A fresh shoulder feather grades into the mantle near its concealed
            // base. The broad, visibly striped inner web is not enamelled brown.
            if(tract>4.5) {
                float buried=(1-smoothstep(0.15f,0.49f,t))*(1-smoothstep(-0.29f,-0.075f,p.x));
                m.base=mix(m.base,sparrowTracts(p,patch.b,fine.a)*(0.87+0.26*barb),buried);
            }
            m.height=0.00097*shaft+0.00071*barbs+0.00048*bundles+0.00021*fine.a;
            m.rough=0.62+0.11*s;m.through=0.10+0.09*hem;m.fuzz=0.13;
        }
    } else if(k==SparrowHorn) {
        float role=floor(uv.y*0.5),t=uv.y-2*role;
        if(role<2) {
            float sn=sin(6.2831853*uv.x), ridge=1-smoothstep(0.01f,0.21f,abs(sn));
            float3 horn=role<0.5 ? mix(quillAsh,quillUmber,0.74) : float3(0.67,0.491,0.437);
            float wear=barbTone(67*t+cos(6.283*uv.x)*4.2,37);
            horn=mix(horn,quillSoot,smoothstep(0.54f,1.0f,t+0.038*(wear-0.5))*(role<0.5 ? 0.88 : 0.74));
            // The lower ramus is rose horn with an opaque cutting edge. The upper
            // surface has a dark dorsal ridge and paler worn sides, not a single cone.
            if(role<0.5) horn=mix(horn,quillSoot,smoothstep(0.55f,0.98f,sn)*(0.45+0.28*patch.a));
            horn*=0.76+0.31*patch.a+0.18*wear;
            float nostril=sparrowLobe(p.xy,float2(-0.483,0.465),float2(0.0084,0.0034));
            m.base=mix(horn,quillSoot*0.53,saturate(ridge*(0.78-0.42*t)+0.73*nostril));
            float polish=role<0.5 ? smoothstep(0.28f,0.93f,sn) : smoothstep(-0.9f,-0.22f,sn);
            m.base+=float3(0.092,0.078,0.071)*polish*(1-0.7*t);
            float cut=band(t*33+cos(uv.x*6.28)*1.6,0.18);
            m.rough=0.43-0.11*polish;m.height=0.00020*cut+0.0004*fine.a-0.0010*nostril;m.through=0.14;
        } else if(role>4.5) {
            m.base=mix(quillSoot,quillUmber,patch.r);m.rough=0.77;
        } else {
            float3 rim=role<3.5 ? quillSoot*0.69 : mix(quillUmber,quillAsh,0.50+0.16*fine.a);
            m.base=mix(rim,sparrowTracts(p,patch.b,fine.a)*(0.81+0.30*fine.a),smoothstep(0.17f,0.40f,t));
            m.rough=0.62;
        }
    } else if(k==Cornea) {
        float rho=length(p.xy);
        float iris=smoothstep(0.38f,0.58f,rho)*(1-smoothstep(0.89f,1.0f,rho));
        float fibres=barbTone(atan2(p.y,p.x)*15+rho*3,55);
        m.base=mix(float3(0.003,0.002,0.0016),mix(quillUmber,quillAsh,0.13),iris*(0.53+0.47*fibres));
        m.rough=0.13;
    } else if(k==WinterTwig) {
        float bark=poreNoise(noise,p*float3(4.6,1.4,3.8));
        float wood=valueNoise(float3(8.1*cos(6.283*uv.x),8.1*sin(6.283*uv.x),12*uv.y)+17,64u);
        float fissure=barbTone(uv.x*26+0.72*sin(27*uv.y)+0.48*wood,12);
        float lenticel=smoothstep(0.68f,0.90f,fine.b+0.12*patch.a)*smoothstep(0.57f,0.81f,wood);
        m.base=mix(albedo*float3(0.59,0.64,0.73),quillAsh*1.04,0.19+0.34*bark+0.23*wood+0.30*lenticel);
        m.base*=0.83+0.28*fissure;m.height=0.0008*bark+0.00068*lenticel+0.00044*fissure;m.rough=0.86;
    } else {
        float role=floor(uv.y*0.5), f=uv.y-2*role;
        float scale=band(f*(role<0.5 ? 14 : 7)+0.13*cos(uv.x*6.283),0.12);
        m.base=role>1.5 ? quillUmber*(0.67+0.45*f) :
            mix(quillUmber,float3(0.339,0.178,0.129),0.68+0.16*fine.b)*(0.89+0.19*scale);
        m.rough=role>1.5 ? 0.39 : 0.60;m.height=0.00044*scale;
    }
    return m;
}
#endif
