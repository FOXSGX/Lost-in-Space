shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// ART-SAMPLE-001 · 层理基岩（复用件）
//
// 岩石在近景里"不像石头"通常不是因为噪声不够，而是缺三件事：
//   1. **层次**：层理要有厚度差、有色差、层间有真实的凹槽（不是均匀条纹）；
//   2. **断裂面**：解理面是平的、棱是锐的、棱上比面上干净（新断口没风化）；
//   3. **积尘与潮气**：朝上的面落尘、贴地的面滞潮、凹处积土。
//
// 顶点遮罩约定（Blender `bake_masks()` 烘进 COLOR）：
//   R = 锐棱（凸）→ 新鲜断面：更亮、更冷、更干
//   G = 自遮挡 → 凹处压暗 + 滞潮
//   B = 斑块 → 苔/水渍/崩落坑的分布
//   A = 朝上 → 落尘与风化色
// ============================================================================

uniform vec4 stone_a : source_color = vec4(0.300, 0.248, 0.202, 1.0);
uniform vec4 stone_b : source_color = vec4(0.150, 0.126, 0.106, 1.0);
uniform vec4 stone_c : source_color = vec4(0.398, 0.336, 0.276, 1.0);
uniform vec4 fresh_color : source_color = vec4(0.455, 0.412, 0.366, 1.0);
uniform vec4 dust_color : source_color = vec4(0.400, 0.352, 0.292, 1.0);
uniform vec4 damp_color : source_color = vec4(0.118, 0.126, 0.118, 1.0);

uniform float strata_period : hint_range(0.05, 1.2) = 0.24;   // 层厚（米）
uniform float strata_strength : hint_range(0.0, 1.0) = 0.55;
uniform float strata_warp : hint_range(0.0, 1.5) = 0.45;
// 0 = 岩壁/岩块（层理沿世界 y）；1 = 地面（改用径向沉积纹，避免平地上出现横条）
uniform float ground_mode : hint_range(0.0, 1.0) = 0.0;
uniform float facet_contrast : hint_range(0.0, 1.0) = 0.35;
uniform float arris_gain : hint_range(0.0, 2.0) = 0.9;
uniform float cavity_gain : hint_range(0.0, 1.5) = 0.9;
uniform float dust_gain : hint_range(0.0, 1.0) = 0.55;
uniform float damp_height : hint_range(0.0, 3.0) = 0.55;
uniform float damp_strength : hint_range(0.0, 1.0) = 0.45;
uniform float patch_gain : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_rough : filter_linear_mipmap, repeat_enable;
uniform bool use_detail = false;
uniform float detail_scale : hint_range(0.1, 12.0) = 3.2;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.65;

uniform float ambient_fill : hint_range(0.0, 1.0) = 0.10;
uniform float world_seed = 0.0;

varying vec3 v_world;
varying vec3 v_world_n;

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

vec3 triplanar_perturb(vec3 p, vec3 n, float scale, float strength) {
	vec3 w = pow(abs(n), vec3(5.0));
	w /= max(1e-4, w.x + w.y + w.z);
	vec3 tx = texture(detail_normal, p.zy * scale).xyz * 2.0 - 1.0;
	vec3 ty = texture(detail_normal, p.xz * scale).xyz * 2.0 - 1.0;
	vec3 tz = texture(detail_normal, p.xy * scale).xyz * 2.0 - 1.0;
	vec3 ox = vec3(0.0, tx.x, tx.y);
	vec3 oy = vec3(ty.x, 0.0, ty.y);
	vec3 oz = vec3(tz.x, tz.y, 0.0);
	return (ox * w.x + oy * w.y + oz * w.z) * strength;
}

