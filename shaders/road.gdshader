// The asphalt out front. One texture laid in the world, but not in a grid you can see: it is read twice, at two sizes and turned against
// each other, and the two are blended by a slow, patchy noise, with a gentle change of tone across tens of metres on top. (A 3 m texture
// laid plainly repeats its cracks every 3 m down a 500 m road.)
shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // roughness in green
uniform float tile = 3.0;              // metres the texture covers
uniform float second_scale = 1.37;     // the second reading is this much bigger,
uniform float second_turn = 0.61;      // and turned this far (radians)
uniform float blend_size = 9.0;        // metres across the patches where one reading or the other shows
uniform float tone_size = 23.0;        // and across the slow changes of tone
uniform float normal_strength = 0.5;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	mat2 turn = mat2(vec2(cos(second_turn), sin(second_turn)), vec2(-sin(second_turn), cos(second_turn)));
	vec2 uv1 = world_xz / tile;
	vec2 uv2 = turn * world_xz / (tile * second_scale) + vec2(0.31, 0.77);
	float m = smoothstep(0.25, 0.75, value_noise(world_xz / blend_size));
	vec3 colour = mix(texture(albedo_texture, uv1).rgb, texture(albedo_texture, uv2).rgb, m);
	colour *= mix(0.9, 1.06, value_noise(world_xz / tone_size + vec2(5.0, 9.0)));
	ALBEDO = colour;
	vec3 n1 = texture(normal_texture, uv1).rgb;
	vec3 n2 = texture(normal_texture, uv2).rgb;
	vec2 n2_xy = transpose(turn) * (n2.xy * 2.0 - 1.0);   // (the second reading's bumps turned back to the road's frame)
	NORMAL_MAP = mix(n1, vec3(n2_xy * 0.5 + 0.5, n2.z), m);
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(texture(arm_texture, uv1).g, texture(arm_texture, uv2).g, m);
	SPECULAR = 0.35;
}
