@tool
class_name ZinoGraphics
extends RefCounted
## Graphics quality presets. ULTRA MAX is the default for both the editor preview and game output.
##
## Presets are user-controlled. Nothing here ever lowers settings on its own: the editor preview
## preset and the game output preset are stored separately, and assets are never modified.
## Forward+ (Vulkan/D3D12/Metal) is required for SDFGI, SSR, SSIL and volumetric fog; on the
## Mobile renderer (iOS) those flags are simply ignored by Godot and reported by `capability_warnings`.

const DEFAULT_PRESET := "ultraMax"
const ORDER := ["ultraMax", "ultra", "high", "balanced", "performance"]

const PRESETS := {
	"ultraMax": {
		"label": "Ultra Max", "msaa": 4, "taa": true, "screenSpaceAA": "smaa", "renderScale": 1.0, "upscaler": "bilinear",
		"directionalShadowSize": 8192, "positionalShadowSize": 8192, "softShadowQuality": 5, "shadowDistance": 400.0,
		"sdfgi": true, "sdfgiCascades": 6, "sdfgiRayCount": 4, "ssr": true, "ssrSteps": 256, "ssrRoughnessQuality": 3,
		"ssao": true, "ssaoQuality": 4, "ssil": true, "ssilQuality": 4, "volumetricFog": true, "fogVolume": 128,
		"glow": true, "anisotropy": 4, "lodThreshold": 0.5, "subsurfaceQuality": 3,
	},
	"ultra": {
		"label": "Ultra", "msaa": 4, "taa": true, "screenSpaceAA": "off", "renderScale": 1.0, "upscaler": "bilinear",
		"directionalShadowSize": 8192, "positionalShadowSize": 4096, "softShadowQuality": 4, "shadowDistance": 300.0,
		"sdfgi": true, "sdfgiCascades": 4, "sdfgiRayCount": 3, "ssr": true, "ssrSteps": 128, "ssrRoughnessQuality": 2,
		"ssao": true, "ssaoQuality": 3, "ssil": true, "ssilQuality": 2, "volumetricFog": true, "fogVolume": 96,
		"glow": true, "anisotropy": 4, "lodThreshold": 1.0, "subsurfaceQuality": 2,
	},
	"high": {
		"label": "High", "msaa": 2, "taa": true, "screenSpaceAA": "off", "renderScale": 1.0, "upscaler": "bilinear",
		"directionalShadowSize": 4096, "positionalShadowSize": 4096, "softShadowQuality": 3, "shadowDistance": 200.0,
		"sdfgi": true, "sdfgiCascades": 4, "sdfgiRayCount": 2, "ssr": true, "ssrSteps": 64, "ssrRoughnessQuality": 1,
		"ssao": true, "ssaoQuality": 2, "ssil": false, "ssilQuality": 1, "volumetricFog": true, "fogVolume": 64,
		"glow": true, "anisotropy": 3, "lodThreshold": 1.0, "subsurfaceQuality": 1,
	},
	"balanced": {
		"label": "Balanced", "msaa": 0, "taa": true, "screenSpaceAA": "off", "renderScale": 0.77, "upscaler": "fsr2",
		"directionalShadowSize": 4096, "positionalShadowSize": 2048, "softShadowQuality": 2, "shadowDistance": 150.0,
		"sdfgi": false, "sdfgiCascades": 4, "sdfgiRayCount": 1, "ssr": false, "ssrSteps": 32, "ssrRoughnessQuality": 0,
		"ssao": true, "ssaoQuality": 1, "ssil": false, "ssilQuality": 0, "volumetricFog": false, "fogVolume": 64,
		"glow": true, "anisotropy": 2, "lodThreshold": 2.0, "subsurfaceQuality": 1,
	},
	"performance": {
		"label": "Performance", "msaa": 0, "taa": false, "screenSpaceAA": "fxaa", "renderScale": 0.67, "upscaler": "fsr2",
		"directionalShadowSize": 2048, "positionalShadowSize": 1024, "softShadowQuality": 1, "shadowDistance": 90.0,
		"sdfgi": false, "sdfgiCascades": 4, "sdfgiRayCount": 0, "ssr": false, "ssrSteps": 16, "ssrRoughnessQuality": 0,
		"ssao": false, "ssaoQuality": 0, "ssil": false, "ssilQuality": 0, "volumetricFog": false, "fogVolume": 64,
		"glow": false, "anisotropy": 1, "lodThreshold": 4.0, "subsurfaceQuality": 0,
	},
}

static func preset(preset_id: String) -> Dictionary:
	return PRESETS.get(preset_id, PRESETS[DEFAULT_PRESET])

static func label(preset_id: String) -> String:
	return preset(preset_id)["label"]

static func is_forward_plus() -> bool:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) == "forward_plus"

