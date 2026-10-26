shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float strength=0.24;
void fragment(){
    vec2 p=(UV-0.5)*2.0;
    float falloff=max(0.0,1.0-dot(p,p));
    ALBEDO=vec3(0.0);
    ALPHA=strength*falloff*falloff;
}
