shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 归航号太空舱 · 工业舱壁/甲板/结构钢 shader（对齐 ART-SAMPLE-002 质感规范）
// 世界坐标分块、板缝倒角、拉丝金属纹、脚踢磨损带与防滑甲板模式。

uniform vec4 paint_color : source_color = vec4(0.66, 0.65, 0.61, 1.0);
uniform vec4 trim_color : source_color = vec4(0.18, 0.24, 0.29, 1.0);
uniform vec4 accent_color : source_color = vec4(0.84, 0.56, 0.24, 1.0);
uniform vec4 bare_metal : source_color = vec4(0.46, 0.50, 0.54, 1.0);
uniform vec2 panel_size = vec2(2.0, 1.25);
uniform float seam_width = 0.022;
uniform float kick_height = 0.42;
uniform float kick_mix = 0.72;
uniform float deck_mode = 0.0;
uniform float metallic_base = 0.28;
uniform float roughness_base = 0.48;
uniform float wear_amount = 0.45;
uniform float variation = 0.0;

varying vec3 w_pos;
varying vec3 w_nrm;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i), hash31(i + vec3(1,0,0)), f.x),
			mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), f.x),
			mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), f.x), f.y),
		f.z);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 an = abs(n);
	vec2 uv;
	float is_wall = 1.0;
	if (an.y >= an.x && an.y >= an.z) {
		uv = w_pos.xz;
		is_wall = 0.0;
	} else if (an.x >= an.z) {
		uv = w_pos.zy;
	} else {
		uv = w_pos.xy;
	}

	vec2 cell = uv / panel_size + vec2(variation * 7.0, variation * 11.0);
	vec2 f = fract(cell);
	float p_hash = hash31(vec3(floor(cell), variation * 29.0));
	vec2 edge_m = min(f, 1.0 - f) * panel_size;
	float edge_min = min(edge_m.x, edge_m.y);

	float seam = 1.0 - smoothstep(0.0, seam_width, edge_min);
	float bevel = (1.0 - smoothstep(seam_width, seam_width * 2.5, edge_min)) * (1.0 - seam);

	float brushed = vnoise(vec3(uv.x * 18.0, uv.y * 3.5, variation * 5.0));
	float micro = vnoise(w_pos * 14.0 + vec3(variation * 9.0));

	vec3 col = paint_color.rgb * (0.92 + p_hash * 0.12) * (0.94 + brushed * 0.12);
	float rough = roughness_base + brushed * 0.08 - bevel * 0.08;
	float metal = metallic_base;

	if (deck_mode > 0.5) {
		// 防滑菱形/条纹工业甲板
		vec2 tread = abs(fract(uv * 6.0) - 0.5);
		float grip = smoothstep(0.16, 0.24, abs(tread.x - tread.y));
		col = mix(trim_color.rgb * 0.85, paint_color.rgb, grip * 0.65);
		col *= 0.90 + p_hash * 0.14;
		float traffic = smoothstep(0.35, 0.85, micro) * wear_amount;
		col = mix(col, bare_metal.rgb, traffic * 0.22);
		rough = clamp(roughness_base + (1.0 - grip) * 0.18 - traffic * 0.16, 0.24, 0.88);
		metal = clamp(metallic_base + traffic * 0.25, 0.15, 0.78);
	} else {
		// 舱壁踢脚带与棱边轻微磨砂裸金属
		float kick = (1.0 - smoothstep(kick_height - 0.02, kick_height, w_pos.y)) * is_wall;
		float stripe = smoothstep(kick_height - 0.06, kick_height - 0.03, w_pos.y) * kick;
		col = mix(col, trim_color.rgb, kick * kick_mix);
		col = mix(col, accent_color.rgb, stripe * 0.85 * kick_mix);
		float edge_wear = clamp((bevel * 0.6 + kick * 0.35) * smoothstep(0.45, 0.80, micro) * wear_amount, 0.0, 1.0);
		col = mix(col, bare_metal.rgb, edge_wear * 0.38);
		metal = clamp(metallic_base + edge_wear * 0.35, 0.05, 0.82);
	}

	// 板缝压暗与微 AO
	col *= 1.0 - seam * 0.42;
	ALBEDO = clamp(col, vec3(0.02), vec3(0.92));
	ROUGHNESS = clamp(rough, 0.16, 0.94);
	METALLIC = metal;
	SPECULAR = 0.48 + bevel * 0.12;
	AO = clamp(0.76 + bevel * 0.16 - seam * 0.42, 0.28, 1.0);
}
