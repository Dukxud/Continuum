'use strict';
// Verify that the moving studio reflection loops only when it is out of view.
// The full GPU shader is also compiled and rendered by aero-webview-rendering.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,'..','assets','AeroBar.html'),'utf8');
const fragment = source.match(/<script id="hybridfrag"[^>]*>([\s\S]*?)<\/script>/)?.[1] ?? '';
const host = source.match(/<script>([\s\S]*?)<\/script><\/body>/)?.[1] ?? '';

const smoothstep=(a,b,x)=>{
 const p=Math.max(0,Math.min(1,(x-a)/(b-a)));
 return p*p*(3-2*p);
};

test('optical sweep is invisible at both sides of the wrap, with a smooth edge entry',()=>{
 const time=fragment.match(/float travel=fract\(uTime\*([.\d]+)\)/);
 const range=fragment.match(/float lightX=mix\((-?[.\d]+),(-?[.\d]+),travel\)/);
 const envelope=fragment.match(/float sweepEnvelope=smoothstep\((-?[.\d]+),(-?[.\d]+),lightX\)\*\s*\(1\.-smoothstep\((-?[.\d]+),(-?[.\d]+),lightX\)\)/);
 assert.ok(time&&range&&envelope,'Moving studio sweep and edge easing must be present');
 const [rate,left,right]=[Number(time[1]),Number(range[1]),Number(range[2])];
 const [enterA,enterB,exitA,exitB]=envelope.slice(1).map(Number);
 assert.ok(rate>0 && rate<1 && left<-4.08 && right>4.08,'Sweep must start and end outside the tube');
 const fade=x=>smoothstep(enterA,enterB,x)*(1-smoothstep(exitA,exitB,x));
 assert.equal(fade(left),0,'Loop begins with zero reflected light');
 assert.equal(fade(right),0,'Loop ends with zero reflected light');
 assert.equal(fade(0),1,'Mid-tube reflection must be full strength');
 assert.ok(fade(enterA+.25)<fade((enterA+enterB)/2));
 assert.ok(fade((enterA+enterB)/2)<fade(enterB));
 assert.ok(fade(exitA)>fade((exitA+exitB)/2));
 assert.ok(fade((exitA+exitB)/2)>fade(exitB-.25));
 // Immediately before and after fract() wraps, the sweep remains invisible.
 const epsilon=1e-6;
 assert.ok(fade(left+(right-left)*epsilon)<1e-7);
 assert.ok(fade(right-(right-left)*epsilon)<1e-7);
});

test('motion is independently phased; startup and re-enable ease shimmer in',()=>{
 assert.match(host,/const startOffset=Math\.random\(\)\/0\.135/);
 assert.match(host,/phase=startOffset/);
 assert.match(host,/getMotion:\(\)=>\(\{startOffset,phase,shimmerReveal\}\)/);
 assert.match(host,/shimmerReveal=Math\.min\(1,shimmerReveal\+dt\/\.65\)/);
 assert.match(host,/if\(nextAero && !aeroEnabled\)shimmerReveal=0/);
 assert.match(host,/shimmer\*shimmerReveal\*shimmerReveal\*\(3-2\*shimmerReveal\)/);
 const intensity=x=>x*x*(3-2*x);
 assert.equal(intensity(0),0);
 assert.ok(intensity(.1)<intensity(.5) && intensity(.5)<intensity(.9));
 assert.equal(intensity(1),1);
 assert.match(fragment,/float glint=G\(bentX,/,'A narrow high-polish reflection must be present');
 assert.match(fragment,/\*uShimmer\*sweepEnvelope/,'The complete moving reflection must be faded at entry and exit');
});
