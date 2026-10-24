"""Run: blender -b --factory-startup --python tools/build_baths.py [-- --samples 256]
The Baths: an indoor park in a Victorian public swimming baths, drained and taken over. A tiled hall 84 × 40 m under a glass roof on
arched iron trusses, galleries down both sides on cast-iron columns (rails along them, stairs at each end), changing cubicles with
tiled benches under the galleries, and three drained pools: a 33 m main pool sloping from 1.2 m deep to a 3.4 m deep end, a 4.2 m
diving pool under a diving tower, and a kidney-shaped learner pool. Skaters have added a plywood roll-in off the south gallery (where
you start), a spine between the big pools and a quarter pipe against the east wall.

The light (the sun through the roof and the windows, the sky, the hanging lamps, and all of it bouncing round the hall) is baked with
Cycles into each vertex's colour, gamma-encoded over GAIN; the game draws the level unlit, textures × that light (scripts/baked_light.gd).
Textures are CC0 from Poly Haven (downloaded to art/baths/downloads the first time; assets/levels/baths_source.json says where from).

Everything is written in Godot's axes (x east, y up, z south) and turned into Blender's (x, -z, y) as the meshes are made.
"""
import bpy, bmesh, json, hashlib, math, os, ssl, sys, time, urllib.request
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.geometry import delaunay_2d_cdt
from math import sin, cos, acos, atan2, pi, sqrt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/levels'
DOWNLOADS = ROOT / 'art/baths/downloads'
DOWNLOADS.mkdir(parents=True, exist_ok=True)
(ROOT / 'art/baths/.gdignore').touch()
ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
SAMPLES = int(ARGS[ARGS.index('--samples') + 1]) if '--samples' in ARGS else 256
GAIN = 3.0          # baked light is stored as (light / GAIN), sRGB-encoded; the game multiplies it back
SUN = Vector((-0.55, 0.53, 0.65)).normalized()   # towards the sun (Godot axes): low in the south-west, through the south windows

# ---- the hall's plan -----------------------------------------------------------------------------------------------------------
HX, HZ = 42.0, 20.0           # inside faces of the walls
EAVES, RIDGE = 13.0, 19.0
GAL_Y, GAL_T = 3.4, 0.35      # gallery floor top, thickness
GAL_FRONT = 16.0              # galleries: |z| from 16 to 20
GAL_X = 35.0                  # galleries run x -35..35; stairs off each end
COL_Z = 16.25                 # the cast-iron columns under the gallery fronts
CUBICLE_Z = 17.2              # changing cubicle fronts
BENCH = (16.62, 0.45)         # tiled bench: front |z|, height
COPING = 0.35                 # pool coping, out from the pool's edge
ROLL_X = (-4.6, -0.4)         # the roll-in, off the south gallery


def B(p):
    """Godot axes to Blender's."""
    return (p[0], -p[2], p[1])


# ---- textures and materials ----------------------------------------------------------------------------------------------------
TEXTURES = {   # key: (Poly Haven id, resolution, metres one repeat covers)
    'deck': ('floor_tiles_06', '2k', 1.4),   # (shown smaller than the photo's 3 m: tiles a Victorian floor would have)
    'wall_tiles': ('long_white_tiles', '2k', 1.27),
    'brick': ('red_brick_03', '2k', 1.0),
    'plaster': ('painted_plaster_wall', '2k', 2.0),
    'boards': ('wood_floor_worn', '2k', 2.0),
    'iron': ('green_metal_rust', '1k', 1.0),
    'doors': ('blue_painted_planks', '1k', 1.0),
    'mosaic': ('rounded_square_tiled_wall', '2k', 2.0),
    'stone': ('concrete_wall_008', '2k', 2.71),
    'ply': ('plywood', '1k', 0.5),
    'osb': ('oriented_strand_board', '2k', 2.51),
    'bench_wood': ('brown_planks_05', '1k', 1.0),
}
sources = {}


def fetch(asset, res):
    folder = DOWNLOADS / asset
    folder.mkdir(exist_ok=True)
    url = f'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/{res}/{asset}/{asset}_diff_{res}.jpg'
    path = folder / f'{asset}_diff_{res}.jpg'
    if not path.exists():
        context = ssl.create_default_context(cafile=os.environ.get('SSL_CERT_FILE'))
        with urllib.request.urlopen(url, context=context) as r:
            path.write_bytes(r.read())
    sources[asset] = {'source': f'https://polyhaven.com/a/{asset}', 'license': 'CC0-1.0',
                      'files': {path.name: {'url': url, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}}}
    return path


MATS = {}   # key -> (bpy material, tile metres)


def textured(key, name, tex, tint=None, rough=0.6):
    asset, res, size = TEXTURES[tex]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = rough
    img = nodes.new('ShaderNodeTexImage')
    img.image = bpy.data.images.load(str(fetch(asset, res)), check_existing=True)
    colour = img.outputs['Color']
    if tint:
        mix = nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs['Factor'].default_value = 1.0
        mix.inputs['B'].default_value = (*tint, 1)
        links.new(colour, mix.inputs['A'])
        colour = mix.outputs['Result']
    links.new(colour, bsdf.inputs['Base Color'])
    MATS[key] = (m, size)


def solid(key, name, colour, rough=0.5, metal=0.0, emit=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*colour, 1)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if emit:
        bsdf.inputs['Emission Color'].default_value = (*colour, 1)
        bsdf.inputs['Emission Strength'].default_value = emit
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
        m.blend_method = 'BLEND'
    MATS[key] = (m, 1.0)


# ---- geometry, gathered per material in Godot axes ------------------------------------------------------------------------------
class Part:
    def __init__(self):
        self.verts, self.faces, self.uvs = [], [], []


PARTS = {}          # material key -> Part
COLLISION = []      # triangles (Godot axes)
PATHS = []          # grind lines
EMPTIES = []        # (name, position, extras)


def newell(pts):
    n = Vector((0, 0, 0))
    for i, a in enumerate(pts):
        b = pts[(i + 1) % len(pts)]
        n += Vector(a).cross(Vector(b))
    return n


def facing(pts, want):
    pts = [tuple(p) for p in pts]
    return pts if newell(pts).dot(Vector(want)) >= 0 else pts[::-1]


def box_uv(p, n, tile):
    a = max(range(3), key=lambda k: abs(n[k]))
    if a == 1:
        return (p[0] / tile, p[2] / tile)
    if a == 0:
        return (p[2] / tile, p[1] / tile)
    return (p[0] / tile, p[1] / tile)


def poly(mat, pts, want, uvs=None, collide=False):
    """A polygon (Godot axes) of material `mat`, its front facing along `want`."""
    pts = [tuple(p) for p in pts]
    if newell(pts).dot(Vector(want)) < 0:
        pts = pts[::-1]
        if uvs:
            uvs = uvs[::-1]
    part = PARTS.setdefault(mat, Part())
    n = newell(pts).normalized()
    base = len(part.verts)
    for i, p in enumerate(pts):
        part.verts.append(p)
        part.uvs.append(uvs[i] if uvs else box_uv(p, n, MATS[mat][1]))
    part.faces.append(tuple(range(base, base + len(pts))))
    if collide:
        for k in range(1, len(pts) - 1):
            COLLISION.append((pts[0], pts[k], pts[k + 1]))


def collide_poly(pts, want):
    pts = facing(pts, want)
    for k in range(1, len(pts) - 1):
        COLLISION.append((pts[0], pts[k], pts[k + 1]))


def grid(mat, origin, du, dv, nu, nv, want, collide=False, uv_fn=None):
    """A flat rectangle origin + s·du + t·dv (s, t in 0..1), split nu × nv (so the bake has vertices to light)."""
    o, du, dv = Vector(origin), Vector(du), Vector(dv)
    for i in range(nu):
        for j in range(nv):
            q = [o + du * (i / nu) + dv * (j / nv), o + du * ((i + 1) / nu) + dv * (j / nv),
                 o + du * ((i + 1) / nu) + dv * ((j + 1) / nv), o + du * (i / nu) + dv * ((j + 1) / nv)]
            poly(mat, q, want, [uv_fn(p) for p in q] if uv_fn else None)
    if collide:
        collide_poly([o, o + du, o + du + dv, o + dv], want)


