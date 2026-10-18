// Records a scenario: the inputs, and what the web build's sim did with them, into tests/fixtures (Gravesend's) or
// tests/fixtures/<level id>/ (every other level's).
//   WEB_REPO=/path/to/Skatepark- node tests/reference/record.mjs <level id> <collision.bin|-> <name> [name …]
// <name> can also be scan:<from>-<to>: runs random:<from> … random:<to> and lists the grinds, loops and lip-airs each one gets into (nothing is
// recorded), to pick seeds that exercise a level's coping, bowls and loops.
// <name> is an existing fixture's name (re-records its expected trace), or one of: ride, rail, ledge, random:<seed>, or a scenario listed
// for that level in LEVEL_SCENARIOS below.
// <collision.bin>: from `godot --headless --path . -s res://tests/reference/dump_collision.gd -- <level id> collision.bin`.
import fs from 'node:fs';
import { buildWorld, run, mulberry } from './lib.mjs';

const [levelId, collisionBin, ...names] = process.argv.slice(2);
const ROOT = new URL('../../', import.meta.url).pathname;
const FIXTURES = new URL(levelId === 'gravesend' ? '../fixtures/' : `../fixtures/${levelId}/`, import.meta.url).pathname;
fs.mkdirSync(FIXTURES, { recursive: true });
// The level's model and play area, read from scripts/levels.gd so there is one place they are written down.
const entry = fs.readFileSync(`${ROOT}scripts/levels.gd`, 'utf8').split(new RegExp(`^\t"${levelId}": \{`, 'm'))[1].split(/^\t\},/m)[0];
const levelPath = ROOT + entry.match(/"file": "res:\/\/([^"]+)"/)[1];
const b = JSON.parse(entry.match(/"bounds": (\{[^}]*\})/)[1]);
const BOUNDS = { x: b.x, z: b.z, cx: b.cx, cz: b.cz };
const DT = 1 / 72;

