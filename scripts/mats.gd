class_name Mats
extends RefCounted

## Shared materials.  Every merged chunk mesh only ever references these, so
## the renderer can batch aggressively.

static var _cache: Dictionary = {}

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

void fragment() {
	// vertex colour = the colour of the neon tube / lit window
	ALBEDO = COLOR.rgb;
}
"""

static func get_mat(key: int) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: Material
	match key:
		MeshBatch.GLASS:
			var gm := StandardMaterial3D.new()
			gm.vertex_color_use_as_albedo = true
			gm.vertex_color_is_srgb = true
			gm.metallic = 0.2
			gm.roughness = 0.22
			gm.metallic_specular = 0.7
			gm.cull_mode = BaseMaterial3D.CULL_BACK
			gm.clearcoat_enabled = true
			gm.clearcoat = 0.6
			gm.clearcoat_roughness = 0.06
			m = gm
		MeshBatch.GLOW:
			var sh := Shader.new()
			sh.code = GLOW_SHADER
			var sm := ShaderMaterial.new()
			sm.shader = sh
			m = sm
		_:
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 0.92
			mat.metallic = 0.0
			mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			m = mat
	_cache[key] = m
	return m

## Simple emissive material factory (used by cars, traffic lights, ...).
static func emissive(color: Color, energy: float = 1.0, unshaded: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.vertex_color_use_as_albedo = false
	return mat