def rect(mat, origin, du, dv, want, step=0.4, collide=False):
    nu = max(1, math.ceil(Vector(du).length / step))
    nv = max(1, math.ceil(Vector(dv).length / step))
    grid(mat, origin, du, dv, nu, nv, want, collide)


def block(mat, lo, hi, collide=True, top=None, step=0.5, skip=()):
    """An axis-aligned box (Godot axes): its faces split for the bake. `top`: another material for its top; `skip`: faces left out
    (x0 x1 y0 y1 z0 z1)."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    faces = {
        'y1': ((x0, y1, z0), (x1 - x0, 0, 0), (0, 0, z1 - z0), (0, 1, 0)),
        'y0': ((x0, y0, z0), (x1 - x0, 0, 0), (0, 0, z1 - z0), (0, -1, 0)),
        'x0': ((x0, y0, z0), (0, y1 - y0, 0), (0, 0, z1 - z0), (-1, 0, 0)),
        'x1': ((x1, y0, z0), (0, y1 - y0, 0), (0, 0, z1 - z0), (1, 0, 0)),
        'z0': ((x0, y0, z0), (x1 - x0, 0, 0), (0, y1 - y0, 0), (0, 0, -1)),
        'z1': ((x0, y0, z1), (x1 - x0, 0, 0), (0, y1 - y0, 0), (0, 0, 1)),
    }
    for key, (o, du, dv, want) in faces.items():
        if key in skip:
            continue
        rect(top if (key == 'y1' and top) else mat, o, du, dv, want, step)
        if collide and key != 'y0':
            collide_poly([Vector(o), Vector(o) + Vector(du), Vector(o) + Vector(du) + Vector(dv), Vector(o) + Vector(dv)], want)


def beam(mat, a, b, w, h, collide=False, up=(0, 1, 0)):
    """A rectangular bar from a to b, w across and h up."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    side = d.cross(Vector(up))
    if side.length < 1e-6:
        side = d.cross(Vector((1, 0, 0)))
    side.normalize()
    upv = side.cross(d).normalized()
    corners = [side * sx * w / 2 + upv * sy * h / 2 for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    steps = max(1, math.ceil((b - a).length / 0.6))
    for k in range(4):
        c0, c1 = corners[k], corners[(k + 1) % 4]
        out = (c0 + c1) / 2
        for s in range(steps):
            pa, pb = a + (b - a) * (s / steps), a + (b - a) * ((s + 1) / steps)
            q = [pa + c0, pb + c0, pb + c1, pa + c1]
            poly(mat, q, out)
            if collide:
                collide_poly(q, out)
    for end, p, out in ((0, a, -d), (1, b, d)):
        q = [p + c for c in corners]
        poly(mat, q, out)
        if collide:
            collide_poly(q, out)


def tube(mat, path, r, sides=10, collide=False, caps=True):
    """A round tube along `path`."""
    path = [Vector(p) for p in path]
    rings = []
    for k, p in enumerate(path):
        t = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
        u = t.cross(Vector((0, 1, 0)))
        if u.length < 1e-4:
            u = t.cross(Vector((1, 0, 0)))
        u.normalize()
        v = u.cross(t).normalized()
        rings.append([p + (u * cos(2 * pi * j / sides) + v * sin(2 * pi * j / sides)) * r for j in range(sides)])
    for k in range(len(path) - 1):
        for j in range(sides):
            q = [rings[k][j], rings[k][(j + 1) % sides], rings[k + 1][(j + 1) % sides], rings[k + 1][j]]
            out = (q[0] + q[1]) / 2 - path[k]
            poly(mat, q, out, [(j / sides, k * 0.5), ((j + 1) / sides, k * 0.5), ((j + 1) / sides, (k + 1) * 0.5), (j / sides, (k + 1) * 0.5)])
            if collide:
                collide_poly(q, out)
    if caps:
        poly(mat, rings[0], path[0] - path[1])
        poly(mat, rings[-1], path[-1] - path[-2])


def cylinder(mat, base, h, r, sides=12, collide=True, rings=None):
    rings = rings or max(1, math.ceil(h / 0.4))
    path = [Vector(base) + Vector((0, h * k / rings, 0)) for k in range(rings + 1)]
    tube(mat, path, r, sides, False)
    if collide:   # (an octagonal prism is plenty to ride into)
        pts = [Vector(base) + Vector((cos(2 * pi * j / 8) * r, 0, sin(2 * pi * j / 8) * r)) for j in range(8)]
        for j in range(8):
            a, b = pts[j], pts[(j + 1) % 8]
            collide_poly([a, b, b + Vector((0, h, 0)), a + Vector((0, h, 0))], (a + b) / 2 - Vector(base))
        collide_poly([p + Vector((0, h, 0)) for p in pts], (0, 1, 0))


def inside(pt, polygon):
    x, z = pt
    hit = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, zi = polygon[i]
        xj, zj = polygon[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi:
            hit = not hit
        j = i
    return hit


def fill(outer, holes, step, emit):
    """Triangles filling the 2D polygon `outer` less `holes`, with points every `step` inside (for the bake), each made 3D by emit(u, v).
    Returns a list of 3D triangles."""
    pts, edges = [], []

    def loop(polygon):
        start = len(pts)
        pts.extend(polygon)
        edges.extend((start + i, start + (i + 1) % len(polygon)) for i in range(len(polygon)))
    loop(outer)
    for h in holes:
        loop(h)
    us = [p[0] for p in outer]
    vs = [p[1] for p in outer]
    boxes = [(min(p[0] for p in h) - step, max(p[0] for p in h) + step, min(p[1] for p in h) - step, max(p[1] for p in h) + step) for h in holes]
    u = min(us) + step / 2
    while u < max(us):
        v = min(vs) + step / 2
        while v < max(vs):
            ok = inside((u, v), outer)
            for (a, b, c, d), h in zip(boxes, holes):
                if ok and a <= u <= b and c <= v <= d and inside((u, v), h):
                    ok = False
            if ok:
                pts.append((u, v))
            v += step
        u += step
    cdt = delaunay_2d_cdt([Vector(p) for p in pts], edges, [], 0, 1e-7)
    verts, faces = cdt[0], cdt[2]
    tris = []
    for f in faces:
        a, b, c = (verts[i] for i in f[:3])
        centre = ((a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3)
        if not inside(centre, outer) or any(inside(centre, h) for h in holes):
            continue
        tris.append([emit(a.x, a.y), emit(b.x, b.y), emit(c.x, c.y)])
    return tris


def fill_poly(mat, outer, holes, step, emit, want, collide=False, uv=None):
    for t in fill(outer, holes, step, emit):
        poly(mat, t, want, [uv(p) for p in t] if uv else None)
        if collide:
            collide_poly(t, want)


def grind(name, points, radius, kind, closed=False):
    PATHS.append((name, {'role': 'grind_path', 'kind': kind, 'closed': closed, 'radius': radius,
                         'points': [round(v, 4) for p in points for v in p]}))


def arched(cx, y0, w, top, n=10):
    """An arched window's outline, (u, y) on its wall: straight sides from y0 to the springing, a semicircle over."""
    r = w / 2
    spring = top - r
    pts = [(cx - r, y0), (cx + r, y0)]
    for k in range(n + 1):
        a = pi * k / n
        pts.append((cx + r * cos(a), spring + r * sin(a)))
    return pts


# ---- outlines (pools) ------------------------------------------------------------------------------------------------------------
def resample(points, step, closed=True):
    pts = [Vector(p) for p in points]
    if closed:
        pts.append(pts[0])
    out = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, math.ceil((b - a).length / step))
        out.extend(a.lerp(b, k / n) for k in range(n))
    return [(p.x, p.y) for p in out]


def rounded_rect(x0, x1, z0, z1, r, step=0.3):
    pts = []
    for cx, cz, a0 in ((x1 - r, z1 - r, 0), (x0 + r, z1 - r, pi / 2), (x0 + r, z0 + r, pi), (x1 - r, z0 + r, 1.5 * pi)):
        for k in range(9):
            a = a0 + (pi / 2) * k / 8
            pts.append((cx + r * cos(a), cz + r * sin(a)))
    return resample(pts, step)


def catmull(points, step=0.3, per=24):
    n = len(points)
    dense = []
    for i in range(n):
        p0, p1, p2, p3 = (Vector(points[(i + k) % n]) for k in (-1, 0, 1, 2))
        for k in range(per):
            t = k / per
            dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return resample([(p.x, p.y) for p in dense], step)


def normals_out(outline):
    """Outward normals (in x z) of a closed outline."""
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(outline, outline[1:] + outline[:1]))
    sign = 1 if area > 0 else -1
    out = []
    for i in range(len(outline)):
        a, b = Vector(outline[i - 1]), Vector(outline[(i + 1) % len(outline)])
        t = (b - a).normalized()
        out.append(Vector((t.y, -t.x)) * sign)
    return out


def offset(outline, normals, d):
    return [(p[0] + n.x * d, p[1] + n.y * d) for p, n in zip(outline, normals)]


def uv_sphere(mat, centre, r, rings=8, segs=12):
    c = Vector(centre)
    for i in range(rings):
        for j in range(segs):
            def at(ii, jj):
                th, ph = pi * ii / rings, 2 * pi * jj / segs
                return c + Vector((sin(th) * cos(ph), cos(th), sin(th) * sin(ph))) * r
            q = [at(i, j), at(i, j + 1), at(i + 1, j + 1), at(i + 1, j)]
            poly(mat, q, sum(q, Vector()) / 4 - c)


# ---- a pool: tiled walls with a transition into its floor, pool coping round it, its grind line ---------------------------------
def pool(name, outline, depth, rmax, wall='pool', band='band_pool', floor='pool', min_vert=0.15, gap=None):
    """`gap(x, z)`: where the wall is left open (the steps down into the shallow end stand there instead)."""
    normals = normals_out(outline)
    n = len(outline)
    lengths = [0.0]
    for a, b in zip(outline, outline[1:] + outline[:1]):
        lengths.append(lengths[-1] + (Vector(b) - Vector(a)).length)
    rows, toes = [], []
    for (x, z), nrm in zip(outline, normals):
        D = depth(x, z)
        R = min(D - min_vert, rmax)
        vert = D - R
        prof = [(0.0, -0.10), (0.0, -vert)]
        prof += [(R * (1 - cos(t)), -D + R * (1 - sin(t))) for t in (pi / 2 * k / 18 for k in range(1, 19))]
        rows.append([(x - nrm.x * i, y, z - nrm.y * i) for i, y in prof])
        toes.append((x - nrm.x * R, z - nrm.y * R))
    m = len(rows[0])
    # the walls: tiles, a band of darker tiles under the coping
    tile = MATS[wall][1]
    for i in range(n):
        j = (i + 1) % n
        if gap and gap(*outline[i]) and gap(*outline[j]):
            continue
        nrm = (normals[i] + normals[j]) / 2
        want = (-nrm.x, 0.5, -nrm.y)
        s0, s1 = lengths[i], lengths[i] + (Vector(outline[j]) - Vector(outline[i])).length
        down = [0.0]
        for k in range(m - 1):
            down.append(down[-1] + (Vector(rows[i][k + 1]) - Vector(rows[i][k])).length)
        for k in range(m - 1):
            q = [rows[i][k], rows[j][k], rows[j][k + 1], rows[i][k + 1]]
            mid_y = (q[0][1] + q[3][1]) / 2
            uv = [(s0 / tile, -down[k] / tile), (s1 / tile, -down[k] / tile), (s1 / tile, -down[k + 1] / tile), (s0 / tile, -down[k + 1] / tile)]
            poly(band if mid_y > -0.32 else wall, q, want, uv)
            collide_poly(q, want)
        collide_poly([(rows[i][0][0], 0.0, rows[i][0][2]), (rows[j][0][0], 0.0, rows[j][0][2]), rows[j][0], rows[i][0]], want)
    # the floor
    fill_poly(floor, toes, [], 0.35, lambda u, v: (u, -depth(u, v), v), (0, 1, 0), collide=True)
    # pool coping: a bullnose block whose round front overhangs the wall, its top level with the deck
    cprof = [(COPING, 0.0), (0.0, 0.0)] + [(0.05 * cos(a), -0.05 + 0.05 * sin(a)) for a in (pi / 2 + pi * k / 10 for k in range(1, 11))]
    crow = [[(x + nrm.x * o, y, z + nrm.y * o) for o, y in cprof] for (x, z), nrm in zip(outline, normals)]
    for i in range(n):
        j = (i + 1) % n
        nrm = (normals[i] + normals[j]) / 2
        for k in range(len(cprof) - 1):
            q = [crow[i][k], crow[j][k], crow[j][k + 1], crow[i][k + 1]]
            o = (cprof[k][0] + cprof[k + 1][0]) / 2 - 0.12
            yy = (cprof[k][1] + cprof[k + 1][1]) / 2 + 0.05
            poly('stone', q, (nrm.x * o, yy, nrm.y * o))
        collide_poly([crow[i][0], crow[j][0], crow[j][1], crow[i][1]], (0, 1, 0))
        if i % 3 == 0:   # the joints between the coping stones
            p, nr = Vector((outline[i][0], 0.0, outline[i][1])), Vector((normals[i].x, 0, normals[i].y))
            side = Vector((-nr.z, 0, nr.x)) * 0.004
            poly('joint', [p + side + Vector((0, 0.0015, 0)), p - side + Vector((0, 0.0015, 0)),
                           p - side + nr * COPING + Vector((0, 0.0015, 0)), p + side + nr * COPING + Vector((0, 0.0015, 0))], (0, 1, 0))
    grind(f'{name}_Coping', [(x, -0.05, z) for x, z in outline[::2]], 0.05, 'coping', closed=True)
    return offset(outline, normals, COPING)


# ---- the hall ------------------------------------------------------------------------------------------------------------------
def main_depth(x, z):
    if x <= -19:
        return 1.2
    if x <= -5:
        return 1.2 + 0.8 * (x + 19) / 14
    if x <= -1:
        return 2.0 + 1.4 * (x + 5) / 4
    return 3.4


def build():
    holes = []
    # the main pool: 33 × 14 m, shallow end west
    main = []   # (rounder at the deep end, so its 2.6 m transition fits the corners)
    for cx, cz, a0, r in ((6 - 3.0, 7 - 3.0, 0, 3.0), (-27 + 1.5, 7 - 1.5, pi / 2, 1.5), (-27 + 1.5, -7 + 1.5, pi, 1.5), (6 - 3.0, -7 + 3.0, 1.5 * pi, 3.0)):
        for k in range(13):
            a = a0 + (pi / 2) * k / 12
            main.append((cx + r * cos(a), cz + r * sin(a)))
    main = resample(main, 0.3)
    holes.append(pool('MainPool', main, main_depth, 2.6, gap=lambda x, z: x < -26.5 and abs(z) < 2.0))
    # lane lines down its floor, and a T at the deep end of each
    for zl in (-3.5, 0.0, 3.5):
        xs = [-25.0 + 0.5 * k for k in range(56)]
        for xa, xb in zip(xs, xs[1:]):
            poly('pool_dark', [(xa, -main_depth(xa, 0) + 0.004, zl - 0.12), (xb, -main_depth(xb, 0) + 0.004, zl - 0.12),
                               (xb, -main_depth(xb, 0) + 0.004, zl + 0.12), (xa, -main_depth(xa, 0) + 0.004, zl + 0.12)], (0, 1, 0))
        poly('pool_dark', [(2.35, -3.396, zl - 0.6), (2.6, -3.396, zl - 0.6), (2.6, -3.396, zl + 0.6), (2.35, -3.396, zl + 0.6)], (0, 1, 0))
    # steps down into the shallow end, with a rail each side
    for k in range(1, 6):
        top = -0.24 * k
        block('stone', (-27.0, -1.2, -2.0), (-27.0 + 0.4 * k, top, 2.0), top='stone', skip=('y0', 'x0'))
    rect('band_pool', (-27.0, -0.24, -2.0), (0, 0, 4.0), (0, 0.14, 0), (1, 0, 0), 0.3, collide=True)   # (behind the top step, up to the coping)
    for zr in (-1.75, 1.75):
        rail = [(-28.1, 0.0, zr), (-28.1, 0.9, zr), (-27.5, 0.9, zr), (-25.2, -0.3, zr), (-25.2, -1.2, zr)]
        tube('chrome', rail, 0.025, 10)
        beam('chrome', rail[0], rail[1], 0.05, 0.05, collide=True)
        beam('chrome', rail[3], rail[4], 0.05, 0.05, collide=True)
        grind(f'PoolSteps_Rail_{"N" if zr < 0 else "S"}', rail[1:4], 0.025, 'rail')
    # ladders at the deep end
    for zs in (-1, 1):
        for xl in (2.7, 3.2):
            z0 = zs * 7.0
            pts = [(xl, 0.0, zs * 7.55), (xl, 0.75, zs * 7.55)]
            for k in range(1, 9):
                a = pi * k / 8
                pts.append((xl, 0.75 + 0.28 * sin(a) - 0.0, zs * (7.55 - 0.32 * (1 - cos(a)) * 1.25)))
            pts.append((xl, -1.6, zs * 6.85))
            tube('chrome', pts, 0.02, 8, caps=True)
        for k in range(4):
            yk = -0.3 - 0.35 * k
            tube('chrome', [(2.7, yk, zs * 6.88), (3.2, yk, zs * 6.88)], 0.015, 6)

    # the diving pool: 12 × 12 m, 4.2 m deep
    holes.append(pool('DivingPool', rounded_rect(16, 28, -6, 6, 3.2), lambda x, z: 4.2, 3.0, min_vert=1.2))
    # the learner pool: a kidney, 1.6 m deep
    kidney = [(-35.5 + dx, -10.0 + dz) for dx, dz in ((-4.2, -1.0), (-3.2, -3.3), (-0.5, -3.8), (2.4, -3.2), (4.3, -1.2), (4.0, 1.4),
                                                        (2.0, 2.6), (0.2, 1.7), (-1.6, 2.9), (-3.8, 2.0))]
    holes.append(pool('LearnerPool', catmull(kidney), lambda x, z: 1.6, 1.4, wall='pool_green', band='band_pool', floor='pool_green'))

    # the deck: tiles everywhere the pools are not
    fill_poly('deck', [(-HX, -HZ), (HX, -HZ), (HX, HZ), (-HX, HZ)], holes, 0.35, lambda u, v: (u, 0.0, v), (0, 1, 0), collide=True)

    walls()
    roof()
    for s in (1, -1):
        gallery(s)
    ramps()
    tower()
    furniture()
    lamps()
    EMPTIES.append(('Spawn_Entrance', (-2.5, GAL_Y + 0.03, 18.0), {'role': 'spawn', 'heading_radians': 0.0}))


def wall_bands(mat_lo, origin, along, length, height_top, holes_uv, want, top_fn=None):
    """A wall face: tiles to 3.4 m, a band of green tiles, brick above (with window `holes_uv`, as (u, y)). `top_fn(u)` its top."""
    o, d = Vector(origin), Vector(along).normalized()
    emit = lambda u, y: tuple(o + d * u + Vector((0, y, 0)))
    for mat, y0, y1 in (('wall_tiles', 0.0, GAL_Y), ('band', GAL_Y, GAL_Y + 0.3)):
        rect(mat, emit(0, y0), d * length, (0, y1 - y0, 0), want, 0.4)
    if top_fn:   # (a gable: the top follows the roof)
        outer = [(0, GAL_Y + 0.3), (length, GAL_Y + 0.3)] + [(u, top_fn(u)) for u in (length * k / 40 for k in range(40, -1, -1))]
    else:
        outer = [(0, GAL_Y + 0.3), (length, GAL_Y + 0.3), (length, height_top), (0, height_top)]
    fill_poly('brick', outer, holes_uv, 0.45, emit, want)
    collide_poly([emit(0, 0), emit(length, 0), emit(length, height_top), emit(0, height_top)], want)


def window(origin, along, inward, outline_uv, depth=0.6, bars=True):
    """The reveal, sill and glass of a window opening in a wall (origin: the wall's inner face at u = 0, y = 0)."""
    o, d, w = Vector(origin), Vector(along).normalized(), Vector(inward).normalized()
    p3 = [o + d * u + Vector((0, y, 0)) for u, y in outline_uv]
    for i in range(len(p3)):
        a, b = p3[i], p3[(i + 1) % len(p3)]
        q = [a, b, b - w * depth, a - w * depth]
        centre = sum((Vector((u, y)) for u, y in outline_uv), Vector((0.0, 0.0))) / len(outline_uv)
        mid = Vector((((outline_uv[i][0] + outline_uv[(i + 1) % len(p3)][0]) / 2), (outline_uv[i][1] + outline_uv[(i + 1) % len(p3)][1]) / 2))
        towards = d * (centre.x - mid.x) + Vector((0, centre.y - mid.y, 0))
        poly('stone' if i == 0 else 'brick', q, towards)
    glass = [p - w * depth * 0.6 for p in p3]
    poly('glass', glass, w)
    if bars:
        us = [u for u, _ in outline_uv]
        ys = [y for _, y in outline_uv]
        u0, u1, y0, y1 = min(us), max(us), min(ys), max(ys)
        k = 1
        while u0 + 0.55 * k < u1 - 0.1:
            u = u0 + 0.55 * k
            top = max(y for (uu, y) in outline_uv if abs(uu - u) < 0.35) if any(abs(uu - u) < 0.35 for uu, _ in outline_uv[2:]) else y1
            beam('iron', o + d * u + Vector((0, y0, 0)) - w * depth * 0.6, o + d * u + Vector((0, min(top, y1) - 0.05, 0)) - w * depth * 0.6, 0.04, 0.05)
            k += 1
        y = y0 + 0.8
        while y < y1 - 1.2:
            beam('iron', o + d * u0 + Vector((0, y, 0)) - w * depth * 0.6, o + d * u1 + Vector((0, y, 0)) - w * depth * 0.6, 0.05, 0.04)
            y += 0.8


def walls():
    gable = lambda u: EAVES + (RIDGE - EAVES) * (1 - abs(u - HZ) / HZ)
    # long walls: arched clerestory windows above the galleries
    xs = [-31.5 + 7 * k for k in range(10)]
    for s in (1, -1):
        origin = (-HX, 0, s * HZ)
        win = [arched(x + HX, 6.0, 2.6, 11.2) for x in xs]
        if s > 0:
            SOUTH_WINDOWS.extend(win)
        wall_bands('wall_tiles', origin, (1, 0, 0), 2 * HX, EAVES, win, (0, 0, -s))
        for w_ in win:
            window(origin, (1, 0, 0), (0, 0, -s), w_)
    # the east end: a great lunette under the ridge, two tall windows
    east = [arched(HZ - 7, 4.5, 2.4, 11.0), arched(HZ + 7, 4.5, 2.4, 11.0)]
    lunette = [(HZ + 5.5 * cos(pi * k / 16), EAVES + 5.5 * sin(pi * k / 16)) for k in range(17)]
    east.append(lunette)
    wall_bands('wall_tiles', (HX, 0, -HZ), (0, 0, 1), 2 * HZ, RIDGE, east, (-1, 0, 0), gable)
    for w_ in east:
        window((HX, 0, -HZ), (0, 0, 1), (-1, 0, 0), w_)
    # the west end: the entrance doors, the name over them, a clock in the gable
    wall_bands('wall_tiles', (-HX, 0, HZ), (0, 0, -1), 2 * HZ, RIDGE, [], (1, 0, 0), gable)
    for z0, z1 in ((-2.7, -0.15), (0.15, 2.7)):
        block('doors', (-HX, 0.0, z0), (-HX + 0.06, 3.5, z1), collide=False, skip=('x0',))
        beam('iron', (-HX + 0.08, 0.0, (z0 + z1) / 2), (-HX + 0.08, 3.5, (z0 + z1) / 2), 0.05, 0.08)
    block('stone', (-HX, 3.5, -3.0), (-HX + 0.25, 3.8, 3.0), collide=False, skip=('x0',))
    TEXTS.append(('MARLOWE STREET BATHS', (-HX + 0.05, 4.7, 0.0), (0, 0, -1), 0.95, 'gold'))
    TEXTS.append(('1898', (-HX + 0.05, 13.0, 0.0), (0, 0, -1), 0.7, 'gold'))
    clock((-HX + 0.08, 15.6, 0.0))


def clock(c):
    c = Vector(c)
    ring = [c + Vector((0, 1.35 * sin(2 * pi * k / 32), 1.35 * cos(2 * pi * k / 32))) for k in range(33)]
    tube('iron', ring, 0.09, 8, caps=False)
    disc = [c + Vector((0.02, 1.28 * sin(2 * pi * k / 32), 1.28 * cos(2 * pi * k / 32))) for k in range(32)]
    poly('clock_face', disc, (1, 0, 0))
    for k in range(12):
        a = 2 * pi * k / 12
        p = c + Vector((0.03, 1.05 * cos(a), 1.05 * sin(a)))
        beam('black', p, p + Vector((0, 0.18 * cos(a), 0.18 * sin(a))), 0.05, 0.02)
    beam('black', c + Vector((0.05, 0, 0)), c + Vector((0.05, 0.62, 0.25)), 0.07, 0.02)
    beam('black', c + Vector((0.06, 0, 0)), c + Vector((0.06, -0.3, -0.85)), 0.05, 0.02)


def roof():
    # glass on both slopes, iron glazing bars, purlins, and an arched truss every 6 m
    for s in (1, -1):
        a, b = (-HX, EAVES, s * HZ), (HX, EAVES, s * HZ)
        c, d = (HX, RIDGE, 0.0), (-HX, RIDGE, 0.0)
        poly('glass', [a, b, c, d], (0, -1, 0))
        for k in range(57):
            x = -HX + 1.5 * k
            beam('iron', (x, EAVES - 0.05, s * HZ), (x, RIDGE - 0.05, 0.0), 0.05, 0.08)
        for f in (0.25, 0.5, 0.75):
            y, z = EAVES + (RIDGE - EAVES) * f, s * HZ * (1 - f)
            beam('iron', (-HX, y - 0.1, z), (HX, y - 0.1, z), 0.1, 0.16)
    beam('iron', (-HX, RIDGE - 0.15, 0), (HX, RIDGE - 0.15, 0), 0.2, 0.3)
    for k in range(15):
        x = -HX + 6 * k
        rib = []
        for j in range(25):
            t = -1 + 2 * j / 24
            rib.append((x, 11.0 + 6.6 * (1 - t * t) ** 0.85, HZ * t))
        tube('iron', rib, 0.11, 8)
        tube('iron', [(x, EAVES, -HZ), (x, EAVES, HZ)], 0.05, 6)
        for j in range(2, 23, 3):
            p = Vector(rib[j])
            f = 1 - abs(p.z) / HZ
            beam('iron', p, (x, EAVES + (RIDGE - EAVES) * f - 0.15, p.z), 0.06, 0.06)
        for s in (1, -1):   # the brackets where each truss meets the wall
            beam('iron', (x, 9.5, s * (HZ - 0.05)), (x, 11.3, s * (HZ - 0.9)), 0.12, 0.12)


def gallery(s):
    z_front, z_back = s * GAL_FRONT, s * HZ
    lo, hi = (-GAL_X, GAL_Y - GAL_T, min(z_front, z_back)), (GAL_X, GAL_Y, max(z_front, z_back))
    block('plaster', lo, hi, top='boards', skip=('z1' if s > 0 else 'z0',))
    beam('iron', (-GAL_X, GAL_Y - 0.22, z_front + s * 0.02), (GAL_X, GAL_Y - 0.22, z_front + s * 0.02), 0.06, 0.18)
    # cast-iron columns, with brackets up to the gallery
    for k in range(15):
        x = max(-34.7, min(34.7, -35 + 5 * k))   # (the end ones stand clear of the stairs)
        cylinder('iron', (x, 0, s * COL_Z), GAL_Y - GAL_T, 0.13, 12)
        block('iron', (x - 0.22, 0, s * COL_Z - 0.22), (x + 0.22, 0.3, s * COL_Z + 0.22))
        block('iron', (x - 0.2, GAL_Y - GAL_T - 0.25, s * COL_Z - 0.2), (x + 0.2, GAL_Y - GAL_T, s * COL_Z + 0.2), collide=False)
        for dx in (-1, 1):
            beam('iron', (x, GAL_Y - 1.0, s * COL_Z), (x + dx * 0.8, GAL_Y - GAL_T - 0.02, s * COL_Z), 0.06, 0.06)
    # the balustrade: posts, rails, balusters; open where the roll-in leaves
    runs = [(-GAL_X, ROLL_X[0]), (ROLL_X[1], GAL_X)] if s > 0 else [(-GAL_X, GAL_X)]
    zr = z_front + s * 0.08
    for a, b in runs:
        tube('iron', [(a, GAL_Y + 1.0, zr), (b, GAL_Y + 1.0, zr)], 0.035, 10)
        for yy in (GAL_Y + 0.12, GAL_Y + 0.55):
            beam('iron', (a, yy, zr), (b, yy, zr), 0.03, 0.03)
        n = max(1, round((b - a) / 1.25))
        for k in range(n + 1):
            x = a + (b - a) * k / n
            beam('iron', (x, GAL_Y, zr), (x, GAL_Y + 1.0, zr), 0.06, 0.06)
        n = max(1, round((b - a) / 0.16))
        for k in range(n):
            x = a + (b - a) * (k + 0.5) / n
            beam('iron', (x, GAL_Y + 0.12, zr), (x, GAL_Y + 0.55, zr), 0.018, 0.018)
        collide_poly([(a, GAL_Y, zr), (b, GAL_Y, zr), (b, GAL_Y + 1.03, zr), (a, GAL_Y + 1.03, zr)], (0, 0, -s))
        collide_poly([(a, GAL_Y, zr), (b, GAL_Y, zr), (b, GAL_Y + 1.03, zr), (a, GAL_Y + 1.03, zr)], (0, 0, s))
        grind(f'Gallery_{"S" if s > 0 else "N"}_Rail_{int(a)}', [(a, GAL_Y + 1.0, zr), (b, GAL_Y + 1.0, zr)], 0.035, 'rail')
    # changing cubicles under it: a row of doors, and a tiled bench along their fronts
    zc = s * CUBICLE_Z
    rect('plaster', (-34.5, 0, zc), (69, 0, 0), (0, GAL_Y - GAL_T, 0), (0, 0, -s), 0.4, collide=True)
    for k in range(57):
        x = -34.2 + 1.2 * k
        block('doors', (x + 0.08, 0.22, zc - s * 0.04 if s > 0 else zc), (x + 1.0, 2.05, zc if s > 0 else zc + 0.04), collide=False)
        beam('iron', (x, 0.0, zc - s * 0.03), (x, 2.3, zc - s * 0.03), 0.07, 0.05)
    beam('iron', (-34.5, 2.3, zc - s * 0.03), (34.5, 2.3, zc - s * 0.03), 0.07, 0.08)
    zb0, zb1 = sorted((s * BENCH[0], zc))
    block('wall_tiles', (-34.0, 0, zb0), (34.0, BENCH[1], zb1), top='stone', skip=('z1' if s > 0 else 'z0',))
    edge = s * (BENCH[0] + 0.03)
    grind(f'Bench_{"S" if s > 0 else "N"}', [(-34.0, BENCH[1] + 0.027, edge), (34.0, BENCH[1] + 0.027, edge)], 0.03, 'ledge')
    # stairs off each end of the gallery, with handrails
    for e in (1, -1):
        z0, z1 = sorted((s * 16.3, s * 19.75))
        for i in range(1, 19):
            top = GAL_Y - 0.179 * i
            xa, xb = e * (GAL_X + 0.3 * (i - 1)), e * (GAL_X + 0.3 * i)
            block('stone', (min(xa, xb) if e > 0 else xb, 0.0, z0), (xb if e > 0 else xa, top, z1), skip=('y0',))
        zi, zw = s * 16.4, s * 19.65
        for zz, name in ((zi, 'Inner'), (zw, 'Wall')):
            top_pt, bot_pt = (e * (GAL_X - 0.3), GAL_Y + 0.9, zz), (e * (GAL_X + 5.4), 0.9, zz)
            end_pt = (e * (GAL_X + 5.9), 0.9, zz)
            tube('iron', [top_pt, (e * GAL_X, GAL_Y + 0.9, zz), bot_pt, end_pt], 0.03, 10)
            grind(f'Stairs_{"S" if s > 0 else "N"}{"E" if e > 0 else "W"}_{name}', [(e * GAL_X, GAL_Y + 0.9, zz), bot_pt], 0.03, 'rail')
            for k in range(5):
                f = k / 4
                x = e * (GAL_X + 5.4 * f)
                y = GAL_Y * (1 - f)
                beam('iron', (x, y, zz), (x, y + 0.9, zz), 0.05, 0.05, collide=(name == 'Inner'))


def ramp_profile_rollin(H=GAL_Y, slope=45.0, r1=0.6, R=3.5):
    """Roll-in, from the lip (d = 0, y = H) down to the floor: rounded lip, straight slope, transition."""
    a = math.radians(slope)
    pts = []
    for k in range(9):
        t = a * k / 8
        pts.append((r1 * sin(t), H - r1 * (1 - cos(t))))
    d0, y0 = pts[-1]
    drop = y0 - R * (1 - cos(a))
    run = drop / math.tan(a)
    d1 = d0 + run
    for k in range(1, 25):
        t = a * (1 - k / 24)
        pts.append((d1 + R * (sin(a) - sin(t)), R * (1 - cos(t)) + 0.003))
    return pts


def extrude_profile(mat, prof, origin, along, across, width, want_up=True, side_mat='osb', collide=True, back=True):
    """A ramp from a profile [(d, y)]: d along `along` from `origin`, `width` along `across`. Sides closed to the floor."""
    o, a, c = Vector(origin), Vector(along).normalized(), Vector(across).normalized()
    at = lambda d, y, w: o + a * d + c * w + Vector((0, y, 0))
    nw = max(1, math.ceil(width / 0.35))
    for k in range(len(prof) - 1):
        (d0, y0), (d1, y1) = prof[k], prof[k + 1]
        n = Vector(at(d1, y1, 0) - at(d0, y0, 0)).cross(c)
        up = n if n.y > 0 else -n
        for j in range(nw):
            w0, w1 = width * j / nw, width * (j + 1) / nw
            q = [at(d0, y0, w0), at(d1, y1, w0), at(d1, y1, w1), at(d0, y0, w1)]
            poly(mat, q, up)
        if collide:
            collide_poly([at(d0, y0, 0), at(d1, y1, 0), at(d1, y1, width), at(d0, y0, width)], up)
    outline = [(d, y) for d, y in prof] + [(prof[-1][0], 0.0), (prof[0][0], 0.0)]
    for w, out in ((0.0, -c), (width, c)):
        pts = [at(d, y, w) for d, y in outline]
        for t in fill(outline, [], 0.35, lambda d, y: tuple(at(d, y, w))):
            poly(side_mat, t, out)
        if collide:
            for t in fill(outline, [], 10.0, lambda d, y: tuple(at(d, y, w))):
                collide_poly(t, out)
    if back and prof[0][1] > 0.05:
        rect(side_mat, at(prof[0][0], 0, 0), c * width, (0, prof[0][1], 0), -a, 0.4, collide=collide)


def quarter_profile(H, R, deck):
    A = acos(1 - H / R)
    pts = [(R * sin(A) - R * sin(t), R * (1 - cos(t)) + 0.003 * (1 - t / A)) for t in (A * (1 - k / 32) for k in range(33))]
    return [(-deck, H)] + [(d, y) for d, y in pts]


def ramps():
    # the roll-in off the south gallery: lip at the gallery's front, down towards the main pool
    prof = ramp_profile_rollin()
    extrude_profile('ply', prof, (ROLL_X[0], 0, GAL_FRONT), (0, 0, -1), (1, 0, 0), ROLL_X[1] - ROLL_X[0])
    tube('galv', [(ROLL_X[0] - 0.02, GAL_Y + 0.01, GAL_FRONT - 0.005), (ROLL_X[1] + 0.02, GAL_Y + 0.01, GAL_FRONT - 0.005)], 0.035, 14)
    grind('RollIn_Coping', [(ROLL_X[0], GAL_Y + 0.01, GAL_FRONT - 0.005), (ROLL_X[1], GAL_Y + 0.01, GAL_FRONT - 0.005)], 0.035, 'coping')
    foot = GAL_FRONT - prof[-1][0]
    block('plate', (ROLL_X[0], 0, foot - 0.25), (ROLL_X[1], 0.004, foot + 0.05), collide=False)
    # a spine between the main pool and the diving pool
    H, R = 1.2, 1.6
    A = acos(1 - H / R)
    run = R * sin(A)
    half = [(run - R * sin(t), R * (1 - cos(t)) + 0.003 * (1 - t / A)) for t in (A * (1 - k / 32) for k in range(33))]
    for side in (1, -1):
        extrude_profile('ply', half, (11.0, 0, -5.5 if side > 0 else 5.5), (side, 0, 0), (0, 0, 1) if side > 0 else (0, 0, -1), 11.0, back=False)
        block('plate', (min(11 + side * run, 11 + side * (run + 0.25)), 0, -5.5), (max(11 + side * run, 11 + side * (run + 0.25)), 0.004, 5.5), collide=False)
    tube('galv', [(11.0, H + 0.01, -5.52), (11.0, H + 0.01, 5.52)], 0.035, 14)
    grind('Spine_Coping', [(11.0, H + 0.01, -5.4), (11.0, H + 0.01, 5.4)], 0.035, 'coping')
    # a quarter pipe against the east wall
    prof = quarter_profile(1.8, 2.4, 1.0)
    extrude_profile('ply', [(d, y) for d, y in prof], (HX - 1.05, 0, -15.0), (-1, 0, 0), (0, 0, 1), 11.0, back=False)
    lip = HX - 1.05
    tube('galv', [(lip, 1.81, -15.02), (lip, 1.81, -3.98)], 0.035, 14)
    grind('EastQuarter_Coping', [(lip, 1.81, -14.8), (lip, 1.81, -4.2)], 0.035, 'coping')
    rect('osb', (HX - 0.01, 0, -15.0), (0, 0, 11.0), (0, 1.8, 0), (-1, 0, 0), 0.4)


def tower():
    # the diving tower east of the diving pool: platforms at 3 m and 5 m, stairs to the top, two springboards
    block('stone', (30.0, 0, -1.5), (33.0, 5.0, 1.5), top='deck')
    block('stone', (26.8, 2.75, -1.1), (30.0, 3.0, 1.1), top='deck')
    block('stone', (27.3, 4.75, -1.1), (30.0, 5.0, 1.1), top='deck', skip=('y0',))
    for y, x0 in ((3.0, 27.0), (5.0, 27.5)):
        for zz in (-1.05, 1.05):
            tube('chrome', [(30.0, y + 1.0, zz), (x0, y + 1.0, zz), (x0, y, zz)], 0.025, 8)
            for xx in (x0, (x0 + 30) / 2):
                beam('chrome', (xx, y, zz), (xx, y + 1.0, zz), 0.04, 0.04, collide=True)
    for i in range(1, 28):
        top = 5.0 - 0.179 * i
        block('stone', (33.0 + 0.28 * (i - 1), 0.0, -0.8), (33.0 + 0.28 * i, top, 0.8), skip=('y0', 'x0'))
    for zz in (-0.85, 0.85):
        rail = [(33.0, 5.9, zz), (33.0 + 0.28 * 27, 5.0 - 0.179 * 27 + 0.9, zz), (41.2, 0.9, zz)]
        tube('chrome', rail, 0.03, 10)
        grind(f'TowerStairs_{"N" if zz < 0 else "S"}', rail[:2], 0.03, 'rail')
        for k in range(6):
            f = k / 5
            x, y = 33.0 + 7.56 * f, 5.0 - 4.83 * f
            beam('chrome', (x, y, zz), (x, y + 0.9, zz), 0.04, 0.04, collide=True)
    TEXTS.append(('4.2 M', (28.4, 0.002, -4.0), (0, 0, 1), 0.45, 'black', 'floor'))
    for zc in (-4.2, 4.2):
        block('stone', (29.0, 0, zc - 0.35), (30.4, 0.8, zc + 0.35))
        block('fibre', (25.6, 0.8, zc - 0.28), (30.4, 0.86, zc + 0.28))


def furniture():
    # wooden benches on the north deck, a lifeguard's chair by the main pool
    for x0 in (-18.0, -8.0, 30.5):
        z = -11.5
        for k in range(4):
            block('bench_wood', (x0, 0.42 - 0.0, z + 0.12 * k), (x0 + 2.5, 0.46, z + 0.12 * k + 0.1), collide=False)
        block('bench_wood', (x0, 0.55, z + 0.48), (x0 + 2.5, 0.85, z + 0.52), collide=False)
        for xx in (x0 + 0.15, x0 + 2.35):
            block('iron', (xx - 0.03, 0, z), (xx + 0.03, 0.46, z + 0.48), collide=False)
            beam('iron', (xx, 0.42, z + 0.5), (xx, 0.9, z + 0.52), 0.05, 0.04)
        collide_poly([(x0, 0.46, z), (x0 + 2.5, 0.46, z), (x0 + 2.5, 0.46, z + 0.48), (x0, 0.46, z + 0.48)], (0, 1, 0))
        collide_poly([(x0, 0.0, z), (x0 + 2.5, 0.0, z), (x0 + 2.5, 0.46, z), (x0, 0.46, z)], (0, 0, -1))
        grind(f'Bench_Wood_{int(x0)}', [(x0, 0.46 + 0.027, z + 0.03), (x0 + 2.5, 0.46 + 0.027, z + 0.03)], 0.03, 'ledge')
    x, z = -14.0, 9.2
    for dx, dz in ((-0.4, -0.3), (0.4, -0.3), (-0.4, 0.3), (0.4, 0.3)):
        beam('bench_wood', (x + dx, 0, z + dz), (x + dx * 0.6, 1.8, z + dz * 0.6), 0.08, 0.08, collide=True)
    block('bench_wood', (x - 0.35, 1.8, z - 0.3), (x + 0.35, 1.86, z + 0.25), collide=False)
    block('bench_wood', (x - 0.35, 1.86, z + 0.2), (x + 0.35, 2.5, z + 0.25), collide=False)
    for k in range(5):
        beam('bench_wood', (x - 0.32, 0.35 * (k + 1), z + 0.3 + 0.0), (x + 0.32, 0.35 * (k + 1), z + 0.3), 0.05, 0.04)
    # depth marks
    for txt, at, right in (('1.2 M', (-24.0, 0.002, 7.6), (1, 0, 0)), ('2.0 M', (-6.0, 0.002, 7.6), (1, 0, 0)), ('3.4 M', (3.0, 0.002, 7.6), (1, 0, 0)),
                           ('1.2 M', (-24.0, 0.002, -7.6), (-1, 0, 0)), ('3.4 M', (3.0, 0.002, -7.6), (-1, 0, 0)),
                           ('SHALLOW END', (-28.4, 0.002, 0.0), (0, 0, -1)), ('DEEP END', (7.0, 0.002, 0.0), (0, 0, 1)),
                           ('1.6 M', (-35.5, 0.002, -4.9), (1, 0, 0))):
        TEXTS.append((txt, at, right, 0.4, 'black', 'floor'))


def lamps():
    for x in (-36, -24, -12, 0, 12, 24, 36):
        for z in (-10.0, 10.0):
            tube('black', [(x, EAVES, z), (x, 7.9, z)], 0.012, 4)
            block('iron', (x - 0.12, 7.75, z - 0.12), (x + 0.12, 7.9, z + 0.12), collide=False)
            uv_sphere('lamp', (x, 7.45, z), 0.3)
            LAMPS.append((x, 7.45, z))


TEXTS = []    # (text, origin, right, size, material[, 'floor'])
LAMPS = []
SOUTH_WINDOWS = []   # (u, y) outlines on the south wall (u = x + HX), for the light shafts


# ---- materials --------------------------------------------------------------------------------------------------------------------
def materials():
    textured('deck', 'Tile | deck checks', 'deck')
    textured('wall_tiles', 'Tile | white glazed', 'wall_tiles')
    textured('band', 'Tile | green band', 'wall_tiles', tint=(0.32, 0.6, 0.44))
    textured('brick', 'Brick | red', 'brick')
    textured('plaster', 'Plaster | painted', 'plaster', tint=(0.95, 0.93, 0.86))
    textured('boards', 'Timber | gallery boards', 'boards')
    textured('iron', 'Iron | green paint', 'iron')
    textured('doors', 'Timber | cubicle doors', 'doors')
    textured('pool', 'Tile | pool mosaic', 'mosaic', tint=(0.72, 0.9, 0.96))
    textured('pool_green', 'Tile | learner pool mosaic', 'mosaic', tint=(0.78, 0.94, 0.82))
    textured('band_pool', 'Tile | pool band', 'mosaic', tint=(0.13, 0.34, 0.62))
    textured('pool_dark', 'Tile | lane lines', 'mosaic', tint=(0.06, 0.13, 0.38))
    textured('stone', 'Stone | cast', 'stone')
    textured('ply', 'Timber | plywood', 'ply')
    textured('osb', 'Timber | OSB', 'osb')
    textured('bench_wood', 'Timber | benches', 'bench_wood')
    solid('chrome', 'Steel | chrome', (0.82, 0.83, 0.85), 0.2, 0.9)
    solid('galv', 'Steel | galvanized', (0.58, 0.6, 0.62), 0.35, 0.9)
    solid('plate', 'Steel | plate', (0.4, 0.4, 0.39), 0.6, 0.8)
    solid('joint', 'Stone | joints', (0.22, 0.21, 0.2), 0.9)
    solid('gold', 'Paint | gilt letters', (0.78, 0.57, 0.2), 0.35, 0.8)
    solid('black', 'Paint | black', (0.03, 0.03, 0.03), 0.6)
    solid('clock_face', 'Paint | clock face', (0.92, 0.9, 0.82), 0.5)
    solid('fibre', 'Fibreglass | springboard', (0.86, 0.9, 0.92), 0.4)
    solid('glass', 'Glass | roof and windows', (0.82, 0.9, 0.94), 0.05, alpha=0.1)
    solid('lamp', 'Lamp | globes', (1.0, 0.8, 0.55), 0.3, emit=40.0)
    solid('shaft', 'FX | light shafts', (1.0, 0.85, 0.62), 1.0)


def srgb(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def make_objects():
    """One mesh object per material (vertices merged, so the baked light is smooth across faces), the texts, the collision."""
    objects = []
    for key, part in PARTS.items():
        me = bpy.data.meshes.new(f'ENV_{key}')
        me.from_pydata([B(v) for v in part.verts], [], part.faces)
        layer = me.uv_layers.new(name='UVMap')
        for p in me.polygons:
            for li in p.loop_indices:
                layer.data[li].uv = part.uvs[me.loops[li].vertex_index]
        me.materials.append(MATS[key][0])
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(f'ENV_{key}', me)
        bpy.context.scene.collection.objects.link(obj)
        objects.append(obj)
    for i, item in enumerate(TEXTS):
        body, origin, right, size, mat = item[:5]
        flat = len(item) > 5
        r = Vector(right).normalized()
        up = Vector((0, 1, 0)).cross(r) if flat else Vector((0, 1, 0))
        n = r.cross(up).normalized()
        cu = bpy.data.curves.new(f'Text{i}', 'FONT')
        cu.body = body
        cu.size = size
        cu.extrude = 0.0 if flat else 0.03
        cu.align_x, cu.align_y = 'CENTER', 'CENTER'
        tmp = bpy.data.objects.new(f'Text{i}', cu)
        bpy.context.scene.collection.objects.link(tmp)
        tmp.matrix_world = Matrix(((B(r)[0], B(up)[0], B(n)[0], B(origin)[0]), (B(r)[1], B(up)[1], B(n)[1], B(origin)[1]),
                                   (B(r)[2], B(up)[2], B(n)[2], B(origin)[2]), (0, 0, 0, 1)))
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg), depsgraph=dg)
        me.transform(tmp.matrix_world)
        bpy.data.objects.remove(tmp, do_unlink=True)
        me.materials.clear()
        me.materials.append(MATS[mat][0])
        obj = bpy.data.objects.new(f'ENV_Text_{i}', me)
        bpy.context.scene.collection.objects.link(obj)
        objects.append(obj)
    return objects


