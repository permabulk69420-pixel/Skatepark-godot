// The sky for a night level (its `night.sky` in levels.gd): a horizon glow, stars (three layers, bright to faint), a faint Milky Way,
// thin cloud lit by the moon, and the moon itself, from a real NASA map (assets/sky/moon.jpg: Lunar Reconnaissance Orbiter data,
// NASA Scientific Visualization Studio) with a phase. Ported from the web build's nightsky.js; scripts/night.gd sets the values.
shader_type sky;

uniform sampler2D moon_texture : source_color, filter_linear_mipmap, repeat_enable;
// colours are linear (night.gd converts them)
uniform vec3 moon_dir = vec3(-0.45, 0.53, -0.71);
uniform vec3 phase_dir = vec3(0.6, 0.12, 0.8);
uniform vec3 zenith = vec3(0.0003, 0.001, 0.003);
uniform vec3 horizon = vec3(0.002, 0.008, 0.02);
uniform vec3 glow = vec3(0.01, 0.007, 0.005);
uniform vec3 galaxy_normal = vec3(0.55, 0.25, -0.8);
uniform float moon_size = 0.026;
uniform float stars = 1.0;
uniform float galaxy = 0.8;
uniform float clouds = 0.6;
// roughly how many radians one pixel covers; the web build asked the GPU (fwidth), this is a fixed guess that works for a headset
uniform float pixel_angle = 0.0012;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// One layer of stars: a random point in each cell of a 3D grid laid over the sky. A star smaller than a pixel is dimmed rather than lost.
// (`t` is the time: TIME only exists inside sky(), not in other functions.)
vec3 star_layer(vec3 dir, float scale, float density, float size, float gain, float t) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	vec3 f = fract(p);
	vec3 h = hash33(id);
	if (hash13(id + 17.7) > density) {
		return vec3(0.0);
	}
	float px = scale * pixel_angle;
	float r = size * (0.6 + 0.8 * h.x);
	float rr = max(r, px * 0.9);
	float d = length(f - (0.25 + 0.5 * h));
	float s = smoothstep(rr, 0.0, d) * min(1.0, (r * r) / (rr * rr));
	float twinkle = 1.0 + 0.22 * sin(t * (1.5 + 4.0 * h.y) + 40.0 * h.z);
	vec3 tint = mix(vec3(1.0, 0.78, 0.6), vec3(0.65, 0.78, 1.0), h.z);
	return tint * s * twinkle * gain * (0.35 + 1.4 * h.y * h.y);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, 0.0, 1.0);

	// sky gradient and a low glow, like a town beyond the trees
	vec3 col = mix(horizon, zenith, pow(up, 0.5));
	col += glow * pow(1.0 - up, 6.0);

	// moon basis
	vec3 md = normalize(moon_dir);
	vec3 mr = normalize(cross(vec3(0.0, 1.0, 0.0), md));
	vec3 mu = cross(md, mr);
	float cos_a = clamp(dot(dir, md), -1.0, 1.0);
	float ang = sqrt(max(2.0 * (1.0 - cos_a), 0.0));
	vec3 moon_light = vec3(0.62, 0.7, 0.9);

	// thin cloud, drifting slowly, brightest near the moon
	float cloud = 0.0;
	if (clouds > 0.0 && dir.y > 0.02) {
		vec3 q = vec3(dir.xz / (dir.y + 0.18), 0.0) * 1.6 + vec3(TIME * 0.012, 0.0, TIME * 0.004);
		cloud = smoothstep(0.52, 0.86, fbm(q)) * smoothstep(0.02, 0.22, dir.y) * clouds;
	}

	// stars, thinned where there is cloud, and washed out near the moon
	vec3 star_sum = star_layer(dir, 34.0, 0.22, 0.07, 1.7, TIME) + star_layer(dir, 80.0, 0.3, 0.09, 1.0, TIME) + star_layer(dir, 190.0, 0.3, 0.12, 0.75, TIME);
	float gn = dot(dir, normalize(galaxy_normal)) / 0.2;
	float band = exp(-gn * gn);
	vec3 dense = star_layer(dir, 330.0, 0.5 * band, 0.14, 0.55, TIME);
	float dust = fbm(dir * 5.0 + 3.0);
	vec3 galaxy_glow = vec3(0.5, 0.58, 0.8) * band * (0.25 + 0.9 * dust) * 0.05 * galaxy;
	float visible = smoothstep(-0.02, 0.12, dir.y) * (1.0 - cloud) * (1.0 - smoothstep(0.0, 0.5, 0.12 / (ang + 0.05)));
	col += (star_sum * stars + dense * stars * galaxy + galaxy_glow) * visible;

	// the moon
	vec2 p = vec2(dot(dir, mr), dot(dir, mu)) / moon_size;
	float r = length(p);
	float edge = pixel_angle / moon_size * 1.5 + 0.01;
	if (cos_a > 0.0 && r < 1.0 + edge) {
		vec3 n = vec3(p, sqrt(max(1.0 - r * r, 0.0)));
		vec2 uv = vec2(0.5 + atan(n.x, n.z) / 6.2831853, 0.5 + asin(clamp(n.y, -1.0, 1.0)) / 3.1415927);
		// the disc is only a few dozen pixels across, so read a smaller copy of the map instead of shimmering
		float disc_pixels = 2.0 * moon_size / pixel_angle;
		float lod = max(0.0, log2(float(textureSize(moon_texture, 0).x) * 0.5 / disc_pixels));
		vec3 albedo = textureLod(moon_texture, uv, lod).rgb;
		float lit = smoothstep(-0.04, 0.3, dot(n, normalize(phase_dir)));
		vec3 surface = albedo * (lit * 3.0 + 0.012) * vec3(1.0, 0.96, 0.88);
		col = mix(col, surface, 1.0 - smoothstep(1.0 - edge, 1.0 + edge, r));
	}
	// halo around the moon, and the moon shining through the cloud
	float halo = 0.045 / (ang * ang * 90.0 + 0.5) + 0.018 / (ang * 3.0 + 0.2);
	col += moon_light * halo * 1.1 * (cos_a > 0.0 ? 1.0 : 0.0);
	col = mix(col, col + vec3(0.02, 0.026, 0.04) + moon_light * halo * 0.9, cloud * 0.8);

	// a little noise so the dark gradient does not band
	col += (hash13(vec3(FRAGCOORD.xy, 1.0)) - 0.5) / 160.0;
	COLOR = max(col, vec3(0.0));
}
