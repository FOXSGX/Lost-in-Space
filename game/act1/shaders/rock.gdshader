shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.31, 0.29, 0.29, 1.0);
uniform vec4 deep_color : source_color = vec4(0.075, 0.085, 0.10, 1.0);
uniform vec4 vein_color : source_color = vec4(0.10, 0.48, 0.56, 1.0);
uniform float noise_scale = 0.30;
uniform float vein_strength = 0.30;
uniform float roughness_base = 0.84;
uniform float vertex_tint : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.27, 0.43));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wpos = VERTEX;
}

void fragment() {
	float n = fbm(wpos * noise_scale);
	float detail = fbm(wpos * 2.9 + vec3(13.7, 5.1, 8.3));
	float strata = 0.5 + 0.5 * sin(wpos.y * 4.7 + n * 5.0 + wpos.x * 0.22);
	vec3 col = mix(deep_color.rgb, base_color.rgb, clamp(n * 1.35 + 0.08, 0.0, 1.0));
	col = mix(col, col * 0.58, smoothstep(0.52, 0.95, detail) * 0.6);
	col = mix(col, base_color.rgb * 1.10, strata * 0.035);
	float crack = 1.0 - smoothstep(0.0, 0.02, abs(sin(wpos.y * 9.0 + n * 9.0 + wpos.x * 1.7)));
	col = mix(col, col * 0.55, crack * 0.12);
	float vein = 1.0 - smoothstep(0.0, 0.075, abs(sin(wpos.y * 1.9 + n * 6.4 + wpos.x * 0.31)));
	col = mix(col, vein_color.rgb, vein * vein_strength * 0.65);
	col *= (1.0 - vertex_tint) + vertex_tint * (0.55 + 0.75 * COLOR.rgb);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_base - detail * 0.12 + vein * 0.08, 0.18, 1.0);
	METALLIC = 0.03;
	SPECULAR = 0.32;
	NORMAL = normalize(NORMAL + vec3((detail - 0.5) * 0.26, (n - 0.5) * 0.20, 0.0));
}
