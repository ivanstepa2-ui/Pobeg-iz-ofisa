extends Node
## Тест предметов: запуск
##   godot --headless --path . --fixed-fps 30 -- --itemtest
## Для каждого случая ставит врага перед героем (лицом к нему или спиной), применяет предмет и печатает результат.

var game: Node

## [название, предмет, тип врага, враг спиной к герою?, ожидание]
const CASES := [
	["pistol", "pistol", "zombie", false, "урон"],
	["shotgun", "shotgun", "fat", false, "урон"],
	["silenced", "silenced", "zombie", false, "урон"],
	["uzi", "uzi", "zombie", false, "урон"],
	["rifle", "rifle", "fat", false, "убит"],
	["back_pistol", "pistol", "fat", true, "убит"],
	["back_silenced", "silenced", "zombie", true, "убит"],
	["knife", "knife", "zombie", false, "урон"],
	["back_knife", "knife", "fat", true, "убит"],
	["axe", "axe", "zombie", false, "урон"],
	["pipe", "pipe", "zombie", false, "урон"],
	["back_pipe", "pipe", "zombie", true, "нокаут", 20],
	["knuckles", "knuckles", "zombie", false, "нокаут", 20],
	["knuckles_fat", "knuckles", "fat", false, "урон"],
	["fist", "fist", "zombie", false, "урон"],
	["back_fist", "fist", "zombie", true, "нокаут", 160],   # 0.12: со спины — удушение 1 с (в «intro» время идёт медленнее), потом лежит 8 с
	["back_fist_fat", "fist", "fat", true, "без урона"],   # 0.12: толстяка кулаком не ранить (только серия 8 → выбыл)
	["brick", "brick", "zombie", false, "нокаут"],
	["extinguisher", "extinguisher", "zombie", false, "нокаут"],
	["shuriken", "shuriken", "zombie", false, "убит"],
	["grenade", "grenade", "zombie", false, "убит"],
	["bottle", "bottle", "zombie", false, "отвлёкся"],
	["alarm", "alarm", "zombie", false, "отвлёкся"],
	["coffee", "coffee", "zombie", false, "лечение"],
]


func run(g: Node) -> void:
	game = g
	await _frames(40)
	var ok := true
	for c in CASES:
		var id: String = c[1]
		var p: Player = game.player
		p.hp = 50.0
		p.dead = false
		game.state = "intro"
		p.cd = 0.0
		p.invuln = 99.0
		p.lock = null
		p.inv = {}
		if id != "fist":
			p.add_item(id, Items.def(id).amount)
			p.selected = id
		# убрать всех врагов, поставить одного в 1.2 м перед героем (на открытом месте — иначе бросок мог упереться в мебель)
		_clear()
		_open_spot(p)
		var f := p.facing()
		var pos := p.position + Vector3(f.x, 0, f.y) * 1.2
		game._add_enemy(c[2], pos, p.angle if c[3] else p.angle + PI, false)
		var e: Enemy = game.enemies[0]
		e.state = Enemy.S.LOOK
		e.t = 99.0
		await _frames(2)
		var hp0 := e.hp
		if id == "fist":
			p.melee()
		else:
			p.use_item()
		await _frames(c[5] if c.size() > 5 else 90)
		var res := "hp %d→%d, состояние %s, герой hp %d" % [hp0, e.hp, Enemy.S.keys()[e.state], p.hp]
		var expect := ""
		match c[4]:
			"урон": expect = "урон" if e.hp < hp0 and not e.is_dead() else ("УБИТ СРАЗУ" if e.is_dead() else "НЕТ УРОНА")
			"без урона": expect = "без урона" if e.hp == hp0 and not e.is_dead() else "РАНЕН"
			"нокаут": expect = "нокаут" if e.state == Enemy.S.KNOCKED else "НЕТ НОКАУТА"
			"убит": expect = "убит" if e.is_dead() else "НЕ УБИТ"
			"отвлёкся": expect = ("отвлёкся" if e.susp >= 0.5 else "НЕ УСЛЫШАЛ") if (e.hp == hp0 and not e.is_down()) else "ОШИБКА: задел врага"
			"лечение": expect = "лечение" if p.hp > 50.0 else "НЕ ВЫЛЕЧИЛ"
		if expect != c[4]:
			ok = false
		print("[itemtest] %-14s %-18s %s" % [c[0], expect, res])
	ok = await _human_test() and ok
	ok = await _clicker_test() and ok
	ok = await _cap_test() and ok
	ok = await _knock_time_test() and ok
	ok = await _lock_test() and ok
	ok = await _rifle_nonlethal_test() and ok
	ok = await _stealth_test() and ok
	ok = await _sneak_test() and ok
	ok = await _slots_test() and ok
	ok = await _cover_test() and ok
	ok = await _glimpse_test() and ok
	ok = await _v014_test() and ok
	ok = await _office_test() and ok
	ok = await _start_room_test() and ok
	ok = await _lair_test() and ok
	ok = await _v0161_test() and ok
	ok = await _fort_test() and ok
	ok = await _battle_test() and ok
	ok = await _cheat_kind_test() and ok
	ok = await _roof_test() and ok
	ok = await _witness_test() and ok
	ok = await _escape_test() and ok
	ok = await _reward_test() and ok
	ok = await _vent_test() and ok
	print("[itemtest] ИТОГ: ", "OK" if ok else "ЕСТЬ ПРОБЛЕМЫ")
	game.get_tree().quit()


func _clear() -> void:
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	game.squads.clear()   # отряды ссылаются на удалённых
	for b in game.bullets:
		b.queue_free()
	game.bullets.clear()


## Захват цели: зомби сбоку (вне автоприцела) — после захвата пистолет попадает в него; повторный тап снимает захват.
func _lock_test() -> bool:
	var p: Player = game.player
	p.cd = 0.0
	p.inv = {}
	p.add_item("pistol", 2)
	p.selected = "pistol"
	_clear()
	var f := p.facing()
	var pos := p.position + Vector3(f.x, 0, f.y) * 1.5
	game._add_enemy("zombie", pos, p.angle + PI, false)
	var e: Enemy = game.enemies[0]
	e.state = Enemy.S.LOOK
	e.t = 99.0
	# отворачиваемся — зомби оказывается сбоку, вне конуса автоприцела
	p.angle = wrapf(p.angle + PI / 2, -PI, PI)
	p.rotation.y = p.angle
	await _frames(2)
	var auto_ok := p.aim_target("pistol") == null
	p.toggle_lock(e)
	var locked := p.aim_target("pistol") == e
	var hp0 := e.hp
	p.use_item()
	await _frames(30)
	var hit := e.hp < hp0
	p.toggle_lock(e)
	var unlocked := p.lock == null
	var ok := auto_ok and locked and hit and unlocked
	print("[itemtest] %-14s %-18s без захвата не целится=%s, захват=%s, попал=%s, снят=%s" % ["lock", "захват" if ok else "НЕ РАБОТАЕТ", auto_ok, locked, hit, unlocked])
	return ok


## Клетка типа kind, через которую по прямой: перед ней 1 свободная клетка (герой), за ней 2 (зомби). {} — нет.
func _find_cover(kind: int) -> Dictionary:
	var L: OfficeLevel = game.L
	for z in range(3, L.H - 3):
		for x in range(3, L.W - 3):
			if L.cell(x, z) != kind: continue
			for k in 4:
				var dx: int = OfficeLevel.DX[k]
				var dz: int = OfficeLevel.DZ[k]
				if L.walkable(x - dx, z - dz) and L.walkable(x + dx, z + dz) and L.walkable(x + 2 * dx, z + 2 * dz):
					return {"hero": Vector3(x - dx + 0.5, 0, z - dz + 0.5), "zombie": Vector3(x + 2 * dx + 0.5, 0, z + 2 * dz + 0.5),
						"ang": atan2(-dx, -dz)}
	return {}


## 0.13: за фикусом/кулером присевшего видно («ты в них не как в кустах»), за столом — нет.
func _cover_test() -> bool:
	var p: Player = game.player
	var res := {}
	for kind in [OfficeLevel.PROP, OfficeLevel.LOW]:
		var spot := _find_cover(kind)
		var tries := 0
		while spot.is_empty() and tries < 6:
			game._load_floor(4 + tries, false)
			p = game.player
			await _frames(3)
			spot = _find_cover(kind)
			tries += 1
		if spot.is_empty():
			res["нет места для проверки %d" % kind] = false
			continue
		_clear()
		p.position = spot.hero
		p.crouch = true
		p.speed_now = 1.2   # крадётся — виден ближе 5 м, если не закрыт
		game._add_enemy("zombie", spot.zombie, spot.ang, false)
		var z: Enemy = game.enemies[-1]
		z.state = Enemy.S.LOOK
		z.t = 99.0
		z.attn = 1.0
		z.model.head.rotation.y = 0.0
		var seen: bool = z._see_factor(p) > 0.0
		if kind == OfficeLevel.PROP:
			res["за фикусом/кулером виден"] = seen
		else:
			res["за столом не виден"] = not seen
	p.crouch = false
	_clear()
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["cover_0.13", "верно" if ok else "НЕВЕРНО", res])
	return ok


func _spawn_office(wid: String, pos: Vector3, ang: float) -> Human:
	var h := Human.new()
	game.level_root.add_child(h)
	h.setup_human(game, game.L, pos, ang, wid, {"members": [], "dest": pos, "fac": "office"}, "guard", "office")
	game.enemies.append(h)
	h.state = Enemy.S.GUARD
	h.look_base = ang
	h.attn = 1.0
	return h


