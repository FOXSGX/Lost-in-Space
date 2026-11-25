shader_type spatial;
render_mode blend_mix, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

// 霜烬星 · 冰体族（雪堆冰壳、封门冰、冰锥、冰晶）。
//
// 对齐标准第 3 条与 B5：冰要读得出“内部深度与光学层次”，而不是一块过曝的白塑料。
//   芯层深色 → 中层浑浊带 → 边缘菲涅尔冷光，内部还有气泡与裂纹；
//   发光只在芯层与边缘，靠 soft-knee 压住，不会整体拉爆。
//   melt 由融冰玩法驱动：越融越湿、越透、发光越弱。

uniform vec4 deep_color : source_color = vec4(0.05, 0.19, 0.25, 1.0);
uniform vec4 body_color : source_color = vec4(0.24, 0.55, 0.64, 1.0);
uniform vec4 rim_color : source_color = vec4(0.72, 0.92, 0.99, 1.0);
uniform vec4 snow_color : source_color = vec4(0.88, 0.94, 0.98, 1.0);
uniform float crack_amount = 0.55;
uniform float bubble_amount = 0.45;
uniform float emission_strength = 0.30;
uniform float snow_amount = 0.55;
uniform float melt = 0.0;
uniform float variation = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		value += vnoise(p) * amplitude;
		p = p * 2.03 + vec3(6.7, 3.9, 5.1);
		amplitude *= 0.47;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 view = normalize(VIEW);
	float fresnel = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.2);
	float up = smoothstep(0.30, 0.92, n.y);

	// 内部裂纹与气泡：越靠中心越浑浊，越靠边缘越通透。
	float depth = clamp(dot(n, view), 0.0, 1.0);
	float murk = 0.55 + fbm(world_pos * 0.55 + vec3(variation * 7.0)) * 0.45;
	vec3 core = mix(deep_color.rgb, body_color.rgb, murk);

	float crack = 1.0 - abs(fbm(world_pos * 1.05 + vec3(variation * 11.0)) * 2.0 - 1.0);
	float crack_line = smoothstep(0.72, 0.96, crack) * crack_amount;
	vec3 albedo = mix(core, rim_color.rgb, crack_line * 0.35 * (1.0 - depth * 0.5));

	float bubbles = smoothstep(0.80, 0.96, vnoise(world_pos * 9.0 + vec3(variation * 17.0)));
	albedo = mix(albedo, rim_color.rgb * 1.05, bubbles * bubble_amount * 0.35);

	// 边缘冷光与顶面薄雪：冰的体积感与“长在地上”的关系都靠这两笔。
	albedo = mix(albedo, rim_color.rgb, fresnel * 0.55);
	float snow_noise = fbm(world_pos * 0.7 + vec3(variation * 29.0));
	float snow = up * smoothstep(0.44, 0.70, snow_noise) * snow_amount;
	albedo = mix(albedo, snow_color.rgb, snow);

	// 融化：湿、透、不发光。
	float wet = smoothstep(0.0, 1.0, melt);
	albedo = mix(albedo, deep_color.rgb * 1.3, wet * 0.45);

	float rough = mix(0.10, 0.38, murk * 0.5) + crack_line * 0.10 + snow * 0.55 + wet * 0.22;
	float emit = emission_strength * (0.22 + fresnel * 0.55 + crack_line * 0.35) * (1.0 - wet * 0.65);
	emit = emit / (1.0 + emit * 0.62);

	ALBEDO = clamp(albedo, vec3(0.02), vec3(0.95));
	ROUGHNESS = clamp(rough, 0.04, 0.92);
	METALLIC = 0.0;
	SPECULAR = 0.62;
	ALPHA = clamp(1.0 - wet * 0.70, 0.10, 1.0);
	EMISSION = rim_color.rgb * emit;
}
