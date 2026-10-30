shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Floor layer: three nested reads instead of one flat color:
// 1) broad slate base, 2) warm dust drift, 3) darker compacted route strip.

uniform vec4 base_color : source_color = vec4(0.22, 0.19, 0.21, 1.0);
uniform vec4 dust_color : source_color = vec4(0.52, 0.34, 0.25, 1.0);
uniform vec4 route_color : source_color = vec4(0.18, 0.15, 0.17, 1.0);
uniform float macro_scale = 0.12;
uniform float detail_scale = 1.5;
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
    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z
    );
}

float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.55;
    for (int i = 0; i < 3; i++) {
        value += vnoise(p) * amplitude;
        p = p * 2.1 + vec3(2.3, 9.1, 4.7);
        amplitude *= 0.47;
    }
    return value;
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float macro = fbm(world_pos * macro_scale + vec3(variation * 9.0));
    float detail = fbm(world_pos * detail_scale + vec3(variation * 17.0));
    float route = smoothstep(4.6, 1.25, abs(world_pos.z + 0.15));
    float dust = clamp(macro * 0.7 + detail * 0.45, 0.0, 1.0);

    vec3 c = mix(base_color.rgb, dust_color.rgb, dust * 0.34);
    c = mix(c, route_color.rgb, route * 0.42);
    c *= 0.84 + detail * 0.22;
    c += route * 0.022 * vec3(0.8, 0.65, 0.48);

    vec3 n = normalize(world_normal);
    float wet = smoothstep(0.2, 0.9, 1.0 - n.y) * 0.28;
    c *= 1.0 - wet * 0.35;

    ALBEDO = clamp(c, vec3(0.015), vec3(0.86));
    ROUGHNESS = clamp(0.90 - route * 0.14 - wet * 0.18 + detail * 0.04, 0.35, 1.0);
    SPECULAR = 0.25;
    METALLIC = 0.0;
    AO = mix(0.62, 1.0, detail);
}
