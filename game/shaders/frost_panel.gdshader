shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 霜烬星 · 涂装钢构族（站房墙板、屋面、门框、设备箱体、混凝土基座共用一套语汇）。
//
// 对齐 ART-PLANET-VISUAL-STANDARD v1 的第 4 条“材质必须体现使用历史”：
//   面漆 → 底漆 → 裸金属 的分层，磨损出现在板缝、铆钉、棱边，积垢在凹处，
//   落雪在朝上的面。全部由世界坐标生成，不用贴图、不依赖 UV，远景近景同一套。
//   混凝土由 concrete_mode 切换为骨料 / 气孔 / 模板缝，与钢材一眼可分。

uniform vec4 paint_color : source_color = vec4(0.72, 0.71, 0.66, 1.0);
uniform vec4 primer_color : source_color = vec4(0.44, 0.27, 0.20, 1.0);
uniform vec4 bare_color : source_color = vec4(0.55, 0.57, 0.58, 1.0);
uniform vec4 accent_color : source_color = vec4(0.30, 0.62, 0.66, 1.0);
uniform vec4 snow_color : source_color = vec4(0.86, 0.92, 0.96, 1.0);
uniform vec4 grime_color : source_color = vec4(0.16, 0.17, 0.18, 1.0);
uniform vec4 emission_color : source_color = vec4(0.95, 0.85, 0.62, 1.0);

