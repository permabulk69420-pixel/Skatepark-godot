"""Run: blender -b --factory-startup --python tools/build_breakwater_panorama.py [-- --test | --preview] [--samples N] [--cpu]
Needs Blender 4.2 or newer and an internet connection the first time (it downloads the sky and two trees from Poly Haven into
art/breakwater_panorama/downloads, which git ignores). Renders on the GPU when Blender finds one (OptiX, CUDA, HIP, Metal or
oneAPI), otherwise on the CPU; --cpu forces the CPU. The full render takes a few hours on a 4-core CPU.

A 360° harbour-city backdrop for Breakwater's sky: an 8192 × 4096 equirectangular render seen from the middle of the park.

The buildings are built from facade modules modelled here in 3D, one storey bay each: brick walls with real window reveals, stone
sills and lintels, painted frames and glazing bars; precast concrete office bays with ribbon glazing and mullions; aluminium
curtain wall; rendered flats with balconies; shopfronts on the ground floor. Behind every pane is a shallow room (back wall,
ceiling with a light that is on in some, curtains or blinds in some). The modules are instanced over the walls of the buildings
that are near enough to show them; farther buildings get a texture rendered from the same modules, and the farthest only a
plain version of it.

The sky and its light are a photographed sky (Poly Haven, CC0), turned so its sun matches Breakwater's sunDirection. Haze
colour is read from the same sky just above the horizon in each direction, so distant buildings fade into exactly the sky
behind them.

--test renders close views of the modules on a short street instead (art/breakwater_panorama/test_*.png).
--preview renders the panorama at 2048 × 1024 (art/breakwater_panorama/preview.png).
--crop x0 x1 y0 y1 renders one part of it at full size (art/breakwater_panorama/crop.png).
--size 4096 makes the full render 4096 × 2048 instead (about a quarter of the time).
Without either: art/breakwater_panorama/breakwater_panorama.blend, …_8k.png and assets/sky/breakwater_panorama.jpg (the game's
copy; Breakwater's look in scripts/levels.gd already names it, and the game uses it as soon as it exists).

Units: metres. Blender Z-up; Godot (x, y, z) is Blender (x, -z, y). Godot's PanoramaSkyMaterial puts the middle of the image at
Godot +Z, so the camera faces Blender -Y.
"""
import bpy, bmesh, json, math, random, sys, urllib.request
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art/breakwater_panorama'
ART.mkdir(parents=True, exist_ok=True)
(ART / '.gdignore').touch()
GAME = ROOT / 'assets/sky'
ASSETS = ART / 'downloads'

TEST = '--test' in sys.argv
PREVIEW = '--preview' in sys.argv
CPU = '--cpu' in sys.argv
SIZE = int(sys.argv[sys.argv.index('--size') + 1]) if '--size' in sys.argv else 8192   # width of the full render
SAMPLES = int(sys.argv[sys.argv.index('--samples') + 1]) if '--samples' in sys.argv else None
# --crop x0 x1 y0 y1: just that part of the full-size panorama (fractions of its width and height, y from the bottom), to check
# detail without rendering all of it; written to art/breakwater_panorama/crop.png
CROP = [float(a) for a in sys.argv[sys.argv.index('--crop') + 1:][:4]] if '--crop' in sys.argv else None
rng = random.Random(11)


def fetch():
	"""Downloads (once) what the render uses from Poly Haven (all CC0): the sky (8K for the full render, 4K otherwise) and
	two trees with their textures. Returns the sky's path."""
	def open_url(url):   # (Poly Haven turns away Python's own user agent)
		return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'skatepark-godot panorama build'}))
	def get(url, path):
		if path.exists():
			return
		path.parent.mkdir(parents=True, exist_ok=True)
		print('downloading', url)
		with open_url(url) as r:
			path.write_bytes(r.read())
	def files(asset):
		with open_url(f'https://api.polyhaven.com/files/{asset}') as r:
			return json.loads(r.read())
	sky = 'kloofendal_48d_partly_cloudy_puresky'
	res = '4k' if TEST or PREVIEW else '8k'
	hdri = ASSETS / f'hdri/{sky}_{res}.hdr'
	if not hdri.exists():
		get(files(sky)['hdri'][res]['hdr']['url'], hdri)
	for tree in ('island_tree_02', 'tree_small_02'):
		blend = ASSETS / f'trees/{tree}_1k.blend'
		if blend.exists():
			continue
		f = files(tree)['blend']['1k']['blend']
		for path, inc in f['include'].items():
			get(inc['url'], ASSETS / 'trees' / path)
		get(f['url'], blend)
	return hdri


HDRI = fetch()


def godot_to_blender(v):
	return Vector((v[0], -v[2], v[1]))


SUN_DIR = godot_to_blender((-0.40, 0.73, -0.56)).normalized()   # Breakwater's sunDirection
CAM_Z = 2.0

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = 'Breakwater panorama'


def collection(name, parent=None, hide=False):
	c = bpy.data.collections.new(name)
	(parent or scene.collection).children.link(c)
	if hide:
		c.hide_render = True
		c.hide_viewport = True
	return c


# ======================================================================================================================= nodes
class Tree:
	"""Builds a node graph by hand: t.node('Math', operation='MULTIPLY'), t.math('ADD', a, b), t.mix(fac, a, b) …"""

	def __init__(self, nt):
		self.nt = nt

	def node(self, kind, **props):
		n = self.nt.nodes.new(kind if kind.startswith(('ShaderNode', 'NodeGroup', 'GeometryNode', 'FunctionNode')) else 'ShaderNode' + kind)
		for k, v in props.items():
			setattr(n, k, v)
		return n

	def set(self, sock, v):
		if isinstance(v, bpy.types.NodeSocket):
			self.nt.links.new(v, sock)
		elif isinstance(v, bpy.types.Node):
			self.nt.links.new(v.outputs[0], sock)
		elif v is not None:
			if isinstance(v, tuple) and sock.type == 'VECTOR':
				v = v[:3]
			sock.default_value = v

	def math(self, op, a, b=0.0, clamp=False):
		n = self.node('Math', operation=op, use_clamp=clamp)
		self.set(n.inputs[0], a)
		self.set(n.inputs[1], b)
		return n.outputs[0]

	def vmath(self, op, a, b=(0, 0, 0), out=0):
		n = self.node('VectorMath', operation=op)
		self.set(n.inputs[0], a)
		self.set(n.inputs[1], b)
		return n.outputs[out]

	def mix(self, fac, a, b):
		n = self.node('Mix', data_type='RGBA')
		self.set(n.inputs[0], fac)
		self.set(n.inputs[6], a)
		self.set(n.inputs[7], b)
		return n.outputs[2]

	def mixf(self, fac, a, b):
		n = self.node('Mix', data_type='FLOAT')
		self.set(n.inputs[0], fac)
		self.set(n.inputs[2], a)
		self.set(n.inputs[3], b)
		return n.outputs[0]

	def mixshader(self, fac, a, b):
		n = self.node('MixShader')
		self.set(n.inputs[0], fac)
		self.set(n.inputs[1], a)
		self.set(n.inputs[2], b)
		return n.outputs[0]

	def sep(self, v):
		n = self.node('SeparateXYZ')
		self.set(n.inputs[0], v)
		return n.outputs

	def comb(self, x, y, z):
		n = self.node('CombineXYZ')
		for i, v in enumerate((x, y, z)):
			self.set(n.inputs[i], v)
		return n.outputs[0]

	def ramp(self, fac, stops):
		n = self.node('ValToRGB')
		self.set(n.inputs[0], fac)
		els = n.color_ramp.elements
		rgba = lambda c: (*c, 1.0) if len(c) == 3 else c
		els[0].position, els[0].color = stops[0][0], rgba(stops[0][1])
		els[1].position, els[1].color = stops[-1][0], rgba(stops[-1][1])
		for pos, col in stops[1:-1]:
			els.new(pos).color = rgba(col)
		return n.outputs[0]

	def noise(self, vec, scale, detail=6.0, rough=0.55, dims='3D', out='Fac'):
		n = self.node('TexNoise', noise_dimensions=dims)
		self.set(n.inputs['Vector'], vec)
		n.inputs['Scale'].default_value = scale
		n.inputs['Detail'].default_value = detail
		n.inputs['Roughness'].default_value = rough
		return n.outputs[out]

	def smooth(self, e0, e1, x):
		n = self.node('MapRange', interpolation_type='SMOOTHSTEP')
		self.set(n.inputs[0], x)
		n.inputs[1].default_value = e0
		n.inputs[2].default_value = e1
		return n.outputs[0]

	def hash(self, v):
		n = self.node('TexWhiteNoise', noise_dimensions='3D')
		self.set(n.inputs[0], v)
		return n.outputs[0]

	def group(self, g):
		n = self.node('ShaderNodeGroup')
		n.node_tree = g
		return n

	def attr(self, name, kind='INSTANCER', out='Fac'):
		return self.node('Attribute', attribute_type=kind, attribute_name=name).outputs[out]

	def bsdf(self, base=None, rough=None, metal=None, normal=None, **inputs):
		b = self.node('BsdfPrincipled')
		for k, v in (('Base Color', base), ('Roughness', rough), ('Metallic', metal), ('Normal', normal)):
			self.set(b.inputs[k], v)
		for k, v in inputs.items():
			self.set(b.inputs[k.replace('_', ' ')], v)
		return b


def rgba(c):
	return tuple(c) + (1.0,) if len(c) == 3 else tuple(c)


# ================================================================================================================= sky & haze
def hdri_turn():
	"""How far to turn the photographed sky about Z so its sun sits at Breakwater's sun azimuth (radians)."""
	import numpy as np
	img = bpy.data.images.load(str(HDRI), check_existing=True)
	w, h = img.size
	px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3].sum(-1)
	y, x = np.unravel_index(np.argmax(px), px.shape)
	# Blender's equirectangular lookup: u = 0.5 - atan2(d.y, d.x) / 2π
	sun_az = (0.5 - x / w) * 2 * math.pi
	want = math.atan2(SUN_DIR.y, SUN_DIR.x)
	print(f'sky: sun at u={x / w:.3f}, {((y + 0.5) / h - 0.5) * 180:.1f}° up; Breakwater wants {math.degrees(math.asin(SUN_DIR.z)):.1f}°')
	return img, sun_az - want   # (the lookup turns the direction by this, so the sky turns the other way)


