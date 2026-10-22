class_name Fx
extends Node3D
## Частицы-билборды, трассеры, вспышки, кольца шума (как в MGS — видно, насколько ты громкий),
## лужи крови под трупами.

var parts: Array = []
var _mats: Dictionary = {}
var _quad: QuadMesh


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE


func _mat(tex: String, additive: bool, billboard: bool) -> StandardMaterial3D:
	var key := "%s:%s:%s" % [tex, additive, billboard]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_texture = OfficeTex.get_tex(tex)
	m.vertex_color_use_as_albedo = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mats[key] = m
	return m


## Универсальная частица.
func spawn(pos: Vector3, vel: Vector3, life: float, size: float, tex: String, col: Color,
		additive: bool = false, gravity: float = 0.0, grow: float = 0.0, flat: bool = false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := _mat(tex, additive, not flat).duplicate() as StandardMaterial3D
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	mi.scale = Vector3(size, size, size)
	if flat:
		mi.rotation = Vector3(-PI / 2, randf() * TAU, 0)
	add_child(mi)
	parts.append({"n": mi, "m": m, "v": vel, "life": life, "max": life, "size": size, "g": gravity, "grow": grow, "a": col.a})


func update(dt: float) -> void:
	var i := parts.size() - 1
	while i >= 0:
		var p: Dictionary = parts[i]
		p.life -= dt
		if p.life <= 0.0:
			p.n.queue_free()
			parts.remove_at(i)
		else:
			p.v.y -= p.g * dt
			var n: MeshInstance3D = p.n
			n.position += p.v * dt
			if n.position.y < 0.02 and p.g > 0.0:
				n.position.y = 0.02
				p.v = Vector3.ZERO
			var k: float = p.life / p.max
			var s: float = p.size + p.grow * (1.0 - k)
			n.scale = Vector3(s, s, s)
			p.m.albedo_color.a = p.a * minf(1.0, k * 2.0)
		i -= 1


func burst(pos: Vector3, col: Color, n: int, spd: float) -> void:
	for _i in n:
		spawn(pos, Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)) * spd, 0.6, 0.12, "p_dot", col, true, 3.0)


func blood(pos: Vector3, n: int) -> void:
	for _i in n:
		spawn(pos, Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.5), randf_range(-1.5, 1.5)), 0.7, 0.09, "p_solid", Color(0.6, 0.02, 0.02), false, 9.0)


func sparks(pos: Vector3) -> void:
	for _i in 6:
		spawn(pos, Vector3(randf_range(-2, 2), randf_range(0, 3), randf_range(-2, 2)), 0.25, 0.07, "p_dot", Color(1, 0.9, 0.5), true, 8.0)


func glass(pos: Vector3) -> void:
	for _i in 10:
		spawn(pos + Vector3(0, 0.2, 0), Vector3(randf_range(-2.5, 2.5), randf_range(1, 3), randf_range(-2.5, 2.5)), 0.6, 0.12, "p_glass", Color(0.8, 1, 0.9), false, 9.0)


func flash(pos: Vector3) -> void:
	spawn(pos, Vector3.ZERO, 0.06, 0.6, "p_flash", Color(1, 0.95, 0.7), true)


func tracer(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.9, 0.5)
	mi.material_override = m
	add_child(mi)
	parts.append({"n": mi, "m": m, "v": Vector3.ZERO, "life": 0.06, "max": 0.06, "size": 1.0, "g": 0.0, "grow": 0.0, "a": 1.0})


func smoke(pos: Vector3, n: int, col: Color, radius: float) -> void:
	for _i in n:
		var a := randf() * TAU
		var r := randf() * radius * 0.6
		spawn(pos + Vector3(cos(a) * r, 0.3 + randf() * 0.8, sin(a) * r), Vector3(cos(a), 0.4, sin(a)) * randf_range(0.5, 1.5),
			1.4, 0.8, "smoke", col, false, -0.2, 1.4)


func explosion(pos: Vector3) -> void:
	spawn(pos + Vector3(0, 0.6, 0), Vector3.ZERO, 0.35, 1.5, "blast", Color.WHITE, true, 0.0, 3.5)
	for _i in 10:
		spawn(pos + Vector3(0, 0.5, 0), Vector3(randf_range(-3, 3), randf_range(1, 4), randf_range(-3, 3)), 0.5, 0.5, "blast", Color(1, 0.8, 0.5), true, 2.0, 0.5)
	smoke(pos, 10, Color(0.3, 0.3, 0.3), 2.0)
	decal(pos, "stain", Color(0.05, 0.05, 0.05, 0.9), 1.6)


## Кольцо шума на полу: показывает игроку радиус слышимости.
func noise_ring(pos: Vector3, r: float, col: Color) -> void:
	spawn(Vector3(pos.x, 0.06, pos.z), Vector3.ZERO, 0.5, 0.2, "ring", col, true, 0.0, r * 2.0, true)


## Долговечная «наклейка» на пол (лужа крови, копоть).
func decal(pos: Vector3, tex: String, col: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var m := _mat(tex, false, false).duplicate() as StandardMaterial3D
	m.albedo_color = col
	mi.material_override = m
	mi.position = Vector3(pos.x, 0.03, pos.z)
	mi.rotation = Vector3(-PI / 2, randf() * TAU, 0)
	mi.scale = Vector3(size, size, size)
	add_child(mi)


func clear_all() -> void:
	for c in get_children():
		c.queue_free()
	parts.clear()
