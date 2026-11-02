// Bakes the procedural glyph-ring textures of the web build into PNGs (same seeds, same drawing code),
// so the Godot port uses identical script rings. Run from the web repo checkout:
//   node tools/gen_glyph_textures.mjs <path-to-ultrablast-turbo-pc/src/00_core.js> <out dir>
import { createRequire } from 'module';
const { chromium } = createRequire(import.meta.url)('playwright');
import fs from 'fs';
const [core, out] = process.argv.slice(2);
const src = fs.readFileSync(core, 'utf8');
const pick = (name) => { const i = src.indexOf(name); let d = 0, j = src.indexOf('{', i); for (let k = j; k < src.length; k++) { if (src[k] === '{') d++; if (src[k] === '}') { d--; if (!d) return src.slice(i, k + 1); } } };
const code = [
  'const TAU=Math.PI*2; const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));',
  pick('function mulberry32'), pick('function drawGlyph'), pick('function scriptRingCanvas'),
  pick('function scriptRingTexture').replace('const t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace; return t;', 'return cv;')
].join('\n');
const jobs = [
  ['glyph_ring_orb0', 'scriptRingTexture(100,"#ffffff",30)'], ['glyph_ring_orb1', 'scriptRingTexture(113,"#ffffff",30)'],
  ['glyph_ring_portal', 'scriptRingTexture(77,"#ffffff",26)'], ['glyph_ring_pickup13', 'scriptRingTexture(13,"#ffffff",18)'],
  ['glyph_ring_pickup11', 'scriptRingTexture(11,"#ffffff",18)'], ['glyph_ring_fx', 'scriptRingTexture(42,"#ffffff",22)'],
  ['glyph_ring_homing', 'scriptRingTexture(313,"#ffffff",18)'],
  ['puzzle_ring_orb', 'scriptRingCanvas(420,0.40,22,501,"#f4c6a0",0.05,2.4)'], ['puzzle_ring_outer', 'scriptRingCanvas(720,0.415,44,777,"#f4c6a0",0.032,2.2)'],
  ['puzzle_ring_inner', 'scriptRingCanvas(480,0.375,30,913,"#f4c6a0",0.04,2.0)'], ['puzzle_ring_info', 'scriptRingCanvas(240,0.4,14,333,"#f4c6a0",0.07,2)'],
];
const b = await chromium.launch(); const p = await b.newPage();
await p.setContent('<html><body></body></html>');
await p.addScriptTag({ content: code + '\nwindow.__make=(e)=>eval(e).toDataURL("image/png");' });
for (const [name, expr] of jobs) {
  const url = await p.evaluate(e => window.__make(e), expr);
  fs.writeFileSync(`${out}/${name}.png`, Buffer.from(url.split(',')[1], 'base64'));
  console.log('wrote', name);
}
await b.close();
