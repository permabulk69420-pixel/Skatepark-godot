"""Run: blender -b --factory-startup --python tools/build_city_panorama.py [-- --preview]
A 360° city backdrop for a level's sky: an 8192 × 4096 equirectangular render of a procedural city seen from the middle of an open
plaza, where the park sits. Only what the panorama sees is built: boxes with facade shaders, laid out in rings of blocks that get
sparser and simpler with distance, and a skyline of towers in two clusters.

Everything is lit the way the Foundry level is (its `look` in scripts/levels.gd): the same sun direction and colour, and a haze
that fades the city into the same horizon colour as the sky, so the layers sit at different depths.

Writes art/city_panorama/city_panorama.blend, art/city_panorama/city_panorama_8k.png and assets/sky/city_panorama.jpg (the
game's copy). --preview renders a quick 2048 × 1024 to art/city_panorama/preview.png instead (no .blend, no game copy).

Units: metres. Blender Z-up. Godot (x, y, z) is Blender (x, -z, y), so Godot's forward (-Z) is Blender +Y. Godot's
PanoramaSkyMaterial puts the middle of the image at +Z (and the seam at -Z), so the camera faces Blender -Y.
"""
import bpy, bmesh, math, random, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art/city_panorama'
ART.mkdir(parents=True, exist_ok=True)
(ART / '.gdignore').touch()
GAME = ROOT / 'assets/sky'
GAME.mkdir(parents=True, exist_ok=True)

PREVIEW = '--preview' in sys.argv
SEED = 7
rng = random.Random(SEED)


def godot_to_blender(v):
	return Vector((v[0], -v[2], v[1]))


SUN_DIR = godot_to_blender((-0.62, 0.5, -0.6)).normalized()   # Foundry's sunDirection (towards the sun)
SUN_COLOUR = (1.0, 0.86, 0.71)                                 # #ffdcb4
HAZE = (0.77, 0.83, 0.87)                                      # #c4d4de, Foundry's fog: the horizon
ZENITH = (0.10, 0.27, 0.66)
CAM_Z = 3.0                    # a little above eye height: between standing on the plaza and the 6.5 m start tower
BLOCK, ROAD = 96.0, 18.0       # city blocks and the streets between them
PITCH = BLOCK + ROAD
PLAZA = 125.0                  # blocks whose middle is nearer than this (the middle one and the eight round it) are left open...
OPEN = 1.5 * PITCH - ROAD / 2  # ...as lawn out to the first streets, with a paved plaza in the middle where the park is (80 × 72 m)
CITY_R = 7000.0                # blocks stop here; hills beyond
DOWNTOWN = [(Vector((1750.0, 350.0)), 1.0, 750.0),     # the big cluster, ahead of the spawn on the tower (Godot +X), lit from behind
            (Vector((-1500.0, -3400.0)), 0.6, 700.0)]  # a smaller one behind-left of the plaza spawn


# ------------------------------------------------------------------------------------------------------------------------- scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = 'City panorama'
scene.unit_settings.system = 'METRIC'


def collection(name):
	c = bpy.data.collections.new(name)
	scene.collection.children.link(c)
	return c


# ------------------------------------------------------------------------------------------------------------------- node helpers
class Tree:
	"""A small wrapper so shader graphs read top to bottom: t.node('Math', operation='MULTIPLY', inputs=(a, 2.0))."""

	def __init__(self, nt):
		self.nt = nt
		self.x = 0

	def node(self, kind, inputs=(), out=None, **props):
		n = self.nt.nodes.new('ShaderNode' + kind if not kind.startswith(('NodeGroup', 'ShaderNode')) else kind)
		n.location = (self.x, 0)
		self.x += 40
		for k, v in props.items():
			setattr(n, k, v)
		for i, v in enumerate(inputs):
			if v is None:
				continue
			sock = n.inputs[i] if isinstance(i, int) else n.inputs[i]
			self.set(sock, v)
		return n.outputs[out] if out is not None else n

	def set(self, sock, v):
		if hasattr(v, 'is_output') or isinstance(v, bpy.types.NodeSocket):
			self.nt.links.new(v, sock)
		elif isinstance(v, bpy.types.Node):
			self.nt.links.new(v.outputs[0], sock)
		else:
			sock.default_value = v

	def math(self, op, a, b=0.0, c=0.0, clamp=False):
		n = self.node('Math', operation=op, use_clamp=clamp)
		self.set(n.inputs[0], a)
		self.set(n.inputs[1], b)
		if len(n.inputs) > 2:
			self.set(n.inputs[2], c)
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

	def hash(self, v):
		"""A random 0..1 per integer cell: white noise of the floored vector."""
		n = self.node('TexWhiteNoise', noise_dimensions='3D')
		self.set(n.inputs[0], v)
		return n.outputs[0]

	def smooth(self, e0, e1, x):
		n = self.node('MapRange', interpolation_type='SMOOTHSTEP')
		self.set(n.inputs[0], x)
		n.inputs[1].default_value = e0
		n.inputs[2].default_value = e1
		return n.outputs[0]

	def pulse(self, x, lo, hi):
		"""1 where lo < fract(x) < hi (x already scaled to cells), else 0."""
		f = self.math('FRACT', x)
		return self.math('MULTIPLY', self.math('GREATER_THAN', f, lo), self.math('LESS_THAN', f, hi))


def group(name):
	g = bpy.data.node_groups.new(name, 'ShaderNodeTree')
	return g, Tree(g)


def gsock(g, name, io, kind, default=None):
	s = g.interface.new_socket(name, in_out=io, socket_type=kind)
	if default is not None:
		s.default_value = default
	return s


