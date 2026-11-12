class_name ScreenFx
extends CanvasLayer
## Effets d'écran au-dessus de la 3D et sous l'interface : éclair coloré avec aberration chromatique lors d'un
## impact, et lignes de vitesse quand le joueur va très vite. Chaque calque n'est affiché (et ne coûte) que
## pendant son effet : l'aberration relit l'image, ce qui demande une copie de l'écran.

var _hit := ColorRect.new()
var _lines := ColorRect.new()
var _hit_mat := ShaderMaterial.new()
var _lines_mat := ShaderMaterial.new()
var _k := 0.0  # force de l'impact en cours, qui s'éteint
var _speed := 0.0


func _ready() -> void:
	layer = -1
	var hs := Shader.new()
	hs.code = """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float k = 0.0;
uniform vec3 flash : source_color = vec3(1.0);
void fragment() {
	vec2 d = SCREEN_UV - 0.5;
	// les trois couleurs s'écartent vers les bords
	vec2 o = d * 0.025 * k;
	vec3 c = vec3(texture(screen, SCREEN_UV + o).r, texture(screen, SCREEN_UV).g, texture(screen, SCREEN_UV - o).b);
	c = mix(c, flash, k * 0.35 * (0.6 + length(d)));
	COLOR = vec4(c, 1.0);
}"""
	_hit_mat.shader = hs
	_hit.material = _hit_mat
	var ls := Shader.new()
	ls.code = """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform float k = 0.0;
// lignes de vitesse : traits radiaux qui filent vers les bords, seulement en périphérie
float hash(float x) { return fract(sin(x * 91.3) * 47453.5); }
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.6, 1.0);
	float r = length(d);
	float a = atan(d.y, d.x);
	float cell = floor(a * 40.0);
	float on = step(0.55, hash(cell));
	float run = fract(r * 1.5 - TIME * 2.5 - hash(cell + 7.0));
	float streak = on * smoothstep(0.0, 0.1, run) * (1.0 - smoothstep(0.25, 0.55, run));
	float thin = 1.0 - smoothstep(0.0, 0.35, abs(fract(a * 40.0) - 0.5));
	float edge = smoothstep(0.35, 0.8, r);
	COLOR = vec4(vec3(1.0) * streak * thin * edge * k * 0.55, 1.0);
}"""
	_lines_mat.shader = ls
	_lines.material = _lines_mat
	for r: ColorRect in [_lines, _hit]:
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.visible = false
		add_child(r)


func hit(k: float, flash: Color) -> void:
	_k = maxf(_k, k)
	_hit_mat.set_shader_parameter("flash", flash)


## Appelé à chaque image par Main : vitesse horizontale et verticale du joueur local (m/s).
func update(dt: float, h_speed: float, v_speed: float) -> void:
	_k *= exp(-7.0 * dt)
	if _k < 0.01:
		_k = 0.0
	_hit.visible = _k > 0.0
	if _hit.visible:
		_hit_mat.set_shader_parameter("k", _k)
	# au-delà de la course normale (7 m/s) : canon, trampoline, chute libre
	var target := clampf(maxf(h_speed - 10.0, v_speed - 22.0) / 10.0, 0.0, 1.0)
	_speed += (target - _speed) * minf(1.0, dt * 6.0)
	_lines.visible = _speed > 0.02
	if _lines.visible:
		_lines_mat.set_shader_parameter("k", _speed)
