shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Facility metal: dark teal / honey edge families share one wear model so the
// rails, gates and task consoles read as one industrial kit.

uniform vec4 base_color : source_color = vec4(0.12, 0.27, 0.29, 1.0);
uniform vec4 edge_color : source_color = vec4(0.63, 0.45, 0.26, 1.0);
uniform vec4 emission_color : source_color = vec4(0.12, 0.65, 0.72, 1.0);
uniform float metallic_base = 0.62;
uniform float roughness_base = 0.38;
uniform float emission_strength = 0.0;
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
    float grain = vnoise(world_pos * 2.8 + vec3(variation * 7.0));
    float scratch = smoothstep(0.72, 1.0, vnoise(world_pos * 9.0 + vec3(variation * 23.0)));
    float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
    float wear = clamp(edge * 0.55 + scratch * 0.24 + grain * 0.12, 0.0, 1.0);

    vec3 c = mix(base_color.rgb, edge_color.rgb, wear * 0.48);
    c *= 0.82 + grain * 0.22;

    ALBEDO = clamp(c, vec3(0.02), vec3(0.78));
    ROUGHNESS = clamp(roughness_base + grain * 0.16 - wear * 0.08, 0.18, 0.82);
    METALLIC = clamp(metallic_base + grain * 0.14, 0.25, 0.95);
    SPECULAR = 0.55;
    if (emission_strength > 0.001) {
        EMISSION = emission_color.rgb * emission_strength * (0.55 + edge * 0.45);
    }
}
