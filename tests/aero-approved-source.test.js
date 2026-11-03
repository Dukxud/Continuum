// Prevent the approved optical material or corrected tip from silently regressing.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {Script} = require('node:vm');

const root = path.resolve(__dirname, '..');
// Compare the approved optical source, not the checkout's OS-dependent
// line endings. Every other character remains subject to exact equality.
const normalizeNewlines = source => source.replace(/\r\n?/g, '\n');
const reference = normalizeNewlines(fs.readFileSync(path.join(root,'design','Aero-v3-hybrid-approved-v2.0.1.html'),'utf8'));
const production = normalizeNewlines(fs.readFileSync(path.join(root,'assets','AeroBar.html'),'utf8'));
function script(source,id) {
  const match = source.match(new RegExp('<script id="'+id+'"[^>]*>([\\s\\S]*?)<\\/script>'));
  assert.ok(match,'Required shader/source '+id+' missing');
  return match[1];
}

test('source comparison normalizes Windows line endings but still detects altered optics',()=>{
  const shader=script(production,'hybridfrag');
  assert.equal(normalizeNewlines(shader.replaceAll('\n','\r\n')),shader);
  assert.notEqual(normalizeNewlines(shader.replace('float rd=.422;','float rd=.500;')),shader);
  assert.match(shader,/float rd=\.422;/);
});

