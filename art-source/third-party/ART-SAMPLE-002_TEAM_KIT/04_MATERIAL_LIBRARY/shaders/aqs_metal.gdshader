shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// ART-SAMPLE-001 · 分层金属 / 涂装表面（电影质感材质样例 · 复用件）
//
// 这条 shader 覆盖：喷漆钢结构、铸铁、机加工面、橡胶、混凝土。
// 它们之所以能共用一条 shader，是因为真实世界里这几种表面的差别不在
// "用什么公式"，而在**层的顺序**与**每层的粗糙度**：
//
//     面漆（橘皮、半哑光） → 底漆（偏红、略糙） → 裸金属（镜面、边缘先露）
//        ↘ 锈（只在露金属且积水处）   ↘ 积尘（朝上、凹处）
//
// 磨损与污渍的物理原因都写在生成侧（Blender 烘焙 + 几何倒角），这里只负责
// 把它们变成可读的层。shader 不做"随机撒脏"，脏必须来自：
//   * 凸棱（曲率烘焙进 COLOR.r）—— 人手/工具/绳缆最先磨掉漆的地方；
//   * 凹处（自遮挡烘焙进 COLOR.g）—— 灰尘与油泥积在这里；
//   * 朝上（COLOR.a）—— 落尘、雨渍；
//   * 噪声团块（COLOR.b）—— 漆面起皮的实际分布。
//
// 兼容性：Compatibility 与 Forward+ 都能跑；Forward+ 下额外吃到环境反射与 SSAO，
// Compatibility 下用 ambient_fill 保住暗部（不靠提亮整张图）。
// ============================================================================

// --- 基色与层 ---
uniform vec4 paint_color : source_color = vec4(0.76, 0.72, 0.61, 1.0);
uniform vec4 primer_color : source_color = vec4(0.52, 0.30, 0.24, 1.0);
uniform vec4 bare_color : source_color = vec4(0.56, 0.575, 0.585, 1.0);
uniform vec4 rust_color : source_color = vec4(0.33, 0.17, 0.09, 1.0);
uniform vec4 dust_color : source_color = vec4(0.55, 0.50, 0.43, 1.0);

// --- 材质族参数 ---
uniform float metallic_paint : hint_range(0.0, 1.0) = 0.12;
uniform float metallic_bare : hint_range(0.0, 1.0) = 1.0;
uniform float rough_paint : hint_range(0.02, 1.0) = 0.44;
uniform float rough_bare : hint_range(0.02, 1.0) = 0.26;
uniform float rough_rust : hint_range(0.02, 1.0) = 0.86;
uniform float specular_level : hint_range(0.0, 1.0) = 0.5;

// --- 磨损 / 破损 / 锈 / 脏 ---
uniform float wear_gain : hint_range(0.0, 3.0) = 1.0;      // 凸棱磨损强度
uniform float chip_threshold : hint_range(0.0, 1.5) = 0.62; // 高于此值开始掉漆
uniform float chip_gain : hint_range(0.0, 2.0) = 1.0;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.55;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.45;
uniform float streak_amount : hint_range(0.0, 1.0) = 0.55;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.55;
uniform float cavity_amount : hint_range(0.0, 1.0) = 0.75;
uniform float edge_rim : hint_range(0.0, 1.0) = 0.35;

// --- 细节法线 / 粗糙度贴图（三平面，无需 UV）---
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_rough : filter_linear_mipmap, repeat_enable;
uniform bool use_detail = false;
uniform float detail_scale : hint_range(0.05, 12.0) = 1.2;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.75;
uniform float rough_variation : hint_range(0.0, 0.5) = 0.14;

// --- 兜底环境项（Compatibility 下没有环境反射 / SSAO）---
uniform float ambient_fill : hint_range(0.0, 1.0) = 0.12;
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