// A timeline of [seconds, inputs] into per-frame inputs. Left stick = steer/drive, which is also the trick stick unless given.
// An entry's `grab` is the hands holding the board; `act` is something the hands do to the sim at the start of it (see lib.mjs run()).
const timeline = (list) => {
  const frames = [], actions = [];
  for (const [dur, o = {}] of list) {
    if (o.act) actions.push([frames.length, o.act]);
    for (let i = 0; i < Math.max(1, Math.round(dur / DT)); i++) {
      frames.push([o.steer ?? 0, o.drive ?? 0, o.jump ?? 0, o.grind ?? 0, o.flip ?? 0, o.tsx ?? (o.steer ?? 0), o.tsy ?? -(o.drive ?? 0), o.lean ?? (o.steer ?? 0), o.grab ?? 0]);
    }
  }
  return actions.length ? { dt: DT, frames, actions } : { dt: DT, frames };
};

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
// A run-up, then an ollie off the flat: the base for the air scenarios (the air starts after the 0.2 s release).
const ollie = [[0.5], [3, { drive: 1 }], [0.4, { jump: 1, drive: 1 }]];
GENERATED.backflip = () => timeline([...ollie, [0.05, { drive: 1 }], [1.1, { grab: 1, drive: -1, tsy: 1 }], [0.3, {}], [2]]);
GENERATED.frontflip = () => timeline([...ollie, [0.05, { drive: 1 }], [1.1, { grab: 1, drive: 1, tsy: -1 }], [0.3, {}], [2]]);
// land after a body flip of this many radians (a full turn is clean, a bit off is sketchy, further is a bail)
for (const [name, rad] of [['clean', 2 * Math.PI], ['front', -2 * Math.PI], ['double', 4 * Math.PI], ['sketchy', 2 * Math.PI + 0.9], ['bail', 2 * Math.PI + 1.6]]) {
  GENERATED['bodyroll_' + name] = () => timeline([...ollie, [0.05, { drive: 1, act: `roll:${rad}` }], [1.5, { drive: 1 }], [2]]);
}
GENERATED.boardoff_catch = () => timeline([...ollie, [0.1, { drive: 1, grab: 1 }], [0.2, { grab: 1, act: 'detach' }], [0.25, { grab: 1 }], [0.05, { grab: 1, act: 'catch_clean' }], [0.8, { drive: 1 }], [2]]);
GENERATED.boardoff_bail = () => timeline([...ollie, [0.1, { drive: 1, grab: 1 }], [0.2, { grab: 1, act: 'detach' }], [3]]);
GENERATED.boardoff_reversed = () => timeline([...ollie, [0.1, { drive: 1, grab: 1 }], [0.2, { grab: 1, act: 'detach' }], [0.2, { grab: 1 }], [0.05, { grab: 1, act: 'catch_sketchy_reversed' }], [0.8, { drive: 1 }], [2]]);
// Scenarios that only make sense on one level.
const LEVEL_SCENARIOS = {
  foundry: {
    // straight off the start tower: through the loop-the-loop, along the plaza to the big quarter (the air over its lip), back through
    // the loop the other way and up the tower's ramp
    fo_run: () => timeline([[0.5], [20, { drive: 1 }]]),
  },
  flightline: {
    // straight down from the start tower: the first gap (a bail, the respawn at the top), then again over the first gap and on to the second
    fl_run: () => timeline([[0.5], [24, { drive: 1 }]]),
  },
  megaramp: {
    // straight down the roll-in, over the big gap, up the vert quarter (the air over the lip holds you over the pit) and back down
    mega_run: () => timeline([[0.5], [15.5, { drive: 1 }]]),
    // the same, steering right on the run-out so the quarter is met at an angle: press grind near the top and the board latches onto the
    // coping (the magnet), grinds along it and drops off the end
    mega_coping: () => timeline([[0.5], [8.4, { drive: 1 }], [0.9, { drive: 1, steer: 1 }], [0.8, { drive: 1 }], [0.4, { drive: 1, grind: 1 }], [4, { drive: 0.3 }]]),
    // a slower catch: a long grind that runs the speed out of the coping
    mega_coping_slow: () => timeline([[0.5], [8.4, { drive: 1 }], [0.5, { drive: 1, steer: 1 }], [1.3, { drive: 1 }], [0.4, { drive: 1, grind: 1 }], [5, { drive: 0.3 }]]),
    // left unattended on the coping the balance meter dumps you
    mega_coping_bail: () => timeline([[0.5], [8.4, { drive: 1 }], [0.6, { drive: 1, steer: 1 }], [1.2, { drive: 1 }], [0.4, { drive: 1, grind: 1 }], [5, { drive: 0.3 }]]),
    // ollie out of the coping grind
    mega_coping_pop: () => timeline([[0.5], [8.4, { drive: 1 }], [0.9, { drive: 1, steer: 1 }], [0.8, { drive: 1 }], [0.4, { drive: 1, grind: 1 }], [0.1, { drive: 1, jump: 1 }], [3, { drive: 1 }]]),
    // an ollie on the wall of the quarter holding forward: committed to going over the top
    mega_lip_ollie: () => timeline([[0.5], [9.8, { drive: 1 }], [0.3, { drive: 1, jump: 1 }], [6, { drive: 1 }]]),
    // the same ollie with nothing held: stays over the pit
    mega_lip_stay: () => timeline([[0.5], [9.8, { drive: 1 }], [0.3, { drive: 1, jump: 1 }], [6]]),
  },
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
  if (name.startsWith('scan:')) {
    const [from, to] = name.slice(5).split('-').map(Number);
    for (let seed = from; seed <= to; seed++) {
      const seen = [];
      run(ctx, random(seed), BOUNDS, (type, data, frame) => {
        if (type === 'grindStart') seen.push(`${(frame / 72).toFixed(1)}s grind ${data.pathName} (${data.kind}, ${data.mode})`);
        else if (type === 'loopStart') seen.push(`${(frame / 72).toFixed(1)}s loop`);
      });
      console.log(`random:${seed}  ${seen.join(' | ') || '-'}`);
    }
    continue;
  }
  const file = `${FIXTURES}${name}.input.json`;
  const scenario = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8'))
    : name.startsWith('random:') ? random(Number(name.slice(7))) : (LEVEL_SCENARIOS[levelId]?.[name] ?? GENERATED[name])();
  const out = name.replace(':', '');
  fs.writeFileSync(`${FIXTURES}${out}.input.json`, JSON.stringify(scenario));
  const { trace, events } = run(ctx, scenario, BOUNDS);
  fs.writeFileSync(`${FIXTURES}${out}.expected.json`, JSON.stringify({ trace, events }));
  const kinds = {};
  for (const [, type] of events) kinds[type] = (kinds[type] || 0) + 1;
  console.log(`${out}: ${trace.length} frames`, JSON.stringify(kinds));
}
