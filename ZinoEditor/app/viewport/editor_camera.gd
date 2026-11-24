class_name ZinoEditorCamera
extends Camera3D
## Orbit / pan / zoom / fly editor camera with perspective and orthographic Top, Front and Side views.

signal view_changed(view_name: String)

var pivot := Vector3(0, 0, 0)
var yaw := deg_to_rad(35.0)      # rotation around +Y
var pitch := deg_to_rad(-28.0)   # negative looks down
var distance := 60.0
var view_name := "Perspective"
var fly_speed := 20.0

func _ready() -> void:
	near = 0.05
	far = 6000.0
	fov = 60.0
	_apply()

func set_view(view: String) -> void:
	view_name = view
	match view:
		"Top":
			yaw = 0.0
			pitch = deg_to_rad(-89.999)
			projection = PROJECTION_ORTHOGONAL
		"Front":
			yaw = 0.0
			pitch = 0.0
			projection = PROJECTION_ORTHOGONAL
		"Side":
			yaw = deg_to_rad(90.0)
			pitch = 0.0
			projection = PROJECTION_ORTHOGONAL
		_:
			view_name = "Perspective"
			projection = PROJECTION_PERSPECTIVE
			if absf(pitch) > deg_to_rad(85.0) or pitch == 0.0:
				pitch = deg_to_rad(-28.0)
				yaw = deg_to_rad(35.0)
	_apply()
	view_changed.emit(view_name)

func is_ortho() -> bool:
	return projection == PROJECTION_ORTHOGONAL

func orbit(delta_px: Vector2) -> void:
	if is_ortho():
		# Orbiting leaves an orthographic view and returns to perspective, like most DCC tools.
		projection = PROJECTION_PERSPECTIVE
		view_name = "Perspective"
		view_changed.emit(view_name)
	yaw -= delta_px.x * 0.006
	pitch = clampf(pitch - delta_px.y * 0.006, deg_to_rad(-89.0), deg_to_rad(89.0))
	_apply()

func pan(delta_px: Vector2, viewport_height: float) -> void:
	var world_per_px := (size if is_ortho() else 2.0 * distance * tan(deg_to_rad(fov) * 0.5)) / maxf(1.0, viewport_height)
	var b := global_transform.basis
	pivot += (-b.x * delta_px.x + b.y * delta_px.y) * world_per_px
	_apply()

func zoom(steps: float) -> void:
	distance = clampf(distance * pow(1.15, steps), 0.5, 4000.0)
	_apply()

func fly(direction: Vector3, delta: float, fast: bool) -> void:
	var b := global_transform.basis
	var move := (b.x * direction.x + Vector3.UP * direction.y - b.z * direction.z) * fly_speed * (3.0 if fast else 1.0) * delta
	pivot += move
	_apply()

func frame(aabb: AABB) -> void:
	pivot = aabb.get_center()
	var radius := maxf(aabb.size.length() * 0.5, 1.0)
	distance = radius / sin(deg_to_rad(fov) * 0.5) * 1.15
	_apply()

func _apply() -> void:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var offset := basis * Vector3(0, 0, distance)
	global_transform = Transform3D(basis, pivot + offset)
	size = distance
