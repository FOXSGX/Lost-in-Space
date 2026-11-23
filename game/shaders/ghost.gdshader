shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// Ghostly memory performance material: translucent silhouettes with scanlines
// and a soft fresnel edge. Mixed alpha (not pure additive) keeps the cart and
// miners readable against a dark cave instead of dissolving into a light blob.

uniform vec3 tint : source_color = vec3(0.45, 0.86, 1.0);
uniform float strength = 0.65;
uniform float scan_density = 26.0;
uniform float edge_boost = 1.2;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	float scan = 0.65 + 0.35 * sin(v_local.y * scan_density - TIME * 6.0);
	float flicker = 0.92 + 0.08 * sin(TIME * 23.0 + v_local.x * 3.0);
	ALBEDO = tint * (0.55 + 0.45 * scan);
	EMISSION = tint * strength * (0.35 + 0.35 * scan + edge_boost * fres) * flicker;
	ALPHA = clamp(strength * (0.24 + 0.20 * scan + 0.34 * fres), 0.0, 0.86);
}
