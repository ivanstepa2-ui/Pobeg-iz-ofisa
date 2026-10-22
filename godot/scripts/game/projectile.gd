class_name Projectile
extends Node3D
## Брошенный предмет: летит по дуге, бьётся о стены, срабатывает при попадании или приземлении.
##  bottle  — разбивается, шум (только отвлекает, во врагов не попадает);
##  alarm   — падает и звенит 6 сек, приманивая врагов;
##  brick   — попал: нокаут; не попал: шум;
##  extinguisher — облако: нокаут всех в радиусе + шум;
##  shuriken — попал: тихое убийство; не попал: звон (отвлекает);
##  grenade  — взрыв через 1.6 с: убивает всех в радиусе, громкий шум (отвлекает весь этаж).

const G := 18.0

var game: Node
var L: OfficeLevel
var id := ""
var vel := Vector3.ZERO
var age := 0.0
var landed := false
var ring_t := 0.0
var ring_pulse := 0.0
var done := false
var mesh: MeshInstance3D
var spin := Vector3.ZERO


func setup(g: Node, level: OfficeLevel, item_id: String, from: Vector3, to: Vector3) -> void:
	game = g
	L = level
	id = item_id
	position = from
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var d := flat.length()
	var T := clampf(d / 13.0, 0.22, 0.75)
	vel = Vector3(flat.x / T, (to.y + 0.3 - from.y + 0.5 * G * T * T) / T, flat.y / T)
	mesh = MeshInstance3D.new()
	var k := MeshKit.new()
	var tex := "i_" + id
	var half := Vector3(0.1, 0.1, 0.1)
	match id:
		"bottle": half = Vector3(0.05, 0.13, 0.05)
		"brick": half = Vector3(0.12, 0.06, 0.07)
		"shuriken": half = Vector3(0.12, 0.012, 0.12)
		"extinguisher": half = Vector3(0.07, 0.17, 0.07)
		"grenade": half = Vector3(0.06, 0.08, 0.06)
	k.box(Transform3D.IDENTITY, Vector3.ZERO, half, MeshKit.all_faces(tex, "", true), null, Color(0.75, 0.75, 0.75))
	mesh.mesh = k.commit()
	add_child(mesh)
	spin = Vector3(randf_range(5, 12), randf_range(5, 12), 0) if id != "shuriken" else Vector3(0, 25, 0)


func update(dt: float) -> void:
	age += dt
	if id == "grenade" and age >= 1.6:
		_explode()
		return
	if landed:
		if id == "alarm":
			ring_t -= dt
			ring_pulse -= dt
			mesh.position.y = 0.08 + absf(sin(age * 40.0)) * 0.04
			if ring_pulse <= 0.0:
				ring_pulse = 0.5
				game.sfx.play_at("ring", position, game.player.position, 1.0, 22.0)
				game.emit_noise(position, Items.def("alarm").noise, "distract", true)
			if ring_t <= 0.0:
				done = true
		return
	var prev := position
	vel.y -= G * dt
	position += vel * dt
	mesh.rotation += spin * dt
	# попадание во врага
	if id in Items.HITS_ENEMY:
		for e: Enemy in game.enemies:
			if e.is_down(): continue
			if Vector2(e.px() - position.x, e.pz() - position.z).length() < e.radius + 0.25 and position.y > 0.2 and position.y < 2.0:
				_hit_enemy(e)
				return
	# стены
	var c := L.cell(floori(position.x), floori(position.z))
	if c == OfficeLevel.WALL or c == OfficeLevel.TALL or (c == OfficeLevel.LOW and position.y < 0.8):
		position = Vector3(prev.x, prev.y, prev.z)
		vel.x *= -0.25
		vel.z *= -0.25
		if id == "bottle":
			_land()
			return
	if position.y <= 0.05:
		position.y = 0.05
		if id == "grenade" and absf(vel.y) > 2.5:
			vel.y = -vel.y * 0.3
			vel.x *= 0.5
			vel.z *= 0.5
			game.sfx.play_at("clink", position, game.player.position, 0.5)
			return
		_land()


func _land() -> void:
	landed = true
	vel = Vector3.ZERO
	position.y = 0.05
	var df := Items.def(id)
	var lp: Vector3 = game.player.position
	match id:
		"bottle":
			game.sfx.play_at("shatter", position, lp, 1.0, 25.0)
			game.fx.glass(position)
			game.emit_noise(position, df.noise, "distract", true)
			done = true
		"brick":
			game.sfx.play_at("thud", position, lp, 1.0, 25.0)
			game.emit_noise(position, df.noise, "distract", true)
			done = true
		"shuriken":
			game.sfx.play_at("clink", position, lp, 1.0, 25.0)
			game.emit_noise(position, df.noise, "distract", true)
			done = true
		"extinguisher":
			_cloud()
		"alarm":
			ring_t = 6.0
			ring_pulse = 0.6
			mesh.rotation = Vector3.ZERO
			game.sfx.play_at("thud", position, lp, 0.5)
		"grenade":
			mesh.rotation = Vector3.ZERO


func _hit_enemy(e: Enemy) -> void:
	var lp: Vector3 = game.player.position
	match id:
		"brick":
			game.sfx.play_at("hit", position, lp, 1.0, 25.0)
			e.knockdown(Items.def("brick").knock)
			game.stats.knockouts += 1
			game.hud.toast("Нокаут кирпичом!", Color(1, 0.85, 0.35))
			game.emit_noise(position, 4.0, "distract", true)
			done = true
		"shuriken":
			game.sfx.play_at("clink", position, lp, 1.0, 25.0)
			e.take_damage(999.0, game.player, "shuriken")
			game.hud.toast("Сюрикен: тихое устранение", Color(1, 0.4, 0.4))
			done = true
		"extinguisher":
			_cloud()
		"grenade":
			# граната отскакивает от врага и падает рядом
			vel = Vector3(-vel.x * 0.2, 1.0, -vel.z * 0.2)


func _cloud() -> void:
	var df := Items.def("extinguisher")
	game.sfx.play_at("hiss", position, game.player.position, 1.0, 25.0)
	game.fx.smoke(position, 14, Color(0.95, 0.95, 0.95), df.radius)
	var n := 0
	for e: Enemy in game.enemies:
		if e.is_dead(): continue
		if Vector2(e.px() - position.x, e.pz() - position.z).length() < df.radius:
			e.knockdown(df.knock)
			n += 1
	if n > 0:
		game.stats.knockouts += n
		game.hud.toast("Огнетушитель: нокаут ×%d" % n, Color(1, 0.85, 0.35))
	game.emit_noise(position, df.noise, "distract", true)
	done = true


func _explode() -> void:
	var df := Items.def("grenade")
	var r: float = df.radius
	game.sfx.play_at("boom", position, game.player.position, 1.3, 40.0)
	game.fx.explosion(position)
	game.shake(0.7)
	var n := 0
	for e: Enemy in game.enemies:
		if e.is_dead(): continue
		if Vector2(e.px() - position.x, e.pz() - position.z).length() < r:
			e.take_damage(999.0, game.player, "boom")
			n += 1
	var p: Player = game.player
	var dp := Vector2(p.px() - position.x, p.pz() - position.z).length()
	if dp < r + 0.3:
		p.invuln = 0.0
		p.hurt(60.0 * (1.0 - dp / (r + 0.3)) + 10.0, position)
	if n > 0:
		game.hud.toast("Граната: устранено ×%d" % n, Color(1, 0.4, 0.4))
	game.emit_noise(position, df.noise, "boom", true)
	done = true