# --------------------------------------------------------------------------------------------------------------- atmosphere
# The haze colour seen looking along a direction: the horizon colour, warmed and brightened towards the sun. The sky uses it at the
# horizon and every surface fades into it with distance, so a far tower ends up exactly the colour of the sky behind it.
def build_haze_colour():
	g, t = group('Haze colour')
	gsock(g, 'Direction', 'INPUT', 'NodeSocketVector')
	gsock(g, 'Colour', 'OUTPUT', 'NodeSocketColor')
	gi = t.node('NodeGroupInput')
	go = t.node('NodeGroupOutput')
	d = t.vmath('NORMALIZE', gi.outputs[0])
	cos_sun = t.vmath('DOT_PRODUCT', d, tuple(SUN_DIR), out=1)
	c = t.math('MAXIMUM', cos_sun, 0.0)
	wide = t.math('POWER', c, 3.0)      # a broad warm brightening on the sun's side of the sky
	tight = t.math('POWER', c, 40.0)    # and a tighter glow around it
	warm = t.mix(t.math('MULTIPLY', wide, 0.55), HAZE + (1,), (1.0, 0.90, 0.76, 1.0))
	glow = t.mix(t.math('MULTIPLY', tight, 0.7), warm, (1.0, 0.95, 0.85, 1.0))
	# the side away from the sun is a touch cooler and darker
	away = t.math('MULTIPLY', t.math('MAXIMUM', t.math('MULTIPLY', cos_sun, -1.0), 0.0), 0.12)
	col = t.mix(away, glow, (0.62, 0.70, 0.80, 1.0))
	t.set(go.inputs[0], col)
	return g


HAZE_COLOUR = build_haze_colour()
HAZE_STRENGTH = 1.0
HAZE_DIST = 4800.0       # metres for the haze to reach 63% at ground level
HAZE_HEIGHT = 700.0      # it thins with height above this


def build_atmosphere():
	"""Shader in, shader out: the surface faded into the haze by the distance from the camera (exponential height fog)."""
	g, t = group('Atmosphere')
	gsock(g, 'Surface', 'INPUT', 'NodeSocketShader')
	gsock(g, 'Shader', 'OUTPUT', 'NodeSocketShader')
	gi = t.node('NodeGroupInput')
	go = t.node('NodeGroupOutput')
	geo = t.node('NewGeometry')
	rel = t.vmath('SUBTRACT', geo.outputs['Position'], (0.0, 0.0, CAM_Z))
	dist = t.vmath('LENGTH', rel, out=1)
	z = t.sep(geo.outputs['Position'])[2]
	mid = t.math('MULTIPLY', t.math('ADD', z, CAM_Z), 0.5)
	thin = t.math('EXPONENT', t.math('DIVIDE', mid, -HAZE_HEIGHT))
	optical = t.math('MULTIPLY', t.math('DIVIDE', dist, HAZE_DIST), thin)
	fac = t.math('SUBTRACT', 1.0, t.math('EXPONENT', t.math('MULTIPLY', optical, -1.0)))
	hc = t.node('ShaderNodeGroup')
	hc.node_tree = HAZE_COLOUR
	t.set(hc.inputs[0], rel)
	em = t.node('Emission')
	t.set(em.inputs[0], hc.outputs[0])
	em.inputs[1].default_value = HAZE_STRENGTH
	# Only camera rays see the haze: light bouncing between buildings would otherwise pick it up as glow.
	lp = t.node('LightPath')
	cam_fac = t.math('MULTIPLY', fac, lp.outputs['Is Camera Ray'])
	t.set(go.inputs[0], t.mixshader(cam_fac, gi.outputs[0], em.outputs[0]))
	return g


ATMOSPHERE = build_atmosphere()


def finish(mat, t, shader):
	"""Material output through the atmosphere."""
	a = t.node('ShaderNodeGroup')
	a.node_tree = ATMOSPHERE
	t.set(a.inputs[0], shader)
	out = t.node('OutputMaterial')
	t.set(out.inputs[0], a.outputs[0])


def material(name):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	m.node_tree.nodes.clear()
	return m, Tree(m.node_tree)


# -------------------------------------------------------------------------------------------------------------------- world sky
def build_world():
	w = bpy.data.worlds.new('Sky')
	scene.world = w
	w.use_nodes = True
	nt = w.node_tree
	nt.nodes.clear()
	t = Tree(nt)
	tc = t.node('TexCoord')
	d = t.vmath('NORMALIZE', tc.outputs['Generated'])
	z = t.sep(d)[2]
	hc = t.node('ShaderNodeGroup')
	hc.node_tree = HAZE_COLOUR
	t.set(hc.inputs[0], d)
	# up from the horizon: haze to blue, quickly at first (a thin hazy band) and then slowly
	up = t.math('POWER', t.math('MAXIMUM', z, 0.0), 0.45)
	sky = t.mix(t.smooth(0.0, 1.0, up), hc.outputs[0], ZENITH + (1,))
	# scattered fair-weather clouds on a flat layer 1.5 km up: the direction projected onto the layer, so they crowd together and
	# flatten towards the horizon the way real ones do
	zc = t.math('MAXIMUM', z, 0.015)
	x, y, _ = t.sep(d)
	on_layer = t.comb(t.math('DIVIDE', x, zc), t.math('DIVIDE', y, zc), 0.0)
	n = t.node('TexNoise', noise_dimensions='3D')
	n.inputs['Scale'].default_value = 0.55
	n.inputs['Detail'].default_value = 10.0
	n.inputs['Roughness'].default_value = 0.58
	t.set(n.inputs['Vector'], t.vmath('ADD', on_layer, (3.7, 1.2, 0.0)))
	cover = t.node('TexNoise', noise_dimensions='3D')   # where the clouds are at all: big patches of clear sky between
	cover.inputs['Scale'].default_value = 0.09
	cover.inputs['Detail'].default_value = 2.0
	t.set(cover.inputs['Vector'], on_layer)
	dens = t.math('ADD', n.outputs['Fac'], t.math('MULTIPLY', t.math('SUBTRACT', cover.outputs['Fac'], 0.5), 0.9))
	cloud = t.smooth(0.56, 0.72, dens)
	core = t.smooth(0.62, 0.95, dens)   # thick middles are grey underneath
	toward = t.math('MAXIMUM', t.vmath('DOT_PRODUCT', d, tuple(SUN_DIR), out=1), 0.0)
	lit = t.mix(t.math('MULTIPLY', core, 0.7), (1.0, 0.97, 0.92, 1.0), (0.58, 0.62, 0.7, 1.0))
	lit = t.mix(t.math('POWER', toward, 4.0), lit, (1.15, 1.05, 0.92, 1.0))   # silver linings towards the sun
	lit = t.mix(t.smooth(0.0, 0.35, z), hc.outputs[0], lit)                      # far ones fade into the haze
	sky = t.mix(t.math('MULTIPLY', cloud, t.smooth(0.0, 0.05, z)), sky, lit)
	bg = t.node('Background')
	t.set(bg.inputs[0], sky)
	bg.inputs[1].default_value = HAZE_STRENGTH
	out = t.node('OutputWorld')
	t.set(out.inputs[0], bg.outputs[0])


