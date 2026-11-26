shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// ART-SYNC-001 · 奶龙星球场地面（世界空间三级尺度）
//
// 借鉴共振星 ART-ENV-004/005/008 地面体系里"不依赖 UV / 顶点色"的部分：
//   大尺度（5–20 m）：材质分区 + 低频明度漂移（不是一整块同色板）
//   中尺度（0.3–3 m）：踩踏带（沿 X 的球路）、车辙（z=±0.87 两条方向性沟）、
//                      积尘（只在朝上的低频斑块）、矿物碎屑（点，不成片）
//   小尺度（1–20 cm）：颗粒、微裂纹、粗糙度起伏、法线微扰
// 混凝土模式（concrete_mode=1）额外给：骨料色差、模板缝、拆模崩边。
//
// 为什么不用贴图：本项目几何是运行时生成的盒子，没有 UV，也没有烘焙顶点色；
// 所以所有遮罩都用世界坐标与法线现算，代价是几次 fbm，收益是任何缩放都不拉伸。
// ============================================================================

uniform vec4 base_color : source_color = vec4(0.660, 0.628, 0.548, 1.0);
uniform vec4 warm_color : source_color = vec4(0.720, 0.672, 0.572, 1.0);
uniform vec4 cool_color : source_color = vec4(0.372, 0.436, 0.408, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.462, 0.404, 0.322, 1.0);
uniform vec4 dust_color : source_color = vec4(0.742, 0.700, 0.604, 1.0);
uniform vec4 compact_color : source_color = vec4(0.418, 0.376, 0.306, 1.0);
uniform vec4 mineral_color : source_color = vec4(0.586, 0.632, 0.604, 1.0);
uniform vec4 crack_color : source_color = vec4(0.212, 0.196, 0.168, 1.0);

uniform float concrete_mode : hint_range(0.0, 1.0) = 0.0;

// 球场路带：沿 X 方向，z 在 [center-half, center+half] 内是经常被踩/被球滚的地方
uniform float path_center_z = 0.0;
uniform float path_half_width : hint_range(0.2, 12.0) = 2.10;
uniform float wear_gain : hint_range(0.0, 2.0) = 0.70;

// 车辙：两条平行沟，间距 rut_gauge（玩家视线的"球场推车辙"）
uniform float rut_gauge : hint_range(0.2, 4.0) = 0.87;
uniform float rut_gain : hint_range(0.0, 2.0) = 0.55;

uniform float dust_gain : hint_range(0.0, 2.0) = 0.85;
uniform float mineral_gain : hint_range(0.0, 2.0) = 0.60;
uniform float crack_gain : hint_range(0.0, 2.0) = 0.75;
uniform float grain_gain : hint_range(0.0, 2.0) = 0.55;

uniform float rough_base : hint_range(0.2, 1.0) = 0.86;
uniform float rough_var : hint_range(0.0, 0.6) = 0.16;
uniform float ao_gain : hint_range(0.0, 1.5) = 0.55;
uniform float ambient_fill : hint_range(0.0, 1.0) = 0.16;

uniform float zone_scale : hint_range(0.01, 0.5) = 0.070;
uniform float mid_scale : hint_range(0.1, 3.0) = 0.55;
uniform float fine_scale : hint_range(2.0, 30.0) = 7.5;
uniform float world_seed = 0.0;

