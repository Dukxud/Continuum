#version 460 core
#include <flutter/runtime_effect.glsl>
// Derived from the approved Aero v3 v2.0.1 fragment shader in assets/AeroBar.html.
// Only coordinate and premultiplied-alpha adaptation for Flutter are changed.
out vec4 fragColor;
uniform vec2 uRes;
uniform float uFill,uTime,uVel,uFinish,uLights,uLightBackground,uDepth,uCompact,uShimmer,uWorking;
uniform vec3 uAccent;
#define PI 3.141592653589793
float S(float v){return clamp(v,0.,1.);}vec3 C(vec3 v){return clamp(v,0.,1.);}
float G(float a,float s){return exp(-.5*pow(a/max(.0001,s),2.));}
float cap(vec2 p,vec2 a,vec2 b,float r){vec2 d=b-a;return length(p-a-d*S(dot(p-a,d)/dot(d,d)))-r;}
float aabox(vec2 p,vec2 c,vec2 halfsize,vec2 edge){vec2 q=abs(p-c)-halfsize;return (1.-smoothstep(-edge.x,edge.x,q.x))*(1.-smoothstep(-edge.y,edge.y,q.y));}
vec3 tonemap(vec3 a){return C((a*(2.51*a+.03))/(a*(2.43*a+.59)+.14));}
float AA(){return max(.003,10./uRes.x);}
float mask(float d){float e=AA();return 1.-smoothstep(-e,e,d);}
float F(float ndv,float f0){return f0+(1.-f0)*pow(1.-S(ndv),5.);}
float luminance(vec3 v){return dot(v,vec3(.2126,.7152,.0722));}
vec3 tintedEnv(vec3 direction,vec3 x){
 // Reflective photo-studio environment represented as actual softbox panels,
 // dark flags and a horizon in angular direction space, not screen strips.
 vec3 d=normalize(direction);
 vec3 col=vec3(.028,.043,.077) + .055*S(d.y+.7);
 float cool=uLights>.5 && uLights<1.5 ? 1.5:1.;
 float night=step(1.5,uLights);
 col+=mix(vec3(.18,.29,.43),vec3(.045,.08,.16),night)*G(d.y+.72,.28);
 col+=vec3(.10,.125,.17)*G(d.y-.85,.24);
 float big=aabox(d.xy,vec2(-.36,.63),vec2(.47,.085),vec2(.10,.065));
 float side=aabox(d.xy,vec2(.82,-.06),vec2(.115,.76),vec2(.045,.11));
 float strip=aabox(d.xy,vec2(-.67,-.20),vec2(.12,.65),vec2(.045,.11));
 float lower=aabox(d.xy,vec2(.20,-.66),vec2(.85,.045),vec2(.14,.04));
 col+=mix(vec3(2.7,3.2,3.9),vec3(2.1,2.25,2.75),night)*big*cool;
 col+=vec3(2.2,2.45,3.0)*side;
 col+=vec3(1.12,1.56,2.05)*strip;
 col+=vec3(1.35,1.48,1.8)*lower;
 col+=vec3(.75,.37,.34)*night*aabox(d.xy,vec2(.25,.18),vec2(.14,.6),vec2(.09,.12));
 // Concentric black flags shape the mirrored surface into complex bands.
 col*=1.-.78*aabox(d.xy,vec2(-.08,.32),vec2(.115,.045),vec2(.07,.04));
 col*=1.-.55*aabox(d.xy,vec2(.44,-.43),vec2(.18,.065),vec2(.12,.05));
 return col;
}
vec3 illuminate(vec3 normal,vec3 worldPos){
 vec3 view=vec3(0.,0.,1.);vec3 r=reflect(-view,normal);
 vec3 env=tintedEnv(r,worldPos);
 // Area highlights depend on normal, world light location and a changing
 // incident direction; never on a screen-space white rectangle.
 vec3 lamp0=vec3(-3.7+4.7*sin(uTime*.31),2.7,4.5);
 vec3 lamp1=vec3(2.4*cos(uTime*.23+.8),-2.2,4.0);
 vec3 h0=normalize(normalize(lamp0-worldPos)+view);
 vec3 h1=normalize(normalize(lamp1-worldPos)+view);
 float spec0=pow(S(dot(normal,h0)),44.);
 float spec1=pow(S(dot(normal,h1)),88.);
 return env+vec3(2.0,2.12,2.30)*spec0+vec3(2.4,2.1,1.85)*spec1;
}
vec3 colorSurface(vec3 normal,vec3 position,float thickness,vec2 p,float front,float capPresence){
 float nz=S(normal.z),fres=F(nz,.13);
 vec3 e=illuminate(normal,position);
 vec3 dye=pow(uAccent,vec3(1.09));
 // Back-lit pigment is absorbed through a curved path (thicker in center),
 // while the highly reflective upper boundary keeps neutral white reflections.
 float through=S(thickness/.77);
 vec3 transmission=dye*(.27+.61*pow(through,.53));
 vec3 absorption=exp(-vec3(.12,.10,.09)*(.2+thickness));
 transmission*=absorption;
 float highBand=G(p.y-.17,.20),lowBand=G(p.y+.27,.10);
 transmission*=.76+.24*highBand+.31*lowBand;
 float mirror=uFinish;
 float enamel=step(.5,mirror)*(1.-step(1.5,mirror));
 float pearl=step(1.5,mirror);
 float edgeShading=.85+.18*pow(nz,.34);
 vec3 base=transmission*edgeShading;
 // Snell-law refraction through the curved glass boundary. It modulates the
 // transmitted colored light and is independent of the reflected studio rig.
 vec3 refracted=refract(vec3(0.,0.,-1.),normal,1./1.47);
 vec3 transmittedStudio=tintedEnv(refracted,position);
 base+=pow(dye,vec3(.8))*transmittedStudio*(.055+.065*(1.-nz))*(1.-fres);
 base+=dye*vec3(.14,.19,.22)*G(p.y+.30,.13);
 base=mix(base,base*.80,enamel*.4);
 float metalFresnel=mix(fres,.57+ .34*pow(1.-nz,3.),enamel);
 vec3 reflectance=e*(.16+.68*metalFresnel)*mix(vec3(1.0),vec3(.90,.94,1.0),pearl);
 float pearly=pearl*.45*(.5+.5*sin(19.*p.y+uTime*.47))*pow(1.-nz,2.);
 reflectance+=pearly*vec3(.36,.48,.79);
 // The curved-end collar/glow must disappear when the head is flat at 100%.
 float collar=capPresence*G(p.x-(front-.145),.052)*(1.-.65*abs(normal.y));
 float capGlow=capPresence*G(p.x-(front+.05),.17)*pow(1.-nz,1.4);
 base*=1.-collar*.22;
 reflectance+=vec3(.40,.54,.70)*capGlow;
 float pFront=capPresence*G(p.x-(front-.035),.07)*G(p.y-.02,.12);
 reflectance+=vec3(.62,.80,1.0)*pFront*.45;
 // A wide, softly reflected studio light moves across the curved liquid.
 // Its two-dimensional footprint, view-dependent response and curved falloff
 // produce a shifting luminous patch, not a hard vertical zebra stripe.
 // Each sweep begins and ends outside the tube so the loop seam is dark.
 // A soft envelope eases reflected light across the tube's curved edges.
 float travel=fract(uTime*.135);
 float lightX=mix(-7.0,7.0,travel);
 float sweepEnvelope=smoothstep(-7.0,-3.8,lightX)*
                     (1.-smoothstep(3.8,7.0,lightX));
 vec3 view=vec3(.0,.0,1.0);
 vec3 lamp=normalize(vec3(lightX-p.x,1.15-p.y,3.6-position.z));
 vec3 halfLamp=normalize(lamp+view);
 float angular=pow(S(dot(normal,halfLamp)),12.0);
 float bentX=p.x-lightX+.32*normal.y+.13*sin(p.y*5.2+p.x*.65);
 float horizontal=G(bentX,1.13);
 float vertical=G(p.y-.11-.09*sin(p.x*.45+uTime*.17),.31);
 float softbox=horizontal*vertical;
 float specularPatch=softbox*(.28+.82*angular);
 float diffuseHalo=G(bentX,1.76)*G(p.y-.08,.49)*.16;
 // A tighter second reflection raises perceived polish without flattening
 // the original glass, pigment, or shared rounded liquid tip.
 float glint=G(bentX,.38)*G(p.y-.12,.19)*(.18+.30*angular);
 reflectance+=vec3(1.08,1.22,1.34)*(specularPatch+diffuseHalo+glint)*uShimmer*sweepEnvelope;
 // Indeterminate work keeps a constant full tube with moving liquid light:
 // neither the leading edge nor any execution-completion percentage advances.
 float flow=sin(3.2*p.x-uTime*2.4+.38*sin(p.y*8.1+uTime*1.1));
 float eddy=sin(6.1*p.x+uTime*1.8+1.8*p.y);
 float currents=(.5+.5*flow)*(.72+.28*(.5+.5*eddy));
 base+=uWorking*uAccent*.15*currents;
 reflectance+=uWorking*vec3(.35,.48,.61)*G(p.y-.04,.29)*pow(currents,3.)*.64;
 // Gloss appears as genuinely varying reflected environmental radiance.
 return tonemap(base+reflectance);
}