## Features the active renderer cannot provide for this preset (shown to the user, never silently dropped).
static func capability_warnings(preset_id: String) -> PackedStringArray:
	var p := preset(preset_id)
	var w := PackedStringArray()
	if not is_forward_plus():
		for key in ["sdfgi", "ssr", "ssil", "volumetricFog"]:
			if p.get(key, false):
				w.append("%s needs the Forward+ renderer and is unavailable on '%s'." % [key, ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	return w

## Applies viewport-level and global quality settings.
static func apply_viewport(vp: Viewport, preset_id: String) -> void:
	var p := preset(preset_id)
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(int(p["msaa"]), Viewport.MSAA_DISABLED)
	vp.use_taa = p["taa"]
	vp.screen_space_aa = {"fxaa": Viewport.SCREEN_SPACE_AA_FXAA, "smaa": Viewport.SCREEN_SPACE_AA_SMAA}.get(p["screenSpaceAA"], Viewport.SCREEN_SPACE_AA_DISABLED)
	vp.scaling_3d_scale = float(p["renderScale"])
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if p["upscaler"] == "fsr2" and float(p["renderScale"]) < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.positional_shadow_atlas_size = int(p["positionalShadowSize"])
	vp.mesh_lod_threshold = float(p["lodThreshold"])
	vp.anisotropic_filtering_level = int(p["anisotropy"]) as Viewport.AnisotropicFiltering
	RenderingServer.directional_shadow_atlas_set_size(int(p["directionalShadowSize"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p["softShadowQuality"]) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(int(p["softShadowQuality"]) as RenderingServer.ShadowQuality)
	RenderingServer.environment_set_ssao_quality(int(p["ssaoQuality"]) as RenderingServer.EnvironmentSSAOQuality, false, 0.5, 3, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(int(p["ssilQuality"]) as RenderingServer.EnvironmentSSILQuality, false, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_sdfgi_ray_count(int(p["sdfgiRayCount"]) as RenderingServer.EnvironmentSDFGIRayCount)
	RenderingServer.environment_set_volumetric_fog_volume_size(int(p["fogVolume"]), int(p["fogVolume"]))
	RenderingServer.sub_surface_scattering_set_quality(int(p["subsurfaceQuality"]) as RenderingServer.SubSurfaceScatteringQuality)

## Builds the Environment for a scene's settings at the given quality.
static func build_environment(settings: Dictionary, preset_id: String) -> Environment:
	var p := preset(preset_id)
	var env := Environment.new()
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.turbidity = 8.0
	sky_mat.mie_coefficient = 0.004
	sky_mat.sun_disk_scale = 1.2
	sky_mat.ground_color = Color(0.18, 0.2, 0.17)
	sky_mat.energy_multiplier = 1.0
	sky_mat.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var hdri := ZinoAssets.load_texture(str(settings.get("skyHdri", ""))) if settings.get("skyHdri") else null
	if hdri:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri
		pano.energy_multiplier = float(settings.get("skyEnergy", 1.0))
		sky.sky_material = pano
	sky.process_mode = Sky.PROCESS_MODE_QUALITY if preset_id in ["ultraMax", "ultra"] else Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = Sky.RADIANCE_SIZE_512 if preset_id == "ultraMax" else Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(settings.get("ambientIntensity", 1.0))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(settings.get("exposure", 1.0))

	env.ssao_enabled = p["ssao"]
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = p["ssil"]
	env.ssil_radius = 4.0
	env.ssr_enabled = p["ssr"]
	env.ssr_max_steps = int(p["ssrSteps"])
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25

	env.sdfgi_enabled = p["sdfgi"]
	env.sdfgi_cascades = int(p["sdfgiCascades"])
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_min_cell_size = 0.2
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT

	env.glow_enabled = p["glow"]
	var fx: Dictionary = settings.get("postFx", {})
	env.glow_intensity = float(fx.get("glowIntensity", 0.35))
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	var fog_on: bool = settings.get("fogEnabled", true)
	var fog_color := ZinoFormat.col(settings.get("fogColor"), Color(0.72, 0.78, 0.86))
	env.fog_enabled = fog_on
	env.fog_light_color = fog_color
	env.fog_density = float(settings.get("fogDensity", 0.0012))
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = fog_on and p["volumetricFog"]
	env.volumetric_fog_density = float(settings.get("fogDensity", 0.0012)) * 1.5
	env.volumetric_fog_albedo = fog_color
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_sky_affect = 0.2

	env.adjustment_enabled = true
	env.adjustment_contrast = float(fx.get("contrast", 1.04))
	env.adjustment_saturation = float(fx.get("saturation", 1.06))
	return env

## Applies quality to a directional (sun) light.
static func apply_sun(light: DirectionalLight3D, preset_id: String) -> void:
	var p := preset(preset_id)
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_blend_splits = preset_id in ["ultraMax", "ultra"]
	light.directional_shadow_max_distance = float(p["shadowDistance"])
	light.shadow_blur = 1.5 if preset_id == "ultraMax" else 1.0
	light.shadow_normal_bias = 1.2