build_world()


# ------------------------------------------------------------------------------------------------------------------- materials
def facade_material(name, style):
	"""A building facade, drawn on box faces whose UVs are metres (u along the wall, v up it). Per building, the face attribute
	`seed` (0..1) picks a colour and window pattern; per window, the cell it falls in picks lit / blinds / reflective.
	Roof faces (normal up) get roof gravel instead."""
	m, t = material(name)
	uv = t.node('UVMap', uv_map='UVMap').outputs[0]
	seed = t.node('Attribute', attribute_type='GEOMETRY', attribute_name='seed').outputs['Fac']
	geo = t.node('NewGeometry')
	u, v, _ = t.sep(uv)

	col_w, floor_h = style['column'], style['floor']
	cu = t.math('DIVIDE', u, col_w)
	cv = t.math('DIVIDE', v, floor_h)
	cell = t.comb(t.math('FLOOR', cu), t.math('FLOOR', cv), t.math('MULTIPLY', seed, 977.0))
	r_cell = t.hash(cell)
	r_cell2 = t.hash(t.vmath('ADD', cell, (13.1, 7.7, 3.3)))

	# where the glass is: a window rectangle inside each cell (or a continuous band for ribbon windows)
	wx0, wx1 = style['win_x']
	wy0, wy1 = style['win_y']
	in_x = t.pulse(cu, wx0, wx1)
	in_y = t.pulse(cv, wy0, wy1)
	glass_mask = t.math('MULTIPLY', in_x, in_y)
	# the ground floor is a shopfront: taller glass across most of the bay
	ground = t.math('LESS_THAN', v, floor_h * 1.15)
	shop = t.math('MULTIPLY', t.pulse(cu, 0.06, 0.94), t.math('MULTIPLY', t.math('GREATER_THAN', v, 0.4), t.math('LESS_THAN', v, floor_h * 0.95)))
	glass_mask = t.mix(ground, glass_mask, shop)
	glass_mask = t.sep(glass_mask)[0]

	# wall colour: one of the style's palette, varied by the building's seed, with grime streaks down the wall
	wall = t.ramp(seed, style['palette'])
	shade = t.math('ADD', 0.62, t.math('MULTIPLY', t.math('FRACT', t.math('MULTIPLY', seed, 13.7)), 0.38))
	wall = t.vmath('MULTIPLY', wall, t.comb(shade, shade, shade))
	grime = t.node('TexNoise', noise_dimensions='3D')
	grime.inputs['Scale'].default_value = 1.0
	grime.inputs['Detail'].default_value = 6.0
	t.set(grime.inputs['Vector'], t.vmath('MULTIPLY', t.comb(u, v, t.math('MULTIPLY', seed, 50.0)), (0.6, 0.08, 1.0)))
	wall = t.mix(t.math('MULTIPLY', grime.outputs['Fac'], 0.35), wall, (0.18, 0.17, 0.16, 1.0))
	if style.get('brick'):
		b = t.node('TexBrick', offset=0.5, squash=1.0)
		b.inputs['Scale'].default_value = 1.0
		b.inputs['Mortar Size'].default_value = 0.012
		b.inputs['Brick Width'].default_value = 0.23
		b.inputs['Row Height'].default_value = 0.075
		t.set(b.inputs['Vector'], t.comb(u, v, 0.0))
		t.set(b.inputs['Color1'], wall)
		t.set(b.inputs['Color2'], t.mix(0.25, wall, (0.1, 0.05, 0.03, 1)))
		b.inputs['Mortar'].default_value = (0.55, 0.53, 0.5, 1)
		wall = b.outputs['Color']
	if style.get('panels'):   # metal / stone cladding joints
		joint = t.math('MAXIMUM', t.pulse(t.math('DIVIDE', u, col_w * 0.5), 0.0, 0.02), t.pulse(t.math('DIVIDE', v, floor_h * 0.5), 0.0, 0.025))
		wall = t.mix(t.math('MULTIPLY', joint, 0.6), wall, (0.05, 0.05, 0.05, 1))
	# horizontal floor-slab band (curtain walls: spandrel panels)
	slab = t.pulse(cv, 0.0, style.get('slab', 0.0))
	wall = t.mix(t.math('MULTIPLY', slab, 0.5), wall, style.get('slab_colour', (0.3, 0.3, 0.32)) + (1,))

	# glass: dark, reflective, tinted per building; some panes have blinds or a lit room behind them
	tint = t.ramp(t.math('FRACT', t.math('MULTIPLY', seed, 7.31)), style['glass'])
	tint = t.mix(t.math('MULTIPLY', r_cell, 0.35), tint, (0.02, 0.025, 0.03, 1))
	blinds = t.math('GREATER_THAN', r_cell2, 1.0 - style.get('blinds', 0.18))
	tint = t.mix(t.math('MULTIPLY', blinds, t.math('ADD', 0.3, t.math('MULTIPLY', r_cell, 0.5))), tint, (0.36, 0.34, 0.31, 1))
	rough = t.math('ADD', style.get('glass_rough', 0.04), t.math('MULTIPLY', r_cell, 0.08))
	rough = t.mix(blinds, t.comb(rough, rough, rough), (0.6, 0.6, 0.6, 1))
	rough = t.sep(rough)[0]
	is_glass_metal = style.get('glass_metal', 0.2)

	# the mullions / frames: a thin line round each window
	frame = t.math('SUBTRACT', 1.0, glass_mask)

	base = t.mix(glass_mask, wall, tint)
	metal = t.math('MULTIPLY', glass_mask, is_glass_metal)
	roughness = t.mix(glass_mask, (style.get('wall_rough', 0.8),) * 3 + (1,), t.comb(rough, rough, rough))
	roughness = t.sep(roughness)[0]
	spec = t.math('ADD', 0.5, t.math('MULTIPLY', glass_mask, 0.5))

	# recessed windows: bump down where the glass is
	bump = t.node('Bump')
	bump.inputs['Strength'].default_value = 0.6
	bump.inputs['Distance'].default_value = 0.12
	t.set(bump.inputs['Height'], frame)

	# roofs: grey gravel / membrane
	roof_n = t.node('TexNoise', noise_dimensions='3D')
	roof_n.inputs['Scale'].default_value = 0.15
	roof_n.inputs['Detail'].default_value = 4.0
	t.set(roof_n.inputs['Vector'], geo.outputs['Position'])
	roof_col = t.ramp(t.math('ADD', t.math('MULTIPLY', roof_n.outputs['Fac'], 0.6), t.math('MULTIPLY', seed, 0.4)),
		[(0.0, (0.22, 0.22, 0.22)), (0.5, (0.36, 0.35, 0.33)), (1.0, (0.5, 0.5, 0.48))])
	nz = t.sep(geo.outputs['Normal'])[2]
	is_roof = t.math('GREATER_THAN', nz, 0.7)
	base = t.mix(is_roof, base, roof_col)
	metal = t.math('MULTIPLY', metal, t.math('SUBTRACT', 1.0, is_roof))
	roughness = t.math('MAXIMUM', roughness, is_roof)

	bsdf = t.node('BsdfPrincipled')
	t.set(bsdf.inputs['Base Color'], base)
	t.set(bsdf.inputs['Metallic'], metal)
	t.set(bsdf.inputs['Roughness'], roughness)
	t.set(bsdf.inputs['Specular IOR Level'], spec)
	t.set(bsdf.inputs['Normal'], bump.outputs[0])

	# a few rooms lit even by day (warm), visible mostly in the shade
	lit = t.math('MULTIPLY', t.math('GREATER_THAN', r_cell2, 1.0 - style.get('lit', 0.05)), glass_mask)
	lit = t.math('MULTIPLY', lit, t.math('SUBTRACT', 1.0, is_roof))
	em = t.node('Emission')
	em.inputs[0].default_value = (1.0, 0.82, 0.6, 1.0)
	t.set(em.inputs[1], t.math('MULTIPLY', lit, 0.25))
	add = t.node('AddShader')
	t.set(add.inputs[0], bsdf.outputs[0])
	t.set(add.inputs[1], em.outputs[0])
	finish(m, t, add.outputs[0])
	return m