float triplanar_scalar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(5.0));
	w /= max(1e-4, w.x + w.y + w.z);
	return texture(tex, p.zy * scale).r * w.x + texture(tex, p.xz * scale).r * w.y
		 + texture(tex, p.xy * scale).r * w.z;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_world;
	vec3 nw = normalize(v_world_n);
	float arris = COLOR.r;
	float ao = COLOR.g;
	float patch = COLOR.b;
	float up = COLOR.a;

	// ---- 层理：厚度不均 + 层间凹槽 + 每层独立色 ----
	float warp = fbm3(p * 0.55 + world_seed) * strata_warp;
	float band_coord = mix(p.y, length(p.xz) * 0.55 + fbm3(p.xzz * 0.7) * 0.8, ground_mode);
	float band = band_coord / strata_period + warp * 1.6;
	float layer = fract(band);
	float layer_id = floor(band);
	float layer_rand = hash13(vec3(layer_id * 0.41, 2.7, 1.3));
	float seam = smoothstep(0.0, 0.12, layer) * smoothstep(1.0, 0.88, layer);
	float groove = 1.0 - seam;

	vec3 stone = mix(stone_a.rgb, stone_b.rgb, smoothstep(0.3, 0.8, fbm3(p * 1.1 + 4.0)));
	stone = mix(stone, stone_c.rgb, smoothstep(0.55, 0.9, fbm3(p * 2.9 + 9.0)) * patch_gain);
	stone *= 0.80 + 0.42 * layer_rand;
	stone *= mix(1.0, 0.55, groove * strata_strength);

	// ---- 断裂面：锐棱上新、面上旧（风化色只长在平面与凹处）----
	float fresh = smoothstep(0.20, 0.85, arris) * arris_gain;
	stone = mix(stone, fresh_color.rgb * (0.85 + 0.3 * layer_rand), fresh * 0.75);

	// ---- 面与面之间的明暗差：让解理面彼此可分辨（不是一整块噪声）----
	float facet = (abs(nw.x) * 0.5 + abs(nw.z) * 0.5) * 0.5 + abs(nw.y) * 0.25;
	stone *= 1.0 - facet_contrast * (0.55 - facet) * 0.6;

	// ---- 贴地滞潮 + 凹处积土 ----
	float low = smoothstep(damp_height, 0.0, p.y);
	stone = mix(stone, damp_color.rgb, low * damp_strength * 0.7);
	float dirt = smoothstep(0.25, 0.95, ao * 1.2 + low * 0.8);
	stone = mix(stone, stone * vec3(0.62, 0.58, 0.52), dirt * 0.55);

	// ---- 落尘与风化色（朝上的面）----
	float dust_n = fbm3(p * 3.7 + 51.0 + world_seed);
	float dust = smoothstep(0.35, 0.95, up * 0.7 + dust_n * 0.45) * dust_gain;
	stone = mix(stone, dust_color.rgb * (0.8 + 0.3 * dust_n), dust * 0.5);

	// ---- 崩落坑 / 水渍斑 ----
	float pit = smoothstep(0.62, 0.92, patch);
	stone *= 1.0 - pit * 0.30;

	// ---- 自遮挡压暗（接触阴影）----
	stone *= 1.0 - clamp(ao, 0.0, 1.0) * cavity_gain * 0.80;

	float rough = clamp(0.90 - fresh * 0.22 - low * 0.10 + pit * 0.05, 0.45, 1.0);
	vec3 n_final = nw;
	if (use_detail) {
		n_final = normalize(nw + triplanar_perturb(p, nw, detail_scale, detail_strength));
		float rv = triplanar_scalar(detail_rough, p, nw, detail_scale);
		rough = clamp(mix(rough, rough * (0.85 + 0.3 * rv), 0.5), 0.4, 1.0);
	}
	// 细节法线也要吃层的方向：层理凹槽给一点点沿 y 的坡度
	n_final = normalize(n_final + vec3(0.0, groove * strata_strength * 0.35, 0.0));

	ALBEDO = stone;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.28;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_final, 0.0)).xyz);
	EMISSION = stone * ambient_fill * 0.12;
}
