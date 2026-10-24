"""Run: blender -b --factory-startup --python tools/build_pieces.py
Build mode pieces: a wooden quarter pipe, a concrete manual pad with steel edges and a square flat bar in green paint, textured with CC0 materials from
Poly Haven (downloaded to art/build_pieces/downloads the first time; assets/build_pieces/source.json says where each file came from).
Units: metres. Blender Z-up; exported Godot Y-up. Each piece stands on the ground at its origin, with the side you ride at facing
Blender -Y (Godot +Z, the way build mode turns a new piece towards you). Each GLB holds the look, a COL_ collision mesh (none for the
bar, as for the round flat rail) and its grind lines as PATH_ empties.
"""
import bpy, bmesh, json, hashlib, math, os, ssl, urllib.request
from pathlib import Path
from mathutils import Vector
from math import sin, cos, acos, pi

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/build_pieces'
OUT.mkdir(parents=True, exist_ok=True)
DOWNLOADS = ROOT / 'art/build_pieces/downloads'
DOWNLOADS.mkdir(parents=True, exist_ok=True)
(ROOT / 'art/build_pieces/.gdignore').touch()

# Poly Haven texture: (asset id, resolution, metres one repeat of it covers; from the asset's own "dimensions")
TEXTURES = {
    'plywood': ('plywood', '1k', 0.5),
    'osb': ('oriented_strand_board', '2k', 2.51),
    'concrete': ('brushed_concrete', '2k', 2.5),
    'cast': ('concrete_wall_008', '2k', 2.71),
    'paint': ('green_metal_rust', '1k', 1.0),
}
sources = {}


