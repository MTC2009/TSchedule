#ifndef TSCHEDULE_SEASONAL_MATERIALS
#define TSCHEDULE_SEASONAL_MATERIALS
#include "SeasonalSurface.h"

struct SeasonalVertexData { float4 posU, normalV; };
struct SeasonalInstanceData { float4 x,y,z,center,material,extras,curve; };
struct SeasonalShadowFrame { float4 x,y,z; };
struct SeasonalVarying {
    float4 position [[position]];
    float3 world, normal, local; float2 uv;
    float4 material [[flat]],tag [[flat]]; float coating [[flat]];
};
struct SeasonalMaterialResult { half4 color [[color(0)]]; uint id [[color(1)]]; };
inline float3 toLight(float3 p,constant SeasonalShadowFrame &light) {
    float4 q=float4(p,1); return float3(dot(q,light.x),dot(q,light.y),dot(q,light.z));
}
inline float waveAt(float3 p,constant SkyUniforms &u) {
    float age=u.waveContact.w,d=length(p-u.waveContact.xyz);
    if(age<0 || age>=3) return 0;
    float phase=d-0.86*age;
    return 0.044f*exp(-16*phase*phase-1.01*age)*smoothstep(0.0f,0.095f,age)*sin(25*phase);
}
inline float3 specimenWorld(float3 q,float featherV,SeasonalInstanceData s,constant SkyUniforms &u) {
    if(uint(s.extras.y)==Gourd || uint(s.extras.y)==Squash) { float a=atan2(q.z,q.x); q.xz*=0.919+0.070*cos(11*a+0.24*sin(4*q.y))+0.012*cos(3*a); }
    if(uint(s.extras.y)==SparrowVane && s.curve.w<0) {
        float type=floor(featherV*0.5f),tract=type>=12 ? type-12 : type,tip=featherV-2*type;
        float3 out=normalize(float3(q.x+0.062f,(q.y-0.129f)*0.87f,q.z*2.3f)+0.0001f);
        float clearOfEye=smoothstep(0.037f,0.106f,length(q.xy-float2(-0.385,0.474)));
        // Follicles and the folded tail stay put; free distal webs lift from the skin.
        float r=tract<0.5 ? (0.036f+0.015f*(1-smoothstep(0.25f,0.46f,q.y)))*clearOfEye : (tract>4.5 ? 0.012f : 0.0f);
        q+=out*(-s.curve.w*r*tip*tip);
    }
    float3 p=float3x3(s.x.xyz,s.y.xyz,s.z.xyz)*q+s.center.xyz;
    if(s.curve.w>0) { float f=q.y*0.5+0.5; p+=s.curve.xyz*(4*f*(1-f)); }
    if(uint(s.extras.y)==Water) p.y+=0.005*sin(p.x*5.3+p.z*3.9+u.clock.z)+waveAt(p,u);
    return p;
}
inline bool hollowGourd(float3 p) {
    if(p.z>=-0.12) return false;
    float x=abs(p.x),smile=-0.48+0.54*x*x;
    return (abs(x-0.36)<0.19*(1-saturate((p.y-0.08)/0.34)) && p.y>0.08 && p.y<0.42)
        || (x<0.098 && p.y>-0.105 && p.y<0.045-x)
        || (x<0.57 && p.y>smile && p.y<smile+0.14 && !(x>0.22 && x<0.33 && p.y>smile+0.075));
}
struct ShadowOut { float4 position [[position]]; float3 local; uint kind [[flat]]; };
vertex ShadowOut seasonalShadowVertex(uint v [[vertex_id]],uint id [[instance_id]],constant SkyUniforms &u [[buffer(0)]],
                device const SeasonalVertexData *mesh [[buffer(1)]],device const SeasonalInstanceData *objects [[buffer(2)]],
                constant SeasonalShadowFrame &light [[buffer(3)]]) {
    float3 q=mesh[v].posU.xyz; SeasonalInstanceData s=objects[id];
    return {float4(toLight(specimenWorld(q,mesh[v].normalV.w,s,u),light),1),q,uint(s.extras.y)};
}
fragment void seasonalShadowCutout(ShadowOut in [[stage_in]]) {
    if((in.kind==Gourd && hollowGourd(in.local)) || in.kind==Dew || in.kind==Glass || in.kind==Ember) discard_fragment();
}
vertex SeasonalVarying seasonalVertex(uint v [[vertex_id]],uint id [[instance_id]],constant SkyUniforms &u [[buffer(0)]],
                                      device const SeasonalVertexData *mesh [[buffer(1)]],device const SeasonalInstanceData *objects [[buffer(2)]],constant float4 &mirror [[buffer(4)]]) {
    SeasonalInstanceData s=objects[id]; SeasonalVertexData m=mesh[v];
    float3 p=specimenWorld(m.posU.xyz,m.normalV.w,s,u),eye=p-u.camera.xyz-2*mirror.xyz*dot(float4(p,1),mirror);
    float yaw=0.118*(1-smoothstep(0.6f,1.32f,u.viewport.x));
    float4 clip=float4((eye.x-yaw*eye.z)*2/(0.86*u.viewport.x),2*(eye.y-0.102*eye.z)/0.86-eye.z,(eye.z-0.08f)*96.0f/95.92f,eye.z);
    float3 bx=s.x.xyz,by=s.y.xyz-s.curve.xyz*(2*m.posU.y),bz=s.z.xyz;
    float3 localN=m.normalV.xyz;
    if(uint(s.extras.y)==SparrowVane && s.curve.w<0) {
        float type=floor(m.normalV.w*0.5f),tract=type>=12 ? type-12 : type,tip=m.normalV.w-2*type;
        float3 flow=normalize(float3(0.79,-0.49,0.06*sign(m.posU.z)));
        float3 tangent=flow-localN*dot(flow,localN);
        float tilt=tract<0.5 ? 0.73*smoothstep(0.037f,0.106f,length(m.posU.xy-float2(-0.385,0.474))) :
                              (tract>4.5 && tract<8.5 ? 0.10f : 0.0f);
        localN=normalize(localN+tangent*(s.curve.w*tilt*tip));
    }
    float3 n=normalize(cross(by,bz)*localN.x+cross(bz,bx)*localN.y+cross(bx,by)*localN.z);
    return {clip,p,n,m.posU.xyz,float2(m.posU.w,m.normalV.w),s.material,float4(s.extras.xyz,min(length(s.x.xyz),min(length(s.y.xyz),length(s.z.xyz)))),s.extras.w};
}