SKY_IMG, SKY_TURN = hdri_turn()


def sky_lookup(t, direction):
	"""The photographed sky seen along a direction (an Environment Texture node, turned to put its sun where Breakwater's is)."""
	m = t.node('Mapping', vector_type='POINT')
	t.set(m.inputs['Vector'], direction)
	m.inputs['Rotation'].default_value = (0.0, 0.0, SKY_TURN)
	env = t.node('TexEnvironment', interpolation='Cubic')
	env.image = SKY_IMG
	t.set(env.inputs[0], m.outputs[0])
	return env.outputs[0]


def build_world():
	w = bpy.data.worlds.new('Sky')
	scene.world = w
	w.use_nodes = True
	w.node_tree.nodes.clear()
	t = Tree(w.node_tree)
	tc = t.node('TexCoord')
	bg = t.node('Background')
	t.set(bg.inputs[0], sky_lookup(t, tc.outputs['Generated']))
	bg.inputs[1].default_value = 1.0
	out = t.node('OutputWorld')
	t.set(out.inputs[0], bg.outputs[0])
	w.cycles.sampling_method = 'MANUAL'
	w.cycles.sample_map_resolution = 4096


build_world()

HAZE_DIST = 5500.0     # metres for the haze to reach 63% near the ground
HAZE_HEIGHT = 650.0    # and it thins out above this


def build_atmosphere():
	"""Shader in, shader out: the surface faded by its distance from the camera into the sky's own colour just above the
	horizon in that direction (exponential height fog). Only camera rays see it."""
	g = bpy.data.node_groups.new('Atmosphere', 'ShaderNodeTree')
	g.interface.new_socket('Surface', in_out='INPUT', socket_type='NodeSocketShader')
	g.interface.new_socket('Shader', in_out='OUTPUT', socket_type='NodeSocketShader')
	t = Tree(g)
	gi, go = t.node('NodeGroupInput'), t.node('NodeGroupOutput')
	pos = t.node('NewGeometry').outputs['Position']
	rel = t.vmath('SUBTRACT', pos, (0.0, 0.0, CAM_Z))
	dist = t.vmath('LENGTH', rel, out=1)
	x, y, z = t.sep(rel)
	horizon = t.comb(x, y, t.math('MULTIPLY', t.vmath('LENGTH', t.comb(x, y, 0.0), out=1), 0.035))
	haze = sky_lookup(t, horizon)
	mid = t.math('MULTIPLY', t.math('ADD', t.sep(pos)[2], CAM_Z), 0.5)
	optical = t.math('MULTIPLY', t.math('DIVIDE', dist, HAZE_DIST), t.math('EXPONENT', t.math('DIVIDE', mid, -HAZE_HEIGHT)))
	fac = t.math('SUBTRACT', 1.0, t.math('EXPONENT', t.math('MULTIPLY', optical, -1.0)))
	fac = t.math('MULTIPLY', fac, t.node('LightPath').outputs['Is Camera Ray'])
	em = t.node('Emission')
	t.set(em.inputs[0], haze)
	t.set(go.inputs[0], t.mixshader(fac, gi.outputs[0], em.outputs[0]))
	return g


ATMOSPHERE = build_atmosphere()


def material(name, build):
	"""A material whose graph `build(t)` returns its surface shader socket; the atmosphere is added on top."""
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	m.node_tree.nodes.clear()
	t = Tree(m.node_tree)
	shader = build(t)
	a = t.group(ATMOSPHERE)
	t.set(a.inputs[0], shader)
	out = t.node('OutputMaterial')
	t.set(out.inputs[0], a.outputs[0])
	return m


# ================================================================================================================== materials
def bseed(t):
	"""0..1 per building: on the points the modules are instanced from, or on the faces of the plain boxes."""
	return t.math('ADD', t.attr('bseed'), t.attr('bseed', 'GEOMETRY'))


def weathering(t, base, pos, amount=0.25):
	"""Grime: darker streaks running down from ledges and a blotchy patina."""
	streak = t.noise(t.vmath('MULTIPLY', pos, (3.0, 3.0, 0.25)), 1.0, 8.0, 0.6)
	blotch = t.noise(pos, 0.35, 5.0, 0.6)
	dirt = t.math('MULTIPLY', t.math('ADD', t.smooth(0.45, 0.75, streak), t.math('MULTIPLY', t.smooth(0.5, 0.7, blotch), 0.6)), amount)
	return t.mix(dirt, base, t.vmath('MULTIPLY', base, (0.55, 0.53, 0.5)))


def mat_brick():
	def build(t):
		obj = t.node('TexCoord').outputs['Object']
		world = t.node('NewGeometry').outputs['Position']
		seed = bseed(t)
		# brick colour per building: reds, browns, buffs, a few painted
		tone = t.ramp(seed, [(0.0, (0.36, 0.13, 0.08)), (0.25, (0.45, 0.2, 0.12)), (0.45, (0.3, 0.16, 0.11)),
			(0.65, (0.52, 0.36, 0.24)), (0.8, (0.6, 0.48, 0.34)), (1.0, (0.4, 0.24, 0.17))])
		b = t.node('TexBrick', offset=0.5, offset_frequency=2, squash=1.0, squash_frequency=2)
		t.set(b.inputs['Vector'], t.comb(t.sep(obj)[0], t.sep(obj)[2], t.sep(obj)[1]))
		b.inputs['Scale'].default_value = 1.0
		b.inputs['Mortar Size'].default_value = 0.009
		b.inputs['Mortar Smooth'].default_value = 0.2
		b.inputs['Bias'].default_value = 0.0
		b.inputs['Brick Width'].default_value = 0.2267   # 15 bricks across a 3.4 m bay, so bays join seamlessly
		b.inputs['Row Height'].default_value = 0.0762    # 42 courses in a 3.2 m storey
		t.set(b.inputs['Color1'], tone)
		t.set(b.inputs['Color2'], t.vmath('MULTIPLY', tone, (0.72, 0.7, 0.68)))
		b.inputs['Mortar'].default_value = (0.5, 0.48, 0.44, 1.0)
		col = t.mix(t.math('MULTIPLY', t.noise(obj, 9.0, 2.0), 0.35), b.outputs['Color'], t.vmath('MULTIPLY', tone, (1.25, 1.2, 1.15)))
		col = weathering(t, col, world, 0.3)
		bump = t.node('Bump')
		bump.inputs['Strength'].default_value = 0.8
		bump.inputs['Distance'].default_value = 0.006
		t.set(bump.inputs['Height'], t.math('SUBTRACT', 1.0, b.outputs['Fac']))
		return t.bsdf(col, 0.85, normal=bump.outputs[0]).outputs[0]
	return material('Brick', build)


def mat_render():
	"""Painted render (stucco) for the newer flats."""
	def build(t):
		world = t.node('NewGeometry').outputs['Position']
		tone = t.ramp(bseed(t), [(0.0, (0.82, 0.79, 0.72)), (0.3, (0.72, 0.58, 0.44)), (0.5, (0.86, 0.86, 0.84)),
			(0.7, (0.58, 0.6, 0.58)), (0.85, (0.77, 0.7, 0.55)), (1.0, (0.42, 0.44, 0.47))])
		col = t.mix(t.math('MULTIPLY', t.noise(world, 3.0, 6.0), 0.15), tone, t.vmath('MULTIPLY', tone, (0.85, 0.85, 0.85)))
		col = weathering(t, col, world, 0.22)
		bump = t.node('Bump')
		bump.inputs['Strength'].default_value = 0.15
		bump.inputs['Distance'].default_value = 0.002
		t.set(bump.inputs['Height'], t.noise(world, 40.0, 4.0))
		return t.bsdf(col, 0.9, normal=bump.outputs[0]).outputs[0]
	return material('Render', build)


def mat_concrete(name='Concrete', tone=(0.5, 0.49, 0.46), per_building=True):
	def build(t):
		world = t.node('NewGeometry').outputs['Position']
		col = rgba(tone)
		if per_building:
			col = t.mix(bseed(t), col, (0.4, 0.38, 0.35, 1.0))
		col = t.mix(t.math('MULTIPLY', t.noise(world, 1.5, 8.0), 0.3), col, t.vmath('MULTIPLY', col, (0.8, 0.8, 0.8)))
		col = weathering(t, col, world, 0.3)
		bump = t.node('Bump')
		bump.inputs['Strength'].default_value = 0.2
		bump.inputs['Distance'].default_value = 0.003
		t.set(bump.inputs['Height'], t.noise(world, 25.0, 6.0))
		return t.bsdf(col, 0.82, normal=bump.outputs[0]).outputs[0]
	return material(name, build)


def mat_stone():
	def build(t):
		world = t.node('NewGeometry').outputs['Position']
		col = t.mix(t.math('MULTIPLY', t.noise(world, 6.0, 6.0), 0.4), (0.74, 0.7, 0.62, 1.0), (0.6, 0.57, 0.5, 1.0))
		return t.bsdf(weathering(t, col, world, 0.35), 0.75).outputs[0]
	return material('Stone', build)


def mat_paint(name, colour, rough=0.45, metal=0.0, per_building=None):
	def build(t):
		col = rgba(colour)
		if per_building:
			col = t.ramp(bseed(t), per_building)
		return t.bsdf(col, rough, metal).outputs[0]
	return material(name, build)


