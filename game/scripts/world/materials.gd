class_name MatLib
extends RefCounted

## Central material library for Resonance 05.
## Everything is generated at runtime from a handful of shaders so that the
## delivered project has no dependency on external texture folders.

const ROCK_SHADER := preload("res://shaders/rock.gdshader")
const ROCK_SHELL_SHADER := preload("res://shaders/rock_shell.gdshader")
const METAL_SHADER := preload("res://shaders/metal.gdshader")
const CRYSTAL_SHADER := preload("res://shaders/crystal.gdshader")
const ENERGY_SHADER := preload("res://shaders/energy.gdshader")
const HOLO_SHADER := preload("res://shaders/hologram.gdshader")
const HAZARD_SHADER := preload("res://shaders/hazard.gdshader")

static var _cache: Dictionary = {}


static func _cached(key: String, builder: Callable) -> Material:
	if _cache.has(key):
		return _cache[key] as Material
	var made: Material = builder.call() as Material
	_cache[key] = made
	return made


static func rock(tint: Color = Color(0.31, 0.29, 0.29), vein: Color = Color(0.10, 0.48, 0.56), vein_strength: float = 0.30, vertex_tint: float = 0.0) -> ShaderMaterial:
	var key: String = "rock_%s_%s_%.2f_%.2f" % [tint.to_html(), vein.to_html(), vein_strength, vertex_tint]
	return _cached(key, func() -> ShaderMaterial:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = ROCK_SHADER
		m.set_shader_parameter("base_color", tint)
		m.set_shader_parameter("vein_color", vein)
		m.set_shader_parameter("vein_strength", vein_strength)
		m.set_shader_parameter("vertex_tint", vertex_tint)
		m.set_shader_parameter("deep_color", Color(tint.r * 0.25, tint.g * 0.28, tint.b * 0.32))
		return m
	) as ShaderMaterial


static func rock_shell(tint: Color = Color(0.36, 0.335, 0.34), vein: Color = Color(0.10, 0.48, 0.56), vein_strength: float = 0.34, vertex_tint: float = 0.22) -> ShaderMaterial:
	var key: String = "rockshell_%s_%s_%.2f_%.2f" % [tint.to_html(), vein.to_html(), vein_strength, vertex_tint]
	return _cached(key, func() -> ShaderMaterial:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = ROCK_SHELL_SHADER
		m.set_shader_parameter("base_color", tint)
		m.set_shader_parameter("vein_color", vein)
		m.set_shader_parameter("vein_strength", vein_strength)
		m.set_shader_parameter("vertex_tint", vertex_tint)
		m.set_shader_parameter("deep_color", Color(tint.r * 0.28, tint.g * 0.31, tint.b * 0.35))
		return m
	) as ShaderMaterial


static func debris_rock() -> ShaderMaterial:
	return rock(Color(0.27, 0.25, 0.255), Color(0.10, 0.36, 0.42), 0.18)


static func metal(base: Color = Color(0.38, 0.42, 0.45), rough: float = 0.36, metallic: float = 0.72, grime: float = 0.55) -> ShaderMaterial:
	var key: String = "metal_%s_%.2f_%.2f_%.2f" % [base.to_html(), rough, metallic, grime]
	return _cached(key, func() -> ShaderMaterial:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = METAL_SHADER
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("roughness_base", rough)
		m.set_shader_parameter("metallic_base", metallic)
		m.set_shader_parameter("grime_amount", grime)
		return m
	) as ShaderMaterial


static func steel() -> ShaderMaterial:
	return metal(Color(0.36, 0.40, 0.43), 0.34, 0.80, 0.5)


static func dark_steel() -> ShaderMaterial:
	return metal(Color(0.17, 0.185, 0.20), 0.42, 0.72, 0.6)


static func painted_steel(color: Color) -> ShaderMaterial:
	return metal(color, 0.46, 0.35, 0.42)


static func bronze() -> ShaderMaterial:
	return metal(Color(0.46, 0.30, 0.16), 0.30, 0.85, 0.55)


static func copper() -> ShaderMaterial:
	return metal(Color(0.55, 0.27, 0.15), 0.28, 0.9, 0.45)