varying vec3 v_world;
varying vec3 v_wn;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	return vnoise3(p) * 0.55 + vnoise3(p * 2.13) * 0.28 + vnoise3(p * 4.31) * 0.17;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_world;
	vec3 nw = normalize(v_wn);
	float up = smoothstep(0.25, 0.85, nw.y);

	float z1 = fbm3(p * zone_scale + world_seed * 0.37 + 3.1);
	float z2 = fbm3(p * mid_scale + world_seed * 0.71 + 11.7);
	float z3 = fbm3(p * fine_scale + world_seed * 1.13 + 21.3);

	// ---- 大尺度：材质分区（暖球场 / 冷平台 / 覆盖土）----
	vec3 base = mix(base_color.rgb, warm_color.rgb, smoothstep(0.30, 0.80, z1));
	base = mix(base, cool_color.rgb, smoothstep(0.52, 0.92, fbm3(p * zone_scale * 1.7 + 41.0)) * 0.55);
	base = mix(base, dirt_color.rgb, smoothstep(0.46, 0.86, z1 * 0.6 + z2 * 0.5) * 0.32);

	// ---- 混凝土模式：骨料 + 模板缝 + 崩边 ----
	if (concrete_mode > 0.5) {
		float agg = smoothstep(0.55, 0.95, vnoise3(p * 22.0));
		base = mix(base, compact_color.rgb * 1.35, agg * 0.22);
		base = mix(base, base_color.rgb * 1.06, 0.25);
		float sx = abs(fract(p.x / 2.40) - 0.5) * 2.40;
		float sz = abs(fract(p.z / 2.40) - 0.5) * 2.40;
		float seam = (1.0 - smoothstep(0.0, 0.035, sx)) + (1.0 - smoothstep(0.0, 0.035, sz));
		base *= 1.0 - clamp(seam, 0.0, 1.0) * 0.34;
	}

	// ---- 中尺度：球路踩踏带 ----
	float dz = abs(p.z - path_center_z);
	float lane = 1.0 - smoothstep(path_half_width * 0.35, path_half_width * 1.55, dz);
	float wear = lane * (0.55 + 0.45 * z2) * wear_gain;
	base = mix(base, mix(base, dirt_color.rgb, 0.35) * 0.88, wear * 0.55);

	// ---- 中尺度：两条方向性车辙（沿 X 拉长，靠 z 定位）----
	float wob = (fbm3(vec3(p.x * 0.28, 0.0, p.z * 3.2)) - 0.5) * 0.22;
	float d1 = abs(dz - rut_gauge * 0.5 + wob);
	float d2 = abs(dz + rut_gauge * 0.5 + wob);
	float rut = (1.0 - smoothstep(0.0, 0.085, d1)) + (1.0 - smoothstep(0.0, 0.085, d2));
	rut = clamp(rut, 0.0, 1.0) * lane * rut_gain;
	base = mix(base, compact_color.rgb * 0.92, rut * 0.55);

	// ---- 中尺度：积尘（只在朝上的低频斑块）----
	float dust_n = fbm3(p * 0.42 + 61.0 + world_seed);
	float dust = smoothstep(0.50, 0.86, dust_n) * up * dust_gain;
	base = mix(base, dust_color.rgb * (0.86 + 0.20 * z3), dust * 0.42);

	// ---- 中尺度：矿物碎屑（点，不成片）----
	float specks = smoothstep(0.86, 0.95, vnoise3(p * 9.0 + 7.0));
	base = mix(base, mineral_color.rgb, specks * mineral_gain * 0.55);

	// ---- 小尺度：颗粒 / 微裂纹 / 崩边 ----
	base *= 0.92 + 0.16 * z3 * grain_gain;
	float ridge = 1.0 - abs(fbm3(p * 3.1 + 17.0) * 2.0 - 1.0);
	float crack = smoothstep(0.90, 0.985, ridge) * crack_gain;
	base = mix(base, crack_color.rgb, crack * 0.55);

	// ---- 遮蔽：踩踏带外缘的细压暗，避免"球路像贴纸"----
	float lane_edge = (1.0 - smoothstep(0.0, 0.35, abs(lane - 0.5))) * 0.10 * wear_gain;
	base *= 1.0 - lane_edge;

	float rough = clamp(rough_base + rough_var * (z3 - 0.5) * 2.0 - wear * 0.10 + dust * 0.10 + crack * 0.12, 0.45, 1.0);

	// ---- 法线微扰：颗粒的坡度（便宜版：邻域差分）----
	float e = 0.045;
	float h0 = vnoise3(p * fine_scale * 1.7);
	float hx = vnoise3((p + vec3(e, 0.0, 0.0)) * fine_scale * 1.7);
	float hz = vnoise3((p + vec3(0.0, 0.0, e)) * fine_scale * 1.7);
	vec3 n_final = normalize(nw + vec3((h0 - hx), 0.0, (h0 - hz)) * (0.55 * grain_gain));

	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.30;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_final, 0.0)).xyz);
	AO = clamp(1.0 - (crack * 0.25 + (1.0 - lane) * ao_gain * 0.06), 0.35, 1.0);
	EMISSION = base * ambient_fill * 0.10;
}