## 0.15: офисники — лояльны (не целятся в героя, автоприцел их не берёт); враждебны, если видели нападение или
## раненый в сознании (доложил); задушенный без свидетелей — доложит, когда очнётся; бандит и офисник, увидев
## друг друга, — война фракций; офисники только на нечётных этажах (кроме 1-го).
func _office_test() -> bool:
	var p: Player = game.player
	var res := {}
	_clear()
	_open_spot(p)
	p.dead = false
	p.invuln = 99.0
	p.hp = 100.0
	p.inv = {}
	p.selected = ""
	p.crouch = false
	game.state = "play"
	game.autotest = false
	game.office_hostile = false
	game.faction_war_on = false
	var f := p.facing()
	var fwd := Vector3(f.x, 0, f.y)
	# 1) лояльный: смотрит на героя 2 с — не бой; автоприцел его не берёт
	var o := _spawn_office("revolver", p.position + fwd * 4.0, p.angle + PI)
	for _i in 60:
		await _frames(1)
	p.inv = {"pistol": 3}
	p.selected = "pistol"
	res["лоялен: не нападает"] = not o.is_hostile() and not game.office_hostile
	res["автоприцел его не берёт"] = p.aim_target("pistol") == null
	p.inv = {}
	p.selected = ""
	# 2) удар в лицо (в сознании) — доложит сразу: враждебны
	o.position = p.position + fwd * 1.1
	o.angle = p.angle + PI
	p.lock = o
	p.cd = 0.0
	p.melee()
	p.lock = null
	await _frames(2)
	res["ударил в лицо — враждебны"] = game.office_hostile
	_clear()
	game.office_hostile = false
	# 3) задушил без свидетелей — не враждебны, пока не очнётся; очнулся — доложил
	var o2 := _spawn_office("pipe", p.position + fwd * 1.2, p.angle)   # спиной к герою
	await _frames(2)
	p.angle = p.angle_to_point(o2.px(), o2.pz())
	p.cd = 0.0
	p.melee_hold = false
	p.melee()
	await _frames(45)
	var calm_while_out: bool = not game.office_hostile and o2.state == Enemy.S.KNOCKED
	o2.knock_t = 0.05
	await _frames(40)
	res["задушил тихо — пока без сознания, не знают"] = calm_while_out
	res["очнулся — доложил"] = game.office_hostile
	_clear()
	game.office_hostile = false
	# 4) душит на глазах у другого офисника — сразу враждебны
	_open_spot(p)
	f = p.facing()
	fwd = Vector3(f.x, 0, f.y)
	var v :=_spawn_office("pipe", p.position + fwd * 1.2, p.angle)
	var w := _spawn_office("knife", p.position + fwd * 5.0, p.angle + PI)
	await _frames(2)
	p.cd = 0.0
	p.melee()
	await _frames(2)
	res["душит на глазах — сразу враждебны"] = game.office_hostile
	_clear()
	game.office_hostile = false
	await _frames(5)
	# 5) бандит и офисник видят друг друга — война фракций
	_open_spot(p)
	f = p.facing()
	fwd = Vector3(f.x, 0, f.y)
	var b := _spawn_human("knife", p.position + fwd * 2.0, 0.0)
	var o3 := _spawn_office("nailgun", p.position + fwd * 7.0, 0.0)
	b.angle = b.angle_to_point(o3.px(), o3.pz())
	b.rotation.y = b.angle
	b.look_base = b.angle
	o3.angle = o3.angle_to_point(b.px(), b.pz())
	o3.rotation.y = o3.angle
	o3.look_base = o3.angle
	var war := false
	for _i in 120:
		await _frames(1)
		if game.faction_war_on:
			war = true
			break
	await _frames(10)
	res["бандит ↔ офисник: война"] = war and b.foe == o3 and (o3.foe == b or o3.is_hostile())
	_clear()
	# 6) офисники только на нечётных этажах ≥ 3, примерно половина
	var odd := 0
	var even := 0
	var first := 0
	for i in 40:
		for wv in game._plan_waves(5):
			if wv.get("office", false): odd += 1
		for wv in game._plan_waves(4):
			if wv.get("office", false): even += 1
		for wv in game._plan_waves(1):
			if wv.get("office", false): first += 1
	res["нечётный ~50%% (%d/40), чётный и 1-й — нет" % odd] = odd >= 10 and odd <= 30 and even == 0 and first == 0
	game.state = "intro"
	game.office_hostile = false
	game.faction_war_on = false
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["office_0.15", "верно" if ok else "НЕВЕРНО", res])
	return ok


## Полностью свободный квадрат 9×9 (клетки), центр — Vector2i; (-1,-1) — нет.
func _open_block() -> Vector2i:
	var L: OfficeLevel = game.L
	for z in range(5, L.H - 5):
		for x in range(5, L.W - 5):
			var ok := true
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					if not L.walkable(x + dx, z + dz):
						ok = false
						break
				if not ok: break
			if ok:
				return Vector2i(x, z)
	return Vector2i(-1, -1)