def fetch(asset, res):
    """The colour, normal (OpenGL) and AO/roughness/metal maps of a Poly Haven texture, downloaded once."""
    folder = DOWNLOADS / asset
    folder.mkdir(exist_ok=True)
    context = ssl.create_default_context(cafile=os.environ.get('SSL_CERT_FILE'))
    files = {}
    for kind, suffix in [('diff', 'diff'), ('nor_gl', 'nor_gl'), ('arm', 'arm')]:
        url = f'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/{res}/{asset}/{asset}_{suffix}_{res}.jpg'
        path = folder / f'{asset}_{suffix}_{res}.jpg'
        if not path.exists():
            with urllib.request.urlopen(url, context=context) as r:
                path.write_bytes(r.read())
        files[path.name] = {'url': url, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        files[kind] = path
    sources[asset] = {'source': f'https://polyhaven.com/a/{asset}', 'license': 'CC0-1.0',
                      'files': {k: v for k, v in files.items() if isinstance(v, dict)}}
    return files


# ---- materials ------------------------------------------------------------------------------------------------------------

def occlusion_group():
    """The node group the glTF exporter reads ambient occlusion from."""
    group = bpy.data.node_groups.get('glTF Material Output')
    if group is None:
        group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
        group.interface.new_socket('Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
    return group


def textured(name, key):
    asset, res, size = TEXTURES[key]
    maps = fetch(asset, res)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes['Principled BSDF']

    def image(path, colour):
        node = nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(str(path), check_existing=True)
        node.image.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
        return node
    links.new(image(maps['diff'], True).outputs['Color'], bsdf.inputs['Base Color'])
    normal = nodes.new('ShaderNodeNormalMap')
    links.new(image(maps['nor_gl'], False).outputs['Color'], normal.inputs['Color'])
    links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
    split = nodes.new('ShaderNodeSeparateColor')
    links.new(image(maps['arm'], False).outputs['Color'], split.inputs['Color'])
    links.new(split.outputs['Green'], bsdf.inputs['Roughness'])
    links.new(split.outputs['Blue'], bsdf.inputs['Metallic'])
    out = nodes.new('ShaderNodeGroup')
    out.node_tree = occlusion_group()
    links.new(split.outputs['Red'], out.inputs['Occlusion'])
    m['tile'] = size
    return m


def solid(name, colour, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*colour, 1)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    m['tile'] = 1.0
    return m


# ---- geometry -------------------------------------------------------------------------------------------------------------

class Piece:
    """One build piece: its parts (merged by material on export), its collision triangles and its grind lines."""

    def __init__(self, name):
        self.name = name
        self.collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(self.collection)
        self.parts = []
        self.collision = []
        self.markers = []

    def mesh(self, name, verts, faces, mat, uvs=None, smooth=False):
        """A mesh from world-space verts. Without `uvs` each face is projected along its main axis, at the material's real scale."""
        data = bpy.data.meshes.new(name)
        data.from_pydata([tuple(v) for v in verts], [], faces)
        data.update()
        data.materials.append(mat)
        tile = mat['tile']
        layer = data.uv_layers.new(name='UVMap')
        for poly in data.polygons:
            poly.use_smooth = smooth
            n = poly.normal
            axis = max(range(3), key=lambda a: abs(n[a]))
            u_axis, v_axis = [(1, 2), (0, 2), (0, 1)][axis]
            for li in poly.loop_indices:
                vi = data.loops[li].vertex_index
                if uvs:
                    layer.data[li].uv = uvs[vi]
                else:
                    co = data.vertices[vi].co
                    layer.data[li].uv = (co[u_axis] / tile, co[v_axis] / tile)
        obj = bpy.data.objects.new(name, data)
        self.collection.objects.link(obj)
        self.parts.append(obj)
        return obj

    def box(self, name, lo, hi, mat, bevel=0.0, collide=False):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        p = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        obj = self.mesh(name, p, faces, mat)
        if bevel:
            soften(obj, bevel)
        if collide:
            self.collide_box(lo, hi)
        return obj

    def collide_box(self, lo, hi):
        """Collision for a box: its top and sides (never the underside, which nothing reaches)."""
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        p = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        for f in [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
            self.quad(*[p[i] for i in f])

    def cylinder(self, name, a, b, r, mat, sides=16):
        a, b = Vector(a), Vector(b)
        bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=r, depth=(b - a).length, location=(a + b) / 2)
        obj = bpy.context.object
        obj.name = name
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        self.collection.objects.link(obj)
        obj.rotation_mode = 'QUATERNION'
        obj.rotation_quaternion = (b - a).to_track_quat('Z', 'Y')
        obj.data.materials.append(mat)
        for poly in obj.data.polygons:
            poly.use_smooth = len(poly.vertices) == 4
        self.parts.append(obj)
        return obj

    def quad(self, a, b, c, d):
        self.collision.extend([a, b, c, a, c, d])

    def grind(self, name, points, radius, kind):
        marker = bpy.data.objects.new(f'PATH_{self.name}_{name}', None)
        self.collection.objects.link(marker)
        marker['role'] = 'grind_path'
        marker['kind'] = kind
        marker['closed'] = False
        marker['radius'] = radius
        # glTF converts node transforms, not custom numbers: these are written in Godot's axes (x, z, -y) already.
        marker['points'] = [value for x, y, z in points for value in (x, z, -y)]
        self.markers.append(marker)

    def export(self):
        """Evaluated copies merged by material, the collision mesh and the grind empties, to assets/build_pieces/<name>.glb."""
        depsgraph = bpy.context.evaluated_depsgraph_get()
        groups = {}
        for original in self.parts:
            data = bpy.data.meshes.new_from_object(original.evaluated_get(depsgraph), depsgraph=depsgraph)
            copy = bpy.data.objects.new(original.name, data)
            self.collection.objects.link(copy)
            copy.matrix_world = original.matrix_world.copy()
            groups.setdefault(original.data.materials[0].name, []).append(copy)
        merged = []
        for key, objects in groups.items():
            bpy.ops.object.select_all(action='DESELECT')
            for obj in objects:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = objects[0]
            if len(objects) > 1:
                bpy.ops.object.join()
            obj = bpy.context.object
            obj.name = f'{self.name}_{key}'
            bpy.context.scene.cursor.location = (0, 0, 0)
            bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
            merged.append(obj)
        selection = merged + self.markers
        if self.collision:
            data = bpy.data.meshes.new('COL_' + self.name)
            data.from_pydata([tuple(v) for v in self.collision], [], [(i, i + 1, i + 2) for i in range(0, len(self.collision), 3)])
            bm = bmesh.new()
            bm.from_mesh(data)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bm.to_mesh(data)
            bm.free()
            col = bpy.data.objects.new('COL_' + self.name, data)
            self.collection.objects.link(col)
            selection.append(col)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in selection:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = merged[0]
        bpy.ops.export_scene.gltf(filepath=str(OUT / f'{self.name}.glb'), export_format='GLB', use_selection=True,
                                  export_apply=True, export_yup=True, export_materials='EXPORT', export_extras=True,
                                  export_image_format='AUTO', export_cameras=False, export_lights=False)
        triangles = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in merged)
        return {'meshes': len(merged), 'render_triangles': triangles, 'collision_triangles': len(self.collision) // 3,
                'grind_paths': len(self.markers)}


def soften(obj, width, segments=2):
    mod = obj.modifiers.new('Soft edges', 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.harden_normals = True
    for poly in obj.data.polygons:
        poly.use_smooth = True


def thicken(obj, amount):
    mod = obj.modifiers.new('Thickness', 'SOLIDIFY')
    mod.thickness = amount
    mod.offset = -1


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


clear_scene()
galvanized = solid('galvanized steel', (0.52, 0.55, 0.57), 0.4, 1.0)
worn_steel = solid('worn steel edge', (0.45, 0.46, 0.47), 0.22, 1.0)
fixings = solid('steel fixings', (0.30, 0.31, 0.32), 0.38, 1.0)
seam = solid('plywood joint', (0.16, 0.10, 0.055), 0.85)
plywood = textured('plywood', 'plywood')
osb = textured('osb', 'osb')
concrete = textured('brushed concrete', 'concrete')
cast = textured('cast concrete', 'cast')
paint = textured('green paint', 'paint')
report = {}


# ---- quarter pipe ---------------------------------------------------------------------------------------------------------
# 1.2 m high on a 1.8 m radius, 2.44 m wide (two 4 ft sheets), a 0.61 m deck, galvanized coping and a steel kick plate at the foot.

def quarter_pipe():
    piece = Piece('quarter_pipe')
    H, W, R, DECK = 1.2, 2.44, 1.8, 0.61
    A = acos(1 - H / R)
    run = R * sin(A)
    y0 = -(run + DECK) / 2
    lip = y0 + run
    back = lip + DECK
    hw = W / 2
    steps = 48
    profile = []   # (y, z, arc length) up the riding surface
    for i in range(steps + 1):
        t = A * i / steps
        profile.append((y0 + R * sin(t), R * (1 - cos(t)), R * t))

    # The riding surface: one continuous skin, the grain running up it.
    verts, uvs, faces = [], [], []
    for y, z, s in profile:
        for x in (-hw, 0.0, hw):
            verts.append((x, y, z))
            uvs.append((x / TEXTURES['plywood'][2], s / TEXTURES['plywood'][2]))
    for i in range(steps):
        for j in range(2):
            a = i * 3 + j
            faces.append((a, a + 1, a + 4, a + 3))
    piece.mesh('Riding surface', verts, faces, plywood, uvs, smooth=True)
    for i in range(steps):
        (ya, za, _), (yb, zb, _) = profile[i], profile[i + 1]
        piece.quad((-hw, ya, za), (hw, ya, za), (hw, yb, zb), (-hw, yb, zb))
    # The joint between the two sheets, and rows of countersunk screws along the ribs underneath.
    sv = []
    for y, z, _ in profile:
        sv += [(-0.0012, y, z + 0.0005), (0.0012, y, z + 0.0005)]
    piece.mesh('Sheet joint', sv, [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(steps)], seam, smooth=True)
    for x in (-hw + 0.04, -hw / 2, -0.04, 0.04, hw / 2, hw - 0.04):
        for i in range(3, steps, 6):
            y, z, _ = profile[i]
            t = A * i / steps
            n = Vector((0, -sin(t), cos(t)))
            base = Vector((x, y, z))
            piece.cylinder('Screw head', base - n * 0.0004, base + n * 0.0008, 0.0045, fixings, 8)

    # The plywood edge showing along each side, and the OSB cheeks under it, down to the ground and back under the deck.
    for side in (-1, 1):
        x = side * hw
        ev = []
        for y, z, _ in profile:
            ev += [(x, y, max(z - 0.002, 0.0)), (x, y, max(z - 0.03, 0.0))]
        piece.mesh('Laminated edge', ev, [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) if side > 0 else (2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1)
                                           for i in range(steps)], plywood)
        # (it starts at a point where the curve, less the 30 mm of riding sheets, meets the ground: no slivers of no height)
        tip = y0 + R * sin(acos(1 - 0.03 / R))
        cv, cf = [(x, tip, 0.0)], []
        for y, z, _ in profile:
            if y > tip + 1e-4:
                cv += [(x, y, z - 0.03), (x, y, 0.0)]
        cf.append((0, 2, 1) if side > 0 else (0, 1, 2))
        for i in range((len(cv) - 1) // 2 - 1):
            a = 1 + 2 * i
            cf.append((a, a + 1, a + 3, a + 2) if side > 0 else (a, a + 2, a + 3, a + 1))
        n = len(cv)
        cv += [(x, back, H - 0.03), (x, back, 0.0)]
        cf.append((n - 2, n - 1, n + 1, n) if side > 0 else (n - 2, n, n + 1, n - 1))
        cheek = piece.mesh('Cheek', cv, cf, osb)
        thicken(cheek, 0.018)   # (inwards, behind its outward face)
        for i in range(steps):
            (ya, za, _), (yb, zb, _) = profile[i], profile[i + 1]
            q = [(x, ya, 0.0), (x, yb, 0.0), (x, yb, zb), (x, ya, za)]
            piece.quad(*(q if side > 0 else q[::-1]))
        q = [(x, lip, 0.0), (x, back, 0.0), (x, back, H), (x, lip, H)]
        piece.quad(*(q if side > 0 else q[::-1]))
    inner = hw - 0.018   # (between the cheeks, so its edges are hidden behind them)
    back_panel = piece.mesh('Back panel', [(inner, back, 0), (-inner, back, 0), (-inner, back, H - 0.018), (inner, back, H - 0.018)],
                            [(0, 1, 2, 3)], osb)
    thicken(back_panel, 0.018)
    piece.quad((hw, back, 0), (-hw, back, 0), (-hw, back, H), (hw, back, H))

    # The deck: a plywood top behind the coping, the coping itself, and a kick plate where the ramp meets the ground.
    piece.box('Deck', (-hw, lip + 0.03, H - 0.018), (hw, back, H), plywood, 0.002)
    piece.quad((-hw, lip, H), (hw, lip, H), (hw, back, H), (-hw, back, H))
    coping_y, coping_z = lip + 0.004, H + 0.008
    piece.cylinder('Coping', (-hw - 0.01, coping_y, coping_z), (hw + 0.01, coping_y, coping_z), 0.03, galvanized, 32)
    piece.grind('Coping', [(-hw, coping_y, coping_z), (hw, coping_y, coping_z)], 0.03, 'coping')
    piece.box('Kick plate', (-hw, y0 - 0.16, 0.0), (hw, y0 + 0.09, 0.003), galvanized, 0.0015)
    for x in (-hw + 0.08, -hw / 2, 0.0, hw / 2, hw - 0.08):
        piece.cylinder('Plate screw', (x, y0 - 0.1, 0.002), (x, y0 - 0.1, 0.0045), 0.006, fixings, 8)
    return piece, {'height_m': H, 'width_m': W, 'radius_m': R, 'deck_m': DECK, 'depth_m': round(back - y0 + 0.16, 3)}


# ---- manual pad -----------------------------------------------------------------------------------------------------------
# A cast concrete block, 2.4 × 1.2 m and 0.3 m high, with steel angle round its top edges: all four edges are ledges.

def manual_pad():
    piece = Piece('manual_pad')
    L, W, H = 2.4, 1.2, 0.3
    leg, thick = 0.05, 0.005
    hl, hw = L / 2, W / 2
    piece.box('Concrete body', (-hl + thick, -hw + thick, 0.0), (hl - thick, hw - thick, H - thick), cast, 0.004)
    piece.box('Concrete top', (-hl + leg, -hw + leg, H - thick - 0.002), (hl - leg, hw - leg, H), concrete)

    def ring(name, outer, inner, z0, z1, mat):
        """A rectangular frame: `outer` and `inner` half sizes (x, y), from z0 up to z1."""
        (ox, oy), (ix, iy) = outer, inner
        o = [(-ox, -oy), (ox, -oy), (ox, oy), (-ox, oy)]
        i = [(-ix, -iy), (ix, -iy), (ix, iy), (-ix, iy)]
        verts = [(x, y, z0) for x, y in o] + [(x, y, z0) for x, y in i] + [(x, y, z1) for x, y in o] + [(x, y, z1) for x, y in i]
        faces = []
        for k in range(4):
            n = (k + 1) % 4
            faces.append((8 + k, 8 + n, 12 + n, 12 + k))   # top
            faces.append((k, 4 + k, 4 + n, n))             # bottom
            faces.append((k, n, 8 + n, 8 + k))             # outside
            faces.append((4 + k, 12 + k, 12 + n, 4 + n))   # inside
        return piece.mesh(name, verts, faces, mat)
    soften(ring('Steel angle top', (hl, hw), (hl - leg, hw - leg), H - thick, H, worn_steel), 0.0015, 1)
    soften(ring('Steel angle side', (hl, hw), (hl - thick, hw - thick), H - leg, H - thick, worn_steel), 0.0015, 1)
    for x in (-hl + 0.3, 0.0, hl - 0.3):   # the angle's anchor bolts, on the long sides
        for y in (-hw, hw):
            out = -1 if y < 0 else 1
            piece.cylinder('Anchor bolt', (x, y, H - 0.027), (x, y + out * 0.003, H - 0.027), 0.007, fixings, 8)
    piece.collide_box((-hl, -hw, 0.0), (hl, hw, H))
    top = H + 0.027   # ledge lines sit just above the edge they follow
    corners = [(-hl, -hw), (hl, -hw), (hl, hw), (-hl, hw)]
    for k in range(4):
        (xa, ya), (xb, yb) = corners[k], corners[(k + 1) % 4]
        piece.grind(f'Edge_{k}', [(xa, ya, top), (xb, yb, top)], 0.03, 'ledge')
    return piece, {'length_m': L, 'width_m': W, 'height_m': H}


# ---- flat bar -------------------------------------------------------------------------------------------------------------
# A 3.6 m length of 50 mm square tube, its top 0.38 m off the ground, on two legs with bolted foot plates; worn green paint.

def flat_bar():
    piece = Piece('flat_bar')
    L, TOP, T = 3.6, 0.38, 0.05
    hl, ht = L / 2, T / 2
    piece.box('Bar', (-hl, -ht, TOP - T), (hl, ht, TOP), paint, 0.005)
    for x in (-hl + 0.35, hl - 0.35):
        piece.box('Leg', (x - 0.02, -0.02, 0.008), (x + 0.02, 0.02, TOP - T), paint, 0.003)
        piece.box('Foot plate', (x - 0.06, -0.15, 0.0), (x + 0.06, 0.15, 0.008), paint, 0.002)
        for dx in (-0.035, 0.035):
            for dy in (-0.11, 0.11):
                piece.cylinder('Bolt head', (x + dx, dy, 0.008), (x + dx, dy, 0.016), 0.009, fixings, 6)
                piece.cylinder('Washer', (x + dx, dy, 0.008), (x + dx, dy, 0.0095), 0.013, galvanized, 12)
    piece.grind('Bar', [(-hl, 0.0, TOP - ht), (hl, 0.0, TOP - ht)], ht, 'rail')
    return piece, {'length_m': L, 'top_height_m': TOP, 'tube_mm': 50}


for build in (quarter_pipe, manual_pad, flat_bar):
    piece, sizes = build()
    sizes.update(piece.export())
    report[piece.name] = sizes
    print('PIECE', piece.name, json.dumps(sizes), flush=True)

(OUT / 'source.json').write_text(json.dumps(sources, indent=2) + '\n')
(OUT / 'dimensions.json').write_text(json.dumps({**report, 'blender_version': bpy.app.version_string}, indent=2) + '\n')
