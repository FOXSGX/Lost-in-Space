shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// gl_compatibility 假体积光束（天井/闸门/聚光灯空气纵深，克制能量 <= 0.12）
uniform vec4 ray_color : source_color = vec4(0.76, 0.90, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 0.35) = 0.10;

varying float v_y;
varying vec3 v_n;
varying vec3 v_view;

void vertex() {
	v_y = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	v_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_view = normalize(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float edge = pow(abs(dot(normalize(v_n), normalize(v_view))), 1.6);
	float fade = smoothstep(0.0, 0.35, v_y) * smoothstep(1.0, 0.15, v_y);
	float a = clamp(edge * fade * intensity, 0.0, 0.28);
	ALBEDO = ray_color.rgb;
	ALPHA = a;
}
