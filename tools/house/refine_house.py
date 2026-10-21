"""Refines the house model in place: strips detail nobody can see (screws, bolts, chamfers on far-away boards), swaps the leather
Chesterfield for a worn 70s corduroy couch, and puts a rug down in the lounge. Every name, marker and collision mesh the game relies on
is left exactly as it was.
    pip install bpy        (Blender as a Python module)
    python tools/house/refine_house.py <in.glb> <out.glb>
"""
import sys, math, random
import bpy, bmesh
import numpy as np
from mathutils import Vector

src, dst = sys.argv[-2], sys.argv[-1]
random.seed(7)
rng = np.random.default_rng(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
S = bpy.context.scene
FLOOR = 0.30


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


before = sum(tris(o) for o in S.objects if o.type == 'MESH' and not o.name.startswith('COL_'))

# ---- 1. thinning ---------------------------------------------------------------------------------------------------------
# Per object: weld, drop loose bits smaller than `tiny` metres (screws, washers, bolt heads), then let the quadric decimator take the
# least visible detail out down to `keep` of what is left. Things seen up close keep the most.
PLAN = {
    'Boundary_Timber_Weathered_Structure': (0.0, 0.30),   # the fence: 20 m away
    'Boundary_Metal_Blackened_Steel': (0.03, 1.0),        # fence bolts
    'Roof_Metal_Blackened_Steel': (0.05, 1.0),            # roof screws
    'Roof_Timber_Weathered_Structure': (0.0, 0.45),
    'Exterior_Timber_Painted_Interior': (0.0, 0.35),      # veranda balusters
    'Exterior_Metal_Weathered_Galvanised': (0.05, 0.40),  # gutters, downpipes, flashing
    'Exterior_Timber_Sunbleached_Exterior': (0.0, 0.50),
    'Exterior_Timber_Reclaimed_Floor': (0.0, 0.55),
    'Shell_Timber_Sunbleached_Exterior': (0.0, 0.55),
    'Shell_Timber_Weathered_Structure': (0.0, 0.50),
    'Shell_Timber_Painted_Interior': (0.0, 0.70),
    'Interior_Timber_Reclaimed_Floor': (0.0, 0.70),
    'Interior_Metal_Weathered_Galvanised': (0.012, 0.60),  # pendant shades
    'Interior_Metal_Blackened_Steel': (0.012, 0.70),
}


def strip_tiny(o, tiny):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
    if tiny > 0.0:
        bm.faces.ensure_lookup_table()
        seen = set()
        doomed = []
        for f in bm.faces:
            if f in seen:
                continue
            island = []
            stack = [f]
            seen.add(f)
            while stack:
                g = stack.pop()
                island.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h not in seen:
                            seen.add(h)
                            stack.append(h)
            co = [v.co for g in island for v in g.verts]
            size = max(max(c[i] for c in co) - min(c[i] for c in co) for i in range(3))
            if size < tiny:
                doomed.extend(island)
        bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(o.data)
    bm.free()


for name, (tiny, keep) in PLAN.items():
    o = S.objects.get(name)
    if o is None:
        print('missing', name)
        continue
    strip_tiny(o, tiny)
    if keep < 1.0:
        m = o.modifiers.new('thin', 'DECIMATE')
        m.decimate_type = 'COLLAPSE'
        m.ratio = keep
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
    # the imported per-corner normals no longer fit the thinned mesh: shade it again from its own faces
    if o.data.has_custom_normals:
        bpy.context.view_layer.objects.active = o
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    o.data.validate()
    # boards keep their hard edges, round things (pipes, shades) stay round
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))


# ---- 2. textures, made here so the file carries everything --------------------------------------------------------------------
def image(name, rgb, non_color=False):
    h, w, _ = rgb.shape
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[:, :, :3] = np.clip(rgb, 0.0, 1.0)
    img.pixels.foreach_set(px.ravel())
    img.file_format = 'PNG' if non_color else 'JPEG'
    img.pack()
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    return img


