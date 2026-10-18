// Runs the web build's own sim (dist/src/skate/sim.js in the Skatepark- repo) on a level's collision mesh, so the Godot port can be
// checked against it. Point WEB_REPO at a checkout of that repo that has had `npm install` run (it needs `three`).
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

const web = process.env.WEB_REPO;
if (!web) throw new Error('set WEB_REPO to the path of the Skatepark- web repo (with node_modules installed)');
const load = (rel) => import(pathToFileURL(path.join(web, rel)).href);
export const THREE = await load('node_modules/three/build/three.module.js');
const { acceleratedRaycast, computeBoundsTree } = await load('dist/vendor/mesh-bvh.js');
const { SkateWorld } = await load('dist/src/skate/world.js');
const { parseGrindPaths } = await load('dist/src/skate/rails.js');
const { Skater } = await load('dist/src/skate/sim.js');

export const MODES = ['ground', 'air', 'grind', 'bail', 'loop'];

function colliderFrom(positions, indices, name) {
  const geom = new THREE.BufferGeometry();
  geom.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geom.setIndex(new THREE.BufferAttribute(indices, 1));
  const mesh = new THREE.Mesh(geom);
  mesh.name = name;
  geom.computeBoundingBox(); geom.computeBoundingSphere();
  computeBoundsTree.call(geom, { maxLeafTris: 12 });
  mesh.raycast = acceleratedRaycast;
  return mesh;
}

// levelPath: a GLB from tools/prepare-level.mjs. collisionBin: the triangles written by dump_collision.gd (Godot rounds the mesh
// vertices on import, so for a like-for-like comparison use those exact triangles); pass null to use the file's own mesh.
export async function buildWorld(levelPath, collisionBin = null) {
  const doc = await new NodeIO().registerExtensions(ALL_EXTENSIONS).read(levelPath);
  const colliders = [], grindNodes = [];
  const spawn = new THREE.Vector3(); let spawnHeading = 0;
  for (const node of doc.getRoot().listNodes()) {
    const extras = node.getExtras() || {};
    const world = new THREE.Matrix4().fromArray(node.getWorldMatrix());
    if (extras.role === 'collision' || node.getName().startsWith('COL_')) {
      let mesh;
      if (collisionBin) {
        // Godot's faces are clockwise; three.js wants counter-clockwise, so swap the last two vertices of each triangle back.
        const raw = fs.readFileSync(collisionBin);
        const f = new Float32Array(raw.buffer, raw.byteOffset, raw.byteLength / 4);
        const flipped = new Float32Array(f.length);
        for (let t = 0; t < f.length; t += 9) for (let k = 0; k < 3; k++) { flipped[t + k] = f[t + k]; flipped[t + 3 + k] = f[t + 6 + k]; flipped[t + 6 + k] = f[t + 3 + k]; }
        const idx = new Uint32Array(flipped.length / 3).map((_, i) => i);
        mesh = colliderFrom(flipped, idx, node.getName());
      } else {
        const prim = node.getMesh().listPrimitives()[0];
        mesh = colliderFrom(Float32Array.from(prim.getAttribute('POSITION').getArray()), Uint32Array.from(prim.getIndices().getArray()), node.getName());
        mesh.applyMatrix4(world);
      }
      mesh.updateMatrixWorld(true);
      colliders.push(mesh);
    } else if (extras.role === 'grind_path') {
      const o = new THREE.Object3D();
      o.name = node.getName(); o.userData = extras; o.applyMatrix4(world); o.updateMatrixWorld(true);
      grindNodes.push(o);
    } else if (extras.role === 'spawn') {
      spawn.set(...node.getWorldTranslation());
      spawnHeading = extras.heading_radians ?? 0;
    }
  }
  return { world: new SkateWorld(colliders), paths: parseGrindPaths(grindNodes), spawn, spawnHeading };
}

// Same generator the Godot test uses, so the balance wobble and bail tumble line up.
export function mulberry(seed = 12345) {
  return () => { seed = (seed + 0x6D2B79F5) >>> 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// frames: [[steer, drive, jump, grind, flip, stickX, stickY, lean], …]. bounds: the level's play area from levels.gd.
export function run(ctx, { dt, frames }, bounds) {
  const events = [];
  let frame = 0;
  const sim = new Skater({ world: ctx.world, paths: ctx.paths, loops: [], bounds, requireGrind: true, random: mulberry(), onEvent: (type) => events.push([frame, type]) });
  sim.setSpawn(ctx.spawn, ctx.spawnHeading);
  events.length = 0;
  const trace = [];
  for (frame = 0; frame < frames.length; frame++) {
    const [steer, drive, jump, grind, flip, tsx, tsy, lean] = frames[frame];
    sim.update({ steer, drive, jump: !!jump, grind: !!grind, flip: !!flip, trickStick: { x: tsx, y: tsy }, lean, grabbing: false, detach: false, bodyY: undefined }, dt);
    trace.push([sim.pos.x, sim.pos.y, sim.pos.z, sim.vel.x, sim.vel.y, sim.vel.z, sim.heading, MODES.indexOf(sim.mode)].map((v, i) => (i < 7 ? Math.round(v * 1e6) / 1e6 : v)));
  }
  return { trace, events };
}
