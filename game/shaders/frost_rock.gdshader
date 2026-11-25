shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 霜烬星 · 基岩与冰脊族。
//
// 对齐标准第 2 条“自然环境必须有真实的地质形态”：层理厚度不均、层间有硬错台、
// 解理面朝上、裂隙有锐边。层理由世界高度驱动并以低频噪声扰动，所以同一堵墙也
// 不会出现等距条纹。雪与霜只落在朝上的面与裂隙里，与主光方向一致。

uniform vec4 base_color : source_color = vec4(0.20, 0.27, 0.33, 1.0);
uniform vec4 layer_color : source_color = vec4(0.31, 0.38, 0.43, 1.0);
uniform vec4 dark_color : source_color = vec4(0.10, 0.14, 0.19, 1.0);
uniform vec4 frost_color : source_color = vec4(0.60, 0.74, 0.83, 1.0);
uniform vec4 snow_color : source_color = vec4(0.85, 0.91, 0.96, 1.0);

uniform float layer_height = 0.62;
uniform float layer_jitter = 0.55;
uniform float ledge_strength = 0.55;
uniform float frost_amount = 0.55;
uniform float snow_amount = 0.85;
uniform float crack_amount = 0.6;
uniform float roughness_base = 0.86;
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
		p = p * 2.07 + vec3(3.7, 6.1, 2.9);
		amplitude *= 0.46;
	}
	return value;
}

float ridged(vec3 p) {
	float value = 0.0;
	float amplitude = 0.6;
	for (int i = 0; i < 3; i++) {
		float r = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
		value += r * r * amplitude;
		p = p * 2.11;
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
	float side = 1.0 - clamp(n.y, 0.0, 1.0);
	float up = smoothstep(0.35, 0.90, n.y);

	// 层理：高度做基准，低频噪声扰动层界，形成厚薄不一的岩层与错台。
	float warp = fbm(world_pos * 0.11 + vec3(variation * 7.0)) * layer_jitter;
	float strata = (world_pos.y / layer_height) + warp;
	float band = floor(strata);
	float in_band = fract(strata);

	float layer_hash = hash31(vec3(band * 1.37, band * 0.71 + variation * 17.0, band * 2.11));
	vec3 band_color = mix(base_color.rgb, layer_color.rgb, layer_hash * 0.85);
	// 层间错台：靠近层底的一条暗边 + 一条被磨亮的上棱。
	float foot = 1.0 - smoothstep(0.0, 0.14, in_band);
	float lip = smoothstep(0.72, 0.88, in_band) * (1.0 - smoothstep(0.92, 1.0, in_band));
	band_color *= 1.0 - foot * ledge_strength * 0.55;
	band_color = mix(band_color, layer_color.rgb * 1.22, lip * ledge_strength * 0.35);

	float macro = fbm(world_pos * 0.06 + vec3(variation * 3.0));
	float detail = fbm(world_pos * 0.62 + vec3(variation * 13.0));
	vec3 albedo = band_color * (0.84 + macro * 0.28 + detail * 0.12);

	// 解理：锐利的斜向裂纹，只在侧面出现，越靠裂隙越暗。
	float crack = ridged(vec3(world_pos.x * 0.85, world_pos.y * 0.25 + variation * 5.0, world_pos.z * 0.85));
	float crack_line = smoothstep(0.74, 0.92, crack) * side;
	albedo = mix(albedo, dark_color.rgb, crack_line * crack_amount);

	// 霜壳：朝下/背光的岩面结一层发白的霜，边界被噪声咬碎。
	float frost = smoothstep(0.42, 0.78, fbm(world_pos * 0.42 + vec3(variation * 19.0))) * side * frost_amount;
	albedo = mix(albedo, frost_color.rgb, frost * 0.45);

	// 积雪：朝上的台面与裂隙口实际会存住雪。
	float snow_noise = fbm(world_pos * 0.34 + vec3(variation * 23.0));
	float ledge_snow = up * smoothstep(0.34, 0.62, snow_noise + (1.0 - in_band) * 0.18);
	float snow = max(ledge_snow, crack_line * 0.55) * snow_amount;
	albedo = mix(albedo, snow_color.rgb, snow);

	float rough = clamp(roughness_base + detail * 0.10 - snow * 0.45 - frost * 0.10, 0.22, 1.0);
	ALBEDO = clamp(albedo, vec3(0.012), vec3(0.93));
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.28 + frost * 0.18;
	AO = clamp(0.55 + lip * 0.18 - foot * 0.28 + snow * 0.22 - crack_line * 0.22, 0.22, 1.0);
}