STYLES = {
	'glass': dict(column=1.5, floor=3.9, win_x=(0.04, 0.96), win_y=(0.26, 0.98), slab=0.24, slab_colour=(0.16, 0.18, 0.2),
		glass=[(0.0, (0.10, 0.17, 0.22)), (0.3, (0.17, 0.22, 0.24)), (0.55, (0.12, 0.14, 0.15)), (0.8, (0.2, 0.16, 0.12)), (1.0, (0.25, 0.3, 0.33))],
		glass_metal=0.75, glass_rough=0.02, palette=[(0.0, (0.35, 0.37, 0.4)), (1.0, (0.5, 0.52, 0.55))], blinds=0.08, lit=0.02),
	'office': dict(column=3.0, floor=3.7, win_x=(0.12, 0.88), win_y=(0.3, 0.86), panels=True,
		glass=[(0.0, (0.06, 0.08, 0.1)), (1.0, (0.12, 0.15, 0.17))], glass_metal=0.3,
		palette=[(0.0, (0.72, 0.70, 0.66)), (0.35, (0.58, 0.58, 0.57)), (0.7, (0.82, 0.8, 0.76)), (1.0, (0.45, 0.46, 0.48))], blinds=0.25, lit=0.02),
	'ribbon': dict(column=4.0, floor=3.8, win_x=(-1.0, 2.0), win_y=(0.38, 0.85), panels=True,
		glass=[(0.0, (0.07, 0.1, 0.13)), (1.0, (0.1, 0.13, 0.12))], glass_metal=0.5,
		palette=[(0.0, (0.62, 0.64, 0.66)), (0.5, (0.42, 0.44, 0.47)), (1.0, (0.8, 0.8, 0.79))], blinds=0.15, lit=0.02),
	'brick': dict(column=3.4, floor=3.3, win_x=(0.25, 0.75), win_y=(0.25, 0.8), brick=True,
		glass=[(0.0, (0.05, 0.06, 0.07)), (1.0, (0.1, 0.11, 0.12))], glass_metal=0.1, glass_rough=0.08,
		palette=[(0.0, (0.30, 0.13, 0.09)), (0.4, (0.40, 0.2, 0.13)), (0.7, (0.26, 0.17, 0.13)), (1.0, (0.48, 0.38, 0.29))], blinds=0.3, lit=0.02),
	'render': dict(column=3.6, floor=3.0, win_x=(0.22, 0.78), win_y=(0.22, 0.8),
		glass=[(0.0, (0.05, 0.06, 0.07)), (1.0, (0.1, 0.11, 0.12))], glass_metal=0.1, glass_rough=0.08,
		palette=[(0.0, (0.86, 0.82, 0.74)), (0.3, (0.78, 0.62, 0.48)), (0.55, (0.9, 0.9, 0.88)), (0.8, (0.68, 0.7, 0.68)), (1.0, (0.8, 0.74, 0.58))],
		blinds=0.35, lit=0.02),
}
FACADES = {k: facade_material('Facade ' + k, s) for k, s in STYLES.items()}


