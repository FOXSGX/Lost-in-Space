shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

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
// 白色/浅色涂装在强光下会整体裁切到 1.0（细节全丢）。这两项沿用 aenv4 的
// 反过曝做法：spec_cap 限制镜面峰值，hi_rolloff 对 albedo 做一次软膝压缩。
uniform float spec_cap : hint_range(0.0, 1.0) = 1.0;
uniform float hi_rolloff : hint_range(0.0, 1.0) = 0.0;

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
uniform float uv_curv_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float uv_micro_scale : hint_range(0.1, 16.0) = 6.0;
uniform float uv_micro_strength : hint_range(0.0, 1.0) = 0.25;

uniform float ambient_fill : hint_range(0.0, 1.0) = 0.12;
uniform float world_seed = 0.0;

// ---- M1 增补：给"大平面建筑壳体"用的降噪开关（默认值保持 v2 外观不变）----
// 2K 分族掩膜原本按世界坐标 p.xz*0.35 采样，对 8 m 的墙板等于每 2.85 m 铺一张
// 带曲率/AO 的掩膜 —— 在玩家眼里就是"整面墙的斑驳色块"。烘焙过 UV 的资产
// 打开 `detail_uv_space` 后，掩膜改走 UV（每件资产自己的图集 tile），
// 磨损/积灰才会贴着真实的折边与缝隙生长。
uniform bool detail_uv_space = false;
uniform float detail_uv_scale : hint_range(0.1, 8.0) = 1.0;
// 2 m 级色块漂移的强度与尺度（建筑壳体调小，机器件维持默认）
uniform float patch_gain : hint_range(0.0, 0.8) = 0.24;
uniform float patch_scale : hint_range(0.05, 3.0) = 0.55;
// 接触阴影（贴地/贴墙的压暗）强度，独立于烘培 AO
uniform float contact_shade : hint_range(0.0, 1.5) = 1.0;
// ---- 板缝：给"大平面壳体"补上工艺分块 ----
// 建筑壳体/柜体/地板/船壳这类大面积单件，光靠噪声永远是"一整块塑料"。
// `plate_mode` 在 UV 上画 m×n 的板缝（暗线 + 更高的粗糙度），
// 让 8 m 的墙板读成"若干张钢板拼起来的"。
uniform bool plate_mode = false;
uniform float plate_uv_scale : hint_range(1.0, 12.0) = 4.0;
uniform float plate_seam_width : hint_range(0.005, 0.12) = 0.028;
uniform float plate_seam_dark : hint_range(0.0, 0.8) = 0.42;
// 0 = UV 空间（贴图会跟着物体的 UV 走）
// 1 = **物体空间**三平面：给没有 UV 的网格（矿车舱体、临时拼装件）用。
//     不能用世界空间——车一开动，板缝会"游"。
uniform int plate_space = 0;

varying vec3 v_obj;
varying vec3 v_obj_n;

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

// 工业钢板网格：长宽比 1.45:1 错缝排布，返回 vec4(接缝, 倒角亮边, 角铆钉, 单板随机偏移)。
vec4 plate_detail_uv(vec2 raw_uv, float w) {
	vec2 scaled = vec2(raw_uv.x * 0.70, raw_uv.y * 1.05);
	float row = floor(scaled.y);
	scaled.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(scaled);
	vec2 f = fract(scaled);
	vec2 d = min(f, vec2(1.0) - f);
	float dist = min(d.x * 1.40, d.y);
	float seam = 1.0 - smoothstep(0.0, max(1e-4, w), dist);
	float lip = (1.0 - smoothstep(0.0, max(1e-4, w * 2.5), dist)) * (1.0 - seam);
	// 四角螺栓/铆钉（位于板内 0.065, 0.085 处）
	vec2 rv = min(abs(f - vec2(0.065, 0.09)), abs(vec2(1.0) - f - vec2(0.065, 0.09)));
	float rd = length(vec2(rv.x * 1.40, rv.y));
	float rivet = 1.0 - smoothstep(0.011, 0.021, rd);
	float tone = hash13(vec3(id, 7.31)) - 0.5;
	return vec4(seam, lip, rivet, tone);
}