def light_rig():
    sc = bpy.context.scene
    world = bpy.data.worlds.new('Afternoon')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (0.52, 0.66, 0.9, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = 1.1
    sc.world = world
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN'))
    sc.collection.objects.link(sun)
    sun.data.energy = 4.5
    sun.data.angle = math.radians(0.8)
    sun.data.color = (1.0, 0.9, 0.78)
    travel = Vector(B(-SUN))
    sun.rotation_mode = 'QUATERNION'
    sun.rotation_quaternion = travel.to_track_quat('-Z', 'Y')
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = SAMPLES
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 4
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.render.threads_mode = 'FIXED'
    sc.render.threads = 4
    sc.render.bake.target = 'VERTEX_COLORS'


DECALS = ('Tile | lane lines', 'Stone | joints')   # (painted on: they take light but cast no shade on what they lie on)


def bake(objects):
    lit = [o for o in objects if not o.data.materials[0].name.split(' | ')[0] in ('Glass', 'Lamp', 'FX')]
    for o in lit:
        if o.name.startswith('ENV_Text_') or o.data.materials[0].name in DECALS:
            o.visible_shadow = False
            o.visible_diffuse = False
            o.visible_glossy = False
            o.visible_transmission = False
    for o in lit:
        o.data.color_attributes.new('Light', 'FLOAT_COLOR', 'POINT')
        o.data.color_attributes.active_color = o.data.color_attributes['Light']
    bpy.ops.object.select_all(action='DESELECT')
    for o in lit:
        o.select_set(True)
    bpy.context.view_layer.objects.active = lit[0]
    t = time.time()
    verts = sum(len(o.data.vertices) for o in lit)
    print(f'BAKE {len(lit)} objects, {verts} vertices, {SAMPLES} samples', flush=True)
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'DIRECT', 'INDIRECT'}, target='VERTEX_COLORS')
    print(f'BAKE took {time.time() - t:.0f} s', flush=True)
    levels = []
    for o in lit:
        for c in o.data.color_attributes['Light'].data:
            r, g, b, _ = c.color
            levels.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            c.color = (srgb(r / GAIN), srgb(g / GAIN), srgb(b / GAIN), 1.0)
    levels.sort()
    stats = {f'p{p}': round(levels[int(len(levels) * p / 100) - 1], 3) for p in (10, 50, 90, 99)}
    stats['max'] = round(levels[-1], 3)
    stats['clipped_share'] = round(sum(1 for v in levels if v > GAIN) / len(levels), 4)
    print('BAKE light levels', json.dumps(stats), flush=True)
    return {'vertices': verts, 'samples': SAMPLES, 'gain': GAIN, 'light': stats}


