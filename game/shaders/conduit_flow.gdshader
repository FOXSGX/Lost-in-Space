shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 物理因果能量导管着色器：支持 未通电(暗铁) / 就绪(琥珀脉冲) / 已激活(青蓝流光)
// 严格执行软膝限幅，禁止过曝炸死白。

uniform vec4 base_color : source_color = vec4(0.16, 0.20, 0.24, 1.0);
uniform vec4 flow_color : source_color = vec4(0.16, 0.86, 1.0, 1.0);
uniform float active_state : hint_range(0.0, 1.0) = 0.0;
uniform float ready_state : hint_range(0.0, 1.0) = 0.0;
uniform float flow_speed = 1.6;
uniform float flow_freq = 2.4;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float along = v_world.x + v_world.z + v_world.y * 0.5;
	float pulse = 0.5 + 0.5 * sin(along * flow_freq - TIME * flow_speed * 6.2831);
	float band = smoothstep(0.35, 0.92, pulse);

	vec3 amber = vec3(0.95, 0.56, 0.14);
	vec3 state_col = mix(amber, flow_color.rgb, active_state);
	float glow_mask = max(active_state, ready_state * 0.55);

	vec3 col = mix(base_color.rgb, state_col, glow_mask * (0.35 + 0.55 * band));
	vec3 emit = state_col * glow_mask * (0.28 + 1.15 * band);
	emit = emit / (1.0 + emit * 0.62);

	ALBEDO = col;
	ROUGHNESS = mix(0.46, 0.22, glow_mask);
	METALLIC = mix(0.68, 0.35, glow_mask);
	EMISSION = emit;
}
