shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.38, 0.42, 0.45, 1.0);
uniform vec4 grime_color : source_color = vec4(0.075, 0.07, 0.06, 1.0);
uniform float metallic_base = 0.72;
uniform float roughness_base = 0.36;
uniform float grime_amount = 0.55;
uniform float speck_amount = 0.25;

varying vec3 wpos;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.21, 0.17, 0.13));
	p *= 19.0;
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
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p *= 2.11;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm(wpos * 1.45);
	float streak = fbm(vec3(wpos.x * 3.2, wpos.y * 0.22, wpos.z * 3.2));
	float wear = smoothstep(0.54, 0.92, n + streak * 0.32);
	vec3 col = mix(base_color.rgb, grime_color.rgb, wear * grime_amount);
	float scratch = smoothstep(0.47, 0.5, sin((wpos.x + wpos.z) * 46.0 + n * 13.0)) * smoothstep(0.55, 0.95, streak);
	col += scratch * 0.05;
	float speck = smoothstep(0.72, 0.84, hash13(floor(wpos * 34.0)));
	col = mix(col, col * 0.55, speck * speck_amount);
	ALBEDO = col;
	METALLIC = metallic_base * (1.0 - wear * 0.4);
	ROUGHNESS = clamp(roughness_base + wear * 0.34 + speck * 0.12, 0.12, 1.0);
	SPECULAR = 0.5;
	NORMAL = normalize(NORMAL + vec3((n - 0.5) * 0.10, (streak - 0.5) * 0.07, 0.0));
}
