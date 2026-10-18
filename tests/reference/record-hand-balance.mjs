// Records the web build's HandBalance on a synthetic hands sequence into tests/fixtures/hand_balance.json.
//   WEB_REPO=/path/to/Skatepark- node tests/reference/record-hand-balance.mjs
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const web = process.env.WEB_REPO;
const { HandBalance } = await import(pathToFileURL(path.join(web, 'dist/src/skate/hand-balance.js')).href);
const hb = new HandBalance();
const dt = 1 / 72;
const frames = [];
const expected = [];
for (let i = 0; i < 900; i++) {
  const tracked = !(i >= 500 && i < 540);                      // one hand lost for half a second
  const left = tracked ? { x: -0.3, y: 1.0 - 0.05 * Math.sin(i / 55), z: 0.1 } : null;
  const right = { x: 0.32, y: 1.0 + 0.12 * Math.sin(i / 40) + (i > 650 ? 0.08 : 0), z: -0.05 };
  const balancing = (i > 200 && i < 420) || (i > 600 && i < 760);
  const learn = !balancing && i % 97 !== 0;
  frames.push([left ? [left.x, left.y, left.z] : null, [right.x, right.y, right.z], balancing, learn]);
  expected.push(hb.update(dt, left, right, { balancing, learn }));
}
const out = new URL('../fixtures/hand_balance.json', import.meta.url).pathname;
fs.writeFileSync(out, JSON.stringify({ dt, frames, expected }));
console.log('recorded', frames.length, 'frames; lean range', Math.min(...expected).toFixed(3), Math.max(...expected).toFixed(3));
