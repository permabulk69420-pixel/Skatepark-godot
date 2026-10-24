// Cuts the Foundry's freestanding obstacles out of its level file as build mode pieces: one GLB with a node per piece, each centred on
// its own footprint at ground level, holding its look (one mesh per material, distance LODs left out), one COL_ collision mesh and its
// grind lines. What lay under or round it (the slab, its saw-cut joints, the bowl's deck, the perimeter wall it backed onto) is left
// behind: each piece is only itself, so it suits whatever ground it is put on.
//   node tools/extract-foundry-pieces.mjs [assets/levels/foundry.glb] [assets/foundry_pieces/foundry_pieces.glb]
// The obstacles' extents are those of the web build's Foundry generator (tools/foundry/park.mjs there). x is east, z south, y up.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune } from '@gltf-transform/functions';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const [input = 'assets/levels/foundry.glb', output = 'assets/foundry_pieces/foundry_pieces.glb'] = process.argv.slice(2);

// box: [x0, z0, x1, z1] round the obstacle; areas: its collision (COL_<area>); paths: the grind lines whose names start so.
// backed: it was built against the south perimeter wall (z 35.6): the wall's face and steel edge there are left out.
// hole: it goes down into the ground; the outline (on the ground, level coordinates) the level must leave open for it.
const SOUTH_WALL = 35.6;
const PIECES = [
  { id: 'seven_stairs', box: [-36.1, -4.1, -13.8, 7.2], areas: ['Street'], paths: ['SevenStairs_', 'BigSeven_'] },
  { id: 'five_stairs', box: [-36.1, 16.3, -23.4, SOUTH_WALL + 0.01], areas: ['Street'], paths: ['FiveStairs_', 'Five_Hubba'], backed: true },
  { id: 'three_stairs', box: [-18.4, 23.9, -5.9, SOUTH_WALL + 0.01], areas: ['Street'], paths: ['ThreeStairs_'], backed: true },
  { id: 'long_ledge', box: [-2.5, -6.2, -1.5, 4.2], areas: ['Street'], paths: ['Long_Ledge'] },
  { id: 'kink_funbox', box: [-5.7, 11.0, -1.6, 21.6], areas: ['Street'], paths: ['Funbox_'] },
  { id: 'kicker', box: [-16.1, 11.7, -14.4, 14.3], areas: ['Street'], paths: [] },
  { id: 'curved_ledge', box: [2.9, 24.9, 10.1, 32.1], areas: ['Street'], paths: ['Curved_Ledge'] },
  { id: 'mini_ramp', box: [11.9, -4.1, 23.1, 2.1], areas: ['Mini'], paths: ['Mini_'] },
  { id: 'big_quarter', box: [23.9, -34.6, 30.0, -20.9], areas: ['Quarter'], paths: ['BigQuarter_'] },
  { id: 'concrete_quarter', box: [32.5, -14.1, 36.6, -1.9], areas: ['Quarter'], paths: ['EastQuarter_'] },
  { id: 'foundry_bowl', box: [17.8, 10.8, 32.2, 21.2], areas: ['Bowl'], paths: ['Bowl_'], hole: bowlOutline({ cx: 25, cz: 16, hx: 7, hz: 5, rc: 3 }) },
];
const GROUND = 0.01;   // a level triangle no higher than this is the ground (the slab, a joint painted on it, the bowl's deck)

// The Foundry bowl's rim, as its generator draws it: a rounded rectangle, 20 points round each corner and one every 0.4 m or less along
// each straight, from the east end of the north side round anticlockwise seen from above.
function bowlOutline({ cx, cz, hx, hz, rc }) {
  const corners = [[hx - rc, -(hz - rc), 0], [-(hx - rc), -(hz - rc), Math.PI / 2], [-(hx - rc), hz - rc, Math.PI], [hx - rc, hz - rc, Math.PI * 1.5]];
  const out = [];
  for (let c = 0; c < 4; c++) {
    const [ox, oz, a0] = corners[c];
    for (let i = 0; i < 20; i++) {
      const a = a0 + (i / 20) * Math.PI / 2;
      out.push([cx + ox + rc * Math.cos(a), cz + oz - rc * Math.sin(a)]);
    }
    const [nx, nz, na] = corners[(c + 1) % 4];
    const a1 = a0 + Math.PI / 2;
    const from = [cx + ox + rc * Math.cos(a1), cz + oz - rc * Math.sin(a1)], to = [cx + nx + rc * Math.cos(na), cz + nz - rc * Math.sin(na)];
    const k = Math.max(1, Math.ceil(Math.hypot(to[0] - from[0], to[1] - from[1]) / 0.4));
    for (let i = 0; i < k; i++) out.push([from[0] + (to[0] - from[0]) * i / k, from[1] + (to[1] - from[1]) * i / k]);
  }
  return out;
}

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const scene = root.getDefaultScene() ?? root.listScenes()[0];
const buffer = root.listBuffers()[0];
const originals = root.listNodes();

