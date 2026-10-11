shader_type canvas_item;
render_mode unshaded;

uniform vec2 viewer = vec2(140.0, 125.0);
uniform vec2 scan_origin;
uniform vec2 heat = vec2(440.0, 350.0);
uniform vec2 beacon_0;
uniform vec2 beacon_1;
uniform vec2 beacon_2;
uniform bool beacon_active_0 = false;
uniform bool beacon_active_1 = false;
uniform bool beacon_active_2 = false;
uniform bool storm = false;
uniform bool scanning = false;
uniform float scan_progress = 0.0;
uniform float scan_max_radius = 520.0;

float aperture(vec2 point, vec2 center, float radius) {
    return 1.0 - smoothstep(radius * 0.68, radius, distance(point, center));
}

void fragment() {
    vec2 point = UV * vec2(990.0, 600.0);
    float radius = storm ? 105.0 : 165.0;
    float sight = aperture(point, viewer, radius);
    float ring_light = 0.0;
    if (scanning) {
        float pulse_radius = scan_max_radius * clamp(scan_progress / 0.85, 0.0, 1.0);
        float pulse_distance = distance(point, scan_origin);
        float fade = 1.0 - smoothstep(0.85, 1.0, scan_progress);
        float bounded = 1.0 - step(scan_max_radius, pulse_distance);
        float pulse_reveal = (1.0 - smoothstep(max(pulse_radius - 24.0, 0.0), max(pulse_radius, 0.01), pulse_distance)) * bounded;
        ring_light = (1.0 - smoothstep(2.0, 7.0, abs(pulse_distance - pulse_radius))) * bounded * fade;
        sight = max(sight, pulse_reveal * 0.84 * fade);
    }
    // 热源和已修复气象信标始终留下微弱导航光，避免失去返程方向。
    sight = max(sight, aperture(point, heat, 65.0) * 0.8);
    if (beacon_active_0) { sight = max(sight, aperture(point, beacon_0, 48.0) * 0.65); }
    if (beacon_active_1) { sight = max(sight, aperture(point, beacon_1, 48.0) * 0.65); }
    if (beacon_active_2) { sight = max(sight, aperture(point, beacon_2, 48.0) * 0.65); }
    vec3 tint = storm ? vec3(0.07, 0.12, 0.18) : vec3(0.006, 0.014, 0.026);
    float opacity = (1.0 - sight) * (storm ? 0.97 : 0.96);
    // 程序化飘雪，仅在地图内绘制，不遮挡 HUD、按钮和过渡页面。
    if (storm) {
        vec2 drift = vec2(UV.x * 92.0 + TIME * 3.4, UV.y * 54.0 + TIME * 2.1);
        vec2 flake = fract(drift);
        float snow = (1.0 - smoothstep(0.035, 0.11, length(flake - vec2(0.5)))) * 0.48;
        tint = mix(tint, vec3(0.82, 0.94, 1.0), snow);
        opacity = max(opacity, snow * 0.4);
    }
    // 可见的细亮环沿固定起点扩散，边缘不会超出最大半径。
    tint = mix(tint, vec3(0.22, 0.85, 0.92), ring_light);
    opacity = max(opacity, ring_light * 0.8);
    COLOR = vec4(tint, opacity);
}