def mat_glass(name, tint=(0.82, 0.88, 0.86), reflect=0.0, rough=0.0):
	"""Window glass. reflect > 0 adds a coated, mirror-like reflection (curtain walls), tinted per building. Shadow rays pass
	straight through (thin glass), so daylight reaches the rooms behind."""
	def build(t):
		return t.mixshader(t.node('LightPath').outputs['Is Shadow Ray'], panes(t), t.node('BsdfTransparent').outputs[0])

	def panes(t):
		g = t.bsdf((1, 1, 1, 1), rough, 0.0, Transmission_Weight=1.0, IOR=1.52)
		t.set(g.inputs['Base Color'], rgba(tint))
		if not reflect:
			return g.outputs[0]
		coat = t.ramp(bseed(t), [(0.0, (0.35, 0.45, 0.5)), (0.3, (0.45, 0.5, 0.52)), (0.6, (0.3, 0.38, 0.36)),
			(0.8, (0.5, 0.45, 0.38)), (1.0, (0.55, 0.6, 0.65))])
		# panes are never perfectly flat: each instance tilts its reflection a little
		r = t.node('ObjectInfo').outputs['Random']
		n = t.vmath('ADD', t.node('NewGeometry').outputs['Normal'], t.comb(t.math('MULTIPLY', t.math('SUBTRACT', r, 0.5), 0.03), 0.0, 0.0))
		mirror = t.node('BsdfGlossy')
		t.set(mirror.inputs['Color'], coat)
		mirror.inputs['Roughness'].default_value = 0.01
		t.set(mirror.inputs['Normal'], t.vmath('NORMALIZE', n))
		return t.mixshader(reflect, g.outputs[0], mirror.outputs[0])
	return material(name, build)


def mat_room():
	"""The inside of a room seen through a window: wall colour, and dark or lit, per instance."""
	def build(t):
		r = t.node('ObjectInfo').outputs['Random']
		col = t.ramp(r, [(0.0, (0.75, 0.72, 0.66)), (0.3, (0.6, 0.62, 0.6)), (0.5, (0.8, 0.78, 0.74)), (0.7, (0.45, 0.4, 0.35)),
			(0.85, (0.65, 0.55, 0.45)), (1.0, (0.3, 0.32, 0.35))])
		dim = t.math('ADD', 0.35, t.math('MULTIPLY', t.hash(t.comb(r, 3.1, 0.0)), 0.65))
		return t.bsdf(t.vmath('MULTIPLY', col, t.comb(dim, dim, dim)), 0.9).outputs[0]
	return material('Room', build)


def mat_ceiling_light():
	"""A ceiling panel: lit in about a third of the rooms."""
	def build(t):
		r = t.hash(t.comb(t.node('ObjectInfo').outputs['Random'], 7.7, 0.0))
		on = t.math('GREATER_THAN', r, 0.62)
		em = t.node('Emission')
		em.inputs[0].default_value = (1.0, 0.93, 0.82, 1.0)
		t.set(em.inputs[1], t.math('MULTIPLY', on, 6.0))
		diff = t.bsdf((0.8, 0.8, 0.8, 1), 0.5)
		add = t.node('AddShader')
		t.set(add.inputs[0], diff.outputs[0])
		t.set(add.inputs[1], em.outputs[0])
		return add.outputs[0]
	return material('Ceiling light', build)


def mat_curtain():
	"""Curtains and blinds: fabric, lit from behind, colour per instance."""
	def build(t):
		r = t.hash(t.comb(t.node('ObjectInfo').outputs['Random'], 1.9, 0.0))
		col = t.ramp(r, [(0.0, (0.85, 0.83, 0.78)), (0.4, (0.75, 0.72, 0.65)), (0.6, (0.45, 0.5, 0.55)), (0.75, (0.6, 0.35, 0.25)),
			(0.9, (0.3, 0.32, 0.3)), (1.0, (0.9, 0.9, 0.9))])
		obj = t.node('TexCoord').outputs['Object']
		folds = t.node('TexWave', wave_type='BANDS', bands_direction='X')
		t.set(folds.inputs['Vector'], obj)
		folds.inputs['Scale'].default_value = 6.0
		col = t.mix(t.math('MULTIPLY', folds.outputs['Fac'], 0.25), col, t.vmath('MULTIPLY', col, (0.7, 0.7, 0.7)))
		return t.bsdf(col, 0.9, Subsurface_Weight=0.0, Transmission_Weight=0.0).outputs[0]
	return material('Curtain', build)


def mat_roof():
	def build(t):
		world = t.node('NewGeometry').outputs['Position']
		col = t.ramp(t.noise(world, 0.3, 6.0), [(0.3, (0.18, 0.18, 0.18)), (0.5, (0.3, 0.3, 0.29)), (0.7, (0.38, 0.37, 0.35))])
		return t.bsdf(col, 0.9).outputs[0]
	return material('Roof', build)


M = {
	'brick': mat_brick(),
	'render': mat_render(),
	'concrete': mat_concrete(),
	'stone': mat_stone(),
	'frame_white': mat_paint('Frame white', (0.8, 0.8, 0.78), 0.4),
	'frame_dark': mat_paint('Frame dark', (0.05, 0.055, 0.06), 0.4, 0.3),
	'alu': mat_paint('Aluminium', (0.55, 0.57, 0.6), 0.32, 0.9),
	'glass': mat_glass('Glass'),
	'glass_cw': mat_glass('Curtain wall glass', (0.7, 0.8, 0.8), reflect=0.55),
	'spandrel': mat_paint('Spandrel', (0.06, 0.07, 0.08), 0.08, 0.6, per_building=[(0.0, (0.06, 0.07, 0.08)), (0.5, (0.12, 0.14, 0.15)), (1.0, (0.18, 0.16, 0.13))]),
	'room': mat_room(),
	'light': mat_ceiling_light(),
	'curtain': mat_curtain(),
	'roof': mat_roof(),
	'metal': mat_paint('Plant metal', (0.5, 0.52, 0.53), 0.45, 0.7),
	'railing': mat_paint('Railing', (0.08, 0.08, 0.08), 0.5, 0.6),
	'balcony_glass': mat_glass('Balcony glass', (0.75, 0.82, 0.82), rough=0.05),
	'awning': mat_paint('Awning', (0.4, 0.1, 0.08), 0.8, per_building=[(0.0, (0.35, 0.08, 0.06)), (0.3, (0.08, 0.2, 0.12)),
		(0.55, (0.1, 0.12, 0.25)), (0.8, (0.6, 0.5, 0.3)), (1.0, (0.12, 0.12, 0.12))]),
	'sign': mat_paint('Sign band', (0.1, 0.1, 0.1), 0.4, per_building=[(0.0, (0.08, 0.08, 0.08)), (0.4, (0.7, 0.68, 0.62)), (0.7, (0.2, 0.25, 0.3)), (1.0, (0.5, 0.15, 0.1))]),
}


# ================================================================================================================== modules
class Mesh:
	"""Boxes and quads into one bmesh, each face given a material slot by name."""

	def __init__(self, name):
		self.name = name
		self.bm = bmesh.new()
		self.slots = []

	def slot(self, mat):
		if mat not in self.slots:
			self.slots.append(mat)
		return self.slots.index(mat)

	def box(self, x0, x1, y0, y1, z0, z1, mat, skip=()):
		"""An axis-aligned box. `skip` names faces to leave off: 'x0','x1','y0','y1','z0','z1'."""
		v = {}
		for i, x in enumerate((x0, x1)):
			for j, y in enumerate((y0, y1)):
				for k, z in enumerate((z0, z1)):
					v[i, j, k] = self.bm.verts.new((x, y, z))
		faces = {
			'x0': (v[0, 0, 0], v[0, 0, 1], v[0, 1, 1], v[0, 1, 0]), 'x1': (v[1, 0, 0], v[1, 1, 0], v[1, 1, 1], v[1, 0, 1]),
			'y0': (v[0, 0, 0], v[1, 0, 0], v[1, 0, 1], v[0, 0, 1]), 'y1': (v[0, 1, 0], v[0, 1, 1], v[1, 1, 1], v[1, 1, 0]),
			'z0': (v[0, 0, 0], v[0, 1, 0], v[1, 1, 0], v[1, 0, 0]), 'z1': (v[0, 0, 1], v[1, 0, 1], v[1, 1, 1], v[0, 1, 1]),
		}
		s = self.slot(mat)
		made = []
		for k, f in faces.items():
			if k not in skip:
				made.append(self.bm.faces.new(f))
				made[-1].material_index = s
		return made

	def quad_y(self, x0, x1, y, z0, z1, mat, facing=1):
		"""A rectangle in the plane y = const, facing +Y (or -Y)."""
		vs = [self.bm.verts.new(p) for p in ((x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1))]
		f = self.bm.faces.new(vs if facing < 0 else list(reversed(vs)))
		f.material_index = self.slot(mat)

	def quad_z(self, x0, x1, y0, y1, z, mat, facing=1):
		vs = [self.bm.verts.new(p) for p in ((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))]
		f = self.bm.faces.new(vs if facing > 0 else list(reversed(vs)))
		f.material_index = self.slot(mat)

	def object(self, coll):
		me = bpy.data.meshes.new(self.name)
		self.bm.to_mesh(me)
		self.bm.free()
		for m in self.slots:
			me.materials.append(M[m])
		ob = bpy.data.objects.new(self.name, me)
		coll.objects.link(ob)
		return ob


def room(m, x0, x1, y_glass, z0, z1, depth=3.2, light=True):
	"""The room behind a window: back wall, floor, ceiling (with a light panel), side walls."""
	yb = y_glass - depth
	m.quad_y(x0, x1, yb, z0, z1, 'room', facing=1)
	m.quad_z(x0, x1, yb, y_glass, z0, 'room', facing=1)
	m.quad_z(x0, x1, yb, y_glass, z1, 'room', facing=-1)
	m.box(x0, x0 + 0.02, yb, y_glass, z0, z1, 'room', skip=('y0', 'y1', 'z0', 'z1'))
	m.box(x1 - 0.02, x1, yb, y_glass, z0, z1, 'room', skip=('y0', 'y1', 'z0', 'z1'))
	if light:
		cx, w = (x0 + x1) / 2, (x1 - x0) * 0.3
		m.quad_z(cx - w, cx + w, yb + 0.6, y_glass - 0.6, z1 - 0.01, 'light', facing=-1)