// Every triangle of the level, in world space, with what it is made of.
function apply(m, [x, y, z], w) {
  return [m[0] * x + m[4] * y + m[8] * z + m[12] * w, m[1] * x + m[5] * y + m[9] * z + m[13] * w, m[2] * x + m[6] * y + m[10] * z + m[14] * w];
}
const visual = [];      // { material, verts: [{p, n, uv, colour}] × 3 }
const collision = {};   // area -> [[p, p, p]]
const paths = [];
for (const node of originals) {
  const extras = node.getExtras() ?? {};
  if (extras.role === 'grind_path') paths.push({ name: node.getName(), extras });
  const mesh = node.getMesh();
  if (!mesh || (extras.lod && extras.lod.level > 0)) continue;
  const m = node.getWorldMatrix();
  const isCollision = node.getName().startsWith('COL_');
  for (const prim of mesh.listPrimitives()) {
    const pos = prim.getAttribute('POSITION'), nor = prim.getAttribute('NORMAL'), uv = prim.getAttribute('TEXCOORD_0');
    const col = prim.getAttribute('COLOR_0'), idx = prim.getIndices();
    const count = idx ? idx.getCount() : pos.getCount();
    const vert = (i) => {
      const p = apply(m, pos.getElement(i, []), 1);
      if (isCollision) return { p };
      let n = nor ? apply(m, nor.getElement(i, []), 0) : [0, 1, 0];
      const l = Math.hypot(...n) || 1;
      n = n.map((v) => v / l);
      const c = col ? col.getElement(i, []) : [1, 1, 1, 1];
      return { p, n, uv: uv ? uv.getElement(i, []) : [0, 0], colour: c.length === 3 ? [...c, 1] : c };
    };
    for (let t = 0; t < count; t += 3) {
      const tri = [0, 1, 2].map((k) => vert(idx ? idx.getScalar(t + k) : t + k));
      if (isCollision) (collision[node.getName().slice(4)] ??= []).push(tri.map((v) => v.p));
      else visual.push({ material: prim.getMaterial(), verts: tri });
    }
  }
}

const centroid = (ps) => [0, 1, 2].map((k) => (ps[0][k] + ps[1][k] + ps[2][k]) / 3);
const normalOf = ([a, b, c]) => {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
  const l = Math.hypot(...n) || 1;
  return n.map((x) => x / l);
};
function keeps(piece, ps, material) {
  const [x0, z0, x1, z1] = piece.box;
  const c = centroid(ps);
  if (c[0] < x0 || c[0] > x1 || c[2] < z0 || c[2] > z1) return false;
  const n = normalOf(ps);
  if (ps.every((p) => Math.abs(p[1]) < GROUND) && Math.abs(n[1]) > 0.99) return false;   // the ground under or round it
  if (piece.backed && c[2] > SOUTH_WALL - 0.1 && (n[2] < -0.5 || material?.getName().startsWith('Steel | graphite'))) return false;
  return true;
}

function accessor(type, array) {
  return doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
}

const top = doc.createNode('FoundryPieces');
for (const piece of PIECES) {
  const [x0, z0, x1, z1] = piece.box;
  const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;
  const node = doc.createNode(piece.id);
  top.addChild(node);
  // its look: one primitive per material
  const byMaterial = new Map();
  for (const tri of visual) {
    if (!keeps(piece, tri.verts.map((v) => v.p), tri.material)) continue;
    if (!byMaterial.has(tri.material)) byMaterial.set(tri.material, []);
    byMaterial.get(tri.material).push(tri.verts);
  }
  const mesh = doc.createMesh(piece.id);
  for (const [material, tris] of byMaterial) {
    const n = tris.length * 3;
    const P = new Float32Array(n * 3), N = new Float32Array(n * 3), U = new Float32Array(n * 2), C = new Float32Array(n * 4);
    tris.flat().forEach((v, i) => {
      P.set([v.p[0] - cx, v.p[1], v.p[2] - cz], i * 3);
      N.set(v.n, i * 3);
      U.set(v.uv, i * 2);
      C.set(v.colour, i * 4);
    });
    const prim = doc.createPrimitive().setMaterial(material)
      .setAttribute('POSITION', accessor('VEC3', P)).setAttribute('NORMAL', accessor('VEC3', N))
      .setAttribute('TEXCOORD_0', accessor('VEC2', U)).setAttribute('COLOR_0', accessor('VEC4', C));
    mesh.addPrimitive(prim);
  }
  const look = doc.createNode(`${piece.id}_look`).setMesh(mesh);
  node.addChild(look);
  // its collision, as one mesh
  const solid = [];
  for (const area of piece.areas) for (const tri of collision[area] ?? []) if (keeps(piece, tri, null)) solid.push(...tri);
  const S = new Float32Array(solid.length * 3);
  solid.forEach((p, i) => S.set([p[0] - cx, p[1], p[2] - cz], i * 3));
  const colMesh = doc.createMesh(`COL_${piece.id}`).addPrimitive(doc.createPrimitive().setAttribute('POSITION', accessor('VEC3', S)));
  node.addChild(doc.createNode(`COL_${piece.id}`).setMesh(colMesh).setExtras({ role: 'collision' }));
  // its grind lines
  let lines = 0;
  for (const { name, extras } of paths) {
    if (!piece.paths.some((p) => name.startsWith(`PATH_${p}`))) continue;
    const points = extras.points.map((v, i) => +(i % 3 === 0 ? v - cx : i % 3 === 2 ? v - cz : v).toFixed(4));
    node.addChild(doc.createNode(name).setExtras({ ...extras, points }));
    lines++;
  }
  if (piece.hole) {
    const points = piece.hole.flatMap(([x, z]) => [+(x - cx).toFixed(4), +(z - cz).toFixed(4)]);
    node.addChild(doc.createNode(`HOLE_${piece.id}`).setExtras({ role: 'ground_hole', points }));
  }
  console.log(`${piece.id}: ${byMaterial.size} materials, ${[...byMaterial.values()].reduce((s, t) => s + t.length, 0)} triangles, ` +
    `${solid.length / 3} collision triangles, ${lines} grind lines, ${(x1 - x0).toFixed(1)} × ${(z1 - z0).toFixed(1)} m`);
}

for (const node of originals) node.dispose();
for (const s of root.listScenes()) s.dispose();
doc.createScene('FoundryPieces').addChild(top);
await doc.transform(prune({ keepLeaves: true }));
mkdirSync(path.dirname(output), { recursive: true });
await io.write(output, doc);
