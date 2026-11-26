shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 霜烬星 · 雪地与雪堆族。
//
// 雪不是一张白色贴图：风蚀纹（sastrugi）有固定风向，纹路被低频噪声扭断；
// 雪面有细碎的晶粒高光；靠近墙体与料堆的雪被灰土与碎屑污染；低处的雪偏蓝。
// 对齐标准第 2 条：侵蚀方向与主光/风向一致，而不是全屏同一种噪声。

uniform vec4 snow_color : source_color = vec4(0.88, 0.93, 0.97, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.56, 0.70, 0.84, 1.0);
uniform vec4 grit_color : source_color = vec4(0.34, 0.35, 0.36, 1.0);
uniform vec3 wind_direction = vec3(0.82, 0.0, 0.57);
uniform float ripple_scale = 0.55;
uniform float ripple_strength = 0.55;
uniform float sparkle_amount = 0.55;
uniform float drift_amount = 0.65;
uniform float grit_amount = 0.42;
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
		f.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		value += vnoise(p) * amplitude;
		p = p * 2.05 + vec3(4.9, 2.7, 6.3);
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
	float up = smoothstep(0.20, 0.85, n.y);

	// 风蚀纹：沿主导风向拉长的波纹，相位被噪声打散，所以不是等距条纹。
	vec3 wind = normalize(wind_direction);
	float along = dot(world_pos, wind) * ripple_scale;
	float across = dot(world_pos, vec3(-wind.z, 0.0, wind.x)) * ripple_scale;
	float warp = fbm(world_pos * 0.18 + vec3(variation * 9.0)) * 2.4;
	float ripple = sin(along * 5.4 + warp * 4.0) * 0.5 + 0.5;
	ripple = pow(ripple, 1.7);

	// 雪堆：低频起伏决定哪里高、哪里薄到露出下面的灰土。
	float drift = fbm(world_pos * 0.09 + vec3(variation * 3.0));
	float grain = fbm(world_pos * 1.4 + vec3(variation * 27.0));

	vec3 albedo = mix(snow_color.rgb, shadow_color.rgb, (1.0 - up) * 0.35);
	// 风蚀纹的背风坡比迎风坡暗一档：起伏靠明暗读出来，不靠几何。
	albedo = mix(albedo, shadow_color.rgb, (1.0 - ripple) * 0.16);
	albedo *= 0.86 + ripple * ripple_strength * 0.26 + grain * 0.10;
	albedo *= 0.94 + drift * 0.14;

	// 灰土与碎屑：只出现在雪薄处（drift 低）和靠墙的低位，不随机撒点。
	float thin = 1.0 - smoothstep(0.30, 0.62, drift * drift_amount + 0.24);
	float grit_noise = smoothstep(0.62, 0.92, vnoise(world_pos * 3.1 + vec3(variation * 13.0)));
	float grit = clamp(thin * grit_noise * 2.2, 0.0, 1.0) * grit_amount;
	albedo = mix(albedo, grit_color.rgb, grit * 0.55);

	// 晶粒高光：极高频的稀疏亮屑，靠 SPECULAR 抬起来，不整体提亮。
	float crystal = pow(vnoise(world_pos * 120.0 + vec3(variation * 41.0)), 18.0);
	float sparkle = crystal * sparkle_amount;

	ALBEDO = clamp(albedo, vec3(0.05), vec3(0.97));
	ROUGHNESS = clamp(0.62 - sparkle * 0.42 + grit * 0.25 + (1.0 - ripple) * 0.10, 0.16, 0.95);
	METALLIC = 0.0;
	SPECULAR = clamp(0.35 + sparkle * 0.55, 0.0, 1.0);
	AO = clamp(0.70 + ripple * 0.20 - grit * 0.18 + drift * 0.10, 0.35, 1.0);
}