def window_frame(m, x0, x1, z0, z1, y, mat, bars=(1, 1), t=0.06, d=0.07):
	"""A frame round an opening with `bars` = (vertical, horizontal) glazing bars, and its glass just behind."""
	m.box(x0, x1, y - d, y, z0, z0 + t, mat)
	m.box(x0, x1, y - d, y, z1 - t, z1, mat)
	m.box(x0, x0 + t, y - d, y, z0, z1, mat)
	m.box(x1 - t, x1, y - d, y, z0, z1, mat)
	for i in range(1, bars[0] + 1):
		x = x0 + (x1 - x0) * i / (bars[0] + 1)
		m.box(x - t / 2, x + t / 2, y - d, y, z0, z1, mat)
	for i in range(1, bars[1] + 1):
		z = z0 + (z1 - z0) * (0.62 if bars[1] == 1 else i / (bars[1] + 1))
		m.box(x0, x1, y - d, y, z - t / 2, z + t / 2, mat)
	m.quad_y(x0, x1, y - d / 2, z0, z1, 'glass')


def curtain(m, x0, x1, z0, z1, y, drawn):
	"""Curtains just inside the glass: drawn to the sides, half drawn, or a blind partly down."""
	w = x1 - x0
	if drawn == 'sides':
		m.quad_y(x0, x0 + w * 0.22, y, z0, z1, 'curtain')
		m.quad_y(x1 - w * 0.22, x1, y, z0, z1, 'curtain')
	elif drawn == 'half':
		m.quad_y(x0, x0 + w * 0.5, y, z0, z1, 'curtain')
	elif drawn == 'blind':
		m.quad_y(x0, x1, y, z1 - (z1 - z0) * rng.uniform(0.2, 0.7), z1, 'curtain')


# Each style: the bay width W and storey height H the modules share, the ground-floor height, and the variants.
# Modules face +Y with the wall face at y = 0, x across -W/2..W/2 and z from 0 (floor level) to H.
STYLES = {
	'brick': dict(W=3.4, H=3.2, G=4.4, wall='brick'),
	'office': dict(W=3.0, H=3.7, G=4.6, wall='concrete'),
	'curtain': dict(W=1.5, H=3.9, G=5.5, wall='alu'),
	'flats': dict(W=3.6, H=3.0, G=4.2, wall='render'),
}


def brick_bay(name, variant):
	W, H = STYLES['brick']['W'], STYLES['brick']['H']
	m = Mesh(name)
	ox, z0, z1, rev = 0.6, 0.85, 2.65, 0.24   # opening half-width, sill and head heights, reveal depth
	# wall round the opening: its inner faces are the reveals
	m.box(-W / 2, -ox, -0.35, 0.0, 0.0, H, 'brick', skip=('y0',))
	m.box(ox, W / 2, -0.35, 0.0, 0.0, H, 'brick', skip=('y0',))
	if variant != 2:
		m.box(-ox, ox, -0.35, 0.0, 0.0, z0, 'brick', skip=('y0',))
		m.box(-ox - 0.08, ox + 0.08, -0.05, 0.06, z0 - 0.07, z0, 'stone')   # sill
	m.box(-ox, ox, -0.35, 0.0, z1, H, 'brick', skip=('y0',))
	m.box(-ox - 0.1, ox + 0.1, -0.02, 0.03, z1, z1 + 0.22, 'stone')     # lintel
	frame = 'frame_white' if variant % 2 == 0 else 'frame_dark'
	if variant == 2:   # a french door onto a little balcony
		window_frame(m, -ox, ox, 0.05, z1, -rev, frame, bars=(1, 2))
		m.box(-ox - 0.3, ox + 0.3, 0.0, 0.55, -0.12, 0.0, 'stone')
		for x in [-ox - 0.28 + i * 0.12 for i in range(int((2 * ox + 0.56) / 0.12) + 1)]:
			m.box(x, x + 0.015, 0.5, 0.515, 0.0, 0.95, 'railing')
		m.box(-ox - 0.3, ox + 0.3, 0.0, 0.55, 0.95, 0.99, 'railing', skip=('z0',))
	else:
		window_frame(m, -ox, ox, z0, z1, -rev, frame, bars=(1, 1 if variant != 3 else 2))
	if variant == 1:   # an air-conditioner hung under the window
		m.box(-0.4, 0.4, 0.0, 0.3, z0 - 0.75, z0 - 0.2, 'metal')
	curtain(m, -ox, ox, z0 if variant != 2 else 0.05, z1, -rev - 0.12, rng.choice(['sides', 'sides', 'half', 'blind', 'none']))
	room(m, -ox, ox, -rev - 0.07, 0.0, H - 0.3)
	return m


def brick_ground(name, variant):
	W, G = STYLES['brick']['W'], STYLES['brick']['G']
	m = Mesh(name)
	m.box(-W / 2, -W / 2 + 0.35, -0.3, 0.0, 0.0, G, 'stone', skip=('y0',))
	m.box(W / 2 - 0.35, W / 2, -0.3, 0.0, 0.0, G, 'stone', skip=('y0',))
	m.box(-W / 2 + 0.35, W / 2 - 0.35, -0.3, 0.0, 3.4, G, 'stone', skip=('y0',))
	m.box(-W / 2 + 0.35, W / 2 - 0.35, -0.3, 0.0, 0.0, 0.35, 'stone', skip=('y0',))
	m.box(-W / 2 + 0.3, W / 2 - 0.3, 0.0, 0.08, 3.45, 4.05, 'sign')
	window_frame(m, -W / 2 + 0.35, W / 2 - 0.35, 0.35, 3.4, -0.12, 'frame_dark', bars=(1 if variant else 0, 1))
	if variant == 1:   # an awning over the shop window
		awn = m.slot('awning')
		vs = [m.bm.verts.new(p) for p in ((-W / 2 + 0.3, 0.0, 3.4), (W / 2 - 0.3, 0.0, 3.4), (W / 2 - 0.3, 1.3, 2.75), (-W / 2 + 0.3, 1.3, 2.75))]
		m.bm.faces.new(vs).material_index = awn
	room(m, -W / 2 + 0.35, W / 2 - 0.35, -0.2, 0.0, 3.8, depth=5.0)
	return m


def office_bay(name, variant):
	W, H = STYLES['office']['W'], STYLES['office']['H']
	m = Mesh(name)
	# precast spandrel panel standing proud, ribbon glazing set back, a head band under the next spandrel
	m.box(-W / 2, W / 2, -0.1, 0.12, 0.0, 1.05, 'concrete')
	m.box(-W / 2, W / 2, -0.1, 0.04, 3.3, H, 'concrete')
	m.box(-W / 2, -W / 2 + 0.08, -0.25, 0.08, 1.05, 3.3, 'concrete')   # the precast fin between bays
	gl = -0.16
	for x0, x1 in ((-W / 2 + 0.08, 0.0), (0.0, W / 2)):
		window_frame(m, x0, x1, 1.05, 3.3, gl, 'alu', bars=(0, 0), t=0.05, d=0.06)
	if variant == 1:
		curtain(m, -W / 2 + 0.08, W / 2, 1.05, 3.3, gl - 0.1, 'blind')
	elif variant == 2:
		m.quad_y(-W / 2 + 0.08, W / 2, gl - 0.1, 1.05, 3.3, 'curtain')
	room(m, -W / 2 + 0.08, W / 2, gl - 0.06, 0.0, H - 0.25, depth=5.0)
	return m


def office_ground(name, variant):
	W, G = STYLES['office']['W'], STYLES['office']['G']
	m = Mesh(name)
	m.box(-W / 2, -W / 2 + 0.5, -0.4, 0.0, 0.0, G, 'concrete', skip=('y0',))
	m.box(-W / 2 + 0.5, W / 2, -0.4, 0.0, 4.0, G, 'concrete', skip=('y0',))
	window_frame(m, -W / 2 + 0.5, W / 2, 0.0, 4.0, -0.3, 'alu', bars=(1, 1), t=0.06)
	room(m, -W / 2 + 0.5, W / 2, -0.38, 0.0, 4.0, depth=8.0)
	return m


def curtain_bay(name, variant):
	W, H = STYLES['curtain']['W'], STYLES['curtain']['H']
	m = Mesh(name)
	# unitised curtain wall: a mullion on the left edge (the next bay supplies the right), a transom at the slab
	m.box(-W / 2, -W / 2 + 0.06, 0.0, 0.16, 0.0, H, 'alu')
	m.box(-W / 2, W / 2, 0.0, 0.1, 0.0, 0.07, 'alu')
	m.box(-W / 2, W / 2, 0.0, 0.08, 1.0, 1.06, 'alu')
	m.quad_y(-W / 2, W / 2, 0.02, 0.07, 1.0, 'spandrel')
	m.quad_y(-W / 2 + 0.06, W / 2, 0.03, 1.06, H, 'glass_cw')
	if variant == 1:
		curtain(m, -W / 2, W / 2, 1.06, H - 0.1, -0.1, 'blind')
	room(m, -W / 2, W / 2, -0.05, 0.9, H - 0.4, depth=6.0)
	m.box(-W / 2, W / 2, -0.4, -0.02, 0.0, 1.0, 'room', skip=('y0',))   # the slab edge behind the spandrel
	return m


def curtain_ground(name, variant):
	W, G = STYLES['curtain']['W'], STYLES['curtain']['G']
	m = Mesh(name)
	m.box(-W / 2, -W / 2 + 0.08, 0.0, 0.2, 0.0, G, 'alu')
	m.box(-W / 2, W / 2, 0.0, 0.2, G - 0.5, G, 'alu')
	m.quad_y(-W / 2, W / 2, 0.05, 0.0, G - 0.5, 'glass')
	room(m, -W / 2, W / 2, 0.0, 0.0, G, depth=10.0)
	return m


