// Adapted from the Godot skill hologram template; flicker disabled by the ship material.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 hologram_color : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float fresnel_power : hint_range(0.5, 16.0, 0.1) = 2.5;
uniform float fresnel_boost : hint_range(0.0, 8.0, 0.05) = 2.0;
uniform float scanline_count : hint_range(0.0, 400.0, 1.0) = 60.0;
uniform float scanline_speed : hint_range(-10.0, 10.0, 0.05) = 1.5;
uniform float scanline_depth : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float flicker_speed : hint_range(0.0, 40.0, 0.1) = 9.0;
uniform float flicker_amount : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float glitch_amount : hint_range(0.0, 0.5, 0.005) = 0.0;

varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
	if (glitch_amount > 0.0) {
		// A horizontal slice that sweeps up the mesh and shears sideways as it passes.
		float slice = step(0.92, fract(VERTEX.y * 3.0 - TIME * 1.7));
		VERTEX.x += slice * glitch_amount * sin(TIME * 37.0);
	}
}

void fragment() {
	// Scanlines run along the mesh's own Y so they stay put as the camera orbits.
	float lines = 0.5 + 0.5 * sin(model_position.y * scanline_count - TIME * scanline_speed * TAU);
	float scan = mix(1.0, lines, scanline_depth);

	// Two out-of-phase sines: a flicker that never settles into a visible beat.
	float flicker = 1.0 - flicker_amount
			* (0.5 + 0.5 * sin(TIME * flicker_speed) * sin(TIME * flicker_speed * 0.37 + 1.3));

	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);

	ALBEDO = hologram_color.rgb * (scan * flicker + fresnel * fresnel_boost);
	ALPHA = clamp((base_alpha * scan + fresnel * fresnel_boost * 0.5) * flicker, 0.0, 1.0)
			* hologram_color.a;
}
