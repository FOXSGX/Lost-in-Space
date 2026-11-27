// 腐墟星专用副本：与 ART-SAMPLE-002 的 aqs2_* 只有一处差异——cull_disabled。
// 腐墟星几何是运行时用 SurfaceTool 生成的倒角体，绕序在部分斜面/车削体上不稳定；
// 关闭背面剔除可以保证任何朝向都可见，法线仍由生成器显式给出，光照不会错。
// 参数与磨损语汇必须继续与 ART-SAMPLE-002 保持一致，改参数请同时改原 shader。

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// ART-SAMPLE-002 · 分层金属 / 涂装 / 混凝土（v2，2K 多尺度 + 烘焙 UV 掩膜）
//
// 与 v1（aqs_metal.gdshader）的区别
// --------------------------------
// 1. **UV 已烘焙的英雄件**（锤头）：走切线空间法线 + 烘焙 AO/曲率掩膜，
//    不再靠三平面噪声模拟——高模的转折真的进到了低模上；
// 2. **2K 多尺度细节**：`detail_normal` / `detail_rough` 用 2048² 分族贴图，
//    并新增 `detail_mask`（R=起皮 G=粗糙度偏移 B=色差/骨料）；
// 3. **混凝土模式**：`concrete_mode=1` 时开启骨料色差、气孔压暗、砂浆脱落的
//    粗糙度变化，让混凝土与钢材在 1 m 内一眼可分；
// 4. 层的顺序、磨损逻辑、`BAL` 配比与 v1 完全一致（材质语言不跳变）。
// ============================================================================

uniform vec4 paint_color : source_color = vec4(0.615, 0.578, 0.488, 1.0);
uniform vec4 primer_color : source_color = vec4(0.52, 0.30, 0.24, 1.0);
uniform vec4 bare_color : source_color = vec4(0.56, 0.575, 0.585, 1.0);
uniform vec4 rust_color : source_color = vec4(0.33, 0.17, 0.09, 1.0);
uniform vec4 dust_color : source_color = vec4(0.55, 0.50, 0.43, 1.0);

uniform float metallic_paint : hint_range(0.0, 1.0) = 0.12;
uniform float metallic_bare : hint_range(0.0, 1.0) = 1.0;
uniform float rough_paint : hint_range(0.02, 1.0) = 0.44;
uniform float rough_bare : hint_range(0.02, 1.0) = 0.26;
uniform float rough_rust : hint_range(0.02, 1.0) = 0.86;
uniform float specular_level : hint_range(0.0, 1.0) = 0.5;

uniform float wear_gain : hint_range(0.0, 3.0) = 1.0;
uniform float chip_threshold : hint_range(0.0, 1.5) = 0.62;
uniform float chip_gain : hint_range(0.0, 2.0) = 1.0;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.55;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.45;
uniform float streak_amount : hint_range(0.0, 1.0) = 0.55;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.55;
uniform float cavity_amount : hint_range(0.0, 1.0) = 0.75;
uniform float edge_rim : hint_range(0.0, 1.0) = 0.35;

// ---- 三平面细节（继承件 / 非烘焙件）----
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_rough : filter_linear_mipmap, repeat_enable;
uniform bool use_detail = false;
uniform float detail_scale : hint_range(0.05, 12.0) = 1.2;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.75;
uniform float rough_variation : hint_range(0.0, 0.5) = 0.14;

// ---- 2K 掩膜（R=起皮 G=粗糙度偏移 B=色差/骨料）----
uniform sampler2D detail_mask : filter_linear_mipmap, repeat_enable;
uniform bool use_detail_mask = false;
uniform float mask_chip_gain : hint_range(0.0, 2.0) = 1.0;
uniform float mask_color_gain : hint_range(0.0, 1.0) = 0.35;
uniform float concrete_mode : hint_range(0.0, 1.0) = 0.0;

