shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
    vec2 edge = abs(UV - vec2(0.5)) * 2.0;
    float vignette = smoothstep(0.52, 1.0, max(edge.x, edge.y));
    COLOR = vec4(0.48, 0.07, 0.06, vignette * strength);
}