void main() {
    vec2 uv=FlutterFragCoord().xy/uRes.xy;
    uv.y=1.-uv.y;
    float f=clamp(uFill,0.,1.);
    // Shared pixel-space capsule: native fill and WebGL optical layer use the
    // SAME tip position, border inset and rounded endcap at every size.
    // This replaces the previous concave-looking -0.20 offset and hard clip.
    float px=uv.x*uRes.x;
    float py=uv.y*uRes.y;
    float edgeY=max(1.,floor(uRes.y/13.+.5));
    float edgeX=max(1.,floor(uRes.x/400.+.5));
    float radiusPx=max(.5,(uRes.y-2.*edgeY)*.5);
    float tipPx=clamp(f*uRes.x-2.*uRes.x/400.,edgeX,uRes.x-edgeX);
    tipPx=mix(tipPx,uRes.x-edgeX,step(.999999,f));
    float occupied=max(0.,tipPx-edgeX);
    float rd=.422;
    float rx=radiusPx;
    float ry=radiusPx;
    float centerPx=tipPx-radiusPx;
    float fullTip=step(.999999,f);
    float dxPx,dyPx=py-uRes.y*.5;
    if(occupied<2.*radiusPx){
        // At 1-2% fill the tiny drop contracts into a circular bead.
        rx=max(.05,occupied*.5);
        ry=max(.05,min(radiusPx,rx));
        centerPx=(edgeX+tipPx)*.5;
        dxPx=px-centerPx;
    }else{
        // Normal fill: straight left body, convex hemispherical leading edge.
        dxPx=mix(max(px-centerPx,0.),0.,fullTip);
    }
    vec2 delta=vec2(dxPx*rd/rx,dyPx*rd/ry);
    float rr=length(delta);
    float aa=rd/max(ry,1.);
    float cov=1.-smoothstep(rd-aa,rd+aa,rr);
    float left=smoothstep(edgeX-.5,edgeX+.5,px);
    float alpha=cov*left*step(.00001,f)*.94*(1.-fullTip*smoothstep(uRes.x-edgeX-.5,uRes.x-edgeX+.5,px));
    float zz=sqrt(max(0.,rd*rd-rr*rr));
    vec3 norm=normalize(vec3(delta,zz+.00001));
    float front=-4.08+centerPx/uRes.x*8.16;
    vec2 world=vec2(-4.08+px/uRes.x*8.16,(uv.y-.5)*.845);
    vec3 liquid=colorSurface(norm,vec3(world,zz+.35),2.*zz,world,front,1.-fullTip);
    float meniscusContact=G(rr-rd+.015,.023);
    liquid=mix(liquid,liquid*.71,meniscusContact*.28);
    fragColor=vec4(liquid*alpha,alpha);
}
