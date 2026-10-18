// Records a scenario: the inputs, and what the web build's sim did with them, into tests/fixtures.
//   WEB_REPO=/path/to/Skatepark- node tests/reference/record.mjs <level.glb> <collision.bin|-> <name> [name …]
// <name> is an existing tests/fixtures/<name>.input.json (re-records its expected trace), or one of: ride, rail, ledge, random:<seed>.
// <collision.bin>: from `godot --headless --path . -s res://tests/reference/dump_collision.gd -- collision.bin`.
import fs from 'node:fs';
import { buildWorld, run, mulberry } from './lib.mjs';

const [levelPath, collisionBin, ...names] = process.argv.slice(2);
const FIXTURES = new URL('../fixtures/', import.meta.url).pathname;
const BOUNDS = { x: 29, z: 22.5, cx: 0, cz: 0 };   // Gravesend, from scripts/levels.gd
const DT = 1 / 72;

// A timeline of [seconds, inputs] into per-frame inputs. Left stick = steer/drive, which is also the trick stick unless given.
const timeline = (list) => ({
  dt: DT,
  frames: list.flatMap(([dur, o = {}]) => Array.from({ length: Math.max(1, Math.round(dur / DT)) }, () =>
    [o.steer ?? 0, o.drive ?? 0, o.jump ?? 0, o.grind ?? 0, o.flip ?? 0, o.tsx ?? (o.steer ?? 0), o.tsy ?? -(o.drive ?? 0), o.lean ?? (o.steer ?? 0)])),
});

const GENERATED = {
  // rolling, carving, ollies, a kickflip, a manual, a shove-it and braking
  ride: () => timeline([[0.6], [3, { drive: 1 }], [1.5, { steer: 0.5, drive: 1 }], [1.5, { steer: -0.5, drive: 1 }], [0.8, { drive: 1 }], [0.25, { jump: 1 }], [0.9, { drive: 1 }],
    [0.2, { jump: 1 }], [0.12], [0.3, { flip: 1, steer: -1 }], [1], [2, { drive: 1 }], [0.15, { drive: 1 }], [0.15, { drive: -1 }], [1.5, { lean: 0 }], [0.2, { jump: 1 }], [0.15],
    [0.2, { flip: 1, tsx: 0, tsy: 1, drive: -1 }], [1], [2.5, { drive: -1 }]]),
  // from the spawn, turn left, ollie and press grind: a 50-50 on the rail
  rail: () => timeline([[0.5], [0.5, { steer: -0.6, drive: 1 }], [0.8, { drive: 1 }], [0.18, { jump: 1, drive: 1 }], [0.1, { drive: 1 }], [0.12, { drive: 1, grind: 1 }], [1.5, { drive: 0.3 }]]),
  // the same, but a longer run-up to the ledge on the box
  ledge: () => timeline([[0.5], [0.5, { steer: -0.6, drive: 1 }], [1.8, { drive: 1 }], [0.9, { drive: 1 }], [0.18, { jump: 1, drive: 1 }], [0.1, { drive: 1 }], [0.12, { drive: 1, grind: 1 }], [1.5, { drive: 0.3 }]]),
};
const STICKS = [[-1, 0], [1, 0], [0, 1], [-0.8, 0.8], [0.8, 0.8], [0, -1], [-1, -0.4]];
function random(seed) {
  const rnd = mulberry(seed);
  const pick = (a) => a[Math.floor(rnd() * a.length)];
  const list = [[0.5]];
  let total = 0.5, steer = 0;
  const add = (dur, o) => { list.push([dur, o]); total += dur; };
  while (total < 22) {
    const r = rnd();
    if (r < 0.40) { steer = pick([-1, -0.6, -0.3, 0, 0, 0.3, 0.6, 1]); add(0.3 + rnd() * 1.4, { steer, drive: rnd() < 0.85 ? 1 : 0 }); }
    else if (r < 0.62) {
      add(0.05 + rnd() * 0.4, { jump: 1, drive: 1, steer: steer * 0.3 });
      if (rnd() < 0.5) add(0.03 + rnd() * 0.15, { drive: 1 });
      if (rnd() < 0.55) { const [tx, ty] = pick(STICKS); add(0.12 + rnd() * 0.2, { flip: 1, tsx: tx, tsy: ty, steer: tx, drive: -ty }); }
      if (rnd() < 0.35) add(0.1, { grind: 1, drive: 0.4 });
      add(0.3 + rnd() * 0.8, { drive: rnd() < 0.5 ? 1 : 0, steer: pick([0, 0, -0.5, 0.5, 1, -1]) });
    } else if (r < 0.72) { add(0.08 + rnd() * 0.1, { drive: 1 }); add(0.08 + rnd() * 0.1, { drive: -1 }); add(0.6 + rnd() * 1.4, { lean: pick([0, 0, 0.3, -0.3]) }); }
    else if (r < 0.80) add(0.1, { grind: 1, drive: 1 });
    else if (r < 0.86) add(0.4 + rnd(), { drive: -1 });
    else if (r < 0.92) add(0.3 + rnd() * 0.8, { drive: 1, steer: pick([-1, 1]) });
    else add(0.3 + rnd(), { drive: 1, lean: pick([-0.6, 0.6, 0]) });
  }
  return timeline(list);
}

const ctx = await buildWorld(levelPath, collisionBin === '-' ? null : collisionBin);
for (const name of names) {
  const file = `${FIXTURES}${name}.input.json`;
  const scenario = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8'))
    : name.startsWith('random:') ? random(Number(name.slice(7))) : GENERATED[name]();
  const out = name.replace(':', '');
  fs.writeFileSync(`${FIXTURES}${out}.input.json`, JSON.stringify(scenario));
  const { trace, events } = run(ctx, scenario, BOUNDS);
  fs.writeFileSync(`${FIXTURES}${out}.expected.json`, JSON.stringify({ trace, events }));
  const kinds = {};
  for (const [, type] of events) kinds[type] = (kinds[type] || 0) + 1;
  console.log(`${out}: ${trace.length} frames`, JSON.stringify(kinds));
}