def simple_material(name, colour, rough=0.6, metal=0.0, noise=0.0, noise_scale=1.0):
	m, t = material(name)
	b = t.node('BsdfPrincipled')
	c = colour + (1,)
	if noise:
		n = t.node('TexNoise', noise_dimensions='3D')
		n.inputs['Scale'].default_value = noise_scale
		n.inputs['Detail'].default_value = 6.0
		t.set(n.inputs['Vector'], t.node('NewGeometry').outputs['Position'])
		c = t.mix(t.math('MULTIPLY', n.outputs['Fac'], noise), c, tuple(x * 0.6 for x in colour) + (1,))
	t.set(b.inputs['Base Color'], c)
	b.inputs['Roughness'].default_value = rough
	b.inputs['Metallic'].default_value = metal
	finish(m, t, b.outputs[0])
	return m


def ground_material():
	"""Streets, pavements, the plaza and the lawn round it, all from the world position (the same grid the blocks are laid on)."""
	m, t = material('Ground')
	pos = t.node('NewGeometry').outputs['Position']
	x, y, _ = t.sep(pos)
	# where in the street grid: 0..PITCH, with the road at the start of each pitch
	gx = t.math('FLOORED_MODULO', t.math('ADD', x, PITCH * 0.5 + ROAD * 0.5), PITCH)
	gy = t.math('FLOORED_MODULO', t.math('ADD', y, PITCH * 0.5 + ROAD * 0.5), PITCH)
	road_x = t.math('LESS_THAN', gx, ROAD)
	road_y = t.math('LESS_THAN', gy, ROAD)
	road = t.math('MAXIMUM', road_x, road_y)
	# pavement: 4 m either side of the road
	pave = t.math('MAXIMUM', t.math('LESS_THAN', t.math('FLOORED_MODULO', t.math('ADD', gx, 4.0), PITCH), ROAD + 8.0),
		t.math('LESS_THAN', t.math('FLOORED_MODULO', t.math('ADD', gy, 4.0), PITCH), ROAD + 8.0))
	# centre line dashes
	cl_x = t.math('MULTIPLY', t.math('LESS_THAN', t.math('ABSOLUTE', t.math('SUBTRACT', gx, ROAD * 0.5)), 0.12), t.pulse(t.math('DIVIDE', y, 6.0), 0.0, 0.5))
	cl_y = t.math('MULTIPLY', t.math('LESS_THAN', t.math('ABSOLUTE', t.math('SUBTRACT', gy, ROAD * 0.5)), 0.12), t.pulse(t.math('DIVIDE', x, 6.0), 0.0, 0.5))
	line = t.math('MULTIPLY', t.math('MAXIMUM', t.math('MULTIPLY', cl_x, t.math('SUBTRACT', 1, road_y)), t.math('MULTIPLY', cl_y, t.math('SUBTRACT', 1, road_x))), 1.0)

	n = t.node('TexNoise', noise_dimensions='3D')
	n.inputs['Scale'].default_value = 0.4
	n.inputs['Detail'].default_value = 8.0
	t.set(n.inputs['Vector'], pos)
	asphalt = t.mix(t.math('MULTIPLY', n.outputs['Fac'], 0.5), (0.085, 0.085, 0.09, 1), (0.16, 0.16, 0.16, 1))
	concrete = t.mix(t.math('MULTIPLY', n.outputs['Fac'], 0.5), (0.5, 0.49, 0.46, 1), (0.36, 0.35, 0.33, 1))
	lot = t.mix(t.math('MULTIPLY', n.outputs['Fac'], 0.5), (0.3, 0.3, 0.29, 1), (0.2, 0.2, 0.2, 1))
	col = t.mix(pave, lot, concrete)
	col = t.mix(road, col, asphalt)
	col = t.mix(line, col, (0.75, 0.72, 0.6, 1))
	# the open ground round the camera: lawn, with a paved plaza in the middle where the park is
	ax = t.math('ABSOLUTE', x)
	ay = t.math('ABSOLUTE', y)
	in_open = t.math('MULTIPLY', t.math('LESS_THAN', ax, OPEN), t.math('LESS_THAN', ay, OPEN))
	in_plaza = t.math('MULTIPLY', t.math('LESS_THAN', ax, 52.0), t.math('LESS_THAN', ay, 48.0))
	gn = t.node('TexNoise', noise_dimensions='3D')
	gn.inputs['Scale'].default_value = 0.08
	gn.inputs['Detail'].default_value = 6.0
	t.set(gn.inputs['Vector'], pos)
	grass = t.ramp(gn.outputs['Fac'], [(0.3, (0.12, 0.16, 0.05)), (0.7, (0.2, 0.24, 0.08))])
	paths = t.math('MAXIMUM', t.math('LESS_THAN', t.math('ABSOLUTE', t.math('SUBTRACT', ax, ay)), 3.0),
		t.math('MAXIMUM', t.math('LESS_THAN', ax, 3.0), t.math('LESS_THAN', ay, 3.0)))
	open_col = t.mix(paths, grass, concrete)
	open_col = t.mix(in_plaza, open_col, concrete)
	col = t.mix(in_open, col, open_col)
	b = t.node('BsdfPrincipled')
	t.set(b.inputs['Base Color'], col)
	b.inputs['Roughness'].default_value = 0.85
	finish(m, t, b.outputs[0])
	return m


MAT_GROUND = ground_material()
MAT_ROOFTOP = simple_material('Rooftop plant', (0.42, 0.42, 0.42), rough=0.5, metal=0.6, noise=0.4, noise_scale=0.5)
MAT_TANK = simple_material('Water tank', (0.32, 0.22, 0.15), rough=0.8, noise=0.5, noise_scale=0.8)
MAT_HILLS = simple_material('Hills', (0.22, 0.26, 0.2), rough=0.9, noise=0.5, noise_scale=0.002)
MAT_TREE = simple_material('Tree', (0.10, 0.17, 0.05), rough=0.8, noise=0.7, noise_scale=0.6)
MAT_TRUNK = simple_material('Trunk', (0.15, 0.11, 0.08), rough=0.9)
MAT_POLE = simple_material('Lamp post', (0.15, 0.16, 0.17), rough=0.4, metal=0.8)
MAT_CONCRETE = simple_material('Viaduct concrete', (0.55, 0.54, 0.5), rough=0.85, noise=0.4, noise_scale=0.3)
MAT_RAIL_CAR = simple_material('Train', (0.72, 0.74, 0.76), rough=0.3, metal=0.7)
MAT_SPIRE = simple_material('Spire', (0.6, 0.62, 0.64), rough=0.25, metal=1.0)
MAT_CRANE = simple_material('Crane', (0.85, 0.6, 0.1), rough=0.5)