## 0.14: приём из слепой зоны (сбоку) и перелезание через LOW. Площадка — временно расставленные клетки.
func _v014_test() -> bool:
	var p: Player = game.player
	var res := {}
	# площадка 9×9: свободная на этаже или временно расчищенная в середине (этажи плотно заставлены мебелью)
	var L: OfficeLevel = game.L
	var real_cells := L.cells.duplicate()
	var c := _open_block()
	if c.x < 0:
		c = Vector2i(L.W / 2, L.H / 2)
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				L.cells[(c.y + dz) * L.W + c.x + dx] = OfficeLevel.FLOOR
	var saved := L.cells.duplicate()
	_clear()
	p.dead = false
	p.invuln = 99.0
	p.hp = 100.0
	p.inv = {}
	p.selected = ""
	p.crouch = false
	game.state = "play"
	game.autotest = false
	var base := Vector3(c.x + 0.5, 0, c.y + 0.5)
	var right := Vector3(1, 0, 0)
	# --- A) приём сбоку по зомби: вне его fov — можно, в fov — нельзя; заход за спину и удушение
	p.position = base
	p.angle = 0.0
	p.rotation.y = 0.0
	game._add_enemy("zombie", base + right * 1.1, 0.0, false)   # смотрит туда же, куда герой: герой у него сбоку
	var z: Enemy = game.enemies[-1]
	z.state = Enemy.S.LOOK
	z.t = 99.0
	z.look_base = 0.0
	z.model.head.rotation.y = 0.0
	await _frames(1)
	p.angle = p.angle_to_point(z.px(), z.pz())
	p.rotation.y = p.angle
	res["зомби: сбоку вне fov — ДУШИТЬ"] = p.sneak_target() == z
	z.angle = z.angle_to_point(p.px(), p.pz())   # повернулся к герою — в поле зрения
	z.rotation.y = z.angle
	z.look_base = z.angle
	res["зомби: в fov — нельзя"] = p.sneak_target() == null
	z.angle = 0.0
	z.rotation.y = 0.0
	z.look_base = 0.0
	p.cd = 0.0
	p.melee()
	await _frames(8)
	var behind := Vector2(z.px(), z.pz()) - z.facing() * 0.45
	var moved_behind := Vector2(p.px(), p.pz()).distance_to(behind) < 0.25
	await _frames(40)
	res["сбоку: зашёл за спину и задушил"] = moved_behind and z.state == Enemy.S.KNOCKED
	_clear()
	# --- B) бандит: сбоку (вне ~120°) — можно, под 40° — нельзя
	p.position = base
	var h := _spawn_human("knife", base + right * 1.15, 0.0)
	h.state = Enemy.S.GUARD
	h.look_base = 0.0
	await _frames(1)
	h.angle = 0.0
	h.rotation.y = 0.0
	p.angle = p.angle_to_point(h.px(), h.pz())
	res["бандит: сбоку — можно"] = p.sneak_target() == h
	h.angle = h.angle_to_point(p.px(), p.pz()) + deg_to_rad(40.0)
	h.rotation.y = h.angle
	res["бандит: под 40° — нельзя"] = p.sneak_target() == null
	_clear()
	await _frames(2)
	# --- C) перелезание
	var vault_case := func(cells_low: Array, cells_wall: Array) -> Dictionary:
		L.cells = saved.duplicate()
		for q in cells_low: L.cells[q.y * L.W + q.x] = OfficeLevel.LOW
		for q in cells_wall: L.cells[q.y * L.W + q.x] = OfficeLevel.WALL
		p.position = Vector3(c.x + 0.5, 0, c.y + 0.72)
		p.angle = 0.0
		p.rotation.y = 0.0
		p.vel2 = Vector2.ZERO
		p.vault_cd = 0.0
		return p.vault_target()
	var one: Dictionary = vault_case.call([Vector2i(c.x, c.y + 1)], [])
	var t0 := Time.get_ticks_msec()
	var started := p.start_vault()
	var frames := 0
	while p.is_vaulting() and frames < 90:
		await _frames(1)
		frames += 1
	res["1 блок: ~0.6 с (%.2f), на той стороне" % (frames / 30.0)] = started and one.n == 1 and frames >= 14 and frames <= 24 \
		and Vector2(p.px() - (c.x + 0.5), p.pz() - (c.y + 2.5)).length() < 0.1
	# 0.14.1: лез присевшим — после перелезания снова присел; стоя — стоит
	res["лез стоя — стоит"] = not p.crouch
	vault_case.call([Vector2i(c.x, c.y + 1)], [])
	p.crouch = true
	p.start_vault()
	var mid_crouch := p.crouch
	while p.is_vaulting(): await _frames(1)
	res["лез присевшим — снова присел (на столе — нет)"] = p.crouch and not mid_crouch
	p.crouch = false
	var two: Dictionary = vault_case.call([Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y + 2)], [])
	p.start_vault()
	frames = 0
	while p.is_vaulting() and frames < 90:
		await _frames(1)
		frames += 1
	res["2 блока (стол): ~1.2 с (%.2f)" % (frames / 30.0)] = two.n == 2 and frames >= 30 and frames <= 44
	var side: Dictionary = vault_case.call([Vector2i(c.x, c.y + 1)], [Vector2i(c.x, c.y + 2)])
	res["за стеной — на свободную клетку сбоку"] = not side.is_empty() and absf(side.to.x - (c.x + 0.5)) > 0.9
	var none: Dictionary = vault_case.call([Vector2i(c.x, c.y + 1)], [Vector2i(c.x, c.y + 2), Vector2i(c.x - 1, c.y + 2), Vector2i(c.x + 1, c.y + 2)])
	res["некуда — кнопки нет"] = none.is_empty()
	# приземление занято (сидит зомби) — соседняя клетка
	vault_case.call([Vector2i(c.x, c.y + 1)], [])
	game._add_enemy("zombie", Vector3(c.x + 0.5, 0, c.y + 2.5), PI, true)
	var occ := p.vault_target()
	res["точка занята зомби — сдвиг"] = not occ.is_empty() and absf(occ.to.x - (c.x + 0.5)) > 0.9
	_clear()
	# тихо / в тревоге; видевший идёт к точке приземления
	vault_case.call([Vector2i(c.x, c.y + 1)], [])
	p.start_vault()
	var quiet := not p.vault_loud
	while p.is_vaulting(): await _frames(1)
	vault_case.call([Vector2i(c.x, c.y + 1)], [])
	game._add_enemy("zombie", base + Vector3(-3, 0, 0), PI * 0.5, false)
	var zw: Enemy = game.enemies[-1]
	zw.foe = p
	zw.alert()
	zw.sees = true
	p.vault_cd = 0.0
	p.start_vault()
	res["без тревоги тихо, в тревоге шумно"] = quiet and p.vault_loud
	res["видевший идёт к точке приземления"] = zw.last_seen.distance_to(p.vault_to) < 0.01
	while p.is_vaulting(): await _frames(1)
	_clear()
	# --- D) зомби через LOW не ходит, бандит — может (стена из столов поперёк)
	L.cells = saved.duplicate()
	for dx in range(-4, 5):
		L.cells[(c.y + 1) * L.W + c.x + dx] = OfficeLevel.LOW
	for dx in [-5, 5]:
		L.cells[(c.y + 1) * L.W + c.x + dx] = OfficeLevel.WALL
	var pz := L.find_path(c.x, c.y + 3, c.x, c.y - 1)
	var ph := L.find_path(c.x, c.y + 3, c.x, c.y - 1, 4000, 2.0)
	var z_low := false
	for q in pz:
		if L.cells[q] == OfficeLevel.LOW: z_low = true
	var h_low := false
	for q in ph:
		if L.cells[q] == OfficeLevel.LOW: h_low = true
	res["путь зомби — в обход, бандита — через стол"] = not z_low and h_low
	# бандит в погоне перелезает
	p.position = Vector3(c.x + 0.5, 0, c.y - 0.5)
	p.crouch = false
	var hb := _spawn_human("knife", Vector3(c.x + 0.5, 0, c.y + 3.5), PI)
	hb.foe = p
	hb._instant_alert = true
	hb.alert()
	hb._instant_alert = false
	var v0: int = game.npc_stats.bandit_vaults
	for _i in 120:
		await _frames(1)
		if hb.pz() < c.y + 1.0:
			break
	res["бандит в погоне перелез (%d)" % (game.npc_stats.bandit_vaults - v0)] = game.npc_stats.bandit_vaults > v0 and hb.pz() < c.y + 1.0
	_clear()
	L.cells = real_cells
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["v014", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.13: замер вприсядку на открытом в 6 м в поле зрения — «?», зомби идёт к тому месту,
## вблизи — тревога; замер за столом — реакции нет.
func _glimpse_test() -> bool:
	var p: Player = game.player
	var res := {}
	_clear()
	_open_spot(p)
	p.dead = false
	p.invuln = 99.0
	p.hp = 100.0
	p.crouch = true
	game.state = "play"
	game.autotest = false
	var z := _put("zombie", 6.0, false)
	var t := 0
	var went := false
	while t < 240 and not went:
		await _frames(1)
		t += 1
		if z.state == Enemy.S.LOOK:
			# смотрит на героя (проверяем правило, а не случайный поворот головы при осмотре)
			z.angle = z.angle_to_point(p.px(), p.pz())
			z.rotation.y = z.angle
			z.look_base = z.angle
			z.model.head.rotation.y = 0.0
		went = z.state == Enemy.S.INVESTIGATE
	res["6 м: «?» и идёт проверить (%.1f с)" % (t / 30.0)] = went and Vector2(z.target.x - p.px(), z.target.z - p.pz()).length() < 2.0
	var alarm := false
	for _i in 300:
		await _frames(1)
		if z.is_hostile():
			alarm = true
			break
	res["подошёл — тревога (в %.1f м)" % z.dist_to(p)] = alarm
	# за столом — без реакции
	_clear()
	var spot := _find_cover(OfficeLevel.LOW)
	if not spot.is_empty():
		p.position = spot.hero
		game._add_enemy("zombie", spot.zombie, spot.ang, false)
		var z2: Enemy = game.enemies[-1]
		z2.state = Enemy.S.LOOK
		z2.t = 99.0
		z2.attn = 1.0
		for _i in 90:
			z2.state = Enemy.S.LOOK if z2.state == Enemy.S.LOOK else z2.state
			z2.angle = spot.ang
			z2.rotation.y = spot.ang
			z2.model.head.rotation.y = 0.0
			await _frames(1)
		res["за столом — ничего"] = z2.susp < 0.05 and z2.state == Enemy.S.LOOK
	p.crouch = false
	game.state = "intro"
	_clear()
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["glimpse_0.13", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.13: слоты — один вид на слот; другой вид не берётся сам (кнопка «Заменить»), награда в занятый слот — на пол;
## замена роняет старое со всем запасом; тот же вид — докладывается до потолка; кончилось — слот свободен.
func _slots_test() -> bool:
	var p: Player = game.player
	_clear()
	for pk in game.pickups:
		pk.node.queue_free()
	game.pickups.clear()
	p.dead = false
	p.inv = {}
	p.add_item("bottle", 2)
	var res := {}
	res["кирпич в слот бутылок не берётся"] = p.add_item("brick", 1) == 0 and p.inv.get("brick", 0) == 0
	res["пистолет и узи — разные слоты"] = p.add_item("pistol", 3) == 3 and p.add_item("uzi", 5) == 5
	res["ПБ в слот пистолета — нет"] = p.add_item("silenced", 2) == 0
	game.state = "play"
	game.give_reward("brick", 1)
	await _frames(3)
	var brick_pk: Dictionary = {}
	for pk in game.pickups:
		if pk.id == "brick":
			brick_pk = pk
	res["награда в занятый слот — на полу"] = not brick_pk.is_empty() and p.inv.get("brick", 0) == 0
	# стоим рядом — кнопка «Заменить»
	p.position = Vector3(brick_pk.node.position.x, 0, brick_pk.node.position.z) + Vector3(0.2, 0, 0)
	await _frames(3)
	res["кнопка «Заменить»"] = game.swap_pk == brick_pk
	game.do_swap()
	await _frames(2)
	var bottles_floor := 0
	for pk in game.pickups:
		if pk.id == "bottle":
			bottles_floor += pk.n
	res["замена: кирпич в руках, 2 бутылки на полу"] = p.inv.get("brick", 0) == 1 and p.inv.get("bottle", 0) == 0 and bottles_floor == 2
	# тот же вид докладывается сам до потолка
	p.inv["uzi"] = 5
	res["узи докладывается до потолка"] = p.add_item("uzi", 20) == Items.cap("uzi") - 5
	# кончились патроны — слот свободен, берётся другое
	p.inv.erase("pistol")
	res["слот освободился — ПБ берётся"] = p.add_item("silenced", 2) == 2
	game.state = "intro"
	for pk in game.pickups:
		pk.node.queue_free()
	game.pickups.clear()
	p.inv = {}
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["slots_0.13", "верно" if ok else "НЕВЕРНО", res])
	return ok


## Враг type в dist м перед героем; back — стоит спиной к герою.
func _put(type: String, dist: float, back: bool) -> Enemy:
	var p: Player = game.player
	var f := p.facing()
	game._add_enemy(type, p.position + Vector3(f.x, 0, f.y) * dist, p.angle if back else p.angle + PI, false)
	var e: Enemy = game.enemies[-1]
	e.state = Enemy.S.LOOK
	e.t = 99.0
	e.attn = 1.0
	e.look_base = e.angle   # осматривается вокруг своего направления (иначе разворачивается к углу 0)
	return e


## 0.12: удушение и нож со спины для зомби и бандитов (не толстяк/щелкун), долгое удушение — насмерть,
## подсказка ДУШИТЬ, кулак 15 (бухгалтерша 5 ударов, толстяк — 8 ударов → выбыл 5 с), тревога зовёт 1–3,
## громкий выстрел рядом с отрядом — бандиты знают, где герой.
func _sneak_test() -> bool:
	var p: Player = game.player
	_clear()
	_open_spot(p)
	p.dead = false
	p.hp = 100.0
	p.invuln = 99.0
	p.inv = {}
	p.selected = ""
	p.lock = null
	game.state = "play"   # в «intro» герой обновляется не каждый кадр — таймеры удушения идут медленнее
	game.autotest = false
	var res := {}
	# 1) зомби со спины: подсказка, короткое удушение → без сознания 8 с
	var z := _put("zombie", 1.0, true)
	await _frames(2)
	res["подсказка ДУШИТЬ"] = p.sneak_target() == z and not p.blade_ready()
	p.cd = 0.0
	p.melee_hold = false
	p.melee()
	res["душит зомби"] = p.is_choking() and z.state == Enemy.S.CHOKED
	await _frames(40)
	res["вырубил на 8 с"] = z.state == Enemy.S.KNOCKED and absf(z.knock_t - 8.0) < 0.5
	# 2) держит кнопку — насмерть (1 + 2 с)
	_clear()
	z = _put("woman", 1.0, true)
	await _frames(2)
	p.cd = 0.0
	p.melee_hold = true
	p.melee()
	await _frames(50)
	var still_alive := not z.is_dead() and p.is_choking() and p.choke_long
	await _frames(70)
	res["держал — насмерть"] = still_alive and z.is_dead()
	p.melee_hold = false
	# 3) бандит: держит — насмерть
	_clear()
	var h := _spawn_human("knife", p.position + Vector3(p.facing().x, 0, p.facing().y) * 1.0, p.angle)
	h.state = Enemy.S.GUARD
	h.look_base = p.angle
	await _frames(1)
	p.cd = 0.0
	p.melee_hold = true
	p.melee()
	await _frames(100)
	res["бандит задушен насмерть"] = h.is_dead()
	p.melee_hold = false
	# 4) толстяк и щелкун — нельзя
	_clear()
	var fat := _put("fat", 1.0, true)
	await _frames(2)
	res["толстяка нельзя"] = p.sneak_target() == null
	_clear()
	var c := _spawn_clicker(p.position + Vector3(p.facing().x, 0, p.facing().y) * 1.0, p.angle)
	await _frames(2)
	res["щелкуна нельзя"] = p.sneak_target() == null
	# 5) нож со спины — быстрое убийство (~0.45 с: сразу не умирает, через 0.6 с — мёртв), подсказка УБИТЬ
	_clear()
	z = _put("zombie", 1.0, true)
	p.add_item("knife", 3)
	p.selected = "knife"
	await _frames(2)
	var kill_hint := p.sneak_target() == z and p.blade_ready()
	p.cd = 0.0
	p.melee()
	await _frames(5)
	var anim := not z.is_dead() and z.state == Enemy.S.CHOKED
	await _frames(22)   # 0.14: +0.2 с — заход за спину
	res["нож со спины (УБИТЬ, анимация)"] = kill_hint and anim and z.is_dead()
	p.inv = {}
	p.selected = ""
	# 6) кулак: бухгалтерша — 5 ударов; толстяк — 8 ударов → выбыл на 5 с, hp не тронут
	_clear()
	z = _put("woman", 1.1, false)
	var hits := 0
	while not z.is_dead() and hits < 12:
		p.cd = 0.0
		z.state = Enemy.S.LOOK
		z.position = p.position + Vector3(p.facing().x, 0, p.facing().y) * 1.1
		z.angle = p.angle + PI   # лицом к герою (иначе, оглядываясь, отворачивается — и это уже приём сбоку, 0.14)
		z.rotation.y = z.angle
		z.look_base = z.angle
		z.model.head.rotation.y = 0.0
		p.melee()
		hits += 1
		await _frames(1)
	res["бухгалтерша 5 ударов"] = hits == 5
	_clear()
	fat = _put("fat", 1.2, false)
	var hp0 := fat.hp
	hits = 0
	while fat.state != Enemy.S.KNOCKED and hits < 12:
		p.cd = 0.0
		fat.position = p.position + Vector3(p.facing().x, 0, p.facing().y) * 1.2
		if fat.state != Enemy.S.KNOCKED:
			fat.state = Enemy.S.LOOK
			fat.stagger_cd = 0.0
		p.melee()
		hits += 1
		await _frames(1)
	res["толстяк 8 ударов → 5 с"] = hits == 8 and absf(fat.knock_t - 5.0) < 0.2 and fat.hp == hp0
	# 7) тревога: заметивший зовёт 1–3 ближних, остальные не идут
	_clear()
	var a := _put("zombie", 4.0, false)
	var others: Array = []
	for k in 5:
		var o := _put("zombie", 4.0, true)
		o.position += Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		others.append(o)
	game.state = "play"
	a.foe = p
	a.alert()
	var came := others.filter(func(o): return o.search_t > 0.0).size()
	res["тревога: пришло 1–3 (%d)" % came] = came >= 1 and came <= 3
	game.state = "intro"
	# 8) громкий выстрел рядом с отрядом — бандиты знают, где герой (без растерянности, в бой)
	_clear()
	var fwd := Vector3(p.facing().x, 0, p.facing().y)
	var h1 := _spawn_human("knife", p.position + fwd * 6.0, p.angle)
	var h2 := _spawn_human("uzi", p.position + fwd * 6.5 + Vector3(0.6, 0, 0), p.angle)
	var sq := {"members": [h1, h2], "leader": h1, "phase": "settled", "dest": h1.position, "pairs": [], "t": 99.0,
		"wary": false, "main": true, "plan": ""}
	h1.squad = sq
	h2.squad = sq
	game.squads = [sq]
	game.state = "play"
	game.emit_noise(p.position, 14.0, "gun", true)
	await _frames(2)
	res["выстрел: бандиты знают"] = h1.is_hostile() and h2.is_hostile() and h1.foe == p and h2.know_t > 0.0
	game.state = "intro"
	game.squads = []
	_clear()
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["sneak_0.12", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.11: присед (одно правило для героя и бандитов) и ПОИСК там, где видели последний раз.
func _stealth_test() -> bool:
	var p: Player = game.player
	_clear()
	_open_spot(p)
	await _frames(2)
	var f := p.facing()
	game._add_enemy("zombie", p.position + Vector3(f.x, 0, f.y) * 3.0, p.angle + PI, false)
	var z: Enemy = game.enemies[0]
	z.state = Enemy.S.LOOK
	z.t = 99.0
	z.attn = 1.0
	var res := {}
	# 0.12: присел-замер на открытом — виден ближе 2.5 м; крадётся — ближе 5 м
	var cases := [["стоит 3 м", false, 0.0, 3.0, true], ["присел, замер 2 м", true, 0.0, 2.0, true],
		["присел, замер 3 м", true, 0.0, 3.0, false], ["крадётся 4 м", true, 1.2, 4.0, true],
		["крадётся 6 м", true, 1.2, 6.0, false]]
	var ok := true
	for c in cases:
		z.position = p.position + Vector3(f.x, 0, f.y) * float(c[3])
		z.angle = p.angle + PI
		z.rotation.y = z.angle
		z.model.head.rotation.y = 0.0
		p.crouch = c[1]
		p.speed_now = c[2]
		var seen: bool = z._see_factor(p) > 0.0
		res[c[0]] = seen
		if seen != c[4]:
			ok = false
	p.crouch = false
	# бандит, крадущийся вприсядку, — по тому же правилу
	var h := _spawn_human("knife", p.position + Vector3(f.x, 0, f.y) * 4.0, 0.0)
	h.hide_t = 5.0
	h.state = Enemy.S.LOOK
	h.speed_now = 0.0
	z.position = p.position
	z.angle = atan2(f.x, f.y)
	z.rotation.y = z.angle
	var h_hidden: bool = z._see_factor(h) <= 0.0
	ok = ok and h_hidden
	# ПОИСК: идёт к месту, где видели, 20–30 с, потом успокаивается
	var spot := z.position + Vector3(f.x, 0, f.y) * 2.0
	z._start_search(spot)
	var searching: bool = z.state == Enemy.S.INVESTIGATE and z.hot and z.search_t >= 20.0 \
		and Vector2(z.target.x - spot.x, z.target.z - spot.z).length() < 2.0
	z.search_t = 0.05
	await _frames(4)
	var calmed: bool = not z.hot and z.search_t <= 0.0
	ok = ok and searching and calmed
	print("[itemtest] %-14s %-18s зомби видит героя: %s; бандит в укрытии скрыт=%s; поиск=%s, успокоился=%s" % [
		"stealth", "верно" if ok else "НЕВЕРНО", res, h_hidden, searching, calmed])
	_clear()
	return ok


func _spawn_human(wid: String, pos: Vector3, ang: float) -> Human:
	var h := Human.new()
	game.level_root.add_child(h)
	h.setup_human(game, game.L, pos, ang, wid, {"anchor": pos, "dest": pos}, "guard")
	game.enemies.append(h)
	return h


## Ставит героя туда, где впереди 9 м свободно и видно (этаж случайный — иначе тесты зрения нестабильны).
func _open_spot(p: Player) -> void:
	var L: OfficeLevel = game.L
	for z in range(2, L.H - 2):
		for x in range(2, L.W - 2):
			if not L.walkable(x, z): continue
			for k in 4:
				var ex: int = x + OfficeLevel.DX[k] * 9
				var ez: int = z + OfficeLevel.DZ[k] * 9
				if not L.walkable(ex, ez) or L.line_blocked(x + 0.5, z + 0.5, ex + 0.5, ez + 0.5, 2):
					continue
				p.position = Vector3(x + 0.5, 0, z + 0.5)
				p.angle = atan2(OfficeLevel.DX[k], OfficeLevel.DZ[k])
				p.rotation.y = p.angle
				return


## 0.7: растерянность, удушение, лежачий человек уязвим, пистолет — 2 попадания.
func _human_test() -> bool:
	var p: Player = game.player
	_open_spot(p)
	var f := p.facing()
	var front := p.position + Vector3(f.x, 0, f.y) * 1.2
	p.invuln = 99.0
	p.dead = false
	var ok := true
	# 1) растерянность: человек лицом к герою замечает его — сначала STARTLED, крика ещё нет
	_clear()
	var h := _spawn_human("knife", p.position + Vector3(f.x, 0, f.y) * 4.0, p.angle + PI)
	h.attn = 1.0
	game.state = "play"
	game.autotest = false
	var startled := false
	var chase_after := 0.0
	var shouted_early := false
	for i in 60:
		await _frames(1)
		if h.state == Enemy.S.STARTLED:
			startled = true
			if h.shout_cd > 0.0: shouted_early = true
		if startled and h.is_hostile() and chase_after == 0.0:
			chase_after = i / 30.0
	game.state = "intro"
	var a := startled and not shouted_early and chase_after > 0.0
	ok = ok and a
	print("[itemtest] %-14s %-18s растерялся=%s, крикнул в растерянности=%s, бой через %.2f с" % ["startled", "верно" if a else "НЕВЕРНО", startled, shouted_early, chase_after])
	# 1б) отдых (0.8): фонарь опущен — на 9 м не видит, на 5 м видит; вскакивает из отдыха ~1 с, оружие убрано
	_clear()
	h = _spawn_human("uzi", p.position + Vector3(f.x, 0, f.y) * 9.0, p.angle + PI)
	h.attn = 1.0   # проверка — на «среднего» (сонный вскакивает позже — так и задумано, 0.11)
	h._enter_rest()
	h.angle = p.angle + PI
	h.rotation.y = h.angle
	var stowed0 := h.weapon_stowed() and h.is_dim()
	game.state = "play"
	await _frames(30)
	var far_calm := h.state == Enemy.S.REST
	h.position = p.position + Vector3(f.x, 0, f.y) * 4.0
	var rest_startle := false
	for i in 45:
		await _frames(1)
		if h.state == Enemy.S.STARTLED:
			rest_startle = absf(h.startle_dur - 0.9) < 0.01 and h.from_rest   # 0.16.1: 0.9 с (было 1.0)
			break
	game.state = "intro"
	var a2 := stowed0 and far_calm and rest_startle
	ok = ok and a2
	print("[itemtest] %-14s %-18s оружие убрано+фонарь опущен=%s, на 9 м не видит=%s, вскочил за 0.9 с=%s" % ["rest", "верно" if a2 else "НЕВЕРНО", stowed0, far_calm, rest_startle])
	# 2) удушение: кулак сзади по спокойному человеку → захват 1 с → без сознания 8 с
	_clear()
	h = _spawn_human("axe", front, p.angle)   # стоит спиной к герою
	h.state = Enemy.S.GUARD
	await _frames(2)
	p.cd = 0.0
	p.selected = ""
	p.melee()
	var choked := h.state == Enemy.S.CHOKED and p.is_choking()
	await _frames(44)   # 0.14: +0.2 с — заход за спину
	var knocked := h.state == Enemy.S.KNOCKED and absf(h.knock_t - 8.0) < 0.3 and not p.is_choking()
	# 3) лежачий человек: кулак — 50 урона
	p.cd = 0.0
	var hp0 := h.hp
	p.melee()
	var down_fist := hp0 - h.hp
	# 4) труба по лежачему человеку — насмерть
	p.inv = {"pipe": 3}
	p.selected = "pipe"
	p.cd = 0.0
	p.use_item()
	var pipe_kill := h.is_dead()
	var b := choked and knocked and absf(down_fist - 50.0) < 0.1 and pipe_kill
	ok = ok and b
	print("[itemtest] %-14s %-18s захват=%s, без сознания 8 с=%s, кулак по лежачему=%d, труба добила=%s" % ["choke", "верно" if b else "НЕВЕРНО", choked, knocked, down_fist, pipe_kill])
	# 5) пистолет: человек (100 hp) — за 2 попадания (лицом к герою, не в спину)
	_clear()
	h = _spawn_human("knife", front, p.angle + PI)
	await _frames(2)
	p.inv = {"pistol": 6}
	p.selected = "pistol"
	var shots := 0
	while not h.is_dead() and shots < 5:
		p.cd = 0.0
		h.position = front
		h.angle = p.angle + PI
		p.use_item()
		shots += 1
		await _frames(2)
	var c := shots == 2
	ok = ok and c
	print("[itemtest] %-14s %-18s выстрелов из пистолета: %d" % ["human_hp", "верно" if c else "НЕВЕРНО", shots])
	_clear()
	return ok


func _spawn_clicker(pos: Vector3, ang: float) -> Clicker:
	var c := Clicker.new()
	game.level_root.add_child(c)
	c.setup_clicker(game, game.L, pos, ang)
	game.enemies.append(c)
	return c


## 0.9: щелкун слепой и идёт на звук; укус героя 20 без захвата; бандита — насмерть (или напарник отбивает);
## нож сзади убивает, кулак сзади не валит.
func _clicker_test() -> bool:
	var p: Player = game.player
	_open_spot(p)
	var f := p.facing()
	p.invuln = 0.0
	p.dead = false
	p.hp = 100.0
	var ok := true
	game.state = "play"
	game.autotest = false
	# 1) слепой: герой стоит в 3 м перед ним — не замечает; выстрел — идёт на звук
	_clear()
	var c := _spawn_clicker(p.position + Vector3(f.x, 0, f.y) * 3.0, p.angle + PI)
	c.state = Enemy.S.LOOK
	c.t = 99.0
	await _frames(45)
	var blind := c.state == Enemy.S.LOOK and p.hp == 100.0
	p.inv = {"pistol": 6}
	p.selected = "pistol"
	p.cd = 0.0
	p.angle = wrapf(p.angle + PI, -PI, PI)   # стреляем в сторону
	p.use_item()
	await _frames(2)
	var rushes := c.mode() == "rush"
	# 2) укус героя: 20 урона, без захвата (герой не заморожен и может уйти)
	_clear()
	p.hp = 100.0
	p.invuln = 0.0
	c = _spawn_clicker(p.position + Vector3(f.x, 0, f.y) * 0.8, p.angle + PI)
	for i in 30:
		await _frames(1)
		if p.hp < 100.0: break
	var bite := absf(p.hp - 80.0) < 0.1 and not p.frozen
	ok = ok and blind and rushes and bite
	print("[itemtest] %-14s %-18s слепой=%s, на выстрел=%s, укус 20 без захвата=%s" % ["clicker", "верно" if blind and rushes and bite else "НЕВЕРНО", blind, rushes, bite])
	# 3) одинокий бандит — схвачен и убит, щелкун ест
	_clear()
	p.position += Vector3(f.x, 0, f.y) * -20.0   # герой подальше
	var far := p.position + Vector3(f.x, 0, f.y) * 20.0
	var h := _spawn_human("knife", far, 0.0)
	h.state = Enemy.S.GUARD
	c = _spawn_clicker(far + Vector3(0.7, 0, 0), 0.0)
	c._start_grab(h)
	c.rescue = false
	await _frames(45)
	var killed := h.is_dead() and c.mode() == "feed"
	# 4) напарник рядом отбивает (форсируем удачу): щелкун падает, схваченный жив и ранен
	_clear()
	h = _spawn_human("knife", far, 0.0)
	var h2 := _spawn_human("axe", far + Vector3(1.0, 0, 0), 0.0)
	h.state = Enemy.S.GUARD
	h2.state = Enemy.S.GUARD
	c = _spawn_clicker(far + Vector3(-0.7, 0, 0), 0.0)
	c._start_grab(h)
	c.rescue = true
	await _frames(45)
	var saved := not h.is_dead() and h.hp < h.max_hp and c.mode() == "down"
	ok = ok and killed and saved
	print("[itemtest] %-14s %-18s одинокий убит+ест=%s, напарник отбил=%s" % ["clicker_grab", "верно" if killed and saved else "НЕВЕРНО", killed, saved])
	# 5) нож сзади — насмерть; кулак сзади — не валит
	_clear()
	_open_spot(p)
	f = p.facing()
	c = _spawn_clicker(p.position + Vector3(f.x, 0, f.y) * 1.2, p.angle)   # спиной к герою
	c.state = Enemy.S.LOOK
	c.t = 99.0
	p.inv = {}
	p.selected = ""
	p.cd = 0.0
	p.melee()
	var fist_no_knock := c.state != Enemy.S.KNOCKED
	c.angle = p.angle
	c.rotation.y = c.angle
	c.state = Enemy.S.LOOK
	p.inv = {"knife": 3}
	p.selected = "knife"
	p.cd = 0.0
	p.use_item()
	var knife_kill := c.is_dead()
	game.state = "intro"
	ok = ok and fist_no_knock and knife_kill
	print("[itemtest] %-14s %-18s кулак не валит=%s, нож сзади убил=%s" % ["clicker_kill", "верно" if fist_no_knock and knife_kill else "НЕВЕРНО", fist_no_knock, knife_kill])
	_clear()
	return ok


## Потолок запаса: подбор сверх потолка оставляет остаток на полу; полный запас — не подбирается;
## награда за взлом сверх потолка падает на пол.
func _cap_test() -> bool:
	var p: Player = game.player
	_clear()
	for pk in game.pickups:
		pk.node.queue_free()
	game.pickups.clear()
	p.inv = {"pistol": 5}
	game._add_pickup("pistol", 4, p.position)
	await _frames(3)
	var a: bool = p.inv.get("pistol", 0) == 6 and game.pickups.size() == 1 and game.pickups[0].n == 3
	# стоим рядом с полным запасом — не берёт
	await _frames(3)
	var b: bool = p.inv.get("pistol", 0) == 6 and game.pickups[0].n == 3
	for pk in game.pickups:
		pk.node.queue_free()
	game.pickups.clear()
	# награда сверх потолка: кофе 2/2 + ещё 1 → на полу 1
	p.inv = {"coffee": 2}
	game.give_reward("coffee", 1)
	var c: bool = p.inv.get("coffee", 0) == 2 and game.pickups.size() == 1 and game.pickups[0].n == 1
	await _frames(3)
	var d: bool = game.pickups.size() == 1   # рядом, но не подбирается и не исчезает
	for pk in game.pickups:
		pk.node.queue_free()
	game.pickups.clear()
	var ok: bool = a and b and c and d
	print("[itemtest] %-14s %-18s подобрал до потолка=%s, полный не берёт=%s, награда на пол=%s, лежит=%s" % ["cap", "верно" if ok else "НЕВЕРНО", a, b, c, d])
	return ok


## Длительность оглушений: кулак сзади 1.2 с, труба сзади 2.5 с, кастет 162 с; кулаком зомби умирает с 5 ударов.
func _knock_time_test() -> bool:
	var p: Player = game.player
	var ok := true
	for c in [["pipe", 2.5], ["knuckles", 162.0]]:   # 0.12: кулак сзади теперь душит (_sneak_test)
		_clear()
		p.cd = 0.0
		p.inv = {}
		var f := p.facing()
		game._add_enemy("zombie", p.position + Vector3(f.x, 0, f.y) * 1.2, p.angle, false)
		var e: Enemy = game.enemies[0]
		e.state = Enemy.S.LOOK
		e.t = 99.0
		await _frames(2)
		if c[0] == "fist":
			p.melee()
		else:
			p.add_item(c[0], 3)
			p.selected = c[0]
			p.use_item()
		var kt := e.knock_t
		var good := e.state == Enemy.S.KNOCKED and absf(kt - c[1]) < 0.05
		ok = ok and good
		print("[itemtest] %-14s %-18s лежит %.1f с (нужно %.1f)" % ["knock_" + c[0], "верно" if good else "НЕВЕРНО", kt, c[1]])
	# кулак: сколько ударов на обычного зомби (лицом к лицу)
	_clear()
	var f2 := p.facing()
	game._add_enemy("zombie", p.position + Vector3(f2.x, 0, f2.y) * 1.2, p.angle + PI, false)
	var z: Enemy = game.enemies[0]
	var hits := 0
	while not z.is_dead() and hits < 20:
		p.cd = 0.0
		z.state = Enemy.S.LOOK
		z.position = p.position + Vector3(f2.x, 0, f2.y) * 1.2
		p.melee()
		hits += 1
		await _frames(1)
	var good2 := hits == 7   # 0.12: кулак 15 — 7 ударов (было 20 — 5)
	ok = ok and good2
	print("[itemtest] %-14s %-18s ударов кулаком на зомби: %d" % ["fist_kill", "верно" if good2 else "НЕВЕРНО", hits])
	return ok


## Болтовка людей по игроку: сильно ранит, но не добивает.
func _rifle_nonlethal_test() -> bool:
	var p: Player = game.player
	p.hp = 30.0
	p.invuln = 0.0
	p.dead = false
	game.state = "play"
	_clear()
	game.hud.toasts.clear()
	var h := Human.new()
	game.level_root.add_child(h)
	var f := p.facing()
	h.setup_human(game, game.L, p.position + Vector3(f.x, 0, f.y) * 1.2, p.angle + PI, "rifle", {"anchor": p.position}, "pair")
	game.enemies.append(h)
	game.damage_player(h.W.dmg_p, h, true)
	var ok := not p.dead and p.hp >= 1.0
	print("[itemtest] %-14s %-18s герой hp 30 → %d" % ["rifle_vs_hero", "не добила" if ok else "УБИЛА", p.hp])
	game.state = "intro"
	return ok


func _frames(n: int) -> void:
	for i in n:
		await game.get_tree().process_frame


## 0.20.3: в стартовой зоне героя (его комната / 14 шагов) при появлении врагов нет — на всех типах этажей;
## «только приехал» — первые 3 с зомби в 3 м перед героем его не замечает, потом замечает;
## «ЕЩЁ РАЗ» после смерти — с этажа, выбранного в начале, «НАЧАТЬ СМЕНУ» — с 1-го.
func _start_room_test() -> bool:
	var res := {}
	var worst := 0
	var loads := 0
	var plan := [[1, ""], [3, ""], [5, ""], [9, ""], [12, ""], [16, ""], [22, ""], [27, ""],
		[5, "lair"], [10, "fort"], [10, "battle"], [30, "roof"]]
	for c in plan:
		for _t in 2:
			game._load_floor(c[0], false, c[1])
			loads += 1
			var L: OfficeLevel = game.L
			var sd := L.start_dist()
			var near := 0
			for e: Enemy in game.enemies:
				if L.in_start_zone(floori(e.pz()) * L.W + floori(e.px()), sd):
					near += 1
			worst = maxi(worst, near)
			await game.get_tree().process_frame
	res["%d этажей всех типов: врагов у старта %d" % [loads, worst]] = worst == 0
	# «только приехал»
	game._load_floor(3, false)
	await _frames(2)
	var p: Player = game.player
	_clear()
	_open_spot(p)
	p.dead = false
	p.invuln = 99.0
	p.hp = 100.0
	p.crouch = false
	game.autotest = false
	game.state = "play"
	game.arrive_grace = game.ARRIVE_GRACE
	var z := _put("zombie", 3.0, false)
	var early := false
	var seen_t := -1.0
	for i in 200:
		await _frames(1)
		if z.state == Enemy.S.LOOK:
			z.angle = z.angle_to_point(p.px(), p.pz())
			z.rotation.y = z.angle
			z.look_base = z.angle
			z.model.head.rotation.y = 0.0
		if i < 80 and (z.is_hostile() or z.susp > 0.12):
			early = true
		if z.is_hostile():
			seen_t = (i + 1) / 30.0
			break
	res["только приехал: зомби в 3 м не замечает 2,7 с"] = not early
	res["потом — замечает (%.1f с)" % seen_t] = seen_t > 3.0 and seen_t < 6.0
	_clear()
	# «ЕЩЁ РАЗ» — с выбранного этажа
	game.start_run(25)
	await _frames(2)
	game.floor_num = 28
	game.on_button("retry", true)
	await _frames(2)
	res["ЕЩЁ РАЗ — снова с 25-го"] = game.floor_num == 25 and int(game.stats.from) == 25
	game.on_button("start", true)
	await _frames(2)
	res["НАЧАТЬ СМЕНУ — с 1-го"] = game.floor_num == 1 and game.run_from == 1
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["start_0.20.3", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.16: спецэтажи и логово. Каждый 5-й ~50% логово, остальные — никогда; логово без ПК и зомби, 6–10 бандитов,
## бочки, один охранник у комнаты с маскировкой, ключ-карта на спине у одного; бандиты греются (≤ 2 у бочки) и ходят
## к стене; вырубил хозяина карты — карта на полу, подобрал — лифт открыт. Маскировка: бандиты свои, офисники — нет;
## надеть нельзя, пока бандит гонится; душишь бандита на глазах у другого — раскрыт (вид героя — обратно).
func _lair_test() -> bool:
	var res := {}
	var DT := 1.0 / 30.0
	# 1) шанс спецэтажа
	var on5 := 0
	var other := 0
	for _i in 40:
		if game._floor_kind_for(10, true) != "normal": on5 += 1   # 0.17: спецэтаж — логово или офис
		if game._floor_kind_for(7, true) == "lair" or game._floor_kind_for(4, true) == "lair": other += 1
	res["5-й/10-й спец ~50%% (%d/40), остальные — нет" % on5] = on5 >= 10 and on5 <= 30 and other == 0
	# 2) этаж-логово
	game._load_floor(5, false, "lair")
	await _frames(3)
	var p: Player = game.player
	p.invuln = 999.0
	p.frozen = true
	p.position = Vector3(-50, 0, -50)   # вне этажа — никого не тревожит
	var L: OfficeLevel = game.L
	var hs: Array = game.enemies.filter(func(e): return e is Human)
	var zs: Array = game.enemies.filter(func(e): return not e is Human)
	var guards: Array = hs.filter(func(h): return h.has_post)
	var disg: Array = game.pickups.filter(func(pk): return pk.id == "disguise")
	res["логово: без ПК и зомби, бандитов %d, бочек %d" % [hs.size(), L.fires.size()]] = L.pcs.is_empty() and zs.is_empty() \
		and hs.size() >= 6 and hs.size() <= 10 and L.fires.size() >= 1
	var loot_ok: bool = disg.size() == 1 and L.room_at(disg[0].node.position.x, disg[0].node.position.z).get("id", -1) == L.loot.room
	res["охранник у комнаты с маскировкой"] = guards.size() == 1 and loot_ok and guards[0].position.distance_to(L.loot.guard) < 1.5
	res["ключ-карта на спине у одного"] = game.key_holder != null and game.key_holder.model.keycard != null \
		and hs.filter(func(h): return h.has_key).size() == 1
	res["без карты лифт закрыт"] = not game.exit_open()
	# 3) жизнь логова — до 5 мин (пока не увидим и костёр, и «к стене»)
	var max_fire := 0
	var fire_seen := false
	var pee_seen := false
	for _s in 300 * 30:
		if fire_seen and pee_seen and _s > 60 * 30:
			break
		game._update_world(DT, false)
		var per := {}
		for h: Human in hs:
			if h.is_dead() or h.state != Enemy.S.REST: continue
			if h.rest_kind == "fire":
				fire_seen = true
				per[h.fire_i] = per.get(h.fire_i, 0) + 1
			elif h.rest_kind == "pee":
				pee_seen = true
		for k in per:
			max_fire = maxi(max_fire, per[k])
	res["греются (у бочки ≤ 2: %d), ходят к стене" % max_fire] = fire_seen and pee_seen and max_fire <= 2
	res["никто не встревожен"] = hs.filter(func(h): return h.is_hostile()).is_empty()
	# 4) вырубили хозяина карты — карта на полу; подобрал — лифт открыт
	var kh: Human = game.key_holder
	kh.knockdown(20.0, true)
	game._update_world(DT, false)
	var cards: Array = game.pickups.filter(func(pk): return pk.id == "keycard")
	res["вырубил — карта упала"] = cards.size() == 1 and not kh.has_key and kh.model.keycard == null
	if cards.size() == 1:
		p.position = cards[0].node.position
		game._update_pickups(DT)
	res["подобрал — лифт открыт"] = game.key_taken and game.exit_open()
	# 5) маскировка
	_clear()
	p.position = Vector3(-50, 0, -50)
	p.frozen = false
	_open_spot(p)
	game.state = "play"
	var f := p.facing()
	var fwd := Vector3(f.x, 0, f.y)
	p.inv = {"disguise": 1}
	p.selected = "disguise"
	p.cd = 0.0
	var b := _spawn_human("knife", p.position + fwd * 4.0, p.angle + PI)
	b.foe = p
	b.state = Enemy.S.CHASE
	p.use_item()
	res["нельзя надеть, пока бандит гонится"] = not p.disguised and p.inv.get("disguise", 0) == 1
	_clear()
	b = _spawn_human("knife", p.position + fwd * 4.0, p.angle + PI)   # смотрит на героя
	b.attn = 1.0
	p.cd = 0.0
	p.use_item()
	for _i in 75:
		await _frames(1)
	res["надел: бандит свой, вид бандита"] = p.disguised and p.inv.get("disguise", 0) == 0 and not b.is_hostile() \
		and b.is_loyal() and p.model.kind == "human"
	_clear()
	var o := _spawn_office("pipe", p.position + fwd * 4.0, p.angle + PI)   # смотрит на героя (впереди всегда открыто)
	o.angle = o.angle_to_point(p.px(), p.pz())
	o.rotation.y = o.angle
	o.look_base = o.angle
	o.attn = 1.0
	for _i in 75:
		await _frames(1)
	res["офисник в маскировке — враг"] = not o.is_loyal() and o.foe == p and (o.is_hostile() or o.state == Enemy.S.STARTLED)
	_clear()
	# душит бандита на глазах у другого — раскрыт
	var v := _spawn_human("knife", p.position + fwd * 1.2, p.angle)       # спиной к герою
	var w := _spawn_human("axe", p.position + fwd * 5.0, p.angle + PI)     # смотрит на героя
	await _frames(2)
	p.angle = p.angle_to_point(v.px(), v.pz())
	p.cd = 0.0
	p.melee()
	await _frames(3)
	res["душит на глазах — раскрыт, вид героя"] = game.disguise_blown and not w.is_loyal() and p.model.kind == "player"
	_clear()
	p.disguised = false
	p.set_look("player")
	game.disguise_blown = false
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["lair_0.16", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.16.1: кнопка «СНЯТЬ ЦЕЛЬ» снимает захват; луч бандита против героя 54° (герой под 25° — виден, зомби там же —
## нет: против остальных 46°); замешательство 0.5–0.7 с, с отдыха 0.9 с.
func _v0161_test() -> bool:
	var res := {}
	game._load_floor(4, false)
	await _frames(3)
	game.state = "play"
	var p: Player = game.player
	p.invuln = 999.0
	_clear()
	_open_spot(p)
	var f := p.facing()
	var fwd := Vector3(f.x, 0, f.y)
	var z := _put("zombie", 5.0, false)
	p.lock = z
	game.on_button("unlock", true)
	res["«СНЯТЬ ЦЕЛЬ» снимает захват"] = p.lock == null
	_clear()
	# бандит в 6 м перед героем, смотрит мимо на 25° — героя видит, зомби на том же месте — нет
	var b := _spawn_human("knife", p.position + fwd * 6.0, 0.0)
	b.angle = b.angle_to_point(p.px(), p.pz()) + deg_to_rad(25.0)
	b.rotation.y = b.angle
	var hero_seen: bool = b._see_factor(p) > 0.0
	var z2 := _put("zombie", 0.5, false)
	z2.position = p.position
	var zombie_seen: bool = b._see_factor(z2) > 0.0
	res["бандит: герой под 25° виден, зомби — нет"] = hero_seen and not zombie_seen
	b.angle = b.angle_to_point(p.px(), p.pz()) + deg_to_rad(29.0)
	res["под 29° — не виден"] = b._see_factor(p) == 0.0
	# замешательство
	var mn := 9.0
	var mx := 0.0
	for _i in 30:
		b.state = Enemy.S.PATROL
		b.from_rest = false
		b.alert()
		mn = minf(mn, b.startle_dur)
		mx = maxf(mx, b.startle_dur)
	b.state = Enemy.S.REST
	b.was_resting = true
	b.alert()
	res["замешательство %.2f–%.2f с, с отдыха %.1f с" % [mn, mx, b.startle_dur]] = mn >= 0.5 and mx <= 0.7 and is_equal_approx(b.startle_dur, 0.9)
	_clear()
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["v0161", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.17: укреплённый офис — на 5-м/10-м бывают и логово, и офис; без зомби и ПК, 5–7 офисников, лифт открыт; двое
## болтают рядом, один у радио, охранник у комнаты с пакетами; кража на глазах — гонит кулаком (не насмерть), остальные
## не враги; ударил в ответ — враги все; пакеты — бег без шума (зомби за спиной не слышит).
func _fort_test() -> bool:
	var res := {}
	var DT := 1.0 / 30.0
	var kinds := {}
	for _i in 60:
		var k: String = game._floor_kind_for(10, true)
		kinds[k] = kinds.get(k, 0) + 1
	res["10-й: обычный/логово/офис %s" % kinds] = kinds.get("lair", 0) >= 5 and kinds.get("fort", 0) >= 5 and kinds.get("normal", 0) >= 15
	game._load_floor(10, false, "fort")
	await _frames(3)
	var p: Player = game.player
	p.invuln = 0.0
	p.hp = 100.0
	p.frozen = true
	p.position = Vector3(-50, 0, -50)
	var L: OfficeLevel = game.L
	var hs: Array = game.enemies.filter(func(e): return e is Human)
	res["офис: без ПК и зомби, офисников %d, лифт открыт" % hs.size()] = L.pcs.is_empty() and hs.size() == game.enemies.size() \
		and hs.size() >= 5 and hs.size() <= 7 and hs.all(func(h): return h.faction == "office") and game.exit_open()
	for _s in 40 * 30:
		game._update_world(DT, false)
	var talkers: Array = hs.filter(func(h): return h.role == "talk" and h.state == Enemy.S.REST and h.rest_kind == "talk")
	res["двое болтают рядом"] = talkers.size() == 2 and talkers[0].dist_to(talkers[1]) < 2.0
	res["один слушает радио"] = hs.filter(func(h): return h.role == "radio" and h.state == Enemy.S.REST and h.rest_kind == "sit").size() == 1
	var guard: Human = hs.filter(func(h): return h.role == "guard")[0]
	var bags_pk: Array = game.pickups.filter(func(pk): return pk.id == "bags")
	res["охранник у комнаты с пакетами"] = bags_pk.size() == 1 and guard.position.distance_to(L.loot.guard) < 1.5 \
		and L.room_at(bags_pk[0].node.position.x, bags_pk[0].node.position.z).get("id", -1) == L.loot.room
	# кража на глазах
	game.state = "play"
	p.frozen = false
	p.inv = {}
	p.position = L.loot.pos
	# охранник рядом, на открытой линии (комната может быть заставлена)
	var gc := Vector2i(-1, -1)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var cx: int = floori(p.px()) + dx
			var cz: int = floori(p.pz()) + dz
			if gc.x < 0 and (dx != 0 or dz != 0) and L.walkable(cx, cz) and not L.line_blocked(cx + 0.5, cz + 0.5, p.px(), p.pz(), 0):
				gc = Vector2i(cx, cz)
	guard.position = Vector3(gc.x + 0.5, 0, gc.y + 0.5)
	guard.angle = guard.angle_to_point(p.px(), p.pz())
	guard.rotation.y = guard.angle
	game._update_pickups(DT)
	res["взял пакеты"] = p.inv.get("bags", 0) == 1
	res["охранник гонит взашей"] = guard.angry_t > 0.0 and guard.foe == p and guard.is_hostile()
	for _i in 180:
		await _frames(1)
	res["кулаком, не насмерть (hp %d), остальные не враги" % int(p.hp)] = p.hp < 100.0 and p.hp >= 1.0 and not p.dead \
		and not game.office_hostile
	# ударил в ответ — враги все
	p.lock = guard
	p.cd = 0.0
	p.angle = p.angle_to_point(guard.px(), guard.pz())
	guard.position = p.position + Vector3(sin(p.angle), 0, cos(p.angle)) * 1.0
	p.melee()
	p.lock = null
	await _frames(3)
	res["ударил в ответ — враги все"] = game.office_hostile
	# пакеты: бег не слышен зомби за спиной
	_clear()
	game.office_hostile = false
	p.hp = 100.0
	p.invuln = 99.0
	game.state = "intro"   # мир крутим сами
	var heard := []
	for with_bags in [false, true]:
		_open_spot(p)
		p.bags = with_bags
		var f := p.facing()
		var z := _put("zombie", 3.0, true)
		z.position = p.position - Vector3(f.x, 0, f.y) * 1.6   # в 1.6 м позади героя, смотрит в другую сторону (за стеной слышно хуже — ближе надёжнее)
		z.angle = p.angle + PI
		z.rotation.y = z.angle
		z.look_base = z.angle
		var got := false
		for _s in 50:
			p.update(DT, Vector2(f.x, f.y))   # бежим вперёд (впереди открыто 9 м), прочь от зомби
			z.update(DT)
			if z.susp > 0.2 or z.state != Enemy.S.LOOK:
				got = true   # подозрение быстро гаснет — ловим за весь бег
		heard.append(got)
		_clear()
	res["бег: без пакетов слышно, в пакетах — нет"] = heard[0] and not heard[1]
	p.bags = false
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["fort_0.17", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.18: поле битвы — на 10-м бывают все три спецэтажа; без зомби и ПК, лифт открыт; 4–6 офисников и 5–6 бандитов
## у разных концов, ящик с патронами; стороны встречаются и воюют, победители подбирают стволы/салютуют;
## ящик заряжает огнестрельное до потолка.
func _battle_test() -> bool:
	var res := {}
	var DT := 1.0 / 30.0
	var kinds := {}
	for _i in 90:
		var k: String = game._floor_kind_for(10, true)
		kinds[k] = kinds.get(k, 0) + 1
	res["10-й: %s" % kinds] = kinds.get("battle", 0) >= 5 and kinds.get("fort", 0) >= 5 and kinds.get("lair", 0) >= 5
	game._load_floor(10, false, "battle")
	await _frames(3)
	var p: Player = game.player
	p.frozen = true
	p.invuln = 999.0
	p.position = Vector3(-60, 0, -60)
	var L: OfficeLevel = game.L
	var off: Array = game.enemies.filter(func(e): return e is Human and e.faction == "office")
	var ban: Array = game.enemies.filter(func(e): return e is Human and e.faction == "human")
	var da := L.bfs_dist(floori(L.sides[0].pos.x), floori(L.sides[0].pos.z))
	var bpos: Vector3 = L.sides[1].pos
	res["офисников %d, бандитов %d, без зомби и ПК, лифт открыт" % [off.size(), ban.size()]] = off.size() >= 4 and off.size() <= 6 \
		and ban.size() >= 5 and ban.size() <= 6 and off.size() + ban.size() == game.enemies.size() and L.pcs.is_empty() and game.exit_open()
	res["стороны далеко (%d шагов), ящик патронов есть" % da[floori(bpos.z) * L.W + floori(bpos.x)]] = da[floori(bpos.z) * L.W + floori(bpos.x)] >= 18 \
		and game.pickups.filter(func(pk): return pk.id == "ammo").size() == 1
	var t := 0.0
	var after_t := -1.0
	while t < 480.0:
		game._update_world(DT, false)
		t += DT
		if game.battle_phase == "after" and after_t < 0.0:
			after_t = t
		if after_t >= 0.0 and t > after_t + 15.0:
			break
	var st: Dictionary = game.npc_stats
	if game.battle_phase != "after":
		print("[dbg] бой не кончился: ", game.enemies.filter(func(e): return not e.is_dead()).map(func(e): return "%s:%s:%s:%s" % [e.faction, e.role, Enemy.S.keys()[e.state], e.foe.faction if Enemy.alive(e.foe) and e.foe is Enemy else "-"]))
	res["встретились и воевали (бой с %d с)" % int(st.battle_start_t)] = game.faction_war_on
	res["бой кончился: победили %s (за %d с)" % [st.battle_winner, int(after_t)]] = game.battle_phase == "after" and st.battle_winner != ""
	var winners: Array = game.enemies.filter(func(e): return e is Human and not e.is_dead() and not e.is_down() and e.faction == st.battle_winner)
	res["победители (%d) бродят, стволов взяли %d" % [winners.size(), st.battle_guns_taken]] = st.battle_winner == "none" \
		or winners.all(func(h): return h.role in ["fort", "loot"] or h.is_hostile())
	# ящик с патронами
	_clear()
	game.state = "play"
	p.frozen = false
	p.inv = {"pistol": 1}
	p.position = L.ammo_pos
	game._update_pickups(DT)
	res["ящик: пистолет 1 → %d" % p.inv.get("pistol", 0)] = p.inv.get("pistol", 0) == Items.cap("pistol") \
		and game.pickups.filter(func(pk): return pk.id == "ammo").is_empty()
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["battle_0.18", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.18.2: чит-сборка — «Играть с этажа» с выбранным типом: start_run(N, kind) грузит этот тип; без чит-сборки
## кнопки типа не действуют.
func _cheat_kind_test() -> bool:
	var res := {}
	for k in ["lair", "fort", "battle", "normal"]:
		game.start_run(10, k)
		await _frames(2)
		res["этаж 10 → %s" % k] = game.floor_kind == k
	game.state = "floors"
	game.cheat_kind = ""
	game.on_button("kind_lair", true)
	res["без чит-сборки выбор не действует"] = game.cheat_kind == ""
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["cheat_0.18.2", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.19: крыша (финал). 30-й — всегда крыша (и из чит-меню тоже); без зомби и ПК, 10–12 бандитов, выход закрыт; курят
## у парапета; герой у площадки → вертолёт садится за 5 с → трое элитных (hp 150, M4A1-S); в маскировке обычные свои,
## элита — нет; элита лежит → выход открыт → «в вертолёт» → победа. M4A1-S героя — в слоте «длинноствол».
func _roof_test() -> bool:
	var res := {}
	var DT := 1.0 / 30.0
	game.start_run(30, "lair")
	await _frames(3)
	res["30-й — крыша (даже если в чите выбрано логово)"] = game.floor_kind == "roof"
	var p: Player = game.player
	p.invuln = 999.0
	p.frozen = true
	p.visible = false
	p.position = Vector3(-60, 0, -60)
	var L: OfficeLevel = game.L
	var hs: Array = game.enemies.filter(func(e): return e is Human)
	res["без зомби и ПК, бандитов %d, выход закрыт" % hs.size()] = L.pcs.is_empty() and hs.size() == game.enemies.size() \
		and hs.size() >= 10 and hs.size() <= 12 and not game.exit_open() and game.heli_phase == "wait"
	var smoke := false
	for _s in 120 * 30:
		game._update_world(DT, false)
		for h: Human in hs:
			if h.state == Enemy.S.REST and h.rest_kind == "smoke":
				smoke = true
		if smoke and _s > 30 * 30:
			break
	res["курят у парапета"] = smoke
	# маскировка: обычные — свои
	p.disguised = true
	var normal_loyal: bool = hs[0].is_loyal()
	# герой у площадки → посадка → элита
	p.visible = true
	p.frozen = false
	p.position = L.helipad + Vector3(-8.0, 0, 0)
	game.state = "intro"
	for _s in 30:
		game._update_world(DT, false)
	res["герой у площадки — вертолёт садится"] = game.heli_phase == "landing"
	for _s in 6 * 30:
		game._update_world(DT, false)
	var el: Array = game.elites
	res["сел, элита %d (hp %s, %s)" % [el.size(), el.map(func(e): return int(e.max_hp)), el.map(func(e): return e.weapon)]] = \
		game.heli_phase == "landed" and el.size() == 3 and el.all(func(e): return e.elite and e.max_hp == 150.0 and e.weapon == "m4")
	res["в маскировке: обычный свой, элита — нет"] = normal_loyal and el.all(func(e): return not e.is_loyal())
	p.disguised = false
	res["пока элита на ногах — выход закрыт"] = not game.exit_open()
	el[0].take_damage(999.0, p, "gun")
	el[1].knockdown(30.0, true)
	el[2].take_damage(999.0, p, "gun")
	res["элита лежит — выход открыт"] = game.exit_open()
	var b0: int = game.beaten
	p.position = L.exit_elev.stand
	game._board_heli()
	res["в вертолёт — победа"] = game.state == "victory" and game.beaten == b0 + 1 and not p.visible
	# M4 героя
	p.inv = {}
	res["M4A1-S героя: длинноствол, 15"] = Items.slot_of("m4") == "long" and p.add_item("m4", 15) == 15 and Items.def("m4").cat == Items.Cat.WEAPON
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["roof_0.19", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.19.1: свидетели. Ближник один видит удушение своего — не нападает, бежит к своим и приводит 2–3 обыскивать;
## свой рядом (≤ 5 м) — нападают вместе; своих нет — дерётся; стрелок — сразу бой. Лояльный офисник на шаги героя
## только оглядывается (без «?», не идёт), враждебный — настораживается.
func _witness_test() -> bool:
	var res := {}
	var DT := 1.0 / 30.0
	game._load_floor(4, false)
	await _frames(3)
	var p: Player = game.player
	p.invuln = 999.0
	var L: OfficeLevel = game.L
	var setup := func(wid: String, ally_d: float) -> Array:
		_clear()
		_open_spot(p)
		game.state = "play"
		p.frozen = false
		p.cd = 0.0
		p.inv = {}
		p.selected = ""
		var f := p.facing()
		var fwd := Vector3(f.x, 0, f.y)
		var v := _spawn_human("knife", p.position + fwd * 1.2, p.angle)            # спиной к герою
		var w := _spawn_human(wid, p.position + fwd * 6.0, p.angle + PI)          # смотрит на героя
		w.attn = 1.0
		var allies: Array = []
		if ally_d > 0.0:
			# свой — на проходимой клетке в ally_d от свидетеля (как можно точнее)
			var dw := L.bfs_dist(floori(w.px()), floori(w.pz()))
			var best := -1
			for i in L.W * L.H:
				var far_ok: bool = ally_d < 5.0 or Vector2(i % L.W + 0.5 - w.px(), i / L.W + 0.5 - w.pz()).length() >= 12.0   # дальше 10 м — не слышит крика
				if far_ok and dw[i] > 0 and L.cells[i] == OfficeLevel.FLOOR and (best < 0 or absf(dw[i] - ally_d) < absf(dw[best] - ally_d)):
					best = i
			var a := _spawn_human("axe", Vector3(best % L.W + 0.5, 0, best / L.W + 0.5), 0.0)
			allies.append(a)
			allies.append(_spawn_human("knife", Vector3(best % L.W + 0.5, 0, best / L.W + 0.5) + Vector3(0.8, 0, 0), 0.0))
		await _frames(2)
		p.angle = p.angle_to_point(v.px(), v.pz())
		p.melee()
		await _frames(2)
		return [v, w, allies]
	# 1) один ближник, свои далеко — бежит, не нападает; добежал/услышали — обыск 2–3
	var r1: Array = await setup.call("knife", 16.0)
	var w1: Human = r1[1]
	res["ближник один — бежит за своими, не нападает"] = w1.report_t > 0.0 and not w1.is_hostile()
	game.state = "intro"
	var searched := false
	for _s in 30 * 30:
		game._update_world(DT, false)
		if game.npc_stats.witness_searches > 0:
			searched = true
			break
	var seekers: Array = (r1[2] as Array).filter(func(a): return a.state == Enemy.S.INVESTIGATE or not a.search_pts.is_empty())
	res["привёл своих обыскивать (%d)" % seekers.size()] = searched and seekers.size() >= 1
	# 2) свой рядом (≤ 5 м) — нападают вместе
	var r2: Array = await setup.call("knife", 3.0)
	res["свой рядом — нападают вместе"] = (r2[1] as Human).is_hostile() and (r2[2][0] as Human).is_hostile()
	# 3) своих нет — дерётся сам
	var r3: Array = await setup.call("knife", 0.0)
	res["один на этаже — дерётся"] = (r3[1] as Human).is_hostile() and (r3[1] as Human).report_t <= 0.0
	# 4) стрелок — кричит и стреляет
	var r4: Array = await setup.call("uzi", 16.0)
	res["стрелок — сразу бой"] = (r4[1] as Human).is_hostile()
	# 5) лояльный офисник на шаги героя — только взгляд
	_clear()
	_open_spot(p)
	game.state = "intro"
	game.office_hostile = false
	var f2 := p.facing()
	var o := _spawn_office("pipe", p.position + Vector3(f2.x, 0, f2.y) * 3.0, p.angle)   # спиной к герою
	var st0 := o.state
	game.emit_noise(p.position, 6.5, "step", true)
	res["лояльный на шаги — оглянулся, не идёт (susp %.2f)" % o.susp] = o.glance_t > 0.0 and o.state == st0 and o.susp < 0.05
	game.office_hostile = true
	game.emit_noise(p.position, 6.5, "step", true)
	res["враждебный — насторожился"] = o.susp > 0.2 or o.state in [Enemy.S.SUSPICIOUS, Enemy.S.INVESTIGATE]
	game.office_hostile = false
	_clear()
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["witness_0.19.1", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.20: пожарные лестницы — на обычных 20–29 по 1–2 люка во внешней стене (на 19-м, 30-м и спецэтажах нет);
## после 3-го взлома спускаются 2–3 бандита (не больше 3), потом ещё; потолок живых бандитов; люк блокируется удержанием
## 3 с — с него больше никто не спускается.
func _escape_test() -> bool:
	var res := {}
	var DT := 1.0 / 30.0
	game._load_floor(19, false, "normal")
	var none19: bool = game.L.escapes.is_empty()
	game._load_floor(25, false, "lair")
	var none_lair: bool = game.L.escapes.is_empty()
	game._load_floor(25, false, "normal")
	await _frames(3)
	var L: OfficeLevel = game.L
	var es: Array = L.escapes
	var border_ok := es.all(func(e): return (e.x == 0 or e.z == 0 or e.x == L.W - 1 or e.z == L.H - 1) \
		and L.walkable(floori(e.stand.x), floori(e.stand.z)))
	res["люков на 25-м: %d (у стены, проход есть); на 19-м и в логове — нет" % es.size()] = es.size() >= 1 and es.size() <= 2 and border_ok \
		and none19 and none_lair
	var p: Player = game.player
	p.invuln = 999.0
	p.frozen = true
	p.position = Vector3(-60, 0, -60)
	game.waves = []   # обычные отряды не мешают счёту
	var humans := func() -> int: return game.enemies.filter(func(e): return e is Human and e.faction == "human" and not e.is_dead()).size()
	var h0: int = humans.call()
	for _s in 20 * 30:
		game._update_world(DT, false)
	res["до 3-го взлома никто не спустился"] = humans.call() == h0
	game.hacked = 3
	for _s in 12 * 30:
		game._update_world(DT, false)
	var h1: int = humans.call()
	res["после 3-го взлома спустились %d" % (h1 - h0)] = h1 - h0 >= 2 and h1 - h0 <= 3
	res["следующая — через 3 мин (%.0f с)" % game.esc_t] = game.esc_t > 160.0 and game.esc_t <= 180.0   # 0.20.1
	game.esc_t = 0.01
	game._update_world(DT, false)
	var h2: int = humans.call()
	res["следующая волна — ещё %d" % (h2 - h1)] = h2 - h1 >= 1 and h2 - h1 <= 3
	# потолок
	while humans.call() < game.escape_cap():
		game._spawn_squad(2, false, es[0])
	var hc: int = humans.call()
	game.esc_t = 0.01
	game._update_world(DT, false)
	res["потолок %d — больше не спускаются" % game.escape_cap()] = humans.call() == hc
	# блокировка люка
	for e in game.enemies:
		if e is Human:
			e.die(null)
	var e0: Dictionary = es[0]
	p.frozen = false
	p.visible = true
	p.position = e0.stand
	game.state = "play"
	game.ctx_held = true
	for _s in 100:
		game._update_context(DT)
	game.ctx_held = false
	res["держал 3 с — люк заблокирован"] = e0.locked
	for e in es:
		e.locked = true
	var hl: int = humans.call()
	game.esc_t = 0.01
	game._update_world(DT, false)
	res["все люки закрыты — не спускаются"] = humans.call() == hl
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["escape_0.20", "верно" if ok else "НЕВЕРНО", res])
	return ok


## 0.20.2: за взлом ПК бутылки больше не выпадают (только стартовый набор и лут с людей).
func _reward_test() -> bool:
	var counts := {}
	for _i in 3000:
		var rw: Dictionary = Items.roll_reward(game.rng, 1.0 if _i % 2 == 0 else 0.3, {} if _i % 3 == 0 else {"brick": 2})
		counts[rw.id] = counts.get(rw.id, 0) + 1
	var ok: bool = not counts.has("bottle") and counts.has("alarm") and counts.has("brick")
	print("[itemtest] %-14s %-18s 3000 наград: бутылок %d, будильников %d, кирпичей %d" % ["reward_0.20.2", "верно" if ok else "НЕВЕРНО",
		counts.get("bottle", 0), counts.get("alarm", 0), counts.get("brick", 0)])
	return ok


## 0.21: больше выходов (тупиков минимум вдвое меньше, чем дал бы старый генератор); вентиляция: на этаже одна пара
## решёток, перед ними проход; без тревоги — нельзя; залез — пропал, гнавшийся потерял, урона нет, вылез у другой
## решётки; второй раз — нельзя.
func _vent_test() -> bool:
	var res := {}
	var before := 0
	var after := 0
	var rooms_n := 0
	var vmin := 99
	var stand_ok := true
	for n in [1, 3, 6, 9, 12, 16, 22, 27]:
		for s in 3:
			var L := OfficeLevel.generate(n, 1000 + n * 31 + s)
			before += L.dead_before
			after += L.dead_ends()
			rooms_n += L.rooms.filter(func(r): return not r.corridor).size()
			vmin = mini(vmin, L.vents.size())
			for v in L.vents:
				for e in [v.a, v.b]:
					if not L.walkable(floori(e.stand.x), floori(e.stand.z)): stand_ok = false
	res["тупиков: было бы %d, стало %d (комнат %d)" % [before, after, rooms_n]] = after * 2 <= before
	res["вентиляция: на этаже одна пара (мин %d), перед решёткой проход" % vmin] = vmin == 1 and stand_ok
	# без тревоги — нельзя; залезть, когда гонится зомби
	game._load_floor(6, false)
	await _frames(2)
	var p: Player = game.player
	var L2: OfficeLevel = game.L
	_clear()
	p.dead = false
	p.invuln = 0.0
	p.hp = 100.0
	p.crouch = false
	game.autotest = false
	game.state = "play"
	var v: Dictionary = L2.vents[0]
	p.position = Vector3(v.a.stand.x, 0, v.a.stand.z)
	await _frames(2)
	game.ctx_held = true
	await _frames(2)
	game.ctx_held = false
	await _frames(2)
	res["без тревоги — «ВЕНТ. ✕», не залез"] = game.vent.is_empty() and not v.used and p.visible
	game._add_enemy("zombie", p.position + Vector3(v.a.normal.x, 0, v.a.normal.z) * 2.0, 0.0, false)
	var z: Enemy = game.enemies[-1]
	z.angle = z.angle_to_point(p.px(), p.pz())
	z.rotation.y = z.angle
	z.foe = p
	z.alert()
	await _frames(3)
	var chased := z.is_hostile()
	game.ctx_held = true
	await _frames(2)
	game.ctx_held = false
	res["гнался (%s) — залез: герой пропал" % chased] = chased and not game.vent.is_empty() and not p.visible
	var hp0 := p.hp
	var lost := false
	var t := 0
	while not game.vent.is_empty() and t < 300:
		await _frames(1)
		t += 1
		if not z.sees: lost = true
	res["гнавшийся потерял, урона нет (hp %d)" % p.hp] = lost and p.hp >= hp0
	var out := Vector2(p.px() - v.b.stand.x, p.pz() - v.b.stand.z).length() < 0.3
	res["вылез у другой решётки (%.1f с)" % (t / 30.0)] = out and p.visible and not p.frozen
	await _frames(10)
	z.position = p.position + Vector3(v.b.normal.x, 0, v.b.normal.z) * 2.0   # снова гонится — второй раз нельзя
	z.foe = p
	z.alert()
	await _frames(3)
	game.ctx_held = true
	await _frames(2)
	game.ctx_held = false
	res["второй раз нельзя (кнопки нет)"] = game.vent.is_empty() and game.ctx.get("kind", "") != "vent"
	_clear()
	game.state = "intro"
	var ok := true
	for k in res:
		if not res[k]:
			ok = false
	print("[itemtest] %-14s %-18s %s" % ["vent_0.21", "верно" if ok else "НЕВЕРНО", res])
	return ok
