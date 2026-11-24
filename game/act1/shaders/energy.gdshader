shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.20, 0.85, 1.0, 1.0);
uniform float energy = 1.6;
uniform float speed = 1.2;
uniform float stripe_scale = 6.0;
uniform float pulse = 0.0;

void fragment() {
	float s = fract(UV.y * stripe_scale - TIME * speed);
	float bar = smoothstep(0.62, 1.0, s) * 0.85 + 0.15;
	float flicker = 0.92 + 0.08 * sin(TIME * 13.0);
	vec3 c = color.rgb * energy * bar * flicker;
	if (pulse > 0.0) {
		c += color.rgb * pulse * (0.25 + 0.25 * sin(TIME * 4.0));
	}
	ALBEDO = c;
	ALPHA = clamp(bar * 0.85 + 0.12, 0.0, 1.0);
}