test('production uses exact owner-approved vertex shader and corrected optical fragment',()=>{
  assert.equal(script(production,'v3vert'),script(reference,'v3vert'));
  // The approved 2.0.1 shader is unchanged except for a dedicated moving
  // specular reflection and its intensity uniform.
  const approved=script(reference,'hybridfrag');
  const augmented=script(production,'hybridfrag');
  const stripped=augmented
    .replace('uDepth,uCompact,uShimmer,uWorking;','uDepth,uCompact;')
    .replace(/ \/\/ A wide, softly reflected studio light[\s\S]*?\*uShimmer\*sweepEnvelope;\r?\n/, '')
    .replace(/ \/\/ Indeterminate work keeps a constant full tube[\s\S]*?reflectance\+=uWorking[^;]*;\r?\n/, '')
    .replace('    float fullTip=step(.999999,f);\n','')
    .replace('    tipPx=mix(tipPx,uRes.x-edgeX,step(.999999,f));\n','')
    .replace('dxPx=mix(max(px-centerPx,0.),0.,fullTip);','dxPx=max(px-centerPx,0.);')
    .replace('float alpha=cov*left*step(.00001,f)*.94*(1.-fullTip*smoothstep(uRes.x-edgeX-.5,uRes.x-edgeX+.5,px));','float alpha=cov*left*step(.00001,f)*.94;')
    // Remove only the owner-requested 100%-flat cap shading correction.
    .replace('vec3 colorSurface(vec3 normal,vec3 position,float thickness,vec2 p,float front,float capPresence){','vec3 colorSurface(vec3 normal,vec3 position,float thickness,vec2 p,float front){')
    .replace(' // The curved-end collar/glow must disappear when the head is flat at 100%.\n',' // A rounded end catches a localized curved cap reflection and dark collar.\n')
    .replace('float collar=capPresence*G(','float collar=G(')
    .replace('float capGlow=capPresence*G(','float capGlow=G(')
    .replace('float pFront=capPresence*G(','float pFront=G(')
    .replace('vec3 liquid=colorSurface(norm,vec3(world,zz+.35),2.*zz,world,front,1.-fullTip);','vec3 liquid=colorSurface(norm,vec3(world,zz+.35),2.*zz,world,front);');
  assert.equal(stripped,approved);
  assert.match(augmented,/specularPatch/);
  assert.match(augmented,/float sweepEnvelope=smoothstep/);
  assert.match(augmented,/float glint=G\(bentX,/);
  assert.match(augmented,/float currents=/);
  assert.match(augmented,/uniform float .*uWorking/);
  assert.match(production,/getFrames:\(\)=>frames/);
  assert.match(production,/getSettings:\(\)=>/);
  assert.ok(!production.includes('hybrid&&aero)'));

  assert.match(script(production,'hybridfrag'),/Shared pixel-space capsule/);
  assert.match(script(production,'hybridfrag'),/float cov=1\.-smoothstep/);
});

test('production preserves captured Windows v1.8 bar pixels and compositor',()=>{
  assert.deepEqual(JSON.parse(script(production,'native-images')),
                   JSON.parse(script(reference,'native-images')));
  const a=reference.match(/function nativePaint\(([\s\S]*?)function drawNativeAll\(\)/);
  const b=production.match(/function nativePaint\(([\s\S]*?)function paintNative\(\)/);
  assert.ok(a&&b);
  // The approved image compositor remains byte-for-byte intact; only its
  // outermost captured black terminal pixels are softened afterward.
  const baseline=b[1].split('// Leave the captured Windows source')[0]
    .replaceAll('aeroEnabled','aero')
    .replace('const tip=value>=1?w-edgeX:Math.max(edgeX,Math.min(w-edgeX,percent*w-2*w/400));',
             'const tip=Math.max(edgeX,Math.min(w-edgeX,percent*w-2*w/400));')
    .replace(/     if\(value>=1\)\{\r?\n       \/\/ At exactly 100%[^\n]*\r?\n       ctx\.rect\(edgeX,cy-rad,used,2\*rad\);\r?\n     \}else if\(used<rad\*2\)\{/,'     if(used<rad*2){')
    .trim();
  assert.equal(a[1].trim(),baseline);
  assert.match(production,/const tip=value>=1\?w-edgeX:/);
  assert.match(production,/if\(value>=1\)\{[\s\S]*?ctx\.rect\(edgeX,cy-rad,used,2\*rad\)/);
  assert.match(script(production,'hybridfrag'),/float fullTip=step\(\.999999,f\)/);
  assert.match(script(production,'hybridfrag'),/tipPx=mix\(tipPx,uRes\.x-edgeX,step\(\.999999,f\)\)/);
  assert.match(script(production,'hybridfrag'),/dxPx=mix\(max\(px-centerPx,0\.\),0\.,fullTip\)/);
  // Partial capsules retain their cap reflection. At full fill all three
  // localized cap highlights are disabled without changing the studio sweep.
  const fragment=script(production,'hybridfrag');
  assert.match(fragment,/colorSurface\(norm,vec3\(world,zz\+\.35\),2\.\*zz,world,front,1\.-fullTip\)/);
  for(const term of ['collar','capGlow','pFront']){
    assert.match(fragment,new RegExp('float '+term+'=capPresence\\\\*G\\\\('),term+' must be gated by the cap shape');
  }
  assert.match(production,/if\(value===1\)\{visual=1;velocity=0;lastNative=-1;\}/);
  assert.match(production,/function softenOutline\(canvas\)/);
});

test('isolated WebView2 page is local and its host API is syntactically valid',()=>{
  const source=production.match(/<script>([\s\S]*?)<\/script><\/body>/);
  assert.ok(source);
  new Script(source[1]);
  assert.match(production,/Content-Security-Policy/);
  assert.match(production,/connect-src 'none'/);
  assert.match(source[1],/window\.chrome\.webview\.addEventListener\('message'/);
  assert.match(source[1],/window\.aeroBarProof/);
  assert.match(source[1],/const startOffset=Math\.random\(\)\/0\.135/);
  assert.match(source[1],/phase=startOffset/);
  assert.match(source[1],/shimmerReveal\+dt\/\.65/);
  assert.match(source[1],/mode:nextMode/);
  assert.match(source[1],/if\(!working\)\{visual=1;velocity=0;lastNative=-1;\}/);
  assert.match(source[1],/getSettings:\(\)=>\(\{aero:aeroEnabled,finish,lighting,shimmer,speed,working\}\)/);
  assert.match(source[1],/getMotion:\(\)=>/);
  // Engine reporting is an asynchronous host-side JavaScript evaluation.
  // The page no longer requires a fragile browser-to-PowerShell handshake.
  const host=fs.readFileSync(path.join(root,'components','AeroProgress','AeroProgress.psm1'),'utf8');
  assert.match(host,/EngineProbe=\$control\.CoreWebView2\.ExecuteScriptAsync/);
  assert.match(host,/Complete-AeroProgressEngineProbe -State \$state/);
  assert.doesNotMatch(host,/Add_WebMessageReceived/);
  assert.doesNotMatch(source[1],/data\.type==='probe'/);
  assert.match(source[1],/requestAnimationFrame\(tick\)/);
  assert.equal((production.match(/getContext\('webgl2'/g)||[]).length,1);
  assert.match(source[1],/function updateCustomSprite/);
  assert.match(source[1],/selectedColor\.startsWith/);
});