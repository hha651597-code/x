const fs = require('fs');
const path = require('path');
const os = require('os');
const v = require(path.join(process.env.GLTF_VALIDATOR_DIR || path.join(os.homedir(), 'Tools', 'gltf-validator'), 'node_modules', 'gltf-validator'));
const p = process.argv[2];
const d = fs.readFileSync(p);
v.validateBytes(new Uint8Array(d), {uri: p, externalResourceFunction: (uri) => {
  const base = p.substring(0, p.lastIndexOf('/') + 1);
  return Promise.resolve(new Uint8Array(fs.readFileSync(base + decodeURIComponent(uri))));
}}).then(r => {
  const i = r.issues;
  console.log(p.split('/').pop(), 'errors', i.numErrors, 'warnings', i.numWarnings, 'infos', i.numInfos, 'hints', i.numHints);
  const seen = {};
  for (const m of i.messages) { seen[m.code] = (seen[m.code] || 0) + 1; }
  console.log(JSON.stringify(seen));
  for (const m of i.messages.filter(m => m.severity === 0).slice(0, 10)) console.log('ERR', m.code, m.message, m.pointer);
  for (const m of i.messages.filter(m => m.severity > 1).slice(0, 3)) console.log('INFO', m.code, m.message, m.pointer);
  console.log('info', JSON.stringify({vertices: r.info.totalVertexCount, triangles: r.info.totalTriangleCount, drawCalls: r.info.drawCallCount, materials: r.info.materialCount}));
}).catch(e => { console.error('validator failed', e); process.exit(1); });
