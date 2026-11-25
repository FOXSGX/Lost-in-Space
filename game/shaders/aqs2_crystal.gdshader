shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// ART-SAMPLE-002 · 晶体（v2：三层光学结构）
//
// 目标：不再是"一块过曝的蓝白色塑料"，也不是简单自发光装饰，而是有
// **表面 → 次表面 → 芯** 三层深度关系的外星矿物。
//
// 三层（全部在不透明管线内做出"透明感"，Compatibility 也能成立）：
//   1. **表面层**：高光 + 菲涅尔边缘 + 极低粗糙度；法线带微观起伏（解理面不会像镜子）。
//   2. **次表面层**：视线掠过晶体时"透出"内部体色（用菲涅尔调节体色浓度），
//      并在根部混入岩石/泥沙色（晶体是从岩里长出来的）。
//   3. **芯层**：内部晶脉（3D 噪声）+ 一个更亮的"共振芯"（由真实 pulse 驱动），
//      只在中心区域可见，边缘被吸收。
//
// 反过曝：emission 过软膝；`pulse` 提升的是**芯层**亮度而不是整块 albedo。
//
// 玩法接口：pulse / alarm（由 CrystalVisual 镜像，不改判定）。
// ============================================================================

uniform vec4 deep_color : source_color = vec4(0.014, 0.075, 0.105, 1.0);
uniform vec4 body_color : source_color = vec4(0.075, 0.330, 0.430, 1.0);
uniform vec4 tip_color : source_color = vec4(0.560, 0.860, 0.960, 1.0);
uniform vec4 vein_color : source_color = vec4(0.360, 0.220, 0.780, 1.0);
uniform vec4 root_color : source_color = vec4(0.190, 0.150, 0.120, 1.0);

uniform float emission_energy : hint_range(0.0, 4.0) = 0.55;
uniform float core_strength : hint_range(0.0, 4.0) = 0.40;
uniform float vein_strength : hint_range(0.0, 1.0) = 0.30;
uniform float murk_height : hint_range(0.0, 2.0) = 0.60;
uniform float root_grime : hint_range(0.0, 1.0) = 0.75;
uniform float facet_glow : hint_range(0.0, 2.0) = 0.55;
uniform float specular_level : hint_range(0.0, 1.0) = 0.9;
uniform float rough_base : hint_range(0.02, 0.6) = 0.10;
uniform float surface_wobble : hint_range(0.0, 0.5) = 0.14;
uniform float absorption : hint_range(0.0, 1.0) = 0.55;
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
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.4);

	// ---- 表面层：解理面朝向 ----
	float facing = clamp(dot(nw, normalize(vec3(0.35, 0.82, 0.45))), -1.0, 1.0);
	float facet = 0.5 + 0.5 * facing;

	// ---- 内部结构 ----
	float vein_n = vnoise3(p * 2.6 + world_seed) * 0.6 + vnoise3(p * 6.1 + 7.0 + world_seed) * 0.4;
	float vein = smoothstep(0.52, 0.88, vein_n);
	float mottle = smoothstep(0.35, 0.9, vnoise3(p * 1.4 + 3.0 + world_seed));
	// 根部浑浊：越靠下越浑、越暗（杂质与泥沙沉积）
	float murk = 1.0 - smoothstep(0.0, murk_height, v_local_y);

	// ---- 1) 表面：极深色 + 高光；越靠边缘吸收越弱（薄处透光）
	vec3 surf = mix(deep_color.rgb, body_color.rgb, smoothstep(0.15, 0.85, facet));
	float thin = pow(fres, 0.8);                 // 边缘 = 薄 = 更透

	// ---- 2) 次表面：体色随"薄度"透出，带一点尖端冷白
	vec3 sub = body_color.rgb * (0.55 + 0.75 * thin);
	sub = mix(sub, tip_color.rgb, smoothstep(0.55, 1.0, v_local_y / 1.9) * 0.45 + thin * 0.20);
	sub = mix(sub, vein_color.rgb, vein * vein_strength * 0.65);

	// ---- 3) 芯：只在中部可见，根部被岩土吞掉
	vec3 core = mix(vein_color.rgb, tip_color.rgb, 0.45) * (0.5 + 0.5 * mottle);
	core *= (1.0 - murk * 0.85);

	// 三层合成：表面 + 次表面（吸收）+ 芯（中央）
	vec3 col = mix(surf, sub, clamp(thin * (0.55 + 0.45 * absorption), 0.0, 1.0));
	col = mix(col, core, pow(1.0 - ndv, 1.4) * 0.25 + smoothstep(0.75, 1.0, mottle) * 0.15 * (1.0 - murk));

	// 根部：泥与碎屑（接触关系）
	col = mix(col, root_color.rgb, murk * root_grime * 0.9);

	// ---- 发光：面朝向 + 边缘 + 晶脉 + 共振余振（只抬芯层）
	float glow = emission_energy * (0.30 + 0.70 * facet) * (0.45 + 0.85 * fres);
	glow += core_strength * vein * 0.55 * (1.0 - murk * 0.7);
	glow += pulse * 2.2 * (0.30 + 1.10 * fres) * (1.0 - murk * 0.5);
	glow += alarm * 2.6;
	glow *= (0.35 + 0.65 * facet_glow);

	vec3 emit = col * glow;
	emit = emit / (1.0 + emit * 0.62);           // 软膝：近距离也不会打成纯白
	emit = mix(emit, vec3(1.0, 0.30, 0.20) * (0.5 + glow * 0.45),
			   clamp(alarm, 0.0, 1.0) * 0.5);

	// ---- 法线：微观起伏（解理面不是镜子）
	vec3 wob = vec3(vnoise3(p * 26.0 + world_seed) - 0.5,
					vnoise3(p * 26.0 + 11.0) - 0.5,
					vnoise3(p * 26.0 + 19.0) - 0.5) * surface_wobble;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(wob, 0.0)).xyz);

	ALBEDO = col * (1.0 - murk * 0.30);
	ROUGHNESS = clamp(rough_base + murk * 0.40 + vein * 0.06, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = specular_level;
	EMISSION = emit;
}
