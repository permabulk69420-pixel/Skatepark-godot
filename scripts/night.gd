# The night version of a scanned level (a level's `night` in levels.gd). A scan's lighting is painted into its texture and its material
# is unlit, so real lights do nothing to it. Its material is swapped for shaders/night_scan.gdshader instead, which multiplies the
# texture by a made-up light: a dark ambient, a big "floodlight" pool from where the sun was when the scan was photographed (so the
# baked shadows still make sense), and a few lamp pools. The same lamps are also real lights, so the board, hands and rider are lit
# by them, and each gets a pole, a lamp head and a glow so there is something to look at. The sky is shaders/night_sky.gdshader.
# Ported from the web build's night.js and nightsky.js.
class_name Night
extends RefCounted

const MAX_LAMPS := 4   # the scan shader has room for this many
const MOON := "res://assets/sky/moon.jpg"
const LIT_AMBIENT := "1a2744"   # the dim blue the lit things (board, hands, rider) get from the air
const LIT_AMBIENT_ENERGY := 0.8


# A "#rrggbb" colour as the linear value the shaders want (the web build's three.js reads colours the same way).
static func _linear(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


static func _vec(colour: Color, strength := 1.0) -> Vector3:
	return Vector3(colour.r, colour.g, colour.b) * strength


static func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


# The night sky, as a Sky for the level's environment. `look` is the level's look (its fog colour is what the horizon is mixed from).
static func make_sky(look: Dictionary, night: Dictionary) -> Sky:
	var settings: Dictionary = night.get("sky", {})
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/night_sky.gdshader") as Shader
	var moon: Array = settings.get("moon", night.get("key", {}).get("direction", [0.3, 0.5, -0.8]))
	var phase := deg_to_rad(float(settings.get("phaseDegrees", 38.0)))   # the moon is lit from the right, this far from full
	var horizon: Color = _linear(settings["horizon"]) if settings.has("horizon") else _linear(look.fog).lerp(_linear("#0a1830"), 0.6)
	material.set_shader_parameter("moon_texture", load(MOON))
	material.set_shader_parameter("moon_dir", _vec3(moon).normalized())
	material.set_shader_parameter("phase_dir", Vector3(sin(phase), 0.12, cos(phase)).normalized())
	material.set_shader_parameter("moon_size", float(settings.get("moonSize", 0.026)))
	material.set_shader_parameter("zenith", _vec(_linear(settings.get("zenith", "#01030a"))))
	material.set_shader_parameter("horizon", _vec(horizon))
	material.set_shader_parameter("glow", _vec(_linear(settings.get("glow", "#1c1410"))))
	material.set_shader_parameter("galaxy_normal", _vec3(settings.get("galaxyNormal", [0.55, 0.25, -0.8])).normalized())
	material.set_shader_parameter("stars", float(settings.get("stars", 1.0)))
	material.set_shader_parameter("galaxy", float(settings.get("galaxy", 0.8)))
	material.set_shader_parameter("clouds", float(settings.get("clouds", 0.6)))
	var sky := Sky.new()
	sky.sky_material = material
	return sky


# Light for the things that are lit, taken from a flat dim colour instead of from the sky: the night sky is too busy to be worth
# turning into light every frame.
static func light_environment(env: Environment) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(LIT_AMBIENT)
	env.ambient_light_energy = LIT_AMBIENT_ENERGY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED


# Makes `level` (already loaded, under `parent`) its night version: the scan's materials become the night shader, and the lamps go up.
static func apply(parent: Node3D, level: LevelLoader, night: Dictionary) -> void:
	var lamps: Array = night.lamps.slice(0, MAX_LAMPS)
	var shader := load("res://shaders/night_scan.gdshader") as Shader
	var swapped := {}   # original material -> its night replacement (shared by every mesh that used it)
	for mesh_instance: MeshInstance3D in level.render_meshes:
		for surface in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			# the scan's material is the unlit, textured one; anything else keeps its own look
			if original == null or original.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or original.albedo_texture == null:
				continue
			if not swapped.has(original):
				var night_material := ShaderMaterial.new()
				night_material.shader = shader
				night_material.set_shader_parameter("albedo_texture", original.albedo_texture)
				_set_light(night_material, night, lamps)
				swapped[original] = night_material
			mesh_instance.set_surface_override_material(surface, swapped[original])
	_build_lamps(parent, lamps)


# Hands the scan shader the ambient, the floodlight pool and the lamps (all in the level's own coordinates).
static func _set_light(material: ShaderMaterial, night: Dictionary, lamps: Array) -> void:
	var key: Dictionary = night.key
	material.set_shader_parameter("ambient", _vec(_linear(night.ambient)))
	material.set_shader_parameter("key_dir", _vec3(key.direction).normalized())
	material.set_shader_parameter("key_colour", _vec(_linear(key.colour), float(key.strength)))
	material.set_shader_parameter("key_centre", Vector2(float(key.centre[0]), float(key.centre[1])))
	material.set_shader_parameter("key_radius", float(key.radius))
	for i in lamps.size():
		var lamp: Dictionary = lamps[i]
		var tag := "lamp_%s_" % "abcd"[i]
		material.set_shader_parameter(tag + "pos", _vec3(lamp.base) + Vector3(0.0, float(lamp.height), 0.0))
		material.set_shader_parameter(tag + "colour", _vec(_linear(lamp.colour), float(lamp.power)))
		material.set_shader_parameter(tag + "radius", float(lamp.radius))


# Each lamp: a pole, a bright bar for the head, a soft glow round it and a real light for the board, hands and rider.
static func _build_lamps(parent: Node3D, lamps: Array) -> void:
	var holder := Node3D.new()
	holder.name = "NightLamps"
	parent.add_child(holder)
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color("2a2d33")
	pole_material.roughness = 0.7
	pole_material.metallic = 0.6
	var glow := _glow_texture()
	for lamp: Dictionary in lamps:
		var base := _vec3(lamp.base)
		var height := float(lamp.height)
		var head := base + Vector3(0.0, height, 0.0)
		var colour := Color(lamp.colour)

		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.09
		pole_mesh.bottom_radius = 0.15
		pole_mesh.height = height
		pole_mesh.radial_segments = 8
		pole_mesh.rings = 1
		var pole := MeshInstance3D.new()
		pole.mesh = pole_mesh
		pole.material_override = pole_material
		pole.position = base + Vector3(0.0, height / 2.0, 0.0)
		holder.add_child(pole)

		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(1.5, 0.18, 0.45)
		var bar_material := StandardMaterial3D.new()
		bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar_material.albedo_color = _linear(lamp.colour).lerp(Color.WHITE, 0.6).linear_to_srgb()
		bar_material.disable_fog = true
		var bar := MeshInstance3D.new()
		bar.mesh = bar_mesh
		bar.material_override = bar_material
		bar.position = head + Vector3(0.0, 0.05, 0.0)
		holder.add_child(bar)

		var glow_size := float(lamp.get("glow", 9.0))
		var glow_mesh := QuadMesh.new()
		glow_mesh.size = Vector2(glow_size, glow_size)
		var glow_material := StandardMaterial3D.new()
		glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		glow_material.billboard_keep_scale = true
		glow_material.albedo_texture = glow
		glow_material.albedo_color = colour
		glow_material.disable_fog = true
		var glow_quad := MeshInstance3D.new()
		glow_quad.mesh = glow_mesh
		glow_quad.material_override = glow_material
		glow_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow_quad.position = head
		holder.add_child(glow_quad)

		var light := OmniLight3D.new()
		light.light_color = colour
		light.light_energy = float(lamp.power) * 0.5
		light.omni_range = float(lamp.radius) * 2.5
		light.omni_attenuation = 2.0
		light.position = head
		holder.add_child(light)


# A soft round glow: white in the middle, fading to nothing at the edge.
static func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture
