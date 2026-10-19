// A scanned level at night. The scan's lighting is painted into its texture (its material is unlit), so real lights do nothing to it.
// This multiplies the texture by a made-up light instead: a dark ambient, a big "floodlight" pool that comes from the direction of the sun
// the scan was photographed in (so the baked shadows still make sense), and up to four lamp pools. See scripts/night.gd, which sets it up.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// all colours here are already linear (night.gd converts them), with their strength multiplied in
uniform vec3 ambient = vec3(0.004, 0.01, 0.02);
uniform vec3 key_dir = vec3(0.31, 0.42, 0.85);
uniform vec3 key_colour = vec3(0.5, 0.65, 1.0);
uniform vec2 key_centre = vec2(0.0);
uniform float key_radius = 20.0;

uniform vec3 lamp_a_pos = vec3(0.0, -1000.0, 0.0);
uniform vec3 lamp_a_colour = vec3(0.0);
uniform float lamp_a_radius = 1.0;
uniform vec3 lamp_b_pos = vec3(0.0, -1000.0, 0.0);
uniform vec3 lamp_b_colour = vec3(0.0);
uniform float lamp_b_radius = 1.0;
uniform vec3 lamp_c_pos = vec3(0.0, -1000.0, 0.0);
uniform vec3 lamp_c_colour = vec3(0.0);
uniform float lamp_c_radius = 1.0;
uniform vec3 lamp_d_pos = vec3(0.0, -1000.0, 0.0);
uniform vec3 lamp_d_colour = vec3(0.0);
uniform float lamp_d_radius = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 lamp_light(vec3 pos, vec3 colour, float radius, vec3 n) {
	vec3 to_lamp = pos - world_pos;
	float d = max(length(to_lamp), 0.001);
	float r = d / radius;
	float a = 1.0 / (1.0 + r * r);
	return colour * a * a * (0.4 + 0.6 * max(dot(n, to_lamp / d), 0.0));
}

void fragment() {
	vec3 n = normalize(world_normal);
	float away = length(world_pos.xz - key_centre) / key_radius;
	float pool = 1.0 / (1.0 + away * away);
	vec3 lit = ambient + key_colour * (0.35 + 0.65 * max(dot(n, normalize(key_dir)), 0.0)) * pool * pool;
	lit += lamp_light(lamp_a_pos, lamp_a_colour, lamp_a_radius, n);
	lit += lamp_light(lamp_b_pos, lamp_b_colour, lamp_b_radius, n);
	lit += lamp_light(lamp_c_pos, lamp_c_colour, lamp_c_radius, n);
	lit += lamp_light(lamp_d_pos, lamp_d_colour, lamp_d_radius, n);
	ALBEDO = texture(albedo_texture, UV).rgb * lit;
}
