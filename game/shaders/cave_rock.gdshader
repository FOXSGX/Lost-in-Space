shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Stylized, triplanar, world-space rock.  No textures are used, so the huge
// Blender shell does not show a repeated UV seam or a single flat albedo.

uniform vec4 base_color : source_color = vec4(0.36, 0.20, 0.15, 1.0);
uniform vec4 warm_color : source_color = vec4(0.57, 0.31, 0.22, 1.0);
uniform vec4 cool_color : source_color = vec4(0.20, 0.15, 0.20, 1.0);
uniform float macro_scale = 0.085;
uniform float detail_scale = 0.85;
uniform float roughness_base = 0.84;
uniform float wet_strength = 0.42;
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
    float n000 = hash31(i);
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.55;
    for (int i = 0; i < 4; i++) {
        value += vnoise(p) * amplitude;
        p = p * 2.03 + vec3(7.1, 3.7, 5.3);
        amplitude *= 0.48;
    }
    return value;
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 n = normalize(world_normal);
    float macro = fbm(world_pos * macro_scale + vec3(variation * 8.0));
    float detail = fbm(world_pos * detail_scale + vec3(variation * 19.0 + 4.0));
    float band = sin(world_pos.y * 2.15 + macro * 7.0 + variation * 3.0) * 0.5 + 0.5;
    float side = 1.0 - clamp(n.y, 0.0, 1.0);

    vec3 c = mix(base_color.rgb, warm_color.rgb, clamp(macro * 1.22, 0.0, 1.0));
    c = mix(c, cool_color.rgb, smoothstep(0.36, 0.95, side) * 0.34);
    c *= 0.82 + detail * 0.26;
    c += band * 0.018;

    // Damp vertical faces and the floor contact zone: darker, less rough.
    float wet = smoothstep(0.18, 0.90, side) * wet_strength;
    c *= 1.0 - wet * 0.30;
    float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
    c += rim * 0.055 * vec3(1.0, 0.74, 0.56);

    ALBEDO = clamp(c, vec3(0.015), vec3(0.92));
    ROUGHNESS = clamp(roughness_base + detail * 0.10 - wet * 0.24, 0.30, 1.0);
    SPECULAR = 0.30;
    METALLIC = 0.0;
    AO = mix(0.52, 1.0, detail);
}