static func crystal(a: Color = Color(0.10, 0.72, 0.88), b: Color = Color(0.46, 0.32, 0.95), emission: float = 1.35, speed: float = 1.1) -> ShaderMaterial:
	var key: String = "crystal_%s_%s_%.2f_%.2f" % [a.to_html(), b.to_html(), emission, speed]
	return _cached(key, func() -> ShaderMaterial:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = CRYSTAL_SHADER
		m.set_shader_parameter("color_a", a)
		m.set_shader_parameter("color_b", b)
		m.set_shader_parameter("emission_energy", emission)
		m.set_shader_parameter("pulse_speed", speed)
		return m
	) as ShaderMaterial


static func cave_crystal() -> ShaderMaterial:
	return crystal(Color(0.10, 0.64, 0.82), Color(0.34, 0.24, 0.82), 0.75, 0.65)


static func core_crystal() -> ShaderMaterial:
	return crystal(Color(0.05, 0.62, 0.85), Color(0.42, 0.20, 0.85), 0.18, 1.05)


static func energy(color: Color = Color(0.20, 0.85, 1.0), intensity: float = 1.6, speed: float = 1.2, stripe: float = 6.0) -> ShaderMaterial:
	var key: String = "energy_%s_%.2f_%.2f_%.2f" % [color.to_html(), intensity, speed, stripe]
	return _cached(key, func() -> ShaderMaterial:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = ENERGY_SHADER
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("energy", intensity)
		m.set_shader_parameter("speed", speed)
		m.set_shader_parameter("stripe_scale", stripe)
		return m
	) as ShaderMaterial


static func hazard() -> ShaderMaterial:
	return hazard_material()


static func holo(color: Color = Color(0.35, 0.85, 1.0), alpha: float = 0.55) -> ShaderMaterial:
	var key: String = "holo_%s_%.2f" % [color.to_html(), alpha]
	return _cached(key, func() -> ShaderMaterial:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = HOLO_SHADER
		m.set_shader_parameter("tint", color)
		m.set_shader_parameter("alpha", alpha)
		return m
	) as ShaderMaterial


static func hazard_material() -> ShaderMaterial:
	return _cached("hazard_mat", func() -> ShaderMaterial:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = HAZARD_SHADER
		return m
	) as ShaderMaterial


static func rubber() -> StandardMaterial3D:
	return _cached("rubber", func() -> StandardMaterial3D:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(0.055, 0.06, 0.065)
		m.roughness = 0.92
		m.metallic = 0.0
		return m
	) as StandardMaterial3D


static func grip() -> StandardMaterial3D:
	return _cached("grip", func() -> StandardMaterial3D:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(0.11, 0.12, 0.13)
		m.roughness = 0.88
		m.metallic = 0.15
		return m
	) as StandardMaterial3D


static func emissive(color: Color, energy: float = 3.0, unshaded: bool = true) -> StandardMaterial3D:
	var key: String = "emit_%s_%.2f_%s" % [color.to_html(), energy, str(unshaded)]
	return _cached(key, func() -> StandardMaterial3D:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = color * 0.35
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if not unshaded:
			m.roughness = 0.4
		return m
	) as StandardMaterial3D


static func flat(color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var key: String = "flat_%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	return _cached(key, func() -> StandardMaterial3D:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		return m
	) as StandardMaterial3D


static func suit(color: Color = Color(0.16, 0.29, 0.36)) -> StandardMaterial3D:
	return flat(color, 0.62, 0.25)


static func skin() -> StandardMaterial3D:
	return flat(Color(0.62, 0.42, 0.33), 0.8, 0.0)


static func soft_dot_texture() -> GradientTexture2D:
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = grad
	return tex


static func particle_material(color: Color, additive: bool = true) -> StandardMaterial3D:
	var key: String = "particle_%s_%s" % [color.to_html(), str(additive)]
	return _cached(key, func() -> StandardMaterial3D:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.4
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = soft_dot_texture()
		m.disable_receive_shadows = true
		return m
	) as StandardMaterial3D
