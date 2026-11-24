shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 stripe_a : source_color = vec4(0.92, 0.62, 0.10, 1.0);
uniform vec4 stripe_b : source_color = vec4(0.07, 0.065, 0.06, 1.0);
uniform float scale = 3.2;
uniform float roughness_base = 0.55;

varying vec3 wpos;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.07, 0.19, 0.31));
	p *= 23.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = step(0.5, fract((wpos.x + wpos.y + wpos.z * 0.25) * scale));
	vec3 col = mix(stripe_a.rgb, stripe_b.rgb, s);
	float wear = smoothstep(0.55, 0.9, hash13(floor(wpos * 16.0)));
	col = mix(col, col * 0.55, wear * 0.35);
	ALBEDO = col;
	METALLIC = 0.35;
	ROUGHNESS = roughness_base + wear * 0.2;
}
