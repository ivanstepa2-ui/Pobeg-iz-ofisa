class_name Bullet
extends Node3D
## Пуля людей (узи): летит с видимой скоростью — от очереди можно увернуться, если бежать вбок.
## Попадает в стены, в игрока, в зомби и (0.12.1) в своих, если те на линии огня.

var game: Node
var L: OfficeLevel
var vel := Vector2.ZERO
var dmg_p := 0.0
var dmg_z := 0.0
var shooter: Enemy
var life := 1.4
var done := false
static var _mesh: ArrayMesh


func setup(g: Node, level: OfficeLevel, from: Vector3, dir: Vector2, speed: float, dp: float, dz: float, who: Enemy) -> void:
	game = g
	L = level
	position = from
	vel = dir * speed
	dmg_p = dp
	dmg_z = dz
	shooter = who
	if _mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, 0.4)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.35)
		bm.material = m
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
		_mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	rotation.y = atan2(dir.x, dir.y)


func update(dt: float) -> void:
	life -= dt
	if life <= 0.0:
		done = true
		return
	var dist := vel.length() * dt
	var steps := maxi(1, ceili(dist / 0.15))
	var step := vel * dt / steps
	for _i in steps:
		position.x += step.x
		position.z += step.y
		var c := L.cell(floori(position.x), floori(position.z))
		if c == OfficeLevel.WALL or c == OfficeLevel.TALL:
			game.fx.sparks(position)
			done = true
			return
		var p: Player = game.player
		if Enemy.alive(p) and Vector2(p.px() - position.x, p.pz() - position.z).length() < p.radius + 0.1:
			game.damage_player(dmg_p, shooter)
			game.fx.blood(position, 4)
			done = true
			return
		for e: Enemy in game.enemies:
			if e == shooter or e.is_down():
				continue
			if Vector2(e.px() - position.x, e.pz() - position.z).length() < e.radius + 0.1:
				if shooter != null and e.faction == shooter.faction:
					# 0.12.1: свой на линии огня — ранен (как герой), но врагом стрелка не становится
					e.take_damage(dmg_p, shooter, "friendly")
					if not game.npc_stats.is_empty():
						game.npc_stats.friendly_hits += 1
						game.battle_log(shooter, "friendly")
				else:
					game.battle_log(shooter, "hit")
					e.take_damage((shooter as Human).dmg_vs(e) if is_instance_valid(shooter) and shooter is Human else dmg_z, shooter, "gun")
				done = true
				return
