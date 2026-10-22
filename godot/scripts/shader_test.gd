extends Node3D
## Тестовая сцена PS1-шейдера: пол, стены, вращающиеся кубы, туман, пост-эффект.
## Пробел/тап — переключить PS1-эффекты (сравнить «до/после»).

var _cubes: Array[MeshInstance3D] = []
var _ps1_on := true
var _post: PS1PostFX
var _cam: Camera3D
var _t := 0.0


func _ready() -> void:
	var floor_tex := PS1Material.make_checker(Color(0.25, 0.28, 0.36), Color(0.19, 0.21, 0.29))
	var wall_tex := PS1Material.make_checker(Color(0.72, 0.66, 0.52), Color(0.62, 0.56, 0.44), 32, 16)
	var box_tex := PS1Material.make_checker(Color(0.85, 0.3, 0.25), Color(0.95, 0.85, 0.3), 32, 4)

	# Пол 20x20 м, разбит на полигоны 2x2 м — так аффинные искажения видны, но не уродливы.
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	plane.subdivide_width = 9
	plane.subdivide_depth = 9
	_add_mesh(plane, Vector3.ZERO, PS1Material.create(floor_tex, Color.WHITE, Vector2(10, 10)))

	# Стены «офиса».
	for i in 3:
		var wall := BoxMesh.new()
		wall.size = Vector3(6, 2.6, 0.4)
		_add_mesh(wall, Vector3(-6 + i * 6, 1.3, -5), PS1Material.create(wall_tex, Color.WHITE, Vector2(3, 1)))

	for i in 3:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		_cubes.append(_add_mesh(box, Vector3(-2.5 + i * 2.5, 0.9, 0), PS1Material.create(box_tex)))

	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.8
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.5, 1.5)
	lamp.omni_range = 6
	lamp.light_color = Color(1.0, 1.0, 0.85)
	add_child(lamp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.36, 0.34)
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.035, 0.045)
	env.fog_density = 0.07
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_post = PS1PostFX.new()
	add_child(_post)


func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	for i in _cubes.size():
		_cubes[i].rotation = Vector3(_t * 0.6 + i, _t * (0.8 + i * 0.3), 0)
	# Камера медленно облетает сцену — так лучше видно дрожание вершин.
	var a := _t * 0.25
	_cam.position = Vector3(sin(a) * 7.0, 4.5, cos(a) * 7.0 + 1.0)
	_cam.look_at(Vector3(0, 0.8, 0))


func _unhandled_input(event: InputEvent) -> void:
	var toggle: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE)
	if toggle:
		_ps1_on = not _ps1_on
		PS1Material.set_global_strength(1.0 if _ps1_on else 0.0, 1.0 if _ps1_on else 0.0)
		_post.visible = _ps1_on