def smooth_noise(h, w, scale, seed):
    r = np.random.default_rng(seed).normal(0, 1, (h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    n = np.fft.ifft2(np.fft.fft2(r) * np.exp(-((fx * w / scale) ** 2 + (fy * h / scale) ** 2))).real
    return n / max(n.std(), 1e-6)


def material(name, base, normal=None, rough=0.85, normal_strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes.get('Principled BSDF')
    p.inputs['Roughness'].default_value = rough
    t = nt.nodes.new('ShaderNodeTexImage')
    t.image = base
    nt.links.new(t.outputs['Color'], p.inputs['Base Color'])
    if normal is not None:
        tn = nt.nodes.new('ShaderNodeTexImage')
        tn.image = normal
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nm.inputs['Strength'].default_value = normal_strength
        nt.links.new(tn.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], p.inputs['Normal'])
    return m


N = 1024
y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N
# corduroy: 48 wales across the tile, a faded burnt orange, rubbed paler in patches
wale = 0.5 + 0.5 * np.cos(2 * math.pi * x * 48)
rust = np.array([0.60, 0.30, 0.16])
cord = rust[None, None, :] * (0.80 + 0.20 * wale)[:, :, None]
cord *= (1.0 + 0.07 * smooth_noise(N, N, 6, 1))[:, :, None]
cord += (0.05 * np.clip(smooth_noise(N, N, 3, 2) - 1.0, 0, 1))[:, :, None]
cord *= (1.0 + rng.normal(0, 0.025, (N, N)))[:, :, None]
slope = -np.sin(2 * math.pi * x * 48) * 0.55
cord_n = np.stack([0.5 + 0.5 * slope, np.full_like(x, 0.5), np.full_like(x, 1.0)], axis=2)
CORD = material('Fabric_Corduroy_Rust', image('corduroy_base', cord), image('corduroy_normal', cord_n, True), 0.92, 0.8)

# rug: a worn kilim, madder red field, indigo and cream bands, rows of lozenges, faded down the middle where it is walked on
RH, RW = 1024, 1536
ry, rx = np.mgrid[0:RH, 0:RW].astype(np.float32)
u = rx / RW
v = ry / RH
red = np.array([0.50, 0.14, 0.10]); indigo = np.array([0.13, 0.17, 0.30]); cream = np.array([0.82, 0.76, 0.62]); ochre = np.array([0.72, 0.50, 0.18])
rug = np.broadcast_to(red, (RH, RW, 3)).copy()
edge = np.minimum(np.minimum(u, 1 - u) * RW, np.minimum(v, 1 - v) * RH)
rug[edge < 70] = indigo
rug[(edge >= 70) & (edge < 86)] = cream
rug[(edge >= 86) & (edge < 112)] = ochre
rug[(edge >= 112) & (edge < 124)] = cream
inside = edge >= 150
cx = ((u - 0.5) * RW) % 170 - 85
cy = ((v - 0.5) * RH) % 210 - 105
dia = np.abs(cx) / 85 + np.abs(cy) / 105
rug[inside & (dia < 0.62)] = indigo
rug[inside & (dia < 0.42)] = cream
rug[inside & (dia < 0.22)] = ochre
hook = inside & (np.abs(dia - 0.8) < 0.04)
rug[hook] = cream * 0.9
rug *= (1.0 + 0.10 * smooth_noise(RH, RW, 9, 3))[:, :, None]
wear = np.exp(-(((u - 0.5) / 0.28) ** 2 + ((v - 0.5) / 0.35) ** 2))
rug = rug * (1 - 0.18 * wear[:, :, None]) + 0.18 * wear[:, :, None] * np.array([0.62, 0.55, 0.47])
rug *= (1.0 + rng.normal(0, 0.04, (RH, RW)))[:, :, None]
weave = 0.5 + 0.5 * np.sign(np.sin(rx * 0.9)) * np.sign(np.sin(ry * 0.9))
rug *= (0.94 + 0.06 * weave)[:, :, None]
RUG = material('Fabric_Rug_Kilim', image('rug_base', rug), None, 0.95)

# throw blanket: cream wool with indigo and red stripes
TB = 512
ty, tx = np.mgrid[0:TB, 0:TB].astype(np.float32) / TB
throw = np.broadcast_to(np.array([0.80, 0.75, 0.64]), (TB, TB, 3)).copy()
for c, a, b in [(indigo, 0.18, 0.26), (red, 0.30, 0.33), (indigo, 0.70, 0.78), (red, 0.66, 0.69)]:
    throw[(ty > a) & (ty < b)] = c
throw *= (0.93 + 0.07 * (0.5 + 0.5 * np.sin(tx * 2 * math.pi * 90)))[:, :, None]
THROW = material('Fabric_Throw_Wool', image('throw_base', throw), None, 0.95)
WOOD = bpy.data.materials.get('Timber_Weathered_Structure')


# ---- 3. the couch and the rug ----------------------------------------------------------------------------------------------
def box_uv(o, scale):
    """Box-projects UVs in world metres * scale (so the corduroy is the same size on every piece)."""
    me = o.data
    uv = me.uv_layers.new(name='UVMap') if not me.uv_layers else me.uv_layers[0]
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        keep = [i for i in range(3) if i != ax]
        for li in p.loop_indices:
            co = o.matrix_world @ me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (co[keep[1]] * scale, co[keep[0]] * scale) if ax != 2 else (co[0] * scale, co[1] * scale)


def piece(name, centre, size, mat, bevel, segs, subsurf=0, sag=0.0, tilt=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.rotation_euler = (0.0, tilt, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    b = o.modifiers.new('bevel', 'BEVEL')
    b.width = bevel
    b.segments = segs
    b.limit_method = 'NONE'
    if subsurf:
        s = o.modifiers.new('soft', 'SUBSURF')
        s.levels = subsurf
        s.render_levels = subsurf
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    if sag:
        # cushions sit down in the middle and puff at the seams
        c = Vector(centre)
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            d = ((w.y - c.y) / (size[1] / 2)) ** 2 + ((w.x - c.x) / (size[0] / 2)) ** 2
            if w.z > c.z:
                v.co.z -= sag * max(0.0, 1.0 - d)
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    box_uv(o, 5.0)
    return o


old = S.objects.get('Interior_Fabric_Sofa_Leather')
if old is not None:
    bpy.data.objects.remove(old, do_unlink=True)
z0 = FLOOR
parts = []
# the couch faces west (towards the TV), back at x = -2.2, 2.2 m long, as the old one stood
for y in (-1.0, 1.0):
    for x in (-3.0, -2.3):
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.022, depth=0.10, location=(x, y, z0 + 0.05))
        leg = bpy.context.active_object
        leg.name = 'Couch_Leg'
        leg.data.materials.append(WOOD)
        parts.append(leg)
parts.append(piece('Couch_Base', (-2.65, 0.0, z0 + 0.19), (0.86, 2.16, 0.18), CORD, 0.03, 2))
for y in (-1.0, 1.0):
    parts.append(piece('Couch_Arm', (-2.66, y, z0 + 0.37), (0.88, 0.22, 0.54), CORD, 0.07, 3, 1))
parts.append(piece('Couch_Back', (-2.31, 0.0, z0 + 0.58), (0.18, 1.80, 0.58), CORD, 0.05, 2))
for y in (-0.45, 0.45):
    parts.append(piece('Couch_BackCushion', (-2.50, y, z0 + 0.62), (0.20, 0.88, 0.46), CORD, 0.07, 2, 2, tilt=-0.18))
    parts.append(piece('Couch_SeatCushion', (-2.76, y, z0 + 0.37), (0.60, 0.88, 0.17), CORD, 0.05, 2, 2, sag=0.018))
throw = piece('Couch_Throw', (-2.78, 0.62, z0 + 0.48), (0.36, 0.44, 0.045), THROW, 0.018, 2, 1)
throw.rotation_euler = (0.0, 0.0, 0.25)
parts.append(throw)
bpy.ops.object.select_all(action='DESELECT')
for p in parts:
    p.select_set(True)
bpy.context.view_layer.objects.active = parts[-1]
bpy.ops.object.join()
couch = bpy.context.active_object
couch.name = 'Interior_Couch'

# the rug: under the coffee table and the front feet of the couch
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-4.30, 0.0, z0 + 0.004))
rug_o = bpy.context.active_object
rug_o.name = 'Interior_Rug'
rug_o.scale = (2.7, 1.9, 0.008)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
rug_o.data.materials.append(RUG)
uv = rug_o.data.uv_layers.new(name='UVMap')
for p in rug_o.data.polygons:
    for li in p.loop_indices:
        co = rug_o.data.vertices[rug_o.data.loops[li].vertex_index].co
        uv.data[li].uv = (co.x / 2.7 + 0.5, co.y / 1.9 + 0.5)

after = sum(tris(o) for o in S.objects if o.type == 'MESH' and not o.name.startswith('COL_'))
print('render triangles: %d -> %d (couch %d, rug %d)' % (before, after, tris(couch), tris(rug_o)))

# ---- 4. export, as the modeller did -------------------------------------------------------------------------------------------
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=False, export_yup=True, export_apply=True,
                          export_extras=True, export_cameras=False, export_lights=False, export_animations=False)
print('wrote', dst)
