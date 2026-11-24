shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// ART-SAMPLE-001 · 晶体（共振钟晶体，复用件）
//
// 上一版的近景问题：解理窗在 1 m 内读成一块过曝白方块；晶面像均匀发光的塑料。
// 这一版的原则：
//   1. **发光要跟几何走**：亮度来自解理面朝向（fresnel + 面法线与视线的夹角），
//      而不是整体 emission 拉满；
//   2. **内部有东西**：3D 噪声做出晶脉与浑浊带，越靠根部越浑浊（杂质沉积）；
//   3. **根部脏**：晶体从岩里长出来，根部有土、有碎石、亮度更低（接触遮蔽）；
//   4. **防过曝**：emission 过一次软膝（smooth knee），近距离也不会打成纯白。
//
// 玩法接口（由 aqs001_motion.gd 每帧写入，不改判定逻辑）：
//   pulse      敲击后的共振余振 0..1（真实衰减）
//   alarm      异常状态 0..1
// ============================================================================

uniform vec4 deep_color : source_color = vec4(0.020, 0.110, 0.170, 1.0);
uniform vec4 body_color : source_color = vec4(0.090, 0.420, 0.520, 1.0);
uniform vec4 tip_color : source_color = vec4(0.700, 0.960, 1.000, 1.0);
uniform vec4 vein_color : source_color = vec4(0.480, 0.320, 0.900, 1.0);

uniform float emission_energy : hint_range(0.0, 6.0) = 0.9;
uniform float core_strength : hint_range(0.0, 4.0) = 1.0;
uniform float vein_strength : hint_range(0.0, 1.0) = 0.35;
uniform float murk_height : hint_range(0.0, 2.0) = 0.55;   // 根部浑浊带高度（米）
uniform float root_grime : hint_range(0.0, 1.0) = 0.7;
uniform float facet_glow : hint_range(0.0, 2.0) = 0.85;
uniform float specular_level : hint_range(0.0, 1.0) = 0.85;
uniform float rough_base : hint_range(0.02, 0.6) = 0.12;
uniform float pulse = 0.0;
uniform float alarm = 0.0;
uniform float world_seed = 0.0;

varying vec3 v_world;
varying vec3 v_world_n;
varying float v_local_y;

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

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_local_y = VERTEX.y;
}

void fragment() {
	vec3 p = v_world;
	vec3 nw = normalize(v_world_n);

	// ---- 面朝向决定了大部分亮度：解理面之间的明暗台阶是"晶"的关键 ----
	float facing = clamp(dot(nw, normalize(vec3(0.35, 0.82, 0.45))), -1.0, 1.0);
	float facet = 0.5 + 0.5 * facing;

	// ---- 内部：晶脉与浑浊带（越往根部越浑）----
	float vein = smoothstep(0.52, 0.88, vnoise3(p * 2.6 + world_seed)
			* 0.6 + vnoise3(p * 6.1 + 7.0 + world_seed) * 0.4);
	float murk = 1.0 - smoothstep(0.0, murk_height, v_local_y);
	float grime = smoothstep(0.45, 1.0, v_local_y + 0.2) * 0.0; // 占位：根部由 murk 处理

	// ---- 颜色：深色芯 → 体色 → 尖端冷白 ----
	vec3 col = mix(deep_color.rgb, body_color.rgb, smoothstep(0.15, 0.85, facet));
	col = mix(col, tip_color.rgb, smoothstep(0.55, 1.0, v_local_y / 1.9) * 0.55);
	col = mix(col, vein_color.rgb, vein * vein_strength * 0.7);

	// ---- 根部：土、碎石、遮蔽（不是"插进砧面"）----
	vec3 root_dirt = vec3(0.19, 0.155, 0.125);
	col = mix(col, root_dirt, murk * root_grime * 0.85);

	// ---- 边缘：视线擦过晶棱时最亮（薄处透光）----
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);

	// ---- 发光：面朝向 + 边缘 + 晶脉 + 共振余振 ----
	float glow = emission_energy * (0.35 + 0.65 * facet) * (0.55 + 0.75 * fres);
	glow += core_strength * vein * 0.55;
	glow += pulse * 2.6 * (0.55 + 0.9 * fres);
	glow += alarm * 3.0;
	glow *= (1.0 - murk * 0.65);

	vec3 emit = col * glow;
	// 软膝：近距离不会把解理窗打成纯白（上一版的核心缺陷）
	emit = emit / (1.0 + emit * 0.55);
	// 报警时偏红
	emit = mix(emit, vec3(1.0, 0.32, 0.22) * (0.6 + glow * 0.5), clamp(alarm, 0.0, 1.0) * 0.55);

	ALBEDO = col * (1.0 - murk * 0.25);
	ROUGHNESS = clamp(rough_base + murk * 0.35 + vein * 0.08, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = specular_level;
	// 晶面轻微法线扰动：让每一面不是镜子（近景里避免"塑料膜"）
	NORMAL = normalize(NORMAL + normalize((VIEW_MATRIX * vec4(
		vec3(vnoise3(p * 21.0) - 0.5, vnoise3(p * 21.0 + 3.0) - 0.5, 0.0), 0.0)).xyz * 0.10));
	EMISSION = emit;
}
