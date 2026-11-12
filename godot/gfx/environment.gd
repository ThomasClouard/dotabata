class_name GameEnv
extends Node3D
## Ciel, soleil, brouillard, mer, nuages et post-traitement. Les réglages s'adaptent au moteur de rendu
## (Forward+, ou Compatibilité si la carte graphique l'impose) et au niveau de qualité choisi.

const SUN_DIR := Vector3(0.5, 0.4, 0.42)  # soleil de fin d'après-midi : bas et doré, ombres longues

var env := Environment.new()
var sun := DirectionalLight3D.new()
var sea := MeshInstance3D.new()
var clouds := MultiMeshInstance3D.new()
var horizon := Color.WHITE
var quality := 2
var forward_plus := true

var _sky_mat := ShaderMaterial.new()
var _sea_mat := ShaderMaterial.new()
var _cam_attr := CameraAttributesPractical.new()
var _vignette := ColorRect.new()  # assombrit doucement les coins (multiplication, sans relire l'image)
var _cloud_mat := ShaderMaterial.new()


func _ready() -> void:
	forward_plus = RenderingServer.get_current_rendering_method() == "forward_plus"

	_sky_mat.shader = load("res://gfx/shaders/sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.46
	# l'ombre prend une teinte bleutée (contraste chaud au soleil, froid à l'ombre)
	env.ambient_light_color = Color("#a9c6ff")
	env.ambient_light_sky_contribution = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 3.2
	env.tonemap_exposure = 0.95
	# essais : --tonemap=agx|filmic|aces|linear
	var tm := str(Config.args.get("tonemap", ""))
	if tm != "":
		env.tonemap_mode = {"agx": Environment.TONE_MAPPER_AGX, "filmic": Environment.TONE_MAPPER_FILMIC, "aces": Environment.TONE_MAPPER_ACES, "linear": Environment.TONE_MAPPER_LINEAR}.get(tm, env.tonemap_mode)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 90.0
	env.fog_depth_end = 360.0
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	we.camera_attributes = _cam_attr
	add_child(we)

	sun.light_color = Gfx.col(0xffdcaa)
	sun.light_energy = 1.15
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.4
	add_child(sun)
	sun.look_at_from_position(SUN_DIR.normalized() * 70.0, Vector3.ZERO)

	_sea_mat.shader = load("res://gfx/shaders/sea.gdshader")
	sea.material_override = _sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.extra_cull_margin = 16.0
	sea.visible = false
	add_child(sea)

	if not forward_plus:
		# le moteur Compatibilité éclaire plus fort à réglages égaux : on compense
		sun.light_energy = 0.7
		env.ambient_light_energy = 0.42
		env.tonemap_white = 4.0
	_build_clouds()
	# vignettage : sous l'interface, au-dessus de la 3D
	var vl := CanvasLayer.new()
	vl.layer = -1
	add_child(vl)
	var vs := Shader.new()
	vs.code = """shader_type canvas_item;
render_mode blend_mul, unshaded;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.25, 1.0);
	float v = smoothstep(0.38, 0.95, length(d));
	COLOR = vec4(mix(vec3(1.0), vec3(0.62, 0.58, 0.78), v), 1.0);
}"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	_vignette.material = vm
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vl.add_child(_vignette)
	set_sky(0x8fd3ff)
	apply_quality(Config.quality)


## Applique un niveau de qualité : 0 = légers (ni ombres ni halo), 1 = moyens (ombres, halo, vignettage,
## anticrénelage rapide), 2 = élevés (ombres fines à pénombre, occlusion ambiante, herbe).
func apply_quality(q: int) -> void:
	quality = q
	var full := q >= 2 and forward_plus
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if full else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0 if full else 75.0
	sun.light_angular_distance = 0.8 if full else 0.0  # pénombre qui s'élargit avec la distance
	RenderingServer.directional_shadow_atlas_set_size(4096 if full else 2048, true)
	env.glow_enabled = q >= 1
	env.glow_strength = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = full
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	# Reflets en espace écran et flou des lointains retirés : ils coûtaient près de 7 ms par image sur une Radeon R9
	# pour un effet peu visible ; ce budget sert à l'écume, aux nuages, à la végétation et au vignettage.
	env.ssr_enabled = false
	_cam_attr.dof_blur_far_enabled = false
	env.glow_intensity = 0.7 if forward_plus else 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.0
	_vignette.visible = q >= 1
	var vp := get_viewport()
	# MSAA + occlusion ambiante / reflets écran noircit l'image par blocs avec les vieux pilotes Radeon : FXAA à la place
	var msaa := q >= 2 and not (full and Config.msaa_breaks_screen_fx())
	vp.msaa_3d = Viewport.MSAA_2X if msaa else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q >= 1 and forward_plus and not msaa else Viewport.SCREEN_SPACE_AA_DISABLED
	if Config.args.has("scale"):
		vp.scaling_3d_scale = float(Config.args["scale"])
	# mesure du coût de chaque effet : --fx=-ssao,-msaa,-glow,-shadows,-vignette,-grass
	var off := str(Config.args.get("fx", "")).split(",", false)
	if off.has("-vignette"):
		_vignette.visible = false
	if off.has("-ssao"):
		env.ssao_enabled = false
	if off.has("-msaa"):
		vp.msaa_3d = Viewport.MSAA_DISABLED
	if off.has("-glow"):
		env.glow_enabled = false
	if off.has("-shadows"):
		sun.shadow_enabled = false
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	var sub: int = [60, 110, 200 if forward_plus else 140][q]
	plane.subdivide_width = sub
	plane.subdivide_depth = sub
	sea.mesh = plane
	_sea_mat.set_shader_parameter("detail", 1.0 if q >= 1 else 0.0)


static func _hsl_offset(c: Color, dh: float, ds: float, dl: float) -> Color:
	# décalage teinte / saturation / luminosité, comme THREE.Color.offsetHSL
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) / 2.0
	var h := 0.0
	var s := 0.0
	if mx != mn:
		var d := mx - mn
		s = d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
		if mx == c.r:
			h = (c.g - c.b) / d + (6.0 if c.g < c.b else 0.0)
		elif mx == c.g:
			h = (c.b - c.r) / d + 2.0
		else:
			h = (c.r - c.g) / d + 4.0
		h /= 6.0
	h = fposmod(h + dh, 1.0)
	s = clampf(s + ds, 0.0, 1.0)
	l = clampf(l + dl, 0.0, 1.0)
	if s == 0.0:
		return Color(l, l, l)
	var q := l * (1.0 + s) if l <= 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0))


static func _hue(p: float, q: float, t: float) -> float:
	t = fposmod(t, 1.0)
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p


func set_sky(color: int) -> void:
	var lin := Gfx.col(color).srgb_to_linear()
	var top := _hsl_offset(lin, -0.02, 0.16, -0.26).linear_to_srgb()
	horizon = lin.lerp(Color.WHITE, 0.42).linear_to_srgb()
	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sea_mat.set_shader_parameter("sky_tint", horizon)
	env.fog_light_color = horizon


## Place la mer à l'altitude `y` (null = pas de mer).
func set_sea(y: Variant, color := 0x1fb6e0) -> void:
	sea.visible = y != null
	if y == null:
		return
	sea.position.y = y
	var lin := Gfx.col(color).srgb_to_linear()
	_sea_mat.set_shader_parameter("deep", Color(lin.r * 0.62, lin.g * 0.62, lin.b * 0.62).linear_to_srgb())
	_sea_mat.set_shader_parameter("light", lin.lerp(Color.WHITE, 0.3).linear_to_srgb())


func update(now: float, focus: Vector3, dt: float) -> void:
	# période commune à toutes les vagues : le temps peut boucler sans à-coup
	_sea_mat.set_shader_parameter("time_s", fposmod(now, 40.0 * PI))
	sea.position.x = roundf(focus.x / 20.0) * 20.0
	sea.position.z = roundf(focus.z / 20.0) * 20.0
	clouds.rotation.y += dt * 0.004


## Nuages moelleux : toutes les boules dans un seul MultiMesh.
func _build_clouds() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Shapes.icosphere(1.0, 2)
	mm.instance_count = 22 * 7
	var i := 0
	for c in 22:
		var a := (c / 22.0) * TAU + randf() * 0.3
		var r := 110.0 + randf() * 140.0
		var cx := sin(a) * r
		var cy := 10.0 + randf() * 90.0
		var cz := cos(a) * r
		var sc := 5.0 + randf() * 8.0
		for k in 7:
			var s := sc * (0.55 + randf() * 0.6) * (1.3 if k == 0 else 1.0)
			var p := Vector3(cx + (k - 3) * sc * 0.75 + randf() * sc * 0.4, cy + (k % 2) * sc * 0.25 + randf() * sc * 0.3 - absf(k - 3) * sc * 0.08, cz + (randf() - 0.5) * sc)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s * 0.72, s)), p))
			i += 1
	_cloud_mat.shader = load("res://gfx/shaders/clouds.gdshader")
	_cloud_mat.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	clouds.multimesh = mm
	clouds.material_override = _cloud_mat
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.custom_aabb = AABB(Vector3(-300, -20, -300), Vector3(600, 160, 600))
	add_child(clouds)