// ---- UV 烘焙件（锤头）：切线空间法线 + 烘焙曲率/AO ----
uniform sampler2D uv_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D uv_mask : filter_linear_mipmap;
uniform bool use_uv_baked = false;
uniform bool vertex_mask_valid = true;
uniform float uv_normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float uv_mask_wear : hint_range(0.0, 2.0) = 1.0;
uniform float uv_mask_cavity : hint_range(0.0, 2.0) = 1.0;
uniform float uv_micro_scale : hint_range(0.1, 16.0) = 6.0;
uniform float uv_micro_strength : hint_range(0.0, 1.0) = 0.25;

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
	vec2 uv = UV;

	// ---- 几何遮罩：顶点色（Blender 烘焙）与 UV 掩膜（高模烘焙）取最大 ----
	// 网格若没有 COLOR 属性（例如只做了 UV 烘焙的锤头），COLOR 会恒为 1，
	// 那会被误读成"整件都磨损且整件都被遮蔽"——所以用 vertex_mask_valid 显式关闭。
	float mask_wear = vertex_mask_valid ? COLOR.r : 0.0;
	float mask_ao = vertex_mask_valid ? COLOR.g : 0.0;
	float mask_chip = vertex_mask_valid ? COLOR.b : 0.0;
	float mask_up = vertex_mask_valid ? COLOR.a : clamp(nw.y * 0.5 + 0.5, 0.0, 1.0);
	float baked_curv = 0.0;
	if (use_uv_baked) {
		vec3 m = texture(uv_mask, uv).rgb;
		baked_curv = m.r;
		mask_wear = max(mask_wear, m.r * uv_mask_wear);
		mask_ao = max(mask_ao, m.g * uv_mask_cavity);
	}

	// ---- 2K 掩膜 ----
	if (use_detail_mask) {
		vec2 tuv = p.xz * 0.35;
		vec3 dm = texture(detail_mask, tuv).rgb;
		mask_chip = min(1.0, mask_chip + dm.r * mask_chip_gain * 0.6);
	}

	// ---- 起皮：噪声团块 + 凸棱加成 ----
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

	// ---- 锈：只在裸金属 + 滞潮条件 ----
	float rust_n = smoothstep(0.52, 0.86, fbm3(p * 1.7 + 12.0 + world_seed));
	float rust = to_bare * rust_n * rust_amount * (0.45 + 0.55 * max(mask_up, mask_ao * 0.8));
	col = mix(col, rust_color.rgb * (0.7 + 0.6 * rust_n), rust);
	rough = mix(rough, rough_rust, rust);
	metal = mix(metal, 0.0, rust * 0.8);

	// ---- 油泥/脏：凹处 + 贴地 + 朝下 ----
	float down = clamp(0.5 - nw.y * 0.5, 0.0, 1.0);
	float grime_n = fbm3(p * 2.2 + 31.0 + world_seed);
	float grime = clamp(grime_n * 0.55 + mask_ao * 0.95 + down * 0.30, 0.0, 1.4);
	float ground_dirt = smoothstep(1.10, 0.10, p.y) * 0.9;
	grime = clamp(grime + ground_dirt * 0.60, 0.0, 1.6);
	grime = smoothstep(0.35, 1.05, grime) * grime_amount;
	float patch = fbm3(p * 0.55 + 5.0 + world_seed) - 0.5;
	col *= 1.0 + patch * 0.24;
	col = mix(col, col * vec3(0.48, 0.46, 0.43), grime * 0.85);
	rough = mix(rough, min(1.0, rough + 0.22), grime * 0.6);

	// ---- 竖向流痕 ----
	float streak_coord = fbm3(vec3(p.x * 3.1, p.y * 0.22, p.z * 3.1) + world_seed);
	float streak = smoothstep(0.55, 0.92, streak_coord) * streak_amount;
	streak *= smoothstep(0.35, 1.0, mask_ao * 0.6 + 0.45 + down * 0.5);
	col = mix(col, col * vec3(0.62, 0.60, 0.56), streak * 0.7);

	// ---- 积尘 ----
	float dust_n = fbm3(p * 4.3 + 71.0 + world_seed);
	float dust = smoothstep(0.42, 0.95, mask_up * 0.75 + mask_ao * 0.55 + dust_n * 0.35);
	dust *= dust_amount;
	col = mix(col, dust_color.rgb * (0.75 + 0.35 * dust_n), dust * 0.55);
	rough = mix(rough, 0.92, dust * 0.45);

	// ---- 自遮挡压暗（接触阴影）----
	float ao_dark = 1.0 - clamp(mask_ao, 0.0, 1.0) * cavity_amount * 0.85;
	col *= ao_dark;
	rough = mix(rough, min(1.0, rough + 0.10), mask_ao * cavity_amount * 0.5);

	// ---- 法线：UV 烘焙（英雄件）优先，其余走三平面细节 ----
	vec3 n_final = nw;
	if (use_uv_baked) {
		vec3 nt = texture(uv_normal, uv).xyz * 2.0 - 1.0;
		nt.xy *= uv_normal_strength;
		vec3 nb = normalize(TANGENT * nt.x + BINORMAL * nt.y + NORMAL * nt.z);
		// 再叠一层极细的微观起伏（避免"法线贴图糊在有 UV 的面上显得干净过头"）
		vec3 micro = triplanar_perturb(p, nw, uv_micro_scale, uv_micro_strength);
		vec3 nw2 = normalize(nw + micro);
		vec3 nb2 = normalize(TANGENT * nt.x + BINORMAL * nt.y + NORMAL * nt.z);
		NORMAL = normalize(mix(nb2, normalize((VIEW_MATRIX * vec4(nw2, 0.0)).xyz), 0.35));
		float rv = triplanar_scalar(detail_rough, p, nw, uv_micro_scale);
		rough = clamp(mix(rough, rough * (0.85 + 0.3 * rv), 0.4), 0.03, 1.0);
	} else if (use_detail) {
		n_final = normalize(nw + triplanar_perturb(p, nw, detail_scale, detail_strength));
		float rv = triplanar_scalar(detail_rough, p, nw, detail_scale);
		rough = clamp(mix(rough, rough * (0.75 + 0.55 * rv), 0.55), 0.03, 1.0);
		NORMAL = normalize((VIEW_MATRIX * vec4(n_final, 0.0)).xyz);
	}

	// ---- 混凝土模式：骨料色差 + 气孔 + 砂浆脱落 ----
	if (concrete_mode > 0.5) {
		vec2 cuv = p.xz * 0.9;
		vec3 cm = texture(detail_mask, cuv).rgb;
		// 骨料：中尺度色差（浅色石英 / 深色碎石）
		float agg = cm.b;
		col *= 0.86 + 0.26 * agg;
		col = mix(col, col * vec3(1.06, 1.02, 0.96), smoothstep(0.6, 0.9, agg) * 0.5);
		// 气孔：压暗 + 提高粗糙度
		float pore = cm.g;
		col *= 1.0 - pore * 0.22;
		rough = clamp(rough + pore * 0.10 - agg * 0.06, 0.2, 1.0);
		// 砂浆脱落：更亮更糙（露出骨料床）
		float spall = cm.r;
		col = mix(col, col * vec3(1.10, 1.05, 0.98), spall * 0.55);
		rough = mix(rough, 0.95, spall * 0.6);
		metal = 0.0;
	}

	rough = clamp(rough + (fbm3(p * 0.7) - 0.5) * rough_variation, 0.03, 1.0);

	// ---- 边缘棱线 ----
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	col += bare_color.rgb * fres * edge_rim * 0.55 * (0.30 + 0.70 * to_bare)
		 * (0.35 + 0.65 * baked_curv);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = specular_level;
	EMISSION = col * ambient_fill * 0.10;
}

