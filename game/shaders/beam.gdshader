shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// Directional resonance beam / focus facet. Alpha falls along +UV.y, so a
// cylinder/quad scaled along its axis reads as a cone of light.

uniform vec3 tint : source_color = vec3(0.30, 0.86, 1.0);
uniform float strength = 0.55;
uniform float scroll = 0.6;
uniform float edge_power = 2.0;

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float edge = pow(1.0 - abs(UV.x * 2.0 - 1.0), edge_power);
	float flow = 0.55 + 0.45 * sin((UV.y * 9.0 - TIME * scroll) * 3.14159265);
	EMISSION = tint * strength * (0.25 + 0.75 * edge) * flow;
	ALPHA = (1.0 - along) * 0.55 * edge * strength;
}