def flats_bay(name, variant):
	W, H = STYLES['flats']['W'], STYLES['flats']['H']
	m = Mesh(name)
	ox = 1.25
	m.box(-W / 2, -ox, -0.3, 0.0, 0.0, H, 'render', skip=('y0',))
	m.box(ox, W / 2, -0.3, 0.0, 0.0, H, 'render', skip=('y0',))
	m.box(-ox, ox, -0.3, 0.0, 2.35, H, 'render', skip=('y0',))
	if variant in (0, 1):   # a balcony: slab, glass balustrade, door
		m.box(-W / 2 + 0.15, W / 2 - 0.15, 0.0, 1.4, -0.18, 0.0, 'concrete')
		m.box(-W / 2 + 0.15, W / 2 - 0.15, 1.36, 1.4, 0.0, 1.05, 'balcony_glass')
		m.box(-W / 2 + 0.15, W / 2 - 0.15, 1.33, 1.42, 1.05, 1.1, 'railing')
		window_frame(m, -ox, ox, 0.0, 2.35, -0.12, 'frame_dark', bars=(1, 0), t=0.05)
		if variant == 1:   # someone's plant pot and a chair
			m.box(W / 2 - 0.6, W / 2 - 0.3, 0.9, 1.2, 0.0, 0.45, 'awning')
	else:
		m.box(-ox, ox, -0.3, 0.0, 0.0, 0.8, 'render', skip=('y0',))
		window_frame(m, -ox, ox, 0.8, 2.35, -0.12, 'frame_dark', bars=(1, 0), t=0.05)
	curtain(m, -ox, ox, 0.0, 2.35, -0.25, rng.choice(['sides', 'half', 'blind', 'none']))
	room(m, -ox, ox, -0.19, 0.0, H - 0.25)
	return m


def flats_ground(name, variant):
	W, G = STYLES['flats']['W'], STYLES['flats']['G']
	m = Mesh(name)
	m.box(-W / 2, -W / 2 + 0.4, -0.25, 0.0, 0.0, G, 'concrete', skip=('y0',))
	m.box(-W / 2 + 0.4, W / 2, -0.25, 0.0, 3.6, G, 'concrete', skip=('y0',))
	window_frame(m, -W / 2 + 0.4, W / 2, 0.0, 3.6, -0.15, 'frame_dark', bars=(1, 1))
	room(m, -W / 2 + 0.4, W / 2, -0.22, 0.0, 3.6, depth=6.0)
	return m


BUILDERS = {'brick': (brick_bay, brick_ground, 4), 'office': (office_bay, office_ground, 3),
	'curtain': (curtain_bay, curtain_ground, 2), 'flats': (flats_bay, flats_ground, 3)}

library = collection('Facade modules (instanced)', hide=True)
MODULES = {}   # style -> {'bay': collection of variants, 'ground': collection}
for style, (bay, ground, n) in BUILDERS.items():
	cb = collection(f'{style} bays', library)
	cg = collection(f'{style} ground floor', library)
	for v in range(n * 2):   # each variant twice over, with its own random curtains
		bay(f'{style}_bay_{v}', v % n).object(cb)
	for v in range(2):
		ground(f'{style}_ground_{v}', v).object(cg)
	MODULES[style] = {'bay': cb, 'ground': cg}


