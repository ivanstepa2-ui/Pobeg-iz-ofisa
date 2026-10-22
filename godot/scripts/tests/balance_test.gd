extends Node
## Тест баланса: поединки людей с зомби и обстрел игрока (стоит / бегает вбок).
##   godot --headless --path . -- --balancetest
## Симуляция идёт шагами по 1/30 с (быстрее реального времени). Печатает долю побед и остаток здоровья.

const DT := 1.0 / 30.0
const TRIALS := 10

var game: Node
var A := Vector3.ZERO     # две точки на открытом месте
var B := Vector3.ZERO
var dir := Vector2.ZERO


func run(g: Node) -> void:
	game = g
	await _frames(20)
	game.state = "gameover"   # главный цикл стоит, мир крутим сами
	_find_arena(7.0)
	print("[balance] арена: %s -> %s" % [A, B])
	if "--shoot" in OS.get_cmdline_user_args():
		# только обстрел героя, 3 разные арены × 10 попыток — числа устойчивее
		for k in 3:
			if k > 0:
				game._load_floor(3, false)
				game.state = "gameover"
				_find_arena(7.0)
			await _shoot_player("uzi", false)
			await _shoot_player("uzi", true)
			await _shoot_player("uzi", true, 99.0)
		print("[balance] ГОТОВО")
		game.get_tree().quit()
		return
	await _duel(["knife"], ["zombie"])
	await _duel(["axe"], ["zombie"])
	await _duel(["knuckles"], ["zombie"])
	await _duel(["uzi"], ["zombie"])
	await _duel(["rifle"], ["zombie"])
	await _duel(["knife"], ["woman"])
	await _duel(["knife"], ["fat"])
	await _duel(["axe"], ["fat"])
	await _duel(["rifle"], ["fat"])
	await _duel(["knife", "axe"], ["fat"])
	await _duel(["knife", "axe", "uzi"], ["zombie", "zombie", "zombie"])
	await _duel(["knife", "axe", "uzi"], ["fat", "zombie", "woman"])
	await _shoot_player("uzi", false)
	await _shoot_player("uzi", true)
	await _shoot_player("uzi", true, 99.0)
	await _shoot_player("rifle", false)
	await _shoot_player("rifle", true)
	print("[balance] ГОТОВО")
	game.get_tree().quit()


## Две проходимые точки на прямой видимости на расстоянии d (ищем самое открытое место).
func _find_arena(d: float) -> void:
	var L: OfficeLevel = game.L
	var best := -1
	for z in range(2, L.H - 2):
		for x in range(2, L.W - 2):
			if not L.walkable(x, z): continue
			for k in 4:
				var dx: int = OfficeLevel.DX[k]
				var dz: int = OfficeLevel.DZ[k]
				var ex := x + dx * int(d)
				var ez := z + dz * int(d)
				if not L.walkable(ex, ez): continue
				if L.line_blocked(x + 0.5, z + 0.5, ex + 0.5, ez + 0.5, 2): continue
				# простор вокруг — сколько свободных клеток по бокам линии
				var room := 0
				for s in int(d) + 1:
					for o in [-2, -1, 1, 2]:
						if L.walkable(x + dx * s + dz * o, z + dz * s + dx * o): room += 1
				if room > best:
					best = room
					A = Vector3(x + 0.5, 0, z + 0.5)
					B = Vector3(ex + 0.5, 0, ez + 0.5)
					dir = Vector2(dx, dz)


func _clear() -> void:
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	for b in game.bullets:
		b.queue_free()
	game.bullets.clear()
	for pk in game.pickups:
		pk.node.queue_free()
	game.pickups.clear()


