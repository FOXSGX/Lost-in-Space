shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Opaque, faceted crystal read.  The silhouette stays crisp; emission lives on
// the rim and tip rather than flooding the whole chamber with white.

uniform vec4 base_color : source_color = vec4(0.08, 0.34, 0.43, 1.0);
uniform vec4 tip_color : source_color = vec4(0.36, 0.82, 0.92, 1.0);
uniform vec4 emission_color : source_color = vec4(0.18, 0.75, 0.88, 1.0);
uniform float emission_strength = 0.62;
uniform float variation = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
            mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
        mix(mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
            mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
        f.z
    );
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 n = normalize(world_normal);
    float facet = vnoise(world_pos * 1.35 + vec3(variation * 11.0));
    float tip = smoothstep(0.0, 10.5, world_pos.y);
    float vertical_band = sin(world_pos.y * 1.6 + facet * 2.0) * 0.5 + 0.5;
    float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);

    vec3 c = mix(base_color.rgb, tip_color.rgb, tip * 0.58 + facet * 0.14);
    c *= 0.82 + vertical_band * 0.16;
    c += rim * 0.12 * emission_color.rgb;

    ALBEDO = clamp(c, vec3(0.02), vec3(0.86));
    ROUGHNESS = clamp(0.14 + facet * 0.08, 0.08, 0.32);
    METALLIC = 0.06;
    SPECULAR = 0.55;
    EMISSION = emission_color.rgb * (0.10 + rim * 0.34 + tip * 0.16) * emission_strength;
}