uniform vec2 panel_size = vec2(1.55, 0.92);
uniform float seam_width = 0.028;
uniform float rivet_amount = 1.0;
uniform float stripe_height = 0.85;
uniform float stripe_mix = 0.85;
uniform float chip_threshold = 0.62;
uniform float wear_gain = 1.0;
uniform float snow_amount = 1.0;
uniform float grime_amount = 0.55;
uniform float metallic_paint = 0.10;
uniform float roughness_base = 0.46;
uniform float concrete_mode = 0.0;
uniform float emission_strength = 0.0;
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
		p = p * 2.03 + vec3(5.1, 3.3, 7.7);
		amplitude *= 0.48;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);

	// 混凝土提前分支：屋面和地坪是全场最大的填充面积，不能先算一遍板缝与掉漆再覆盖。
	if (concrete_mode > 0.5) {
		float up_c = smoothstep(0.35, 0.90, n.y);
		float agg = vnoise(world_pos * 26.0 + vec3(variation * 5.0));
		float pores = smoothstep(0.66, 0.94, vnoise(world_pos * 46.0 + vec3(variation * 9.0)));
		float board = 1.0 - smoothstep(0.0, 0.05, abs(fract(world_pos.y * 1.9) - 0.5) - 0.46);
		float snow_noise_c = fbm(world_pos * 0.62 + vec3(variation * 17.0));
		float low_c = 1.0 - smoothstep(0.0, 1.6, world_pos.y);
		vec3 albedo_c = paint_color.rgb * (0.84 + agg * 0.30);
		albedo_c = mix(albedo_c, paint_color.rgb * 1.18, pores * 0.55);
		albedo_c *= 1.0 - clamp(board, 0.0, 1.0) * 0.12;
		albedo_c = mix(albedo_c, snow_color.rgb * (0.94 + 0.06 * snow_noise_c), clamp(up_c * (0.82 + 0.18 * smoothstep(0.30, 0.70, snow_noise_c)) * snow_amount, 0.0, 1.0));
		albedo_c = mix(albedo_c, grime_color.rgb, low_c * 0.16 * grime_amount);
		ALBEDO = clamp(albedo_c, vec3(0.02), vec3(0.94));
		ROUGHNESS = clamp(roughness_base + agg * 0.08 - up_c * snow_amount * 0.16 + pores * 0.10, 0.30, 0.98);
		METALLIC = 0.0;
		SPECULAR = 0.35;
		AO = clamp(0.72 + agg * 0.14 - pores * 0.22 + up_c * 0.10, 0.35, 1.0);
	} else {

	vec3 an = abs(n);
	vec2 uv;
	float upright = 1.0;
	if (an.x >= an.y && an.x >= an.z) {
		uv = world_pos.zy;
		upright = 0.0;
	} else if (an.y >= an.z) {
		uv = world_pos.xz;
		upright = 0.0;
	} else {
		uv = world_pos.xy;
	}
	vec2 cell = uv / panel_size + vec2(variation * 13.0, variation * 7.0);
	vec2 f = fract(cell);
	// 每块板自己的色差：同一面墙上的板不是复制粘贴，喷漆批次本来就会有深浅。
	float panel_hash = hash31(vec3(floor(cell), variation * 37.0));
	vec2 edge_m = min(f, 1.0 - f) * panel_size;
	float edge_min = min(edge_m.x, edge_m.y);

	// 板缝：核心凹槽 + 外侧 3 mm 高光倒角，读得出“这是分块压出来的钢板”。
	float seam_core = 1.0 - smoothstep(0.0, seam_width, edge_min);
	float seam_soft = 1.0 - smoothstep(0.0, seam_width * 2.4, edge_min);
	float chamfer = smoothstep(seam_width, seam_width * 2.6, edge_min) * seam_soft;

	// 铆钉：只出现在竖板四角，间距随板缝网格走，不做满屏螺栓。
	vec2 half_cell = panel_size * 0.5;
	vec2 inset = abs(f - 0.5) * panel_size;
	vec2 to_corner = inset - (half_cell - vec2(0.085, 0.085));
	float rivet_d = length(to_corner);
	float rivet = (1.0 - smoothstep(0.012, 0.032, rivet_d)) * upright * rivet_amount;

	float grain = vnoise(vec3(uv * 2.35, variation * 11.0));
	// 起皮是毫米到厘米级的片状剥落：高频噪声 + 窄过渡，近景才不会糊成泥点。
	float chip_noise = fbm(vec3(uv * 13.0, world_pos.y * 0.35) + vec3(variation * 23.0, 0.0, 3.0));

	// 磨损集中在板缝、铆钉、墙脚与窗体上沿；不随机撒脏。
	float low = 1.0 - smoothstep(0.0, 1.6, world_pos.y);
	float streak = smoothstep(0.56, 0.94, fbm(vec3(uv.x * 1.6, world_pos.y * 0.55, variation * 31.0)));
	float edge_wear = clamp(seam_soft * 0.55 + rivet * 0.35 + low * 0.30, 0.0, 1.0) * wear_gain;

	// 掉漆不是随机撒点：起皮先出现在板缝与铆钉周边，再沿竖向流痕往下拖。
	float chip_base = smoothstep(chip_threshold, chip_threshold + 0.05, chip_noise);
	float chip_anchor = clamp(0.18 + seam_soft * 0.95 + rivet * 0.55 + streak * 0.30, 0.0, 1.0);
	float chip_mask = chip_base * chip_anchor;

	vec3 albedo = paint_color.rgb;
	// 踢脚带：一栋一个主色的下沿护板，既有识别性，也挡住墙脚积垢。
	float kick = 1.0 - smoothstep(stripe_height - 0.03, stripe_height, world_pos.y);
	albedo = mix(albedo, accent_color.rgb, kick * stripe_mix * upright);
	albedo = mix(albedo, primer_color.rgb, chip_mask * 0.62);
	albedo = mix(albedo, bare_color.rgb, chip_mask * 0.30 + rivet * 0.25);
	albedo *= 0.88 + grain * 0.24;
	albedo *= 0.93 + panel_hash * 0.13;

	// 雪：只落在朝上的面积与板缝的浅台上，边界由噪声撕开。
	float up = smoothstep(0.42, 0.92, n.y);
	float snow_noise = fbm(world_pos * 0.62 + vec3(variation * 17.0));
	float snow = up * smoothstep(0.40, 0.66, snow_noise + 0.18) * snow_amount;
	snow = max(snow, seam_soft * up * 0.85 * snow_amount);
	albedo = mix(albedo, snow_color.rgb, snow);

	// 积垢：竖向流痕 + 墙脚堆积，落在凹处而不是随机。
	float grime = clamp(seam_core * 0.75 + low * 0.55 + streak * 0.20, 0.0, 1.0) * grime_amount;
	albedo = mix(albedo, grime_color.rgb, grime * 0.42);

	float rough = roughness_base + grain * 0.10 + chip_mask * 0.24 - snow * 0.30 + chamfer * 0.04;
	float metal = metallic_paint * (1.0 - chip_mask) + chip_mask * 0.22 * (1.0 - snow);

	ALBEDO = clamp(albedo, vec3(0.012), vec3(0.94));
	ROUGHNESS = clamp(rough, 0.12, 0.98);
	METALLIC = clamp(metal, 0.0, 0.9);
	SPECULAR = 0.42 + seam_core * 0.10;
	AO = clamp(0.62 + chamfer * 0.22 - seam_core * 0.40 + snow * 0.20, 0.22, 1.0);
	}

	if (emission_strength > 0.001) {
		EMISSION = emission_color.rgb * emission_strength;
	}
}
