// Paint that lies flat on other surfaces (lane markings): drawn a little nearer the camera than the surface under it, so the two do
// not fight over the same depth. The nudge grows with distance, because depth gets coarser the further away it is.
shader_type spatial;
render_mode skip_vertex_transform;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform float nudge = 0.02;
uniform float nudge_per_metre = 0.0006;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_NORMAL_MATRIX * NORMAL));
	float away = length(VERTEX);
	VERTEX -= VERTEX / away * (nudge + nudge_per_metre * away);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
}