// 三平面法线扰动（世界空间）。用世界轴向当切/副切，不依赖 UV 与切线。
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
	float a = texture(tex, p.zy * scale).r;
	float b = texture(tex, p.xz * scale).r;
	float c = texture(tex, p.xy * scale).r;
	return a * w.x + b * w.y + c * w.z;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_world;
	vec3 nw = normalize(v_world_n);

	// ---- 几何遮罩（Blender 烘焙：r=凸棱磨损 g=自遮挡 b=起皮斑 a=朝上程度）----
	float mask_wear = COLOR.r;
	float mask_ao = COLOR.g;
	float mask_chip = COLOR.b;
	float mask_up = COLOR.a;

	// ---- 起皮：噪声团块 + 凸棱加成（漆是从棱边开始掉的）----
	float breakup = fbm3(p * 3.4 + world_seed) * 0.65 + vnoise3(p * 11.0 + world_seed) * 0.35;
	float wear = clamp(mask_wear * wear_gain, 0.0, 1.0);
	float chip = mask_chip * chip_gain * 0.80 + wear * 0.85 + (breakup - 0.55) * 0.30;
	float chip_s = smoothstep(chip_threshold, chip_threshold + 0.30, chip);

	// ---- 层：面漆 → 底漆 → 裸金属 ----
	vec3 col = paint_color.rgb;
	float rough = rough_paint;
	float metal = metallic_paint;

	float to_primer = smoothstep(0.02, 0.35, chip_s);
	col = mix(col, primer_color.rgb, to_primer * 0.85);
	rough = mix(rough, rough_paint + 0.12, to_primer);

	float to_bare = smoothstep(0.45, 0.95, chip_s);
	col = mix(col, bare_color.rgb, to_bare);
	rough = mix(rough, rough_bare, to_bare);
	metal = mix(metal, metallic_bare, to_bare);

	// ---- 锈：只在裸金属上、并且需要积水/滞潮（朝上或凹处）----
	float rust_n = smoothstep(0.52, 0.86, fbm3(p * 1.7 + 12.0 + world_seed));
	float rust = to_bare * rust_n * rust_amount * (0.45 + 0.55 * max(mask_up, mask_ao * 0.8));
	col = mix(col, rust_color.rgb * (0.7 + 0.6 * rust_n), rust);
	rough = mix(rough, rough_rust, rust);
	metal = mix(metal, 0.0, rust * 0.8);

	// ---- 油泥/脏：凹处（自遮挡）+ 低频噪声；朝下的面更脏 ----
	float down = clamp(0.5 - nw.y * 0.5, 0.0, 1.0);
	float grime_n = fbm3(p * 2.2 + 31.0 + world_seed);
	float grime = clamp(grime_n * 0.55 + mask_ao * 0.95 + down * 0.30, 0.0, 1.4);
	grime = smoothstep(0.35, 1.05, grime) * grime_amount;
	// ---- 贴地脏污：地面以上 ~1 m 是溅水/脚踩/搬运的落脏带（有物理成因）----
	float ground_dirt = smoothstep(1.10, 0.10, p.y) * 0.9;
	grime = clamp(grime + ground_dirt * 0.60, 0.0, 1.6);
	// 大尺度明度斑块：同一块漆在不同位置有不同明度（避免整面均匀）
	float patch = fbm3(p * 0.55 + 5.0 + world_seed) - 0.5;
	col *= 1.0 + patch * 0.24;
	col = mix(col, col * vec3(0.48, 0.46, 0.43), grime * 0.85);
	rough = mix(rough, min(1.0, rough + 0.22), grime * 0.6);

	// ---- 竖向流痕（雨水/油从紧固件与接缝往下淌）----
	float streak_coord = fbm3(vec3(p.x * 3.1, p.y * 0.22, p.z * 3.1) + world_seed);
	float streak = smoothstep(0.55, 0.92, streak_coord) * streak_amount;
	streak *= smoothstep(0.35, 1.0, mask_ao * 0.6 + 0.45 + down * 0.5);
	col = mix(col, col * vec3(0.62, 0.60, 0.56), streak * 0.7);

	// ---- 积尘：朝上的面积尘（与落尘噪声一起），凹处更厚 ----
	float dust_n = fbm3(p * 4.3 + 71.0 + world_seed);
	float dust = smoothstep(0.42, 0.95, mask_up * 0.75 + mask_ao * 0.55 + dust_n * 0.35);
	dust *= dust_amount;
	col = mix(col, dust_color.rgb * (0.75 + 0.35 * dust_n), dust * 0.55);
	rough = mix(rough, 0.92, dust * 0.45);

	// ---- 自遮挡压暗（接触阴影：Compatibility 下没有 SSAO，这一步是唯一的来源）----
	float ao_dark = 1.0 - clamp(mask_ao, 0.0, 1.0) * cavity_amount * 0.85;
	col *= ao_dark;
	rough = mix(rough, min(1.0, rough + 0.10), mask_ao * cavity_amount * 0.5);

	// ---- 细节法线（近景：橘皮 / 麻点 / 刀纹）----
	vec3 n_final = nw;
	if (use_detail) {
		n_final = normalize(nw + triplanar_perturb(p, nw, detail_scale, detail_strength));
		float rv = triplanar_scalar(detail_rough, p, nw, detail_scale);
		rough = clamp(mix(rough, rough * (0.75 + 0.55 * rv), 0.55), 0.03, 1.0);
	}
	rough = clamp(rough + (fbm3(p * 0.7) - 0.5) * rough_variation, 0.03, 1.0);

	// ---- 边缘棱线：金属在棱上会亮一条（读作"这是铁不是塑料"）----
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	col += bare_color.rgb * fres * edge_rim * 0.55 * (0.30 + 0.70 * to_bare);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = specular_level;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_final, 0.0)).xyz);
	// 兜底环境项：只补一点点，避免暗部死黑（Forward+ 下几乎无感）
	EMISSION = col * ambient_fill * 0.10;
}

