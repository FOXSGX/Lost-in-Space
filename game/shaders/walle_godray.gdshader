shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 beam_color : source_color = vec4(1.0, 0.72, 0.32, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.22;
uniform float soft_power : hint_range(0.5, 5.0) = 2.1;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), soft_power);
	float v_fade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.35, UV.y);
	float mote = 0.88 + 0.12 * sin(v_world.y * 3.2 + v_world.x * 2.1 + v_world.z * 1.9);
	float a = fres * v_fade * mote * intensity;
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(a, 0.0, 0.45);
}