inline float shelter(float3 world,float NoL,constant SeasonalShadowFrame &light,depth2d<float> shadow) {
    float3 p=toLight(world,light); float2 st=float2(0.5+0.5*p.x,0.5-0.5*p.y);
    if(any(st<0) || any(st>1) || p.z<=0 || p.z>=1) return 1;
    constexpr sampler compare(coord::normalized,address::clamp_to_edge,filter::linear,compare_func::less_equal);
    float z=p.z-0.00032f-0.00046f*(1-abs(NoL)),r=1.06f/float(shadow.get_width());
    return 0.25f*(shadow.sample_compare(compare,st+float2(-0.79,-0.55)*r,z)+shadow.sample_compare(compare,st+float2(0.61,-0.86)*r,z)
                 +shadow.sample_compare(compare,st+float2(0.81,0.63)*r,z)+shadow.sample_compare(compare,st+float2(-0.60,0.84)*r,z));
}
// Directionally sample the very same cloud density field, never an environment photograph.
inline float3 seasonalEnvironment(float3 p,float3 ray,constant SkyUniforms &u,texture3d<half> field,texture3d<half> noise) {
    float3 sky=backgroundLight(ray,u); float d=u.clock.x, optical=0;
    if(ray.y>0.025 && u.weather.x>0.04) {
        CloudField f=cloudField(u);
        for(uint i=0;i<3;++i) {
            float t=(float(i)*1.65f+2.1f)/max(0.22f,ray.y);
            optical+=cloudDensity(p+ray*t,f,field,noise,false)*1.04;
        }
    }
    float3 litCloud=mix(u.cloudAmbient.rgb*0.22,u.cloudAmbient.rgb*0.64+u.sunlight.rgb*0.50,d);
    return mix(sky,litCloud,1-exp(-optical));
}
inline float3 reliefNormal(float3 n,float3 world,float height) {
    float3 a=dfdx(world),b=dfdy(world),sx=cross(b,n),sy=cross(n,a);
    float det=dot(a,sx),d=abs(det);
    float3 grad=(dfdx(height)*sx+dfdy(height)*sy)*sign(det)/max(d,0.0000005f);
    return normalize(n-grad/(1+1.8*length(grad)));
}
// This transfer belongs to the almanac, not to the weather or the UI. Use a
// handful of soft ink values with warm paper and indigo in the shadows. Retain
// pigment hue, tiny feather/leaf structure, and the optical behaviour of water.
inline float3 almanacInk(float3 c,float3 p,float3 n,float3 v,uint k) {
    float y=max(0.0001f,dot(c,float3(0.23,0.66,0.11))),tone=sqrt(min(1.0f,y));
    float level=tone*6.0f, painted=(floor(level)+smoothstep(0.26f,0.77f,fract(level)))/6.0f;
    float optical=(k==Dew || k==Glass || k==Water || k==Cornea || k==Membrane) ? 0.36f : 1.0f;
    float target=mix(tone,painted,(k==LotusSilk ? 0.24f : 0.56f)*optical);
    float3 dye=c*(y>1 ? 1 : clamp(target*target/y,0.70f,1.24f));
    float dark=(1-smoothstep(0.13f,0.69f,tone))*optical;
    dye=mix(dye,float3(0.028,0.040,0.060)+dye*0.80,0.45f*dark);
    dye*=mix(float3(1.0),float3(1.055f,1.008f,0.916f),smoothstep(0.39f,0.91f,tone)*optical);
    if(k!=CutInk && k!=CarvedInk && k!=BambooFibre && k!=Ember && k!=LotusSilk && optical>0.9f) {
        float hatch=band(20.0*p.y+12.0*p.x+4.0*p.z+0.21*sin(7*p.x),0.084);
        dye*=1.0f-0.09f*hatch*dark-0.075f*(1-smoothstep(0.08f,0.34f,abs(dot(n,v))));
    }
    return max(float3(0),dye);
}
fragment SeasonalMaterialResult seasonalMaterial(SeasonalVarying in [[stage_in]],constant SkyUniforms &u [[buffer(0)]],
        constant SeasonalShadowFrame &light [[buffer(1)]],depth2d<float> shadow [[texture(0)]],
        texture3d<half> field [[texture(1)]],texture3d<half> noise [[texture(2)]],texture2d<half> behind [[texture(3)]],
        texture2d<half> reflection [[texture(4)]],constant float4 &mirror [[buffer(2)]]) {
    bool mirrored=dot(mirror.xyz,mirror.xyz)>0.5;
    if(mirrored && dot(float4(in.world,1),mirror)<-0.008) discard_fragment();
    uint k=uint(in.tag.y); if(k==Gourd && hollowGourd(in.local)) discard_fragment();
    float3 eye=u.camera.xyz-2*mirror.xyz*dot(float4(u.camera.xyz,1),mirror);
    float3 n=normalize(in.normal), v=normalize(eye-in.world);
    if(k==CutInk || k==CarvedInk) {
        // Opaque relief: the face reads as one pigment in a small composition;
        // a turned edge catches light, and the same mesh casts shadows and IDs.
        float facing=abs(dot(n,v));
        float3 ink=in.material.rgb*(0.79+0.16*smoothstep(0.16f,0.80f,facing)+0.08*u.clock.x);
        if(k==CarvedInk) {
            float3 key=normalize(mix(u.moon.xyz,u.sun.xyz,smoothstep(0.10f,0.78f,u.clock.x)));
            float lit=dot(n,key),visible=shelter(in.world,lit,light,shadow);
            // Shallow carved relief: adjacent planes share one pigment but not
            // the same light. Only these carvings receive a soft notch shadow.
            ink*=mix(0.73f,1.105f,smoothstep(-0.56f,0.80f,lit))*(0.84f+0.16f*visible);
        }
        ink+=in.material.rgb*in.material.a;
        return {half4(half3(almanacInk(ink,in.local,n,v,k)),half(mirrored ? 1.0f : length(in.world-eye))),uint(in.tag.x)};
    }
    SeasonalBRDF m=specimenSurface(k,in.local,in.uv,in.tag.z,in.material.rgb,in.material.a,v,n,noise);
    if(in.coating>0) {
        float frostGrain=poreNoise(noise,in.local*3.18+in.tag.z);
        float exposed=smoothstep(-0.13f,0.64f,n.y+0.43*(frostGrain-0.5f));
        float frost=saturate(in.coating*(0.07+1.21*exposed)*(0.69+0.43*frostGrain));
        m.base=mix(m.base,float3(0.80,0.831,0.839)*(0.82+0.23*frostGrain),frost);
        m.rough=mix(m.rough,0.58f,frost);m.height+=0.023*frost*frostGrain;
    }
    n=reliefNormal(n,in.world,m.height*in.tag.w);
    float day=u.clock.x, mixLight=smoothstep(0.10f,0.78f,day);
    float3 l=normalize(mix(u.moon.xyz,u.sun.xyz,mixLight)),h=normalize(v+l+0.00001f);
    float ndl=dot(n,l),nl=saturate(ndl),nv=max(0.025f,dot(n,v)),nh=saturate(dot(n,h)),vh=saturate(dot(v,h));
    float vis=shelter(in.world,ndl,light,shadow);
    float optical = u.weather.x>0.055 ? shadowDepth(in.world,l,cloudField(u),field,noise) : 0;
    float sunVis=exp(-1.18f*optical)*(1-0.78*u.weather.y);
    float3 key=mix(u.moonlight.rgb*0.98,u.sunlight.rgb*(1.49*u.sun.w),mixLight)*sunVis;
    float skyWeight=saturate(n.y*0.52+0.48);
    float3 skyFill=mix(float3(0.265,0.293,0.34),0.21+0.70*u.cloudAmbient.rgb,mixLight);
    float3 bounce=mix(float3(0.119,0.133,0.16),float3(0.29,0.239,0.16),mixLight);
    float3 fill=mix(bounce,skyFill,skyWeight)*mix(0.77,1.0,vis);
    if(k==SparrowDown || (k==SparrowVane && in.uv.y<2)) {
        // The folded wing shields some diffuse sky from the flank below it;
        // direct light still tests the actual wing in the solar shadow map.
        float3 q=in.local;float flank=smoothstep(0.06f,0.18f,abs(q.z))*smoothstep(-0.37f,-0.20f,q.x);
        float hem=0.009-0.074*q.x, below=smoothstep(-0.012f,0.017f,hem-q.y)*exp(-7.3f*abs(hem-q.y));
        fill*=1-0.35*flank*below;
    }
    // GGX distribution + correlated visibility with dielectric/metal Fresnel; both actors
    // and the ground use the actual sky key (no independent camera-facing studio lamp).
    float alpha=max(0.04f,m.rough*m.rough),aa=alpha*alpha,den=nh*nh*(aa-1)+1;
    float D=aa/max(0.00001f,3.14159f*den*den);
    float G=0.5f/max(0.035f,nl*sqrt(nv*nv*(1-aa)+aa)+nv*sqrt(nl*nl*(1-aa)+aa));
    float3 f0=mix(float3(0.032),m.base,m.metal),F=f0+(1-f0)*pow(1-vh,5.0f);
    float3 color=m.base*(1-m.metal)*(fill+key*(nl*vis));
    if(k==LotusSilk) {
        float wash=smoothstep(0.12f,0.81f,in.uv.y);
        color+=m.base*(skyFill*(0.17f+0.22f*wash)+key*(0.15f*vis*saturate(-ndl)));
    }
    if(k==SparrowDown || k==SparrowVane) {
        // The dorsal web is a rough bundle of keratin fibres. Broad sky scatter
        // is visible on its backlit side as well as the narrow direct reflection.
        float fibreFill=0.13+0.10*skyWeight;
        color+=m.base*(skyFill*fibreFill+key*(m.through*0.31*saturate(-ndl))*vis);
    }
    color+=key*(nl*vis)*min(9.0f,D*G)*F;
    float through=saturate(-ndl*0.78+0.17)*mix(0.24,1.0,vis)*m.through;
    color+=m.base*key*through*(k==Foliage || k==LeafPad ? float3(1.24,1.05,0.49) : float3(1.09,0.86,0.71));
    if(k==Fur || k==Hair || k==Caribou) {
        // Soft forward scattering along the coat includes the sky-facing rim, not just a hard specular stripe.
        float rim=pow(1-saturate(dot(n,v)),1.9f);
        color+=m.base*(0.37*skyFill+0.79*key)*rim*(0.28+0.72*vis);
    }
    color+=m.base*m.fuzz*pow(1-nv,2.6f)*(fill+0.43*key*(0.4+0.6*vis));
    float3 r=reflect(-v,n);
    if(k==Water || k==Dew || k==Glass || k==Membrane || k==Alloy || k==Shell || k==Glaze || k==Cornea) {
        if(k==Water) {
            float2 q=in.world.xz; float t=u.clock.z*0.33;
            float warp=poreNoise(noise,float3(q*0.060,0.31+t*0.012));
            float g=0.12*cos(dot(q,float2(4.3,3.1))+t+4*warp)+0.056*cos(dot(q,float2(-7.1,9.8))-t*1.7);
            float hh=poreNoise(noise,float3(q.x*0.47+t*0.022,q.y*1.22,warp*0.28));
            n=reliefNormal(normalize(in.normal+float3(g,0,0.15*sin(q.y*3.2-2*q.x+warp*5+t))),in.world,waveAt(in.world,u)+0.012*hh);
            r=reflect(-v,n); nv=saturate(dot(n,v));
        }
        float3 reflected=seasonalEnvironment(in.world,r,u,field,noise);
        float fres=0.025+0.975*pow(1-saturate(nv),5.0f);
        constexpr sampler optical(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 size=float2(behind.get_width(),behind.get_height()),st=in.position.xy/size;
        if(k==Water) {
            // The smooth plane and its reflected camera project to the same pixel.
            // Perturb rays only by the short wave normal, not by the plane's macroscopic tilt.
            if(reflection.get_width()>1) {
                float3 dn=n-normalize(in.normal);
                float2 offset=clamp(float2(dn.x,-dn.z)*float2(0.035/u.viewport.x,0.056),-0.024f,0.024f);
                float2 dst=st+offset,step=float2(1.35/reflection.get_width(),1.5/reflection.get_height());
                if(all(dst>0) && all(dst<1)) {
                    float4 reflectedScene=float4(reflection.sample(optical,dst))*0.40;
                    reflectedScene+=float4(reflection.sample(optical,dst+step))*0.15+float4(reflection.sample(optical,dst-step))*0.15;
                    reflectedScene+=float4(reflection.sample(optical,dst+step*float2(-1,1)))*0.15+float4(reflection.sample(optical,dst-step*float2(-1,1)))*0.15;
                    reflected=reflected*(1-saturate(reflectedScene.w))+reflectedScene.rgb;
                }
            }
            float bed=poreNoise(noise,float3(in.world.xz*0.065,0.16));
            float3 deep=m.base*(0.57+0.47*bed)*(0.17+0.83*day);
            color=mix(deep,reflected,saturate(0.32+0.67*fres))+key*pow(saturate(dot(r,l)),160.0f)*vis;
        } else if(k==Dew || k==Glass || k==Membrane) {
            float range=length(in.world-u.camera.xyz),eta=k==Dew ? 1.333f : 1.51f;
            float3 incoming=-v,ref=refract(incoming,n,1.0f/eta);
            float3 exit=in.world,outgoing=ref;
            if(k==Dew) {
                // Snell at both interfaces. At close focus the outgoing ray samples a
                // different vein than the entry ray: a bead acts as a tiny changing lens.
                float path=-2.0f*in.tag.w*min(-0.01f,dot(ref,n));
                exit+=ref*path;
                float3 exitN=normalize(n+ref*(path/max(0.0001f,in.tag.w)));
                float3 second=refract(ref,-exitN,eta);if(dot(second,second)>0.01f) outgoing=second;
            }
            float4 central=float4(behind.sample(optical,st));
            float gap=central.w>range ? clamp(central.w-range,0.03f,min(1.4f,in.tag.w*7.0f)) : in.tag.w*2.0f;
            if(k==Membrane) gap=0.028f;
            float3 q=exit-u.camera.xyz+outgoing*gap;
            float yaw=0.118*(1-smoothstep(0.6f,1.32f,u.viewport.x));
            float2 dst=float2(0.5+(q.x/max(0.12f,q.z)-yaw)/(0.86*u.viewport.x),1-(q.y/max(0.12f,q.z)-0.102)/0.86);
            float4 sample=float4(behind.sample(optical,dst));
            if(sample.w>0 && sample.w<range-0.009) sample=central;
            float3 transmitted=sample.w>range-0.009 ? sample.rgb : seasonalEnvironment(in.world,outgoing,u,field,noise);
            if(k==Membrane) {
                float iridescence=0.5+0.5*cos(27*nv+6*in.uv.y);
                color=mix(transmitted,color,0.16)+reflected*(0.035+0.17*fres)*mix(float3(0.74,0.93,1.0),float3(0.93,0.86,0.68),iridescence);
            } else {
                float solarDisk=pow(saturate(dot(r,l)),92.0f)*2.25f;
                float skyGlint=pow(saturate(r.y),5.0f)*0.13f;
                color=mix(transmitted*0.98,reflected,fres)+key*solarDisk*vis+(0.18+fres)*skyFill*skyGlint+color*0.013;
            }
        } else if(k==Cornea) {
            float fres=0.022+0.978*pow(1-nv,5.0f);
            float opening=dot(r,normalize(float3(-0.30f,0.93f,-0.28f)));
            float skyCatch=smoothstep(0.81f,0.975f,opening)*0.092+smoothstep(0.977f,0.997f,opening)*0.64;
            float3 surroundings=mix(float3(0.035,0.026,0.018),reflected,smoothstep(-0.08f,0.52f,r.y));
            color+=surroundings*fres*0.69+skyFill*skyCatch+key*(pow(saturate(dot(r,l)),290.0f)*vis*2.0f);
        } else {color+=reflected*(f0+(1-f0)*pow(1-nv,5.0f))*(1-0.55*m.rough);}
    }
    if(u.pointLight.w>0) {
        float3 delta=u.pointLight.xyz-in.world;
        color+=m.base*u.pointColor.rgb*(u.pointLight.w/(0.28+dot(delta,delta)))*(0.14+0.76*saturate(dot(n,normalize(delta+0.0001))));
    }
    color+=m.base*m.emission;
    float range=length(in.world-eye);
    float haze=1-exp(-range*(0.0048f+0.007f*u.weather.z));
    color=mix(color,u.skyMiddle.rgb,haze*(0.45+0.37*day));
    return {half4(half3(almanacInk(color,in.local,n,v,k)),half(mirrored ? 1.0f : range)),uint(in.tag.x)};
}
#endif