// 物体空间三平面版：没有 UV 的网格也能拿到"随物体移动"的工业钢板分块与铆钉。
vec4 plate_detail_obj(vec3 p, vec3 n, float zoom, float w) {
	vec3 wp = pow(abs(n), vec3(6.0));
	wp /= max(1e-4, wp.x + wp.y + wp.z);
	vec3 q = p * zoom;
	return wp.x * plate_detail_uv(q.zy, w) + wp.y * plate_detail_uv(q.xz, w) + wp.z * plate_detail_uv(q.xy, w);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_obj = VERTEX;
	v_obj_n = normalize(NORMAL);
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
		// Pointiness 在平滑曲面上恒为 ~0.5：必须阈值化，否则整件都会被当成"磨损露金属"
		float curv_s = smoothstep(uv_curv_threshold, uv_curv_threshold + 0.22, m.r);
		baked_curv = curv_s;
		mask_wear = max(mask_wear, curv_s * uv_mask_wear);
		mask_ao = max(mask_ao, m.g * uv_mask_cavity);
	}

	// ---- 2K 掩膜 ----
	if (use_detail_mask) {
		vec2 tuv = detail_uv_space ? UV * detail_uv_scale : p.xz * 0.35;
		vec3 dm = texture(detail_mask, tuv).rgb;
		mask_chip = min(1.0, mask_chip + dm.r * mask_chip_gain * 0.6);
	}

	// ---- 起皮：噪声团块 + 凸棱与几何倒角边缘磨损 ----
	float geom_edge = clamp(length(fwidth(nw)) * 1.45, 0.0, 0.85);
	float breakup = fbm3(p * 3.4 + world_seed) * 0.65 + vnoise3(p * 11.0 + world_seed) * 0.35;
	float wear = clamp(max(mask_wear, geom_edge * 0.65) * wear_gain, 0.0, 1.0);
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
	float ground_dirt = smoothstep(1.10, 0.10, p.y) * 0.9 * contact_shade;
	grime = clamp(grime + ground_dirt * 0.60, 0.0, 1.6);
	grime = smoothstep(0.35, 1.05, grime) * grime_amount;
	float patch = fbm3(p * patch_scale + 5.0 + world_seed) - 0.5;
	col *= 1.0 + patch * 0.24 * (patch_gain / 0.24);
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

	// ---- 板缝与铆钉：大平面壳体按 UV 或物体空间分块 ----
	if (plate_mode) {
		vec4 pd = plate_space == 1
			? plate_detail_obj(v_obj, v_obj_n, plate_uv_scale, plate_seam_width)
			: plate_detail_uv(UV * plate_uv_scale, plate_seam_width);
		// 相邻钢板轻微色阶与粗糙度差，打破大平面塑料感
		col *= 1.0 + pd.w * 0.095;
		rough = clamp(rough + pd.w * 0.07, 0.04, 1.0);
		// 缝内：压暗 + 表面积灰（粗糙度抬高）
		col = mix(col, col * vec3(0.42, 0.43, 0.45), pd.x * plate_seam_dark);
		rough = mix(rough, min(1.0, rough + 0.18), pd.x);
		// 缝沿补一道窄亮边，让分块在掠射光下有"压条/折边"厚度感
		col += bare_color.rgb * pd.y * 0.075 * (0.45 + 0.55 * to_bare);
		// 角铆钉：微暗环压实 + 中心金属高光点
		col = mix(col, bare_color.rgb * 0.58, pd.z * 0.55);
		metal = mix(metal, max(metal, 0.75), pd.z * 0.65);
		rough = mix(rough, 0.30, pd.z * 0.55);
	}

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
		vec2 cuv = detail_uv_space ? UV * detail_uv_scale * 2.6 : p.xz * 0.9;
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

	// ---- 边缘棱线与冷暖半球环境反弹（WALL-E 金属/旧漆高光与暗部层次）----
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	float edge_catch = max(baked_curv, geom_edge);
	col += bare_color.rgb * fres * edge_rim * 0.65 * (0.35 + 0.65 * to_bare)
		 * (0.38 + 0.62 * edge_catch);

	// ---- 软膝：浅色涂装不至于把高光打成一片白 ----
	// 只压 0.62 以上的高亮区，中低亮度保持原样（上一版用 Reinhard 整体抬亮，
	// 结果奶油白墙板全部变成发光白）。
	if (hi_rolloff > 0.001) {
		vec3 over = max(vec3(0.0), col - vec3(0.62));
		col -= over * min(1.0, hi_rolloff * 1.15);
	}

	vec3 hemi_bounce = mix(vec3(1.12, 0.94, 0.76), vec3(0.86, 0.98, 1.14), clamp(nw.y * 0.5 + 0.5, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = min(specular_level, spec_cap);
	EMISSION = col * hemi_bounce * ambient_fill * 0.11;
}