# ------------------------------------------------------------------------------------------------------------------- geometry
class MeshBuilder:
	"""Collects boxes into one mesh (one object per layer and material keeps the scene small), with metre UVs and a per-face seed."""

	def __init__(self, name, mat, coll):
		self.name, self.mat, self.coll = name, mat, coll
		self.bm = bmesh.new()
		self.uv = self.bm.loops.layers.uv.new('UVMap')
		self.seed = self.bm.faces.layers.float.new('seed')

	def box(self, cx, cy, z0, sx, sy, h, rot=0.0, seed=0.0, roof=True, floor=False):
		c, s = math.cos(rot), math.sin(rot)
		corners = [(-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)]
		pts = [(cx + px * c - py * s, cy + px * s + py * c) for px, py in corners]
		lo = [self.bm.verts.new((x, y, z0)) for x, y in pts]
		hi = [self.bm.verts.new((x, y, z0 + h)) for x, y in pts]
		lens = [sx, sy, sx, sy]
		for i in range(4):
			j = (i + 1) % 4
			f = self.bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
			f[self.seed] = seed
			L = lens[i]
			for loop, (u, v) in zip(f.loops, ((0, z0), (L, z0), (L, z0 + h), (0, z0 + h))):
				loop[self.uv].uv = (u, v)
		faces = []
		if roof:
			faces.append(self.bm.faces.new(hi))
		if floor:
			faces.append(self.bm.faces.new(list(reversed(lo))))
		for f in faces:
			f[self.seed] = seed
			for loop in f.loops:
				loop[self.uv].uv = (loop.vert.co.x, loop.vert.co.y)

	def cylinder(self, cx, cy, z0, r, h, seg=12, seed=0.0, cap=True):
		ring_lo, ring_hi = [], []
		for i in range(seg):
			a = 2 * math.pi * i / seg
			ring_lo.append(self.bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), z0)))
			ring_hi.append(self.bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), z0 + h)))
		circ = 2 * math.pi * r
		for i in range(seg):
			j = (i + 1) % seg
			f = self.bm.faces.new((ring_lo[i], ring_lo[j], ring_hi[j], ring_hi[i]))
			f[self.seed] = seed
			u0, u1 = circ * i / seg, circ * (i + 1) / seg
			for loop, (u, v) in zip(f.loops, ((u0, z0), (u1, z0), (u1, z0 + h), (u0, z0 + h))):
				loop[self.uv].uv = (u, v)
			f.smooth = True
		if cap:
			f = self.bm.faces.new(ring_hi)
			f[self.seed] = seed
			for loop in f.loops:
				loop[self.uv].uv = (loop.vert.co.x, loop.vert.co.y)

	def finish(self):
		me = bpy.data.meshes.new(self.name)
		self.bm.to_mesh(me)
		self.bm.free()
		# bmesh float face layers become a FACE float attribute named 'seed', which the facade shader reads
		me.materials.append(self.mat)
		ob = bpy.data.objects.new(self.name, me)
		self.coll.objects.link(ob)
		return ob


def downtown_boost(p):
	b = 0.0
	for centre, strength, radius in DOWNTOWN:
		d = (p - centre).length
		b = max(b, strength * math.exp(-(d / radius) ** 2))
	return b


def pick_style(height, p):
	if height > 70:
		return rng.choices(['glass', 'office', 'ribbon'], [0.6, 0.25, 0.15])[0]
	if height > 30:
		return rng.choices(['glass', 'office', 'ribbon', 'brick', 'render'], [0.2, 0.3, 0.2, 0.15, 0.15])[0]
	return rng.choices(['office', 'ribbon', 'brick', 'render'], [0.15, 0.1, 0.4, 0.35])[0]


LAYERS = [   # (name, from, to): the rings the city is split into
	('Near', 0.0, 450.0),
	('Mid', 450.0, 1800.0),
	('Far', 1800.0, CITY_R),
]
colls = {name: collection('City ' + name.lower()) for name, _, _ in LAYERS}
builders = {(name, s): MeshBuilder(f'{name} {s}', FACADES[s], colls[name]) for name, _, _ in LAYERS for s in STYLES}
roof_builders = {name: MeshBuilder(f'{name} rooftop plant', MAT_ROOFTOP, colls[name]) for name, _, _ in LAYERS}
tank_builder = MeshBuilder('Near water tanks', MAT_TANK, colls['Near'])
spire_builder = MeshBuilder('Spires', MAT_SPIRE, colls['Far'])


def layer_of(d):
	for name, a, b in LAYERS:
		if a <= d < b:
			return name
	return None