# ============================================================================================================ instancing
def build_instancer():
	"""Geometry nodes: on each vertex of a point cloud, one module from a collection, picked by the point's `variant`,
	turned by its `rot` (Euler, radians). Every point also carries `bseed` for the materials."""
	g = bpy.data.node_groups.new('Facade instancer', 'GeometryNodeTree')
	g.interface.new_socket('Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
	g.interface.new_socket('Modules', in_out='INPUT', socket_type='NodeSocketCollection')
	g.interface.new_socket('Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
	t = Tree(g)
	gi, go = t.node('NodeGroupInput'), t.node('NodeGroupOutput')
	ci = t.node('GeometryNodeCollectionInfo', transform_space='ORIGINAL')
	ci.inputs['Separate Children'].default_value = True
	ci.inputs['Reset Children'].default_value = True
	t.set(ci.inputs['Collection'], gi.outputs[1])
	inst = t.node('GeometryNodeInstanceOnPoints')
	t.set(inst.inputs['Points'], gi.outputs[0])
	t.set(inst.inputs['Instance'], ci.outputs[0])
	inst.inputs['Pick Instance'].default_value = True
	var = t.node('GeometryNodeInputNamedAttribute', data_type='INT')
	var.inputs['Name'].default_value = 'variant'
	t.set(inst.inputs['Instance Index'], var.outputs['Attribute'])
	rot = t.node('GeometryNodeInputNamedAttribute', data_type='FLOAT_VECTOR')
	rot.inputs['Name'].default_value = 'rot'
	e2r = t.node('FunctionNodeEulerToRotation')
	t.set(e2r.inputs[0], rot.outputs['Attribute'])
	t.set(inst.inputs['Rotation'], e2r.outputs[0])
	t.set(go.inputs[0], inst.outputs[0])
	return g


INSTANCER = build_instancer()


class Facades:
	"""Points for one style's modules: where each bay goes, which variant, which way it faces, which building."""

	def __init__(self, name, style, part, coll):
		self.name, self.style, self.part, self.coll = name, style, part, coll
		self.pts, self.var, self.rot, self.seed = [], [], [], []

	def add(self, p, yaw, variant, seed):
		self.pts.append(p)
		self.var.append(variant)
		self.rot.append((0.0, 0.0, yaw))
		self.seed.append(seed)

	def object(self):
		me = bpy.data.meshes.new(self.name)
		me.from_pydata(self.pts, [], [])
		a = me.attributes.new('variant', 'INT', 'POINT')
		a.data.foreach_set('value', self.var)
		a = me.attributes.new('rot', 'FLOAT_VECTOR', 'POINT')
		a.data.foreach_set('vector', [c for r in self.rot for c in r])
		a = me.attributes.new('bseed', 'FLOAT', 'POINT')
		a.data.foreach_set('value', self.seed)
		ob = bpy.data.objects.new(self.name, me)
		self.coll.objects.link(ob)
		mod = ob.modifiers.new('Modules', 'NODES')
		mod.node_group = INSTANCER
		mod['Socket_1'] = MODULES[self.style][self.part]
		return ob


def detailed_building(cx, cy, sx, sy, floors, style, yaw, seed, facades, core, roofs):
	"""A building made of modules: a core box (the corners and the roof), its four walls covered in bays, ground floor first."""
	S = STYLES[style]
	W, H, G = S['W'], S['H'], S['G']
	top = G + floors * H
	c, s = math.cos(yaw), math.sin(yaw)
	to_world = lambda lx, ly, z: Vector((cx + lx * c - ly * s, cy + lx * s + ly * c, z))
	# No solid core: every bay closes its own room behind the glass. What is left is the roof slab and, at each end of each wall,
	# the strip the whole bays do not fill, which closes the corners.
	core.box_rot(cx, cy, sx, sy, top - 0.3, top, yaw, S['wall'], seed)
	n_bay = len(MODULES[style]['bay'].objects)
	n_gnd = len(MODULES[style]['ground'].objects)
	for side in range(4):
		# side 0 faces local -Y, 1 +X, 2 +Y, 3 -X; a module's +Y must point outwards
		L = sx if side % 2 == 0 else sy
		depth = sy if side % 2 == 0 else sx
		face_yaw = yaw + [math.pi, -math.pi / 2, 0.0, math.pi / 2][side]
		n = int((L - 0.6) / W)
		if n < 1:
			continue
		start = -n * W / 2 + W / 2
		m = (L - n * W) / 2
		# (the end walls stop short of the corner, which the front and back strips already fill: faces lying in the same
		# plane render black)
		width = m if side % 2 == 0 else m - 0.4
		for end in (-1, 1) if width > 0.02 else ():
			u, inset = end * (L / 2 - (m - width) - width / 2), depth / 2 - 0.2
			lx, ly = {0: (-u, -inset), 1: (inset, -u), 2: (u, inset), 3: (-inset, u)}[side]
			bx, by = (width, 0.4) if side % 2 == 0 else (0.4, width)
			p = to_world(lx, ly, 0.0)
			core.box_rot(p.x, p.y, bx, by, 0.0, top - 0.3, yaw, S['wall'], seed)
		for i in range(n):
			u = start + i * W
			lx, ly = {0: (-u, -depth / 2), 1: (depth / 2, -u), 2: (u, depth / 2), 3: (-depth / 2, u)}[side]
			facades[(style, 'ground')].add(to_world(lx, ly, 0.0), face_yaw, rng.randrange(n_gnd), seed)
			for f in range(floors):
				facades[(style, 'bay')].add(to_world(lx, ly, G + f * H), face_yaw, rng.randrange(n_bay), seed)
	roofs.rooftop(cx, cy, sx, sy, top, yaw, seed)
	return top


class Boxes:
	"""Plain boxes into one mesh (building cores, rooftop plant), with a per-face `bseed` the materials read as an attribute."""

	def __init__(self, name, coll):
		self.name, self.coll = name, coll
		self.m = Mesh(name)
		self.seed = self.m.bm.faces.layers.float.new('bseed')

	def box_rot(self, cx, cy, sx, sy, z0, z1, yaw, mat, seed=0.0, skip=('z0',)):
		new = self.m.box(-sx / 2, sx / 2, -sy / 2, sy / 2, z0, z1, mat, skip=skip)
		c, s = math.cos(yaw), math.sin(yaw)
		for v in {v for f in new for v in f.verts}:
			x, y = v.co.x, v.co.y
			v.co.x, v.co.y = cx + x * c - y * s, cy + x * s + y * c
		for f in new:
			f[self.seed] = seed

	def rooftop(self, cx, cy, sx, sy, top, yaw, seed):
		"""A parapet, a roof membrane, and plant: units, a lift overrun, vents."""
		t = 0.25
		c, s = math.cos(yaw), math.sin(yaw)
		def at(lx, ly):
			return cx + lx * c - ly * s, cy + lx * s + ly * c
		for lx, ly, w, d in ((0, -sy / 2 + t / 2, sx, t), (0, sy / 2 - t / 2, sx, t), (-sx / 2 + t / 2, 0, t, sy), (sx / 2 - t / 2, 0, t, sy)):
			x, y = at(lx, ly)
			self.box_rot(x, y, w, d, top, top + 1.0, yaw, 'stone' if seed < 0.5 else 'concrete', seed)
		x, y = at(0, 0)
		self.box_rot(x, y, sx - 0.4, sy - 0.4, top, top + 0.05, yaw, 'roof', seed)
		for _ in range(rng.randint(2, 6)):
			ux, uy = rng.uniform(-0.3, 0.3) * sx, rng.uniform(-0.3, 0.3) * sy
			x, y = at(ux, uy)
			self.box_rot(x, y, rng.uniform(1.2, 3.5), rng.uniform(1.0, 2.5), top, top + rng.uniform(0.8, 2.2), yaw, 'metal')
		if sx * sy > 300 and rng.random() < 0.7:
			x, y = at(rng.uniform(-0.2, 0.2) * sx, rng.uniform(-0.2, 0.2) * sy)
			self.box_rot(x, y, 3.0, 4.0, top, top + 3.2, yaw, 'concrete', seed)

	def object(self):
		return self.m.object(self.coll)


# ===================================================================================================================== trees
def load_trees():
	"""Poly Haven's scanned trees (CC0), LOD1, as collections to instance."""
	out = []
	trees = collection('Tree models (instanced)', hide=True)
	for f, name in (('island_tree_02_1k', 'island_tree_02_LOD1'), ('tree_small_02_1k', 'tree_small_02_LOD1')):
		with bpy.data.libraries.load(str(ASSETS / f'trees/{f}.blend')) as (src, dst):
			dst.objects = [name]
		ob = dst.objects[0]
		c = collection(name, trees)
		c.objects.link(ob)
		ob.location = (0, 0, 0)
		out.append((c, ob.dimensions.z))
	return out


TREE_MODELS = load_trees()


def plant_tree(coll, x, y, height):
	ob = bpy.data.objects.new('tree', None)
	ob.instance_type = 'COLLECTION'
	model, model_h = rng.choice(TREE_MODELS)
	ob.instance_collection = model
	ob.location = (x, y, 0.0)
	ob.rotation_euler = (0, 0, rng.uniform(0, 2 * math.pi))
	ob.scale = (height / model_h,) * 3
	coll.objects.link(ob)


# ============================================================================================================ render setup
def ground_plane(coll, mat='concrete', size=40000.0):
	m = Mesh('Ground')
	m.quad_z(-size, size, -size, size, 0.0, mat)
	return m.object(coll)


def gpu():
	"""Turns on the first kind of GPU Cycles can use here; False if there is none (or --cpu)."""
	if CPU:
		return False
	prefs = bpy.context.preferences.addons['cycles'].preferences
	for kind in ('OPTIX', 'CUDA', 'HIP', 'METAL', 'ONEAPI'):
		try:
			prefs.compute_device_type = kind
		except TypeError:
			continue
		prefs.get_devices()
		devices = [d for d in prefs.devices if d.type == kind]
		if devices:
			for d in prefs.devices:
				d.use = d.type == kind
			print('rendering on', kind, ', '.join(d.name for d in devices))
			return True
	print('rendering on the CPU')
	return False


def setup_render(res, samples):
	r = scene.render
	r.engine = 'CYCLES'
	cy = scene.cycles
	cy.device = 'GPU' if gpu() else 'CPU'
	cy.samples = SAMPLES or samples
	cy.use_adaptive_sampling = True
	cy.adaptive_threshold = 0.02
	cy.use_denoising = True
	cy.denoiser = 'OPENIMAGEDENOISE'
	cy.max_bounces = 6
	cy.diffuse_bounces = 2
	cy.glossy_bounces = 3
	cy.transmission_bounces = 4
	cy.transparent_max_bounces = 8
	cy.caustics_reflective = False
	cy.caustics_refractive = False
	cy.sample_clamp_indirect = 8.0
	r.resolution_x, r.resolution_y = res
	r.resolution_percentage = 100
	scene.view_settings.view_transform = 'AgX'
	scene.view_settings.look = 'AgX - Medium High Contrast'
	r.image_settings.file_format = 'PNG'
	r.image_settings.color_mode = 'RGB'


def camera(name, loc, look_at, lens=35.0):
	cd = bpy.data.cameras.new(name)
	cd.lens = lens
	cd.clip_end = 60000.0
	cam = bpy.data.objects.new(name, cd)
	scene.collection.objects.link(cam)
	cam.location = loc
	d = Vector(look_at) - Vector(loc)
	cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
	return cam


# ===================================================================================================================== test
def test_street():
	"""A short street of each style, seen close up and from about as far as the nearest panorama buildings."""
	coll = collection('Test street')
	facades = {(s, p): Facades(f'{s} {p}', s, p, coll) for s in STYLES for p in ('bay', 'ground')}
	core = Boxes('Cores', coll)
	roofs = Boxes('Rooftops', coll)
	x = -60.0
	for style, sx, floors in (('brick', 24.0, 5), ('office', 33.0, 8), ('curtain', 30.0, 14), ('flats', 29.0, 6), ('brick', 21.0, 4)):
		detailed_building(x + sx / 2, 30.0, sx, 18.0, floors, style, 0.0, rng.random(), facades, core, roofs)
		x += sx + 4.0
	for f in facades.values():
		f.object()
	core.object()
	roofs.object()
	ground_plane(coll)
	for i in range(9):
		plant_tree(coll, -55 + i * 14 + rng.uniform(-2, 2), 15.0, rng.uniform(9.0, 14.0))
	setup_render((1600, 900), 64)
	shots = [('test_close', (-15.0, -8.0, 1.7), (-25.0, 30.0, 10.0), 35.0), ('test_street', (5.0, -60.0, 1.7), (10.0, 30.0, 18.0), 28.0),
		('test_far', (10.0, -230.0, 2.0), (10.0, 30.0, 20.0), 60.0)]
	for name, loc, at, lens in shots:
		scene.camera = camera(name, loc, at, lens)
		scene.render.filepath = str(ART / f'{name}.png')
		bpy.ops.render.render(write_still=True)


# ====================================================================================================== far facade textures
BAKE_BAYS, BAKE_FLOORS = 8, 6
PX_PER_M = 26.0


def tag_glass():
	"""Glass writes 1 into the `glass` AOV, so the facade renders below know where the panes are."""
	for key in ('glass', 'glass_cw', 'balcony_glass'):
		nt = M[key].node_tree
		aov = nt.nodes.new('ShaderNodeOutputAOV')
		aov.aov_name = 'glass'
		aov.inputs['Value'].default_value = 1.0


def bake_facades():
	"""Each style's modules as a flat wall, rendered straight on under an even white sky: what the buildings too far away for
	modules wear as a texture (colour, with the shading of the reveals and the rooms behind the glass), plus where the glass is."""
	import tempfile
	tmp = Path(tempfile.mkdtemp(prefix='facades_'))
	tag_glass()
	vl = scene.view_layers[0]
	aov = vl.aovs.add()
	aov.name, aov.type = 'glass', 'VALUE'
	sky_world = scene.world
	white = bpy.data.worlds.new('Even white')
	white.use_nodes = True
	white.node_tree.nodes['Background'].inputs[0].default_value = (1, 1, 1, 1)
	scene.world = white
	scene.use_nodes = True
	nt = scene.node_tree
	nt.nodes.clear()
	rl = nt.nodes.new('CompositorNodeRLayers')
	fo = nt.nodes.new('CompositorNodeOutputFile')
	fo.format.file_format = 'PNG'
	fo.format.color_mode = 'BW'
	nt.links.new(rl.outputs['glass'], fo.inputs[0])
	comp = nt.nodes.new('CompositorNodeComposite')
	nt.links.new(rl.outputs['Image'], comp.inputs[0])
	setup_render((16, 16), 48)
	scene.cycles.use_adaptive_sampling = False
	scene.view_settings.view_transform = 'Standard'
	scene.view_settings.look = 'None'
	out = {}
	for style, S in STYLES.items():
		W, H, G = S['W'], S['H'], S['G']
		coll = collection(f'Bake {style}')
		fac = {p: Facades(f'bake {style} {p}', style, p, coll) for p in ('bay', 'ground')}
		n_bay = len(MODULES[style]['bay'].objects)
		for i in range(BAKE_BAYS):
			x = (i - (BAKE_BAYS - 1) / 2) * W
			fac['ground'].add(Vector((x, 0.0, 0.0)), math.pi, rng.randrange(2), 0.5)
			for f in range(BAKE_FLOORS):
				fac['bay'].add(Vector((x, 0.0, G + f * H)), math.pi, rng.randrange(n_bay), 0.5)
		obs = [f.object() for f in fac.values()]
		width, height = BAKE_BAYS * W, G + BAKE_FLOORS * H
		cd = bpy.data.cameras.new('bake')
		cd.type = 'ORTHO'
		cd.ortho_scale = max(width, height)
		cam = bpy.data.objects.new('bake', cd)
		scene.collection.objects.link(cam)
		cam.location = (0.0, -60.0, height / 2)
		cam.rotation_euler = (math.radians(90), 0.0, 0.0)
		scene.camera = cam
		scene.render.resolution_x = round(width * PX_PER_M)
		scene.render.resolution_y = round(height * PX_PER_M)
		fo.base_path = str(tmp)
		fo.file_slots[0].path = f'{style}_glass_'
		scene.render.filepath = str(tmp / f'{style}_colour.png')
		bpy.ops.render.render(write_still=True)
		glass = next(tmp.glob(f'{style}_glass_*.png'))
		col_img = bpy.data.images.load(str(tmp / f'{style}_colour.png'))
		col_img.name = f'{style} facade'
		col_img.pack()
		mask_img = bpy.data.images.load(str(glass))
		mask_img.name = f'{style} facade glass'
		mask_img.colorspace_settings.name = 'Non-Color'
		mask_img.pack()
		out[style] = (col_img, mask_img, width, height)
		for ob in obs + [cam]:
			bpy.data.objects.remove(ob)
		bpy.data.collections.remove(coll)
	scene.world = sky_world
	scene.use_nodes = False
	scene.view_settings.view_transform = 'AgX'
	scene.view_settings.look = 'AgX - Medium High Contrast'
	return out


def mat_far(style, baked):
	"""A box wearing a style's rendered facade: UVs are metres (u along the wall, v up from the ground), the ground-floor row
	once and the storeys repeating above it; the glass is glossy, the rest matt; roofs get roof membrane."""
	col_img, mask_img, width, height = baked
	S = STYLES[style]
	G, span = S['G'], BAKE_FLOORS * S['H']
	def build(t):
		u, v, _ = t.sep(t.node('UVMap', uv_map='UVMap').outputs[0])
		above = t.math('GREATER_THAN', v, G)
		vv = t.mixf(above, v, t.math('ADD', G, t.math('FLOORED_MODULO', t.math('SUBTRACT', v, G), span)))
		uv = t.comb(t.math('DIVIDE', u, width), t.math('DIVIDE', vv, height), 0.0)
		img = t.node('TexImage', interpolation='Cubic', extension='REPEAT')
		img.image = col_img
		t.set(img.inputs[0], uv)
		msk = t.node('TexImage', interpolation='Linear', extension='REPEAT')
		msk.image = mask_img
		t.set(msk.inputs[0], uv)
		mask = msk.outputs['Color']
		mask = t.sep(mask)[0]
		seed = bseed(t)
		shade = t.math('ADD', 0.78, t.math('MULTIPLY', seed, 0.4))
		col = t.vmath('MULTIPLY', img.outputs['Color'], t.comb(shade, t.math('ADD', shade, -0.02), t.math('ADD', shade, -0.05)))
		# the panes came out pale (they reflected the white sky they were rendered under): darken them to tinted glass, and let
		# the real sky give them their reflections here
		tint = t.ramp(t.math('FRACT', t.math('MULTIPLY', seed, 5.3)), [(0.0, (0.04, 0.06, 0.08)), (0.4, (0.07, 0.09, 0.1)),
			(0.7, (0.05, 0.07, 0.06)), (1.0, (0.1, 0.09, 0.07))])
		col = t.mix(t.math('MULTIPLY', mask, 0.85), col, tint)
		pos = t.node('NewGeometry')
		is_roof = t.math('GREATER_THAN', t.sep(pos.outputs['Normal'])[2], 0.7)
		roof = t.ramp(t.noise(pos.outputs['Position'], 0.3), [(0.3, (0.17, 0.17, 0.17)), (0.7, (0.33, 0.32, 0.3))])
		col = t.mix(is_roof, col, roof)
		mask = t.math('MULTIPLY', mask, t.math('SUBTRACT', 1.0, is_roof))
		metal = 0.3 if style == 'curtain' else 0.1
		return t.bsdf(col, t.mixf(mask, 0.85, 0.05), t.math('MULTIPLY', mask, metal), Specular_IOR_Level=t.mixf(mask, 0.4, 0.8)).outputs[0]
	return material(f'Far {style}', build)


class FarBoxes:
	"""Boxes with metre UVs and a per-face `bseed`, for one style's far buildings."""

	def __init__(self, name, mat, coll):
		self.name, self.mat, self.coll = name, mat, coll
		self.bm = bmesh.new()
		self.uv = self.bm.loops.layers.uv.new('UVMap')
		self.seed = self.bm.faces.layers.float.new('bseed')

	def box(self, cx, cy, z0, sx, sy, h, yaw, seed, u0=0.0):
		c, s = math.cos(yaw), math.sin(yaw)
		pts = [(cx + px * c - py * s, cy + px * s + py * c) for px, py in ((-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2))]
		lo = [self.bm.verts.new((x, y, z0)) for x, y in pts]
		hi = [self.bm.verts.new((x, y, z0 + h)) for x, y in pts]
		for i, L in enumerate((sx, sy, sx, sy)):
			j = (i + 1) % 4
			f = self.bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
			f[self.seed] = seed
			o = u0 + i * 7.3   # so the four walls do not start on the same bay
			for loop, uv in zip(f.loops, ((o, z0), (o + L, z0), (o + L, z0 + h), (o, z0 + h))):
				loop[self.uv].uv = uv
		f = self.bm.faces.new(hi)
		f[self.seed] = seed
		for loop in f.loops:
			loop[self.uv].uv = (loop.vert.co.x, loop.vert.co.y)

	def object(self):
		me = bpy.data.meshes.new(self.name)
		self.bm.to_mesh(me)
		self.bm.free()
		me.materials.append(self.mat)
		ob = bpy.data.objects.new(self.name, me)
		self.coll.objects.link(ob)
		return ob


# ================================================================================================================ the city
# The harbour: water between two straight shores, across the view ahead and to the right of the spawn (Godot -Z, +X). The
# downtown stands on the far shore, side-lit by the sun from ahead-left.
SHORE_N = Vector((0.53, 0.85, 0.0)).normalized()
NEAR_SHORE, FAR_SHORE = 250.0, 1300.0
WATER_Z = -1.4
LEVEL = 165.0                    # the level's own ground reaches 150 m out
BLOCK, ROAD = 92.0, 22.0
PITCH = BLOCK + ROAD
DETAIL_R = 700.0                 # modules this near, textured boxes beyond
CITY_R = 7500.0
DOWNTOWN = [(SHORE_N * 2100.0, 1.0, 750.0), (Vector((-2200.0, -2600.0, 0.0)), 0.45, 800.0)]


def shore(p):
	return p.x * SHORE_N.x + p.y * SHORE_N.y


def on_land(p, margin=0.0):
	d = shore(p)
	return d < NEAR_SHORE - margin or d > FAR_SHORE + margin


def boost(p):
	return max(st * math.exp(-((p - c).length / r) ** 2) for c, st, r in DOWNTOWN)


def pick_style(h):
	if h > 70:
		return rng.choices(['curtain', 'office'], [0.6, 0.4])[0]
	if h > 32:
		return rng.choices(['office', 'brick', 'flats', 'curtain'], [0.35, 0.25, 0.3, 0.1])[0]
	return rng.choices(['brick', 'flats', 'office'], [0.45, 0.4, 0.15])[0]


def lay_out_city(baked):
	near = collection('City near (modules)')
	far = collection('City far (textured)')
	facades = {(s, p): Facades(f'{s} {p}', s, p, near) for s in STYLES for p in ('bay', 'ground')}
	cores = Boxes('Near cores', near)
	roofs = Boxes('Near rooftops', near)
	far_mats = {s: mat_far(s, baked[s]) for s in STYLES}
	fars = {s: FarBoxes(f'Far {s}', far_mats[s], far) for s in STYLES}
	far_roofs = Boxes('Far rooftops', far)
	count = [0, 0]
	n = int(CITY_R / PITCH) + 1
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			c = Vector((i * PITCH, j * PITCH, 0.0))
			d = c.length
			if d > CITY_R or (abs(c.x) < LEVEL + BLOCK / 2 and abs(c.y) < LEVEL + BLOCK / 2):
				continue
			b = boost(c)
			lots = 2 if (d < 2500 or b > 0.3) else rng.choice([1, 2])
			base = 13.0 + 16.0 * math.exp(-d / 3000.0)
			w = BLOCK / lots
			for a in range(lots):
				for k in range(lots):
					p = Vector((c.x - BLOCK / 2 + w * (a + 0.5), c.y - BLOCK / 2 + w * (k + 0.5), 0.0))
					if not on_land(p, w * 0.6) or (abs(p.x) < LEVEL and abs(p.y) < LEVEL):
						continue
					if rng.random() < 0.05 and d < 3000:
						continue   # a gap: a car park, a little square
					bb = boost(p)
					h = base * rng.lognormvariate(0, 0.45) * (1 + 13 * bb * rng.uniform(0.35, 1.25))
					if bb < 0.1 and rng.random() < 0.015:
						h *= rng.uniform(2.5, 4.0)
					h = max(9.0, min(h, 440.0))
					sx, sy = w * rng.uniform(0.72, 0.92), w * rng.uniform(0.72, 0.92)
					if h > 100:
						sx, sy = min(sx, rng.uniform(28, 42)), min(sy, rng.uniform(28, 42))
					style = pick_style(h)
					S = STYLES[style]
					floors = max(2, round((h - S['G']) / S['H']))
					seed = rng.random()
					dist = p.length
					if dist < DETAIL_R:
						detailed_building(p.x, p.y, sx, sy, floors, style, 0.0, seed, facades, cores, roofs)
						count[0] += 1
					else:
						top = S['G'] + floors * S['H']
						fars[style].box(p.x, p.y, 0.0, sx, sy, top, 0.0, seed, rng.uniform(0, 20))
						if dist < 2500:
							far_roofs.rooftop(p.x, p.y, sx, sy, top, 0.0, seed)
						count[1] += 1
	for f in facades.values():
		f.object()
	for b in (cores, roofs, far_roofs):
		b.object()
	for f in fars.values():
		f.object()
	print(f'city: {count[0]} buildings in modules, {count[1]} textured')
	return near


def street_trees(coll):
	"""Trees along the pavements of the nearer streets, and along the near quay."""
	for k in range(-8, 9):
		g = (k + 0.5) * PITCH
		along = -DETAIL_R
		while along < DETAIL_R:
			for side in (-1, 1):
				for x, y in ((g + side * (ROAD / 2 - 1.5), along), (along, g + side * (ROAD / 2 - 1.5))):
					p = Vector((x, y, 0.0))
					if abs(x) < LEVEL and abs(y) < LEVEL or not on_land(p, 6.0) or p.length > DETAIL_R:
						continue
					if rng.random() < 0.8:
						plant_tree(coll, x + rng.uniform(-1, 1), y + rng.uniform(-1, 1), rng.uniform(9.0, 14.0))
			along += 13.0


# ================================================================================================================== harbour
def mat_water():
	def build(t):
		pos = t.node('NewGeometry').outputs['Position']
		ripples = t.math('ADD', t.noise(t.vmath('MULTIPLY', pos, (1.0, 2.2, 0.0)), 0.6, 4.0, 0.5),
			t.math('MULTIPLY', t.noise(t.vmath('MULTIPLY', pos, (2.5, 1.0, 0.0)), 2.5, 3.0, 0.5), 0.5))
		swell = t.noise(t.vmath('MULTIPLY', pos, (0.3, 0.5, 0.0)), 0.08, 2.0, 0.5)
		bump = t.node('Bump')
		bump.inputs['Strength'].default_value = 0.35
		bump.inputs['Distance'].default_value = 0.08
		t.set(bump.inputs['Height'], t.math('ADD', ripples, t.math('MULTIPLY', swell, 3.0)))
		return t.bsdf((0.012, 0.03, 0.035, 1.0), 0.04, 0.0, normal=bump.outputs[0], IOR=1.33).outputs[0]
	return material('Harbour water', build)


def mat_ground():
	"""Streets and pavements on the street grid, light concrete quays."""
	def build(t):
		pos = t.node('NewGeometry').outputs['Position']
		x, y, _ = t.sep(pos)
		gx = t.math('FLOORED_MODULO', t.math('ADD', x, PITCH * 0.5 + ROAD * 0.5), PITCH)
		gy = t.math('FLOORED_MODULO', t.math('ADD', y, PITCH * 0.5 + ROAD * 0.5), PITCH)
		road = t.math('MAXIMUM', t.math('LESS_THAN', gx, ROAD - 6.0), t.math('LESS_THAN', gy, ROAD - 6.0))
		n = t.noise(pos, 0.5, 8.0)
		asphalt = t.mix(t.math('MULTIPLY', n, 0.6), (0.05, 0.05, 0.052, 1), (0.1, 0.1, 0.1, 1))
		paving = t.mix(t.math('MULTIPLY', n, 0.6), (0.36, 0.35, 0.33, 1), (0.25, 0.25, 0.24, 1))
		return t.bsdf(t.mix(road, paving, asphalt), 0.85).outputs[0]
	return material('Streets', build)


M['water'] = mat_water()
M['streets'] = mat_ground()
M['hull'] = mat_paint('Hull', (0.8, 0.8, 0.78), 0.35)
M['hull_dark'] = mat_paint('Hull dark', (0.06, 0.1, 0.16), 0.4)
M['hills'] = mat_concrete('Hills', (0.2, 0.24, 0.17), per_building=False)


def harbour():
	coll = collection('Harbour')
	R = 40000.0
	t = Vector((-SHORE_N.y, SHORE_N.x, 0.0))
	# the land on either side: a big square cut along each shore
	for name, d, keep_below in (('Near shore', NEAR_SHORE, True), ('Far shore', FAR_SHORE, False)):
		sign = 1.0 if keep_below else -1.0
		side = lambda p: sign * (d - shore(p))   # >= 0 on the land
		square = [Vector(p) for p in ((-R, -R, 0), (R, -R, 0), (R, R, 0), (-R, R, 0))]
		poly = []
		for k, a in enumerate(square):   # the square clipped to the land side of the shore line
			b = square[(k + 1) % 4]
			if side(a) >= 0:
				poly.append(a)
			if (side(a) >= 0) != (side(b) >= 0):
				poly.append(a.lerp(b, side(a) / (side(a) - side(b))))
		me = bpy.data.meshes.new(name)
		me.from_pydata([tuple(p) for p in poly], [], [list(range(len(poly)))])
		me.materials.append(M['streets'])
		ob = bpy.data.objects.new(name, me)
		coll.objects.link(ob)
		# the quay wall down to the water, and a railing along the near one
		q = Mesh(name + ' quay')
		a, b = SHORE_N * d - t * R, SHORE_N * d + t * R
		vs = [q.bm.verts.new(p) for p in ((a.x, a.y, WATER_Z - 1), (b.x, b.y, WATER_Z - 1), (b.x, b.y, 0.0), (a.x, a.y, 0.0))]
		f = q.bm.faces.new(vs if keep_below else list(reversed(vs)))
		f.material_index = q.slot('concrete')
		if keep_below:
			for k in range(-1200, 1201, 2):
				p = SHORE_N * (d - 0.4) + t * k
				q.box(p.x - 0.03, p.x + 0.03, p.y - 0.03, p.y + 0.03, 0.0, 1.1, 'railing')
		q.object(coll)
	water = Mesh('Water')
	water.quad_z(-R, R, -R, R, WATER_Z, 'water')
	water.object(coll)
	# the top rail along the near quay
	r = Boxes('Quay rail', coll)
	mid = SHORE_N * (NEAR_SHORE - 0.4)
	r.box_rot(mid.x, mid.y, 0.06, 2400.0, 1.05, 1.12, math.atan2(t.y, t.x) - math.pi / 2, 'railing')
	r.object()
	boats(coll)
	return coll


def boats(coll):
	"""A few boats on the water: a ferry crossing, motor boats, a moored barge."""
	m = Mesh('Boats')
	def boat(p, heading, length, beam, hull, cabin_h, ferry=False):
		c, s = math.cos(heading), math.sin(heading)
		def w(x, y, z):
			return (p.x + x * c - y * s, p.y + x * s + y * c, z)
		# hull: a pointed bow, a flat stern
		outline = [(-length / 2, -beam / 2), (length * 0.3, -beam / 2), (length / 2, 0.0), (length * 0.3, beam / 2), (-length / 2, beam / 2)]
		z0, z1 = WATER_Z - 0.3, WATER_Z + (2.2 if ferry else 0.9)
		lo = [m.bm.verts.new(w(x, y, z0)) for x, y in outline]
		hi = [m.bm.verts.new(w(x, y, z1)) for x, y in outline]
		for i in range(len(outline)):
			j = (i + 1) % len(outline)
			m.bm.faces.new((lo[i], lo[j], hi[j], hi[i])).material_index = m.slot(hull)
		m.bm.faces.new(hi).material_index = m.slot('hull')
		cl, cb = length * (0.6 if ferry else 0.35), beam * 0.75
		ox = -length * 0.1
		for k in range(2 if ferry else 1):
			zz = z1 + k * cabin_h
			ww = 1.0 - 0.15 * k
			vs = [m.bm.verts.new(w(ox + x * ww, y * ww, zz + dz)) for dz in (0.0, cabin_h) for x, y in ((-cl / 2, -cb / 2), (cl / 2, -cb / 2), (cl / 2, cb / 2), (-cl / 2, cb / 2))]
			for i in range(4):
				j = (i + 1) % 4
				m.bm.faces.new((vs[i], vs[j], vs[j + 4], vs[i + 4])).material_index = m.slot('hull')
				# a band of windows round the cabin
				a, b = Vector(vs[i].co), Vector(vs[j].co)
				band = [a.lerp(b, 0.06) + Vector((0, 0, cabin_h * 0.4)), a.lerp(b, 0.94) + Vector((0, 0, cabin_h * 0.4)),
					a.lerp(b, 0.94) + Vector((0, 0, cabin_h * 0.8)), a.lerp(b, 0.06) + Vector((0, 0, cabin_h * 0.8))]
				out = (b - a).cross(Vector((0, 0, 1))).normalized() * 0.03
				m.bm.faces.new([m.bm.verts.new(v + out) for v in band]).material_index = m.slot('glass_cw')
			m.bm.faces.new(vs[4:]).material_index = m.slot('hull')
	boat(SHORE_N * 1100 + Vector((-SHORE_N.y, SHORE_N.x, 0)) * 200, 0.3, 48.0, 12.0, 'hull_dark', 2.6, ferry=True)
	for k in range(7):
		d = rng.uniform(500, 2000)
		along = rng.uniform(-1800, 1500)
		p = SHORE_N * d + Vector((-SHORE_N.y, SHORE_N.x, 0)) * along
		boat(p, rng.uniform(0, 2 * math.pi), rng.uniform(8, 16), rng.uniform(2.8, 4.2), rng.choice(['hull', 'hull_dark']), 1.8)
	m.object(coll)


def hills():
	bm = bmesh.new()
	ring = 128
	rows = [(10000.0, 0.0), (12500.0, 0.6), (16000.0, 1.0), (21000.0, 0.7), (26000.0, 0.0)]
	verts = []
	for r, amp in rows:
		row = []
		for i in range(ring):
			a = 2 * math.pi * i / ring
			h = amp * (180 + 320 * (0.5 + 0.5 * math.sin(a * 3 + 1.3)) * (0.5 + 0.5 * math.sin(a * 7 + 0.4)) + rng.uniform(0, 140))
			row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), h)))
		verts.append(row)
	for k in range(len(rows) - 1):
		for i in range(ring):
			j = (i + 1) % ring
			bm.faces.new((verts[k][i], verts[k][j], verts[k + 1][j], verts[k + 1][i]))
	me = bpy.data.meshes.new('Hills')
	bm.to_mesh(me)
	bm.free()
	for p in me.polygons:
		p.use_smooth = True
	me.materials.append(M['hills'])
	ob = bpy.data.objects.new('Hills', me)
	scene.collection.objects.link(ob)
	ob.modifiers.new('Smooth', 'SUBSURF').render_levels = 2


