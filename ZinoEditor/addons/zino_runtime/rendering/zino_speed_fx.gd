class_name ZinoSpeedFx
extends CanvasLayer
## Speed blur: a radial screen-space blur whose strength follows the player's speed.
## Godot has no built-in camera motion blur; this is the racing-game standard approximation.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform vec2 center = vec2(0.5, 0.55);
void fragment() {
	vec2 dir = SCREEN_UV - center;
	float falloff = smoothstep(0.12, 0.75, length(dir));
	vec3 acc = vec3(0.0);
	const int N = 10;
	for (int i = 0; i < N; i++) {
		float t = float(i) / float(N - 1);
		acc += texture(screen_tex, SCREEN_UV - dir * amount * falloff * t * 0.09).rgb;
	}
	COLOR = vec4(acc / float(N), 1.0);
}
"""

var context
var strength := 1.0
var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)

func current_amount() -> float:
	var v = _mat.get_shader_parameter("amount")
	return float(v) if v != null else 0.0

func _process(delta: float) -> void:
	var car: ZinoVehicle = context.vehicle("player") if context else null
	var target := 0.0
	if car:
		target = clampf((car.speed_kmh - 90.0) / 160.0, 0.0, 1.0) * strength
		if car.nitro_time_left > 0.0:
			target = minf(1.4, target + 0.4)
	var a := lerpf(current_amount(), target, 1.0 - exp(-4.0 * delta))
	_mat.set_shader_parameter("amount", a)
	_rect.visible = a > 0.01
