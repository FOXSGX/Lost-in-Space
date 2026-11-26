shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// ============================================================================
// ART-SYNC-001 · 贴地接触贴片（借鉴共振星 ART-ENV-004 aenv4_decal）
//
// 用途：货箱/立柱/岩石落在地面上时，脚下一圈"灰/压痕"，让物体不是浮在
// 均匀亮度里（gl_compatibility 没有 SSAO，这个贴片是替代品）。
// 用径向衰减而不是薄盘几何：薄盘会露一圈硬边，读成"地上放了个圆饼"。
//
// 约定：调用方把 quad 放在地面 +0.004 起，深度不写（depth_draw_never），
// 避免与地面 z-fighting；每实例的强度走 MultiMesh 颜色 alpha。
// ============================================================================

uniform vec4 tint : source_color = vec4(0.116, 0.104, 0.082, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.55;
uniform float inner : hint_range(0.0, 1.0) = 0.10;
uniform float outer : hint_range(0.1, 1.0) = 0.92;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = clamp(length(uv), 0.0, 1.0);
	float ring = 1.0 - smoothstep(inner, outer, r);
	ALBEDO = tint.rgb;
	ALPHA = ring * strength * COLOR.a;
}
