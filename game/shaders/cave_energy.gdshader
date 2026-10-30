shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Resonance energy nodes.  Slightly animated but deliberately capped so the
// arch and crystal halos guide the eye instead of clipping to white.

uniform vec4 energy_color : source_color = vec4(0.18, 0.78, 0.92, 1.0);
uniform float intensity = 0.85;
uniform float pulse_speed = 1.5;
uniform float variation = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
    float pulse = 0.82 + 0.18 * sin(TIME * pulse_speed + variation * 8.0 + world_pos.x * 0.15);
    vec3 c = energy_color.rgb;
    ALBEDO = c * 0.20;
    ROUGHNESS = 0.24;
    METALLIC = 0.12;
    SPECULAR = 0.45;
    EMISSION = c * intensity * pulse * (0.62 + rim * 0.38);
}
