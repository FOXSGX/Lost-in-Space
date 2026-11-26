shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 霜烬星 · 骨与化石族（标本馆骨架、遗迹巨口、走廊骨脊）。
//
// 对齐标准第 4 条：骨不是一根米色圆柱。表层有松质孔、沉积染色、纵向骨纹、
// 断口与凿痕；朝上的面落雪，贴地的部分吸潮发暗。这样 1–2 m 内才读得出是化石。

uniform vec4 bone_color : source_color = vec4(0.82, 0.75, 0.61, 1.0);
uniform vec4 stain_color : source_color = vec4(0.46, 0.38, 0.27, 1.0);
uniform vec4 cavity_color : source_color = vec4(0.24, 0.21, 0.17, 1.0);
uniform vec4 snow_color : source_color = vec4(0.87, 0.92, 0.97, 1.0);
uniform float pore_amount = 0.40;
uniform float stain_amount = 0.38;
uniform float snow_amount = 0.55;
uniform float roughness_base = 0.72;
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
	for (int i = 0; i < 3; i++) {
		value += vnoise(p) * amplitude;
		p = p * 2.09 + vec3(2.3, 5.7, 4.1);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float up = smoothstep(0.30, 0.90, n.y);

	// 骨纹：沿肢体方向的细长条纹（用世界高度与半径近似，圆柱/水晶体都成立）。
	float grain = fbm(vec3(world_pos.x * 5.2, world_pos.y * 0.7, world_pos.z * 5.2) + vec3(variation * 7.0));
	float mottle = fbm(world_pos * 0.9 + vec3(variation * 19.0));

	vec3 albedo = bone_color.rgb * (0.88 + grain * 0.20 + mottle * 0.14);

	// 松质孔：稀疏的小凹坑，只在表面朝光的区域可见。
	float pores = smoothstep(0.66, 0.90, vnoise(world_pos * 22.0 + vec3(variation * 13.0)));
	albedo = mix(albedo, cavity_color.rgb, pores * pore_amount * 0.55);

	// 沉积染色：贴着地/裂隙的骨段被矿物染成赭色，呈块状而不是均匀变脏。
	float stain = smoothstep(0.46, 0.78, fbm(world_pos * 0.42 + vec3(variation * 31.0))) * stain_amount;
	stain *= 1.0 - up * 0.6;
	albedo = mix(albedo, stain_color.rgb, stain * 0.55);

	// 纵向断口：一条锐的裂缝，两侧略微提亮，交代“断在这里”。
	float crack = 1.0 - abs(fbm(vec3(world_pos.x * 1.1, world_pos.y * 0.20, world_pos.z * 1.1) + vec3(variation * 5.0)) * 2.0 - 1.0);
	float crack_line = smoothstep(0.80, 0.97, crack);
	albedo = mix(albedo, cavity_color.rgb, crack_line * 0.45);

	// 顶面薄雪。
	float snow_noise = fbm(world_pos * 0.8 + vec3(variation * 37.0));
	float snow = up * smoothstep(0.52, 0.78, snow_noise) * snow_amount;
	albedo = mix(albedo, snow_color.rgb, snow);

	float rough = clamp(roughness_base + grain * 0.10 - snow * 0.40 + pores * 0.10, 0.28, 0.98);
	ALBEDO = clamp(albedo, vec3(0.03), vec3(0.94));
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.30 + snow * 0.25;
	AO = clamp(0.66 + mottle * 0.16 - pores * 0.30 - crack_line * 0.15 + snow * 0.16, 0.28, 1.0);
}
