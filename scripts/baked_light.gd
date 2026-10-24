# Levels whose light is baked into their vertex colours (tools/build_baths.py): every surface is drawn unlit, its texture (and tint)
# times the light baked at its vertices, which carries the sun through the windows and roof, the sky, the lamps and all of it
# bouncing round. The bake keeps light / gain, sRGB-encoded, in the vertex colour; `gain` (the level's `baked` in levels.gd) brings it
# back. Glass stays see-through, the lamps glow, and the light shafts ("FX |") are added onto what is behind them.
class_name BakedLight
extends RefCounted

const LAMP := Color(4.0, 3.1, 2.0)     # how bright (linear) the lamps' globes are drawn
const SHAFT := 0.55                    # how much the light shafts add


static func apply(level: LevelLoader, settings: Dictionary) -> void:
	var gain := float(settings.get("gain", 3.0))
	var converted := {}
	for mesh: MeshInstance3D in level.render_meshes:
		if mesh.mesh == null:
			continue
		for s in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(s) as BaseMaterial3D
			if source == null:
				continue
			if not converted.has(source):
				converted[source] = _convert(source, gain)
			mesh.set_surface_override_material(s, converted[source])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _convert(source: BaseMaterial3D, gain: float) -> BaseMaterial3D:
	var m := source.duplicate() as BaseMaterial3D
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.normal_enabled = false
	m.emission_enabled = false
	match source.resource_name.get_slice(" | ", 0):
		"Glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"Lamp":
			m.albedo_color = LAMP.linear_to_srgb()
		"FX":
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = false
			m.albedo_color = Color(SHAFT, SHAFT, SHAFT)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_:
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			var tint := source.albedo_color.srgb_to_linear() * gain
			tint.a = 1.0
			m.albedo_color = tint.linear_to_srgb()
	return m
