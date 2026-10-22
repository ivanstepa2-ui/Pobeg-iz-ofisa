class_name Actor
extends Node3D
## Общая база персонажа: позиция на сетке, поворот, коллизии с клетками уровня.

var game: Node          # Game (scripts/game/game.gd)
var L: OfficeLevel
var model: CharModel
var angle := 0.0        # направление взгляда: (sin, cos) по (x, z)
var radius := 0.3
var hp := 100.0
var max_hp := 100.0
var walk_phase := 0.0
var flash := 0.0
var speed_now := 0.0


func init_actor(g: Node, level: OfficeLevel, kind: String, pos: Vector3, ang: float) -> void:
	game = g
	L = level
	model = CharModel.new()
	add_child(model)
	model.setup(kind)
	position = Vector3(pos.x, 0, pos.z)
	angle = ang
	rotation.y = angle


func px() -> float:
	return position.x


func pz() -> float:
	return position.z


func facing() -> Vector2:
	return Vector2(sin(angle), cos(angle))


func dist_to(o: Node3D) -> float:
	return Vector2(o.position.x - position.x, o.position.z - position.z).length()


func angle_to_point(x: float, z: float) -> float:
	return atan2(x - position.x, z - position.z)


func turn_to(target: float, max_step: float) -> void:
	var d := wrapf(target - angle, -PI, PI)
	angle = wrapf(angle + clampf(d, -max_step, max_step), -PI, PI)
	rotation.y = angle


## Сдвиг с коллизией по осям (скольжение вдоль стен). Возвращает реально пройденное расстояние.
func move(dx: float, dz: float) -> float:
	var ox := position.x
	var oz := position.z
	position.x += dx
	_resolve()
	position.z += dz
	_resolve()
	return Vector2(position.x - ox, position.z - oz).length()


func _resolve() -> void:
	for _it in 2:
		var x0 := floori(position.x - radius)
		var x1 := floori(position.x + radius)
		var z0 := floori(position.z - radius)
		var z1 := floori(position.z + radius)
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1):
				if L.walkable(cx, cz):
					continue
				var qx := clampf(position.x, cx, cx + 1)
				var qz := clampf(position.z, cz, cz + 1)
				var ddx := position.x - qx
				var ddz := position.z - qz
				var d2 := ddx * ddx + ddz * ddz
				if d2 >= radius * radius:
					continue
				if d2 > 1e-8:
					var d := sqrt(d2)
					var push := (radius - d) / d
					position.x += ddx * push
					position.z += ddz * push
				else:
					# центр внутри клетки — выталкиваем по ближайшей оси
					var l := position.x - cx
					var r := cx + 1 - position.x
					var t := position.z - cz
					var b := cz + 1 - position.z
					var m := minf(minf(l, r), minf(t, b))
					if m == l: position.x = cx - radius
					elif m == r: position.x = cx + 1 + radius
					elif m == t: position.z = cz - radius
					else: position.z = cz + 1 + radius


func update_light(dt: float) -> void:
	flash = maxf(0.0, flash - dt * 6.0)
	model.set_light(L.light_color_at(position.x, position.z), flash)


func walk_pose(amp_scale: float = 1.0) -> Dictionary:
	var amp := minf(1.0, speed_now / 2.0) * 0.6 * amp_scale
	var s := sin(walk_phase) * amp
	return {"leg_l": s, "leg_r": -s, "arm_l": -s * 0.8, "arm_r": s * 0.8}
