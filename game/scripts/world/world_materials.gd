class_name WorldMaterials
extends RefCounted
## Main-thread native materials with repeatable, mipmapped surface-specific textures.

const PROFILES := {
	"paint": [0.53, 0.15, 0.5], "concrete": [0.9, 0.0, 0.25],
	"brick": [0.85, 0.0, 1.0], "metal": [0.42, 0.6, 0.5],
	"glass": [0.16, 0.55, 0.25], "plaster": [0.8, 0.0, 0.5],
	"asphalt": [0.97, 0.0, 1.0], "sandstone": [0.9, 0.0, 0.125],
	"grass": [0.92, 0.0, 0.5], "gravel": [0.95, 0.0, 1.0],
	"bark": [0.92, 0.0, 0.5], "foliage": [0.95, 0.0, 0.5],
	"tile": [0.68, 0.05, 0.5], "screen": [0.3, 0.15, 1.0],
	"landing": [0.6, 0.25, 0.25], "snow": [0.85, 0.0, 0.5],
	"basalt": [0.95, 0.0, 0.25], "lava": [0.6, 0.1, 0.5]
}
static var materials: Dictionary = {}
static var textures: Dictionary = {}

static func warm_textures() -> void:
	# Prepare the small fixed texture vocabulary at startup, before flight.
	for surface: String in PROFILES: texture_for(surface)

static func material_for(color: Color, surface: String = "paint") -> StandardMaterial3D:
	var key := surface + "|" + color.to_html()
	if materials.has(key):
		return materials[key]
	var profile: Array = PROFILES.get(surface, PROFILES.paint)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = profile[0]
	material.metallic = profile[1]
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * float(profile[2])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.albedo_texture = texture_for(surface)
	if surface in ["screen", "landing", "lava"]:
		material.emission_enabled = true
		material.emission = color * (0.3 if surface == "screen" else 0.07)
	materials[key] = material
	return material

static func texture_for(surface: String) -> ImageTexture:
	if textures.has(surface):
		return textures[surface]
	var pixels := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for x in 128:
		for y in 128:
			var grain := LegacyWorldProvider.noise_at(x, y, 59)
			var shade := 0.94 + grain * 0.06
			match surface:
				"brick":
					var row := y / 16
					var mortar := y % 16 < 2 or posmod(x + (32 if row % 2 else 0), 64) < 2
					shade = 0.58 if mortar else 0.83 + LegacyWorldProvider.noise_at((x + (32 if row % 2 else 0)) / 64, row, 23) * 0.17 + grain * 0.03
				"concrete":
					shade = 0.78 if x < 2 or y < 2 else 0.94 + grain * 0.06
				"metal":
					shade = 0.69 if x % 16 < 2 else 0.88 + sin(float(x % 16) / 16 * PI) * 0.1 + grain * 0.02
				"glass":
					shade = 0.55 if x < 3 or y < 3 else 0.83 + sin(float(x) / 128 * TAU) * 0.12
				"asphalt":
					shade = 0.85 + grain * 0.15
				"sandstone":
					shade = 0.94 + sin(float(y) * TAU / 64 + sin(float(x) * TAU / 128) * 0.6) * 0.018 + grain * 0.02
				"grass", "foliage":
					shade = 0.92 + grain * 0.035 + sin(float(x) * TAU / 128 + cos(float(y) * TAU / 128)) * 0.025
				"gravel":
					shade = 0.78 + LegacyWorldProvider.noise_at(x / 4, y / 4, 47) * 0.2 + grain * 0.02
				"snow":
					shade = 0.89 + sin(float(y) * TAU / 64 + sin(float(x) * TAU / 128)) * 0.055 + grain * 0.035
				"bark":
					shade = 0.8 + sin(float(x) * TAU / 16) * 0.1 + grain * 0.08
				"tile":
					shade = 0.62 if x % 32 < 2 or y % 32 < 2 else 0.92 + grain * 0.08
				"landing":
					shade = 0.58 if (x > 27 and x < 36) or (x > 91 and x < 100) or (y > 58 and y < 69 and x > 27 and x < 100) else 0.96
			pixels.set_pixel(x, y, Color(shade, shade, shade))
	pixels.generate_mipmaps()
	var texture := ImageTexture.create_from_image(pixels)
	textures[surface] = texture
	return texture
