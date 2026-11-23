class_name MaterialLibrary
extends RefCounted
## Shared runtime materials for the prototype. Keeping these in one place makes
## the level, hammer, cradles and gate read as the same industrial kit.

const ROCK_SHADER: Shader = preload("res://shaders/rock.gdshader")
const ROCK_SHELL_SHADER: Shader = preload("res://shaders/rock_shell.gdshader")

static var _cache: Dictionary = {}


static func metal(color: Color = Color(0.34, 0.37, 0.40), roughness: float = 0.55, metallic: float = 0.72) -> StandardMaterial3D:
	# GL Compatibility has no screen-space reflections and this cave has no sky,
	# so a high metallic value renders almost black. The albedo carries the look
	# and a reduced metallic keeps a metal sheen without killing the mid tones.
	var capped_metallic: float = clampf(metallic * 0.40, 0.0, 0.36)
	var key: String = "metal_%s_%.2f_%.2f" % [color.to_html(), roughness, capped_metallic]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = capped_metallic
	material.metallic_specular = 0.55
	_cache[key] = material
	return material


static func painted(color: Color, roughness: float = 0.62) -> StandardMaterial3D:
	var key: String = "paint_%s_%.2f" % [color.to_html(), roughness]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.10
	_cache[key] = material
	return material


static func rubber(color: Color = Color(0.08, 0.085, 0.09)) -> StandardMaterial3D:
	return painted(color, 0.95)


static func emissive(color: Color, energy: float = 2.0, unshaded: bool = true) -> StandardMaterial3D:
	var key: String = "glow_%s_%.2f_%s" % [color.to_html(), energy, str(unshaded)]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.3
	_cache[key] = material
	return material


static func glass(color: Color = Color(0.20, 0.55, 0.62, 0.55)) -> StandardMaterial3D:
	var key: String = "glass_%s" % color.to_html()
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.12
	material.metallic = 0.0
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	_cache[key] = material
	return material


static func rock() -> ShaderMaterial:
	if _cache.has("rock_shader"):
		return _cache["rock_shader"] as ShaderMaterial
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = ROCK_SHADER
	material.set_shader_parameter("albedo_tex", load("res://assets/textures/rock_limestone_base.png") as Texture2D)
	material.set_shader_parameter("rough_tex", load("res://assets/textures/rock_limestone_rough.png") as Texture2D)
	material.set_shader_parameter("normal_tex", load("res://assets/textures/rock_limestone_normal.png") as Texture2D)
	material.set_shader_parameter("normal_strength", 0.85)
	material.set_shader_parameter("uv_scale", 0.14)
	material.set_shader_parameter("tint", Color(0.60, 0.63, 0.68))
	material.set_shader_parameter("sediment_tint", Color(0.92, 0.78, 0.58))
	material.set_shader_parameter("damp_tint", Color(0.18, 0.27, 0.34))
	material.set_shader_parameter("wetness", 0.20)
	_cache["rock_shader"] = material
	return material


## Two-sided variant for the generated cave shell (vertex-colour AO baked in).
static func rock_shell() -> ShaderMaterial:
	if _cache.has("rock_shell"):
		return _cache["rock_shell"] as ShaderMaterial
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = ROCK_SHELL_SHADER
	material.set_shader_parameter("albedo_tex", load("res://assets/textures/rock_limestone_base.png") as Texture2D)
	material.set_shader_parameter("rough_tex", load("res://assets/textures/rock_limestone_rough.png") as Texture2D)
	material.set_shader_parameter("normal_tex", load("res://assets/textures/rock_limestone_normal.png") as Texture2D)
	material.set_shader_parameter("normal_strength", 0.95)
	material.set_shader_parameter("uv_scale", 0.13)
	material.set_shader_parameter("tint", Color(0.62, 0.64, 0.68))
	material.set_shader_parameter("sediment_tint", Color(0.94, 0.80, 0.60))
	material.set_shader_parameter("damp_tint", Color(0.16, 0.25, 0.33))
	material.set_shader_parameter("wetness", 0.24)
	material.set_shader_parameter("vertex_ao_strength", 1.0)
	_cache["rock_shell"] = material
	return material
