shader_type canvas_item;

// 写实科幻宇航员头盔面罩动态冰霜结冰特效（在极寒暴风雪中沿面罩四周凝结冰晶，回温后自动融化）
uniform float frost_amount : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	if (frost_amount <= 0.005) {
		COLOR = vec4(0.0);
	} else {
		vec2 p = (UV - 0.5) * 2.0;
		// 椭圆曲面面罩边缘距离
		float edge_dist = length(vec2(p.x * 0.92, p.y * 1.08));
		float n1 = vnoise(UV * 16.0);
		float n2 = vnoise(UV * 42.0 + vec2(3.1, 7.4));
		float crystal = n1 * 0.65 + n2 * 0.35;

		float reach = mix(1.22, 0.52, frost_amount);
		float mask = smoothstep(reach, reach + 0.42, edge_dist + (crystal - 0.5) * 0.36);
		float vein = smoothstep(0.62, 0.90, crystal) * mask;

		vec3 ice_col = mix(vec3(0.62, 0.86, 0.98), vec3(0.92, 0.98, 1.0), vein);
		float alpha = clamp(mask * (0.28 + 0.48 * frost_amount) + vein * 0.22 * frost_amount, 0.0, 0.72);
		COLOR = vec4(ice_col, alpha);
	}
}