def building(p, sx, sy, h, rot, d):
	"""One building on a lot: a base box, sometimes set back once or twice going up, with plant on the roof."""
	name = layer_of(d)
	style = pick_style(h, p)
	seed = rng.random()
	b = builders[(name, style)]
	if h > 90 and rng.random() < 0.55:   # a tower on a podium of shops and offices filling the lot
		ph = rng.uniform(10, 24)
		builders[(name, rng.choice(['office', 'brick', 'ribbon']))].box(p.x, p.y, 0.0, sx * 1.35, sy * 1.35, ph, rot, rng.random())
	if h > 140 and rng.random() < 0.25:   # a round glass tower
		r = min(sx, sy) * 0.5
		builders[(name, 'glass')].cylinder(p.x, p.y, 0.0, r, h, seg=28, seed=seed)
		roof_builders[name].box(p.x, p.y, h, r, r, 4.0)
		if rng.random() < 0.6:
			spire_builder.cylinder(p.x, p.y, h + 4.0, 0.8, h * 0.18, seg=8)
		return h
	tiers = 1
	if h > 60 and rng.random() < 0.6:
		tiers = rng.choice([2, 3])
	z = 0.0
	fx, fy = sx, sy
	for k in range(tiers):
		th = h if tiers == 1 else (h * (0.55 if k == 0 else 0.45 / (tiers - 1)))
		b.box(p.x, p.y, z, fx, fy, th, rot, seed)
		z += th
		fx *= rng.uniform(0.65, 0.85)
		fy *= rng.uniform(0.65, 0.85)
	top_w, top_d = fx / 0.75, fy / 0.75
	if name != 'Far' or h > 120:
		for _ in range(rng.randint(1, 4 if name == 'Near' else 2)):
			ux, uy = rng.uniform(-0.3, 0.3) * top_w, rng.uniform(-0.3, 0.3) * top_d
			c, s = math.cos(rot), math.sin(rot)
			roof_builders[name].box(p.x + ux * c - uy * s, p.y + ux * s + uy * c, z, rng.uniform(2, 6), rng.uniform(2, 6), rng.uniform(1.2, 3.5), rot)
		if name == 'Near' and style in ('brick', 'render') and rng.random() < 0.35:   # the old wooden water tank on a stand
			tank_builder.cylinder(p.x + rng.uniform(-3, 3), p.y + rng.uniform(-3, 3), z + 2.5, 2.2, 4.5, seg=10)
			roof_builders[name].box(p.x, p.y, z, 4.5, 4.5, 2.5, rot)
	if h > 200 and rng.random() < 0.5:   # a spire or mast on the tallest
		spire_builder.cylinder(p.x, p.y, z, rng.uniform(0.6, 1.5), h * rng.uniform(0.1, 0.25), seg=8)
	return z


def lay_out_city():
	n = int(CITY_R / PITCH) + 1
	count = 0
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			cx, cy = i * PITCH, j * PITCH
			c = Vector((cx, cy))
			d = c.length
			if d > CITY_R:
				continue
			if abs(cx) < PLAZA and abs(cy) < PLAZA:
				continue   # the open ground round the park
			boost = downtown_boost(c)
			# the farther out, the fewer and simpler the buildings (they are only a few pixels there)
			if d > 3500 and boost < 0.2 and rng.random() < 0.45:
				continue
			lots = 2 if (d < 1800 or boost > 0.3) else (1 if d > 3500 else rng.choice([1, 2]))
			base = 14 + 22 * math.exp(-d / 3000.0)
			if d < 700:
				base *= 0.65   # the streets round the park are mid-rise, so the skyline shows over them
			for a in range(lots):
				for b in range(lots):
					w = BLOCK / lots
					px = cx - BLOCK / 2 + w * (a + 0.5) + rng.uniform(-2, 2)
					py = cy - BLOCK / 2 + w * (b + 0.5) + rng.uniform(-2, 2)
					p = Vector((px, py))
					if rng.random() < 0.06 and d < 3000:
						continue   # a gap: a car park or a square
					tall = rng.lognormvariate(0, 0.55)
					boost = downtown_boost(p)
					h = base * tall * (1 + 14 * boost * rng.uniform(0.35, 1.25))
					if boost < 0.1 and rng.random() < 0.012:
						h *= rng.uniform(3, 5)   # the odd tall building out in the neighbourhoods
					h = max(8.0, min(h, 480.0))
					sx = w * rng.uniform(0.62, 0.9)
					sy = w * rng.uniform(0.62, 0.9)
					if h > 110:   # skyscrapers are slimmer than the lot
						sx, sy = min(sx, rng.uniform(26, 44)), min(sy, rng.uniform(26, 44))
					building(p, sx, sy, h, 0.0, d)
					count += 1
	return count


n_buildings = lay_out_city()
for b in list(builders.values()) + list(roof_builders.values()) + [tank_builder, spire_builder]:
	b.finish()


# ------------------------------------------------------------------------------------------------------------- the near detail
near = colls['Near']


def ground():
	me = bpy.data.meshes.new('Ground')
	R = 40000.0
	me.from_pydata([(-R, -R, 0), (R, -R, 0), (R, R, 0), (-R, R, 0)], [], [(0, 1, 2, 3)])
	me.materials.append(MAT_GROUND)
	ob = bpy.data.objects.new('Ground', me)
	scene.collection.objects.link(ob)


def trees():
	"""Street trees round the open ground and along the nearest streets: a trunk and a lumpy crown."""
	crowns = bmesh.new()
	trunks = MeshBuilder('Tree trunks', MAT_TRUNK, near)
	spots = []
	edge = OPEN - 6
	k = -edge
	while k <= edge:   # a ring of trees round the lawn
		for x, y in ((k, -edge), (k, edge), (-edge, k), (edge, k)):
			spots.append((x + rng.uniform(-1, 1), y + rng.uniform(-1, 1)))
		k += 11.0
	for _ in range(70):   # and scattered on the lawn, outside the park
		x, y = rng.uniform(-edge, edge), rng.uniform(-edge, edge)
		if abs(x) > 62 or abs(y) > 58:
			spots.append((x, y))
	# along the streets out to the near ring
	for i in range(-4, 5):
		for along in range(-450, 451, 14):
			for side in (-1, 1):
				s = i * PITCH + side * (ROAD / 2 + 2.0) + PITCH / 2
				for x, y in ((s, along), (along, s)):
					if abs(x) < OPEN and abs(y) < OPEN:
						continue
					if rng.random() < 0.75:
						spots.append((x, y))
	for x, y in spots:
		h = rng.uniform(5.0, 9.0)
		r = rng.uniform(2.2, 3.6)
		trunks.cylinder(x, y, 0.0, 0.18, h * 0.55, seg=6, cap=False)
		m = bmesh.ops.create_icosphere(crowns, subdivisions=2, radius=r)
		for v in m['verts']:
			n = v.co.normalized()
			v.co = v.co * rng.uniform(0.85, 1.1) * Vector((1.0, 1.0, rng.uniform(1.0, 1.3)))
			v.co += Vector((x, y, h * 0.55 + r * 0.8))
	trunks.finish()
	me = bpy.data.meshes.new('Tree crowns')
	crowns.to_mesh(me)
	crowns.free()
	for p in me.polygons:
		p.use_smooth = True
	me.materials.append(MAT_TREE)
	ob = bpy.data.objects.new('Tree crowns', me)
	near.objects.link(ob)
	# a displacement makes the crowns leafy rather than smooth balls
	tex = bpy.data.textures.new('Leaves', 'CLOUDS')
	tex.noise_scale = 0.6
	mod = ob.modifiers.new('Leaves', 'DISPLACE')
	mod.texture = tex
	mod.strength = 0.9
	mod.texture_coords = 'GLOBAL'


