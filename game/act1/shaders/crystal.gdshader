shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : source_color = vec4(0.10, 0.72, 0.88, 1.0);
uniform vec4 color_b : source_color = vec4(0.46, 0.32, 0.95, 1.0);
uniform float emission_energy = 1.35;
uniform float pulse_speed = 1.1;
uniform float pulse_phase = 0.0;
uniform float facet_contrast = 0.55;
uniform float core_glow = 0.0;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.33, 0.11, 0.27));
	p *= 21.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float band = 0.5 + 0.5 * sin(opos.y * 5.5 + opos.x * 2.6 + TIME * pulse_speed + pulse_phase);
	float facet = 0.5 + 0.5 * sin(onrm.x * 9.0 + onrm.y * 7.0 + onrm.z * 8.0);
	vec3 base = mix(color_a.rgb, color_b.rgb, band * 0.55 + facet * 0.25);
	float sparkle = smoothstep(0.86, 1.0, hash13(floor(opos * 22.0 + vec3(TIME * 0.4))));
	ALBEDO = base * (0.34 + facet * 0.16);
	EMISSION = base * (0.30 + fres * 1.25 + band * 0.20 + sparkle * 0.35) * emission_energy;
	ALBEDO += vec3(sparkle * 0.3);
	ROUGHNESS = 0.16;
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