func _spawn_humans(weapons: Array, at: Vector3, facing: float) -> Array:
	var out: Array = []
	var sq := {"members": [], "anchor": at, "mode": "hold", "t": 999.0}
	var side := Vector3(dir.y, 0, -dir.x)
	for i in weapons.size():
		var h := Human.new()
		game.level_root.add_child(h)
		h.setup_human(game, game.L, at + side * (i - (weapons.size() - 1) * 0.5) * 0.8, facing, weapons[i], sq, "pair")
		game.enemies.append(h)
		sq.members.append(h)
		out.append(h)
	return out


func _duel(weapons: Array, zombies: Array) -> void:
	var wins := 0
	var t_sum := 0.0
	var hp_sum := 0.0
	var alive_sum := 0
	game.player.frozen = true   # игрок вне игры
	for trial in TRIALS:
		_clear()
		var face_b := atan2(B.x - A.x, B.z - A.z)
		var hs := _spawn_humans(weapons, A, face_b)
		var zs: Array = []
		var side := Vector3(dir.y, 0, -dir.x)
		for i in zombies.size():
			game._add_enemy(zombies[i], B + side * (i - (zombies.size() - 1) * 0.5) * 0.8, face_b + PI, false)
			zs.append(game.enemies[game.enemies.size() - 1])
		for i in hs.size():
			hs[i].foe = zs[i % zs.size()]
			hs[i].alert()
		for i in zs.size():
			zs[i].foe = hs[i % hs.size()]
			zs[i].alert()
		var tm := 0.0
		while tm < 60.0:
			for _k in 30:
				game._update_world(DT, false)
				tm += DT
			if _all_dead(hs) or _all_dead(zs):
				break
			await game.get_tree().process_frame
		var hs_alive := hs.filter(func(h): return not h.is_dead())
		if _all_dead(zs) and not hs_alive.is_empty():
			wins += 1
			t_sum += tm
			alive_sum += hs_alive.size()
			for h in hs_alive: hp_sum += h.hp
	print("[balance] %-22s против %-22s люди победили %2d/%d  ср.время %4.1f с  выжило %.1f из %d  ср.hp выживших %3d" % [
		"+".join(weapons), "+".join(zombies), wins, TRIALS, t_sum / maxf(1, wins), float(alive_sum) / maxf(1, wins),
		weapons.size(), hp_sum / maxf(1, alive_sum)])


## Человек стреляет в игрока 8 с: игрок стоит или бегает вбок (уворачивается).
func _shoot_player(weapon: String, dodge: bool, flip_every: float = 1.0) -> void:
	var p: Player = game.player
	var dmg_sum := 0.0
	var dmg_max := 0.0
	for trial in TRIALS:
		_clear()
		p.frozen = false
		p.dead = false
		p.hp = 1000.0
		p.max_hp = 1000.0
		p.invuln = 0.0
		p.position = B
		p.crouch = false
		var hs := _spawn_humans([weapon], A, atan2(B.x - A.x, B.z - A.z))
		var h: Human = hs[0]
		h.foe = p
		h.alert()
		var tm := 0.0
		var side := Vector2(dir.y, -dir.x)
		var sgn := 1.0
		var flip := 0.0
		while tm < 8.0:
			for _k in 30:
				var mv := Vector2.ZERO
				if dodge:
					flip += DT
					if flip > flip_every:
						flip = 0.0
						sgn = -sgn
					mv = side * sgn
				p.invuln = 0.0
				p.update(DT, mv)
				game._update_world(DT, false)
				tm += DT
			await game.get_tree().process_frame
		var dmg := 1000.0 - p.hp
		dmg_sum += dmg
		dmg_max = maxf(dmg_max, dmg)
	p.max_hp = 100.0
	p.hp = 100.0
	print("[balance] %-6s по игроку, %-16s урон за 8 с: средний %3d, максимум %3d (из 100 hp)" % [
		weapon, ("зигзаг" if flip_every < 5.0 else "бег по прямой") if dodge else "стоит на месте", dmg_sum / TRIALS, dmg_max])


func _all_dead(arr: Array) -> bool:
	for a in arr:
		if not a.is_dead(): return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await game.get_tree().process_frame
