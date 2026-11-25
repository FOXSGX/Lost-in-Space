shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 太空舱 / 训练舱 科技感点阵 LED 显示屏着色器（100% gl_compatibility 兼容）
uniform sampler2D screen_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float emit_strength : hint_range(0.2, 3.0) = 1.25;
uniform float pixel_density_x : hint_range(32.0, 512.0) = 220.0;
uniform float pixel_density_y : hint_range(16.0, 256.0) = 76.0;
uniform float scanline_strength : hint_range(0.0, 0.45) = 0.14;
uniform float pulse_speed : hint_range(0.0, 4.0) = 0.85;

void fragment() {
	vec3 tex = texture(screen_tex, UV).rgb;

	// 微细 LED 点阵栅格与轻微横向扫描线
	float gx = 0.86 + 0.14 * smoothstep(0.15, 0.85, abs(sin(UV.x * pixel_density_x * 3.14159)));
	float gy = 0.84 + 0.16 * smoothstep(0.15, 0.85, abs(sin(UV.y * pixel_density_y * 3.14159)));
	float matrix_mask = mix(1.0, gx * gy, 0.55);

	// 柔和缓慢扫屏亮带，强化通电活屏质感
	float sweep_pos = fract(TIME * 0.18 * pulse_speed);
	float sweep = exp(-pow((UV.y - sweep_pos) * 9.0, 2.0)) * scanline_strength;

	// 边缘暗角玻璃感
	vec2 ec = abs(UV - 0.5) * 2.0;
	float vig = 1.0 - smoothstep(0.86, 1.04, max(ec.x, ec.y)) * 0.28;

	vec3 led_col = tex * matrix_mask * vig + vec3(0.12, 0.45, 0.58) * sweep * (0.35 + dot(tex, vec3(0.33)));

	ALBEDO = led_col * 0.35;
	ROUGHNESS = 0.14;
	METALLIC = 0.06;
	SPECULAR = 0.65;
	EMISSION = led_col * emit_strength;
}