def shafts():
    """Light falling through the south windows: open sheets from each window along the sun, bright at the glass, fading to nothing
    by the floor (drawn added onto what is behind them)."""
    me = bpy.data.meshes.new('ENV_shaft')
    verts, faces, cols = [], [], []
    travel = -SUN
    for outline in SOUTH_WINDOWS:
        top = [Vector((u - HX, y, HZ - 0.36)) for u, y in outline]
        bottom = [p + travel * (p.y / -travel.y) for p in top]
        for i in range(len(top)):
            j = (i + 1) % len(top)
            base = len(verts)
            verts.extend([B(top[i]), B(top[j]), B(bottom[j]), B(bottom[i])])
            faces.append((base, base + 1, base + 2, base + 3))
            cols.extend([0.1, 0.1, 0.0, 0.0])
    me.from_pydata(verts, [], faces)
    attr = me.color_attributes.new('Light', 'FLOAT_COLOR', 'POINT')
    me.color_attributes.active_color = attr
    for v, f in zip(attr.data, cols):
        v.color = (f, f * 0.86, f * 0.65, 1.0)
    me.materials.append(MATS['shaft'][0])
    obj = bpy.data.objects.new('ENV_shaft', me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(objects):
    col = bpy.data.meshes.new('COL_Baths')
    col.from_pydata([B(p) for t in COLLISION for p in t], [], [(i, i + 1, i + 2) for i in range(0, len(COLLISION) * 3, 3)])
    bm = bmesh.new()
    bm.from_mesh(col)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(col)
    bm.free()
    col_obj = bpy.data.objects.new('COL_Baths', col)
    bpy.context.scene.collection.objects.link(col_obj)
    empties = []
    for name, extras in PATHS:
        e = bpy.data.objects.new(f'PATH_{name}', None)
        bpy.context.scene.collection.objects.link(e)
        for k, v in extras.items():
            e[k] = v
        empties.append(e)
    for name, pos, extras in EMPTIES:
        e = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(e)
        e.location = B(pos)
        for k, v in extras.items():
            e[k] = v
        empties.append(e)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects + [col_obj] + empties:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT / 'baths.glb'), export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_materials='EXPORT', export_extras=True, export_image_format='AUTO',
                              export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_cameras=False, export_lights=False)
    return {'collision_triangles': len(COLLISION), 'grind_paths': len(PATHS)}


if __name__ == '__main__':
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    materials()
    build()
    objects = make_objects()
    light_rig()
    report = bake(objects)
    objects.append(shafts())
    report.update(export(objects))
    report['render_triangles'] = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
    (OUT / 'baths_source.json').write_text(json.dumps(sources, indent=2) + '\n')
    (ROOT / 'art/baths/report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('REPORT', json.dumps(report), flush=True)