def street_lights():
	poles = MeshBuilder('Street lights', MAT_POLE, near)
	edge = OPEN + 3
	k = -edge
	while k <= edge:
		for x, y in ((k, -edge), (k, edge), (-edge, k), (edge, k)):
			poles.cylinder(x, y, 0.0, 0.1, 8.0, seg=6)
			poles.box(x, y, 7.8, 1.6, 0.35, 0.2)
		k += 30.0
	poles.finish()


def viaduct():
	"""An elevated railway crossing behind the plaza (Godot +Z side): concrete deck on piers, with a train on it."""
	deck = MeshBuilder('Viaduct', MAT_CONCRETE, near)
	y = -1.5 * PITCH   # along the first street out
	for x in range(-2400, 2401, 40):
		deck.box(x, y, 0.0, 2.2, 3.0, 11.0)
	deck.box(0.0, y, 11.0, 4800.0, 10.0, 1.8)
	deck.box(0.0, y - 4.8, 12.8, 4800.0, 0.3, 1.1)
	deck.box(0.0, y + 4.8, 12.8, 4800.0, 0.3, 1.1)
	deck.finish()
	train = MeshBuilder('Train', MAT_RAIL_CAR, near)
	x0 = -230.0
	for k in range(6):
		train.box(x0 + k * 21.0, y - 1.6, 13.0, 20.0, 3.0, 3.6)
	train.finish()


def cranes():
	"""Tower cranes over a couple of building sites: they read as a living city."""
	b = MeshBuilder('Cranes', MAT_CRANE, colls['Mid'])
	for p, h, rot in ((Vector((620.0, 380.0)), 110.0, 0.4), (Vector((-480.0, 780.0)), 90.0, 2.1), (Vector((2500.0, 900.0)), 230.0, 1.2)):
		b.box(p.x, p.y, 0.0, 2.2, 2.2, h)
		c, s = math.cos(rot), math.sin(rot)
		jib = 60.0
		b.box(p.x + c * jib * 0.35, p.y + s * jib * 0.35, h, jib, 1.6, 1.8, rot)
		b.box(p.x - c * 9, p.y - s * 9, h - 2.0, 5.0, 3.0, 2.5, rot)   # counterweight
	b.finish()


def hills():
	"""Low hills far beyond the city, nearly lost in the haze: a ring of noise-displaced ground."""
	bm = bmesh.new()
	ring = 96
	rows = [(9000.0, 0.0), (11000.0, 0.6), (14000.0, 1.0), (18000.0, 0.7), (22000.0, 0.0)]
	verts = []
	for r, amp in rows:
		row = []
		for i in range(ring):
			a = 2 * math.pi * i / ring
			hgt = amp * (220 + 260 * (0.5 + 0.5 * math.sin(a * 3 + 1.3)) * (0.5 + 0.5 * math.sin(a * 7 + 0.4)) + rng.uniform(0, 120))
			row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), hgt)))
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
	me.materials.append(MAT_HILLS)
	ob = bpy.data.objects.new('Hills', me)
	scene.collection.objects.link(ob)
	sub = ob.modifiers.new('Smooth', 'SUBSURF')
	sub.levels = sub.render_levels = 2


ground()
trees()
street_lights()
viaduct()
cranes()
hills()


# --------------------------------------------------------------------------------------------------------------- light, camera
sun_data = bpy.data.lights.new('Sun', 'SUN')
sun_data.color = SUN_COLOUR
sun_data.energy = 4.0
sun_data.angle = math.radians(0.6)
sun = bpy.data.objects.new('Sun', sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = SUN_DIR.to_track_quat('Z', 'Y').to_euler()   # a sun light shines down its -Z

cam_data = bpy.data.cameras.new('Panorama')
cam_data.type = 'PANO'
cam_data.panorama_type = 'EQUIRECTANGULAR'
cam_data.clip_start = 0.1
cam_data.clip_end = 60000.0
cam = bpy.data.objects.new('Panorama', cam_data)
scene.collection.objects.link(cam)
cam.location = (0.0, 0.0, CAM_Z)
cam.rotation_euler = (math.radians(90), 0.0, math.radians(180))   # looking along -Y (Godot +Z), level
scene.camera = cam

# ------------------------------------------------------------------------------------------------------------------- render
r = scene.render
r.engine = 'CYCLES'
cy = scene.cycles
cy.device = 'CPU'
cy.samples = 24 if PREVIEW else 48
cy.use_adaptive_sampling = True
cy.adaptive_threshold = 0.02
cy.use_denoising = True
cy.denoiser = 'OPENIMAGEDENOISE'
cy.max_bounces = 4
cy.diffuse_bounces = 2
cy.glossy_bounces = 2
cy.transmission_bounces = 2
cy.transparent_max_bounces = 2
cy.caustics_reflective = False
cy.caustics_refractive = False
cy.sample_clamp_indirect = 5.0
r.resolution_x, r.resolution_y = (2048, 1024) if PREVIEW else (8192, 4096)
r.resolution_percentage = 100
r.use_persistent_data = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = 0.0
r.image_settings.file_format = 'PNG'
r.image_settings.color_mode = 'RGB'
r.image_settings.color_depth = '8'
r.image_settings.compression = 90

print(f'city: {n_buildings} buildings, {sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")} faces')

if not PREVIEW:
	bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'city_panorama.blend'), compress=True)

r.filepath = str(ART / ('preview.png' if PREVIEW else 'city_panorama_8k.png'))
bpy.ops.render.render(write_still=True)
if not PREVIEW:
	img = bpy.data.images['Render Result']
	r.image_settings.file_format = 'JPEG'
	r.image_settings.quality = 92
	img.save_render(str(GAME / 'city_panorama.jpg'), scene=scene)
print('done')