def panorama():
	baked = bake_facades()
	near = lay_out_city(baked)
	street_trees(near)
	harbour()
	hills()
	cd = bpy.data.cameras.new('Panorama')
	cd.type = 'PANO'
	cd.panorama_type = 'EQUIRECTANGULAR'
	cd.clip_start = 0.1
	cd.clip_end = 60000.0
	cam = bpy.data.objects.new('Panorama', cd)
	scene.collection.objects.link(cam)
	cam.location = (0.0, 0.0, CAM_Z)
	cam.rotation_euler = (math.radians(90), 0.0, math.radians(180))   # looking along -Y (Godot +Z), level
	scene.camera = cam
	if CROP:
		setup_render((8192, 4096), 64)
		r = scene.render
		r.use_border = r.use_crop_to_border = True
		r.border_min_x, r.border_max_x, r.border_min_y, r.border_max_y = CROP
		scene.render.filepath = str(ART / 'crop.png')
	elif PREVIEW:
		setup_render((2048, 1024), 32)
		scene.render.filepath = str(ART / 'preview.png')
	else:
		setup_render((SIZE, SIZE // 2), 64 if SIZE > 4096 else 48)
		bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'breakwater_panorama.blend'), compress=True)
		scene.render.filepath = str(ART / f'breakwater_panorama_{SIZE // 1024}k.png')
	bpy.ops.render.render(write_still=True)
	if not (PREVIEW or CROP):
		scene.render.image_settings.file_format = 'JPEG'
		scene.render.image_settings.quality = 92
		bpy.data.images['Render Result'].save_render(str(GAME / 'breakwater_panorama.jpg'), scene=scene)
		# Godot's import settings for it: compressed on the GPU (uncompressed, 8K would take some 130 MB on a Quest), with
		# mipmaps. Godot fills in the rest of the file on its next import.
		imp = GAME / 'breakwater_panorama.jpg.import'
		if not imp.exists():
			imp.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=2\nmipmaps/generate=true\n')


if TEST:
	test_street()
else:
	panorama()
print('done')
