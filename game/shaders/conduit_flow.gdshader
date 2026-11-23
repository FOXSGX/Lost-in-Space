shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.0, 0.94, 1.0, 1.0);
uniform float energy = 2.0;
uniform float speed = 1.6;
uniform float stripe_scale = 1.15;
uniform float pulse = 0.25;

void fragment() {
	// UV.y is authored in meters along the continuous curved conduit.
	float phase = UV.y * stripe_scale - TIME * speed;
	float wave = pow(0.5 + 0.5 * cos(phase * 6.2831853), 4.0);
	float secondary = pow(0.5 + 0.5 * cos((phase * 2.0 + 0.35) * 6.2831853), 6.0);
	float breath = 1.0 + pulse * (0.28 * sin(TIME * 3.6));

	// Cylindrical Fresnel glass sheen so the core reads with 3D tube volume.
	float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - ndotv, 2.2);

	vec3 deep_core = color.rgb * (0.22 + 0.16 * ndotv);
	vec3 bright_packet = mix(color.rgb, vec3(1.0), 0.32) * (0.78 + 0.45 * energy);
	vec3 rim_tint = mix(color.rgb, vec3(0.95, 0.98, 1.0), 0.25) * (0.35 + 0.25 * energy);

	float packet = clamp(wave + secondary * 0.45, 0.0, 1.0);
	vec3 col = mix(deep_core, bright_packet, packet) * breath + rim_tint * rim * 0.55;
	ALBEDO = col;
}
