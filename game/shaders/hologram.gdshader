shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float alpha = 0.55;
uniform float scan_speed = 2.0;
uniform float scan_density = 90.0;
uniform float flicker = 0.12;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float scan = 0.72 + 0.28 * sin(FRAGCOORD.y * 0.55 + TIME * 11.0);
	float bars = smoothstep(0.55, 0.95, fract((UV.y + TIME * 0.05) * scan_density));
	float f = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 17.0));
	vec3 c = tint.rgb * (0.55 + fres * 1.4) * scan * f;
	ALBEDO = c * 1.6;
	ALPHA = clamp(alpha * (0.55 + fres * 0.9) * f + bars * 0.06, 0.0, 0.92);
}
