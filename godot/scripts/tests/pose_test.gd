extends Node
## Скриншоты стоек героя с каждым предметом: опущено и на изготовке (с захватом цели).
##   godot --path . --rendering-driver opengl3 --resolution 1280x600 -- --posetest <папка>
## Сохраняет <папка>/pose_<id>_low.png и pose_<id>_aim.png.

var game: Node


func run(g: Node, dir: String) -> void:
	game = g
	await _frames(30)
	game.state = "play"
	var p: Player = game.player
	p.invuln = 0.0
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	var f := p.facing()
	game._add_enemy("zombie", p.position + Vector3(f.x, 0, f.y) * 3.0, p.angle + PI, false)
	# зомби-манекен: убираем из списка врагов, чтобы стоял на месте и не нападал
	var e: Enemy = game.enemies[0]
	game.enemies.clear()
	# камера сбоку и ближе, чтобы было видно руки
	game.cam_yaw = p.angle + PI * 0.75
	game.cam_dist = 4.5
	var only: Array = []
	var args := OS.get_cmdline_user_args()
	if "--only" in args:
		only = args[args.find("--only") + 1].split(",")
	for id in Items.ORDER:
		if not only.is_empty() and not id in only:
			continue
		p.inv = {id: 1}
		p.selected = id
		p.lock = null
		await _frames(25)
		_shot(dir, id, "low")
		p.lock = e
		await _frames(25)
		_shot(dir, id, "aim")
	# присед: без предмета, с пистолетом (прицел), с дробовиком; стоя и на ходу. Герой — посреди большой комнаты, вид сбоку
	var big: Dictionary = {}
	for r in game.L.rooms:
		if not r.corridor and (big.is_empty() or r.area > big.area):
			big = r
	var c0: Vector2i = game.L.nearest_walkable((big.x0 + big.x1) / 2, (big.z0 + big.z1) / 2, 4)
	p.position = Vector3(c0.x + 0.5, 0, c0.y + 0.5)
	p.angle = 0.0
	p.rotation.y = 0.0
	e.position = p.position + Vector3(0, 0, 3.5)
	game.cam_pos = p.position
	game.cam_yaw = PI * 0.5
	game.cam_dist = 4.0
	for id in ["", "pistol", "shotgun"]:
		p.inv = {id: 1} if id != "" else {}
		p.selected = id
		p.lock = null
		p.crouch = true
		await _frames(25)
		_shot(dir, "crouch_" + (id if id != "" else "hands"), "idle")
		if id == "pistol":
			p.lock = e
			await _frames(20)
			_shot(dir, "crouch_pistol", "aim")
			p.lock = null
		for k in 4:
			p.speed_now = 1.5
			p.walk_phase += 0.8
			p._animate()
			await _frames(1)
			_shot(dir, "crouch_" + (id if id != "" else "hands"), "walk%d" % k)
	game.get_tree().quit()


## Люди: отряд с фонариками рядом с героем — спокойные, потом в бою (стрелок целится в героя).
func run_humans(g: Node, dir: String) -> void:
	game = g
	await _frames(20)
	game._load_floor(3, false)
	await _frames(10)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.max_hp = 99999.0
	# герой — в центре самой большой комнаты
	var big: Dictionary = {}
	for r in game.L.rooms:
		if not r.corridor and (big.is_empty() or r.area > big.area):
			big = r
	var c0: Vector2i = game.L.nearest_walkable((big.x0 + big.x1) / 2, (big.z0 + big.z1) / 2, 4)
	p.position = Vector3(c0.x + 0.5, 0, c0.y + 0.5)
	p.angle = 0.0
	p.rotation.y = 0.0
	game.cam_yaw = 0.0
	game.cam_pos = p.position
	for wid in [["uzi", "axe", "knife"], ["rifle", "knife", "axe"]]:
		for e in game.enemies:
			e.queue_free()
		game.enemies.clear()
		var sq := {"members": [], "anchor": p.position, "mode": "hold", "t": 999.0}
		for i in 3:
			var h := Human.new()
			game.level_root.add_child(h)
			# стоят чуть дальше героя (от камеры) и светят в стороны — пока не видят его
			var off := Vector3((i - 1) * 2.2, 0, -3.5 - absf(i - 1) * 0.8)
			var cell: Vector2i = game.L.nearest_walkable(floori(p.px() + off.x), floori(p.pz() + off.z), 3)
			h.setup_human(game, game.L, Vector3(cell.x + 0.5, 0, cell.y + 0.5), PI + (i - 1) * 1.2, wid[i], sq, "guard")
			game.enemies.append(h)
		await _frames(20)
		_shot(dir, "humans_" + wid[0], "calm")
		for h in game.enemies:
			h.foe = p
			h.alert()
		await _frames(18)
		_shot(dir, "humans_" + wid[0], "fight")
	game.get_tree().quit()


## Силуэты за стенами: один зомби охотится (красный), один спокойный рядом (оранжевый), один далеко (не виден).
func run_silhouette(g: Node, dir: String) -> void:
	game = g
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	var L: OfficeLevel = game.L
	var shots := 0
	var last := Vector2(-99, -99)
	for z in range(3, L.H - 3):
		for x in range(3, L.W - 3):
			if shots >= 2 or not L.walkable(x, z) or Vector2(x, z).distance_to(last) < 12.0: continue
			p.position = Vector3(x + 0.5, 0, z + 0.5)
			game.cam_yaw = 0.0
			game._place_camera(p.position, 0.0, game.CAM_DIST, 0.0, true)
			var cam: Vector3 = game.camera.global_position
			# ищем 2 клетки в 2.5–6 м за стеной от камеры
			var found: Array = []
			for dz in range(-6, 7):
				for dx in range(-6, 7):
					var c := Vector2i(x + dx, z + dz)
					var d := Vector2(dx, dz).length()
					if d < 2.5 or d > 6.0 or not L.walkable(c.x, c.y): continue
					if game._wall_between(Vector3(c.x + 0.5, 1.0, c.y + 0.5), cam):
						found.append(c)
			if found.size() < 2: continue
			game._add_enemy("zombie", Vector3(found[0].x + 0.5, 0, found[0].y + 0.5), 0.0, false)
			game._add_enemy("woman", Vector3(found[-1].x + 0.5, 0, found[-1].y + 0.5), 0.0, false)
			var hunter: Enemy = game.enemies[0]
			hunter.foe = p
			hunter.alert()
			await _frames(15)
			_shot(dir, "silhouette", str(shots))
			for e in game.enemies:
				e.queue_free()
			game.enemies.clear()
			shots += 1
			last = Vector2(x, z)
	game.get_tree().quit()


## 0.7: удушение, растерянность «!», охотник крадётся к зомби со спины.
func run_07(g: Node, dir: String) -> void:
	game = g
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	var big: Dictionary = {}
	for r in game.L.rooms:
		if not r.corridor and (big.is_empty() or r.area > big.area):
			big = r
	var c0: Vector2i = game.L.nearest_walkable((big.x0 + big.x1) / 2, (big.z0 + big.z1) / 2, 4)
	p.position = Vector3(c0.x + 0.5, 0, c0.y + 0.5)
	p.angle = 0.0
	p.rotation.y = 0.0
	game.cam_pos = p.position
	game.cam_yaw = PI * 0.75
	game.cam_dist = 5.5
	p.invuln = 0.0
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	var sq := {"members": [], "phase": "settled", "dest": p.position}
	# удушение
	var h := Human.new()
	game.level_root.add_child(h)
	h.setup_human(game, game.L, p.position + Vector3(0, 0, 1.0), 0.0, "axe", sq, "guard")
	game.enemies.append(h)
	h.state = Enemy.S.GUARD
	await _frames(3)
	p.cd = 0.0
	p.selected = ""
	p.melee()
	await _frames(15)
	_shot(dir, "07", "choke")
	await _frames(25)
	_shot(dir, "07", "choked_down")
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	# растерянность: человек лицом к герою в 4 м
	var h2 := Human.new()
	game.level_root.add_child(h2)
	h2.setup_human(game, game.L, p.position + Vector3(0, 0, 4.0), PI, "knife", sq, "guard")
	game.enemies.append(h2)
	for i in 30:
		await _frames(1)
		if h2.state == Enemy.S.STARTLED:
			await _frames(4)
			break
	_shot(dir, "07", "startled")
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	# охота: зомби стоит спиной, охотник крадётся сзади (герой «вне игры»)
	p.frozen = true
	game._add_enemy("zombie", p.position + Vector3(0, 0, 3.0), 0.0, false)
	var z: Enemy = game.enemies[0]
	z.state = Enemy.S.LOOK
	z.t = 99.0
	z.look_base = 0.0
	var h3 := Human.new()
	game.level_root.add_child(h3)
	h3.setup_human(game, game.L, p.position + Vector3(0.6, 0, 0.3), 0.0, "knife", sq, "hunt")
	game.enemies.append(h3)
	h3.stalk = z
	h3.state = Enemy.S.STALK
	h3.t = 0.0
	await _frames(25)
	_shot(dir, "07", "stalk")
	game.get_tree().quit()


## 0.8: отдых (сидит раненый — перевязывается, прислонился с узи за спиной, стоит), крадётся с опущенным
## фонарём, вскакивает и выхватывает оружие.
func run_08(g: Node, dir: String) -> void:
	game = g
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.frozen = true
	var big: Dictionary = {}
	for r in game.L.rooms:
		if not r.corridor and (big.is_empty() or r.area > big.area):
			big = r
	var c0: Vector2i = game.L.nearest_walkable((big.x0 + big.x1) / 2, (big.z0 + big.z1) / 2, 4)
	var ctr := Vector3(c0.x + 0.5, 0, c0.y + 0.5)
	p.position = ctr
	p.angle = 0.0
	p.rotation.y = 0.0
	game.cam_pos = p.position
	game.cam_yaw = 0.0
	game.cam_dist = 7.0
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	var sq := {"members": [], "phase": "rest", "dest": ctr, "room": big}
	var hs: Array = []
	var kinds := [["axe", "sit"], ["uzi", "lean"], ["knife", "stand"]]
	for i in 3:
		var h := Human.new()
		game.level_root.add_child(h)
		h.setup_human(game, game.L, ctr + Vector3((i - 1) * 1.8, 0, 2.2), 0.0, kinds[i][0], sq, "rest")
		game.enemies.append(h)
		h._enter_rest()
		h.rest_kind = kinds[i][1]
		h.angle = 0.0
		h.rotation.y = 0.0
		hs.append(h)
	hs[0].hp = 60.0   # ранен — перевязывается
	await game.get_tree().create_timer(0.6).timeout
	_shot(dir, "08", "rest")
	# вскакивает и выхватывает оружие (середина растерянности)
	hs[0].foe = p
	hs[0].alert()
	await game.get_tree().create_timer(0.5).timeout
	_shot(dir, "08", "draw")
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	# крадётся к зомби (фонарь опущен)
	game._add_enemy("zombie", ctr + Vector3(0, 0, 3.0), 0.0, false)
	var z: Enemy = game.enemies[0]
	z.state = Enemy.S.LOOK
	z.t = 99.0
	z.look_base = 0.0
	var hk := Human.new()
	game.level_root.add_child(hk)
	hk.setup_human(game, game.L, ctr + Vector3(0.6, 0, 1.2), 0.0, "knife", sq, "hunt")
	game.enemies.append(hk)
	hk.stalk = z
	hk.state = Enemy.S.STALK
	hk.t = 0.0
	await game.get_tree().create_timer(0.8).timeout
	_shot(dir, "08", "stalk")
	game.get_tree().quit()


## Насколько камере вокруг точки ничего не мешает: клетки без стен/шкафов в радиусе 6 + свет.
func _cam_score(L: OfficeLevel, x: int, z: int) -> float:
	var s := 0.0
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			var c := L.cell(x + dx, z + dz)
			if c != OfficeLevel.WALL and c != OfficeLevel.TALL:
				s += 1.0
	return s + 30.0 * L.visibility_at(x + 0.5, z + 0.5)


func _cam_spot(L: OfficeLevel) -> Vector3:
	var best := -1.0
	var out := Vector3.ZERO
	for z in range(4, L.H - 4, 2):
		for x in range(4, L.W - 4, 2):
			if not L.walkable(x, z) or not L.walkable(x + 1, z): continue
			var s := _cam_score(L, x, z)
			if s > best:
				best = s
				out = Vector3(x + 0.5, 0, z + 0.5)
	return out


## Настоящая LOW-мебель с проходом напрямик: {"hero","land","ang"} (n — 1 или 2 блока); {} — нет.
func _real_low(L: OfficeLevel, n: int) -> Dictionary:
	for z in range(3, L.H - 3):
		for x in range(3, L.W - 3):
			if L.cell(x, z) != OfficeLevel.LOW: continue
			for k in 4:
				var dx: int = OfficeLevel.DX[k]
				var dz: int = OfficeLevel.DZ[k]
				if not L.walkable(x - dx, z - dz) or not L.walkable(x - 2 * dx, z - 2 * dz): continue
				var last := Vector2i(x, z)
				if n == 2:
					if L.cell(x + dx, z + dz) != OfficeLevel.LOW: continue
					last = Vector2i(x + dx, z + dz)
				if L.cell(last.x + dx, last.y + dz) == OfficeLevel.LOW: continue
				if not L.walkable(last.x + dx, last.y + dz) or L.visibility_at(x + 0.5, z + 0.5) < 0.35: continue
				return {"hero": Vector3(x - dx + 0.5 + dx * 0.25, 0, z - dz + 0.5 + dz * 0.25), "far": Vector3(x - 2 * dx + 0.5, 0, z - 2 * dz + 0.5),
					"land": Vector3(last.x + dx + 0.5, 0, last.y + dz + 0.5), "ang": atan2(float(dx), float(dz))}
	return {}


## 0.14: раскадровки — приём сбоку по стоящему зомби, нож по сидящему за ПК сбоку, перелезание через низкий блок
## (тихо и в тревоге), через стол из 2 клеток, бандит перелезает в погоне. Листы anim_v14_*.png.
func run_v014(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 5
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.invuln = 0.0   # неуязвимость мигает — героя не видно на кадрах (hp и так 99999)
	var L: OfficeLevel = game.L
	var ctr := _cam_spot(L)
	_clear_enemies()
	# 1) сбоку по стоящему зомби
	p.position = ctr
	p.angle = PI * 0.5
	p.rotation.y = p.angle
	game.cam_yaw = PI
	game.cam_dist = 4.0
	game._add_enemy("zombie", ctr + Vector3(1.15, 0, 0), 0.0, false)
	var z: Enemy = game.enemies[0]
	for _w in 20:
		z.state = Enemy.S.LOOK
		z.t = 99.0
		z.angle = 0.0
		z.rotation.y = 0.0
		z.look_base = 0.0
		z.model.head.rotation.y = 0.0
		await _frames(1)
	var shots: Array = [_grab()]
	p.cd = 0.0
	p.melee()
	for i in 7:
		await _frames(6)
		shots.append(_grab())
	_sheet(dir, "v14_side_choke", shots)
	print("[v14] сбоку: ", Enemy.S.keys()[z.state])
	_clear_enemies()
	# 2) нож по сидящему за ПК — сбоку
	game._load_floor(5, false)
	await _frames(10)
	game.state = "play"
	p = game.player
	p.hp = 99999.0
	p.invuln = 0.0   # неуязвимость мигает — героя не видно на кадрах (hp и так 99999)
	L = game.L
	var worker: Enemy = null
	var wbest := -1.0
	for e in game.enemies:
		if e.state == Enemy.S.WORK:
			var side: Vector2 = Vector2(e.px(), e.pz()) + Vector2(e.facing().y, -e.facing().x) * 1.0 - e.facing() * 0.4
			if L.walkable(floori(side.x), floori(side.y)):
				var s := _cam_score(L, floori(e.px()), floori(e.pz()))
				if s > wbest:
					wbest = s
					worker = e
					p.position = Vector3(side.x, 0, side.y)
	if worker != null:
		for e in game.enemies:
			if e != worker:
				e.position = Vector3(-50, 0, -50)
				e.state = Enemy.S.KNOCKED
				e.knock_t = 999.0
		p.angle = p.angle_to_point(worker.px(), worker.pz())
		p.rotation.y = p.angle
		p.inv = {}
		p.add_item("knife", 3)
		p.selected = "knife"
		game.cam_yaw = worker.work_ang + PI * 0.75
		game.cam_dist = 4.0
		await _frames(25)
		shots = [_grab()]
		p.cd = 0.0
		p.melee()
		for i in 7:
			await _frames(4)
			shots.append(_grab())
		await _frames(20)
		shots.append(_grab())
		_sheet(dir, "v14_seated_knife", shots)
		print("[v14] сидящий: ", Enemy.S.keys()[worker.state])
	p.inv = {}
	p.selected = ""
	_clear_enemies()
	# 3) перелезание: 1 блок тихо, 1 блок в тревоге, стол из 2 блоков
	for mode in ["quiet", "loud", "two"]:
		var s := _real_low(L, 2 if mode == "two" else 1)
		if s.is_empty():
			print("[v14] нет мебели для ", mode)
			continue
		_clear_enemies()
		p.position = s.hero
		p.angle = s.ang
		p.rotation.y = p.angle
		p.vault_cd = 0.0
		game.cam_yaw = s.ang + PI * 0.5
		game.cam_dist = 4.5
		if mode == "loud":
			game._add_enemy("zombie", s.far, s.ang, false)
			var zl: Enemy = game.enemies[0]
			zl.foe = p
			zl.alert()
		await _frames(15)
		shots = [_grab()]
		p.start_vault()
		var steps := 7
		for i in steps:
			await _frames(3 if mode != "two" else 6)
			shots.append(_grab())
		_sheet(dir, "v14_vault_" + mode, shots)
		print("[v14] перелез (", mode, "): громко=", p.vault_loud)
	# 4) бандит перелезает в погоне
	var sb := _real_low(L, 2)
	if not sb.is_empty():
		_clear_enemies()
		p.position = sb.land + (sb.land - sb.hero).normalized() * 2.0
		var c2 := L.nearest_walkable(floori(p.position.x), floori(p.position.z), 2)
		p.position = Vector3(c2.x + 0.5, 0, c2.y + 0.5)
		var hb := Human.new()
		game.level_root.add_child(hb)
		hb.setup_human(game, L, sb.hero, sb.ang, "knife", {"members": [], "phase": "settled", "dest": sb.hero}, "guard")
		game.enemies.append(hb)
		hb.foe = p
		hb._instant_alert = true
		hb.alert()
		hb._instant_alert = false
		game.cam_yaw = sb.ang + PI * 0.5
		game.cam_dist = 5.5
		shots = []
		for i in 8:
			await _frames(5)
			shots.append(_grab())
		_sheet(dir, "v14_bandit_vault", shots)
		print("[v14] бандит перелез: ", game.npc_stats.bandit_vaults)
	game.get_tree().quit()


## 0.13: герой замер вприсядку на открытом в ~6 м перед зомби — «?», зомби идёт к тому месту,
## вблизи — тревога. Лист anim_glimpse.png (кадр каждые ~0.6 с).
func run_glimpse(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 3
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.invuln = 9999.0
	_clear_enemies()
	var L: OfficeLevel = game.L
	# прямая 7 клеток без мебели, светло
	var spot := {}
	var best := -1.0
	for z in range(2, L.H - 2):
		for x in range(2, L.W - 2):
			for k in 4:
				var dx: int = OfficeLevel.DX[k]
				var dz: int = OfficeLevel.DZ[k]
				if not L.walkable(x + 7 * dx, z + 7 * dz) or L.line_blocked(x + 0.5, z + 0.5, x + 7 * dx + 0.5, z + 7 * dz + 0.5, 2):
					continue
				var v := L.visibility_at(x + 0.5, z + 0.5)
				if v > best:
					best = v
					spot = {"hero": Vector3(x + 0.5, 0, z + 0.5), "zombie": Vector3(x + 6 * dx + 0.5, 0, z + 6 * dz + 0.5),
						"ang": atan2(-dx, -dz), "yaw": atan2(dz, -dx) + PI * 0.5}
	p.position = spot.hero
	p.crouch = true
	game.cam_yaw = spot.yaw
	game.cam_dist = 7.5
	game._add_enemy("zombie", spot.zombie, spot.ang, false)
	var z: Enemy = game.enemies[0]
	z.attn = 1.0
	z.state = Enemy.S.LOOK
	z.t = 99.0
	z.look_base = spot.ang
	await _frames(10)
	var shots: Array = []
	for i in 12:
		for _f in 18:
			await _frames(1)
		shots.append(_grab())
	_sheet(dir, "glimpse", shots)
	print("[glimpse] состояние зомби ", Enemy.S.keys()[z.state], " d=%.1f" % z.dist_to(p))
	game.get_tree().quit()


## 0.13: присевший герой за фикусом (зомби в 2 м замечает — «?»/«!») и за столом (не замечает).
## pose_cover_plant.png / pose_cover_desk.png
func run_cover(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 11
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.invuln = 9999.0
	var L: OfficeLevel = game.L
	for kind in [OfficeLevel.PROP, OfficeLevel.LOW]:
		_clear_enemies()
		var spot := {}
		for z in range(3, L.H - 3):
			for x in range(3, L.W - 3):
				if not spot.is_empty() or L.cell(x, z) != kind: continue
				# за столом зомби ставим через клетку: вплотную к столу он смотрит поверх (так и задумано)
				var far := 1 if kind == OfficeLevel.PROP else 2
				for k in 4:
					var dx: int = OfficeLevel.DX[k]
					var dz: int = OfficeLevel.DZ[k]
					if L.walkable(x - dx, z - dz) and L.walkable(x + dx, z + dz) and L.walkable(x + far * dx, z + far * dz) \
							and L.visibility_at(x + 0.5, z + 0.5) > 0.4:
						spot = {"hero": Vector3(x - dx + 0.5, 0, z - dz + 0.5), "zombie": Vector3(x + far * dx + 0.5, 0, z + far * dz + 0.5),
							"ang": atan2(-dx, -dz), "yaw": atan2(dz, -dx)}
						break
		if spot.is_empty():
			continue
		p.position = spot.hero
		p.crouch = true
		p.angle = spot.ang + PI
		p.rotation.y = p.angle
		game.cam_yaw = spot.yaw + (PI * 0.5 if kind == OfficeLevel.PROP else 0.0)
		game.cam_dist = 5.0
		game._add_enemy("zombie", spot.zombie, spot.ang, false)
		var z: Enemy = game.enemies[0]
		z.attn = 1.0
		for _f in 45:
			if z.state == Enemy.S.LOOK or z.state == Enemy.S.WANDER:
				z.state = Enemy.S.LOOK
				z.t = 99.0
				z.angle = spot.ang
				z.rotation.y = spot.ang
			await _frames(1)
		_shot(dir, "cover", "plant" if kind == OfficeLevel.PROP else "desk")
		print("[cover] ", "фикус" if kind == OfficeLevel.PROP else "стол", ": подозрение %.2f, состояние %s" % [z.susp, Enemy.S.keys()[z.state]])
	game.get_tree().quit()


## 0.15: стычка — два бандита (нож, узи) и два офисника (труба, револьвер) замечают друг друга.
## anim_office_war.png (кадр каждые ~0.4 с).
func run_office_war(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 5
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	_clear_enemies()
	var L: OfficeLevel = game.L
	var ctr := _cam_spot(L)
	p.position = ctr
	p.visible = false
	p.frozen = true
	game.cam_yaw = 0.0
	game.cam_dist = 7.0
	var mk := func(fac: String, wid: String, pos: Vector3, ang: float) -> Human:
		var h := Human.new()
		game.level_root.add_child(h)
		var c := L.nearest_walkable(floori(pos.x), floori(pos.z), 2)
		h.setup_human(game, L, Vector3(c.x + 0.5, 0, c.y + 0.5), ang, wid, {"members": [], "dest": pos, "fac": fac}, "guard", fac)
		game.enemies.append(h)
		h.state = Enemy.S.GUARD
		h.look_base = ang
		return h
	mk.call("human", "knife", ctr + Vector3(-2.6, 0, 0.5), PI * 0.5)
	mk.call("human", "uzi", ctr + Vector3(-3.4, 0, -0.5), PI * 0.5)
	mk.call("office", "pipe", ctr + Vector3(2.6, 0, 0.5), -PI * 0.5)
	mk.call("office", "revolver", ctr + Vector3(3.4, 0, -0.5), -PI * 0.5)
	var shots: Array = []
	for i in 12:
		await _frames(12)
		shots.append(_grab())
	_sheet(dir, "office_war", shots)
	print("[officewar] война: ", game.faction_war_on, " живы: ", game.enemies.filter(func(e): return not e.is_dead()).map(func(e): return e.faction))
	game.get_tree().quit()


## 0.15 (только вид): офисники — без оружия, с револьвером, гвоздомётом, арбалетом; спокойно и на прицеле.
## pose_office_calm.png / pose_office_aim.png / pose_office_close.png (крупно один).
func run_office(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 5
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	_clear_enemies()
	var L: OfficeLevel = game.L
	var ctr := _cam_spot(L)
	p.position = ctr   # камера следует за (невидимым) героем — он в центре группы
	p.visible = false
	p.frozen = true
	var ids := ["", "revolver", "nailgun", "crossbow"]
	var models: Array = []
	for i in ids.size():
		var m := CharModel.new()
		m.setup("office")
		game.level_root.add_child(m)
		m.position = ctr + Vector3((i - 1.5) * 1.1, 0, 0)
		m.rotation.y = PI   # лицом к камере (камера со стороны −Z)
		m.set_light(Color(0.9, 0.88, 0.85))
		models.append(m)
	game.cam_yaw = PI
	game.cam_dist = 4.2
	for mode in ["calm", "aim"]:
		for k in 20:
			for i in ids.size():
				var m: CharModel = models[i]
				var id: String = ids[i]
				var pose := {"arm_l": -0.1, "arm_r": -0.1, "head_yaw": sin(k * 0.1 + i) * 0.1}
				var aim := 1.0 if mode == "aim" else 0.0
				if id != "":
					CharModel.pose_held(pose, id, aim, 0.0, 0.0)
				elif mode == "aim":
					pose = {"arm_l": -1.4, "arm_r": -1.7, "out_l": -0.3, "out_r": -0.2, "lean": 0.1}   # кулаки наготове
				m.apply_pose(pose)
				m.place_held(id, aim, 0.0, false, false)
			await _frames(1)
		_shot(dir, "office", mode)
	# крупно: офисник с арбалетом вполоборота
	for i in ids.size():
		(models[i] as Node3D).visible = i == 3
	var mc: CharModel = models[3]
	mc.rotation.y = PI * 0.75
	game.cam_dist = 2.6
	p.position = mc.position
	await _frames(20)
	_shot(dir, "office", "close")
	print("[office] готово")
	game.get_tree().quit()


## 0.14.2: экран с кнопками «ПЕРЕЛЕЗТЬ» и «ЗАМЕНИТЬ» одновременно — pose_vault_hud.png.
func run_vault_hud(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 5
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	_clear_enemies()
	var s := _real_low(game.L, 1)
	p.position = s.hero
	p.angle = s.ang
	p.rotation.y = p.angle
	p.inv = {}
	p.add_item("bottle", 3)
	game._add_pickup("brick", 2, s.hero + Vector3(0.2, 0, 0), true)
	game.cam_yaw = s.ang + PI
	game.cam_dist = 4.5
	await _frames(25)
	p.angle = s.ang
	p.rotation.y = p.angle
	# 0.16.1: захваченная цель — видна кнопка «СНЯТЬ ЦЕЛЬ»
	game._add_enemy("zombie", p.position + Vector3(sin(s.ang), 0, cos(s.ang)) * -5.0, 0.0, false)
	p.lock = game.enemies[-1]
	game.hud._layout()
	await _frames(3)
	_shot(dir, "vault", "hud")
	print("[vaulthud] перелезть: ", not p.vault_target().is_empty(), " заменить: ", not game.swap_pk.is_empty())
	game.get_tree().quit()


## 0.13: экран с кнопкой «Заменить» (бутылки в слоте, рядом лежит кирпич) — pose_slots_hud.png.
func run_slots(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 7
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.frozen = false
	_clear_enemies()
	var ctr := _bright_spot(game.L)
	p.position = ctr
	p.inv = {}
	p.add_item("bottle", 3)
	p.add_item("pistol", 4)
	p.add_item("knife", 2)
	p.add_item("coffee", 1)
	game._add_pickup("brick", 2, ctr + Vector3(0.3, 0, 0.2), true)
	game.cam_dist = 4.0
	await _frames(30)
	game.hud._layout()
	await _frames(5)
	_shot(dir, "slots", "hud")
	print("[slots] кнопка: ", not game.swap_pk.is_empty())
	game.get_tree().quit()


## Светлое просторное место на этаже (для раскадровок).
func _bright_spot(L: OfficeLevel) -> Vector3:
	var ctr := Vector3.ZERO
	var best := -1.0
	for z0 in range(5, L.H - 5):
		for x0 in range(5, L.W - 5):
			if not L.walkable(x0, z0): continue
			var score := 0.0
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					if L.walkable(x0 + dx, z0 + dz): score += 1.0
			score += 25.0 * L.visibility_at(x0 + 0.5, z0 + 0.5)
			if score > best:
				best = score
				ctr = Vector3(x0 + 0.5, 0, z0 + 0.5)
	return ctr


func _clear_enemies() -> void:
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	game.squads.clear()


## 0.12: раскадровки приёмов — удушение зомби насмерть (держит кнопку), нож со спины по бандиту,
## тревога зомби с подмогой (1–3), окружение бандитами после выстрела. Листы anim_v12_*.png.
func run_v012(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 7
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.invuln = 9999.0
	var L: OfficeLevel = game.L
	var ctr := _bright_spot(L)
	_clear_enemies()
	# A) удушение зомби, кнопку держат — насмерть
	p.position = ctr
	p.angle = 0.0
	p.rotation.y = 0.0
	game.cam_yaw = PI * 0.5
	game.cam_dist = 3.6
	game._add_enemy("zombie", ctr + Vector3(0, 0, 1.25), 0.0, false)
	var z: Enemy = game.enemies[0]
	for _w in 30:
		z.state = Enemy.S.LOOK
		z.t = 99.0
		z.angle = 0.0
		z.rotation.y = 0.0
		await _frames(1)
	var shots: Array = [_grab()]
	p.cd = 0.0
	p.melee_hold = true
	p.melee()
	for i in 11:
		await _frames(9)
		shots.append(_grab())
	p.melee_hold = false
	_sheet(dir, "v12_choke_kill", shots)
	print("[v12] удушение насмерть: зомби мёртв=", z.is_dead())
	_clear_enemies()
	await _frames(5)
	# B) нож со спины по бандиту — быстрое убийство
	p.position = ctr
	p.inv = {}
	p.add_item("knife", 3)
	p.selected = "knife"
	var sq := {"members": [], "phase": "settled", "dest": ctr}
	var h := Human.new()
	game.level_root.add_child(h)
	h.setup_human(game, L, ctr + Vector3(0, 0, 1.25), 0.0, "axe", sq, "guard")
	game.enemies.append(h)
	for _w in 25:
		h.state = Enemy.S.GUARD
		h.angle = 0.0
		h.rotation.y = 0.0
		h.t = 0.0
		await _frames(1)
	shots = [_grab()]
	p.cd = 0.0
	p.melee()
	for i in 7:
		await _frames(3)
		shots.append(_grab())
	_sheet(dir, "v12_knife_takedown", shots)
	print("[v12] нож со спины: бандит мёртв=", h.is_dead())
	p.inv = {}
	p.selected = ""
	_clear_enemies()
	await _frames(5)
	# C) тревога: зомби замечает героя и зовёт 1–3 ближних, остальные остаются
	p.position = ctr
	game.cam_dist = 8.0
	game.cam_yaw = PI * 0.25
	game._add_enemy("zombie", ctr + Vector3(0, 0, 3.5), PI, false)
	var a: Enemy = game.enemies[0]
	for k in 5:
		var off := Vector3(cos(k * 1.25) * 3.0, 0, 3.5 + sin(k * 1.25) * 3.0)
		var c := L.nearest_walkable(floori(ctr.x + off.x), floori(ctr.z + off.z), 2)
		if c.x >= 0:
			game._add_enemy("zombie", Vector3(c.x + 0.5, 0, c.y + 0.5), randf() * TAU, false)
	await _frames(5)
	shots = [_grab()]
	a.foe = p
	a.alert()
	for i in 7:
		await _frames(12)
		shots.append(_grab())
	_sheet(dir, "v12_zombie_alarm", shots)
	print("[v12] тревога: пришло на помощь ", game.npc_stats.zombie_helpers)
	_clear_enemies()
	await _frames(5)
	# D) выстрел рядом с отрядом: пара в лоб, вторая обходит, стрелок разворачивается
	p.position = ctr
	game.cam_dist = 9.0
	game.cam_yaw = PI * 0.5
	var sq2 := {"members": [], "leader": null, "phase": "settled", "dest": ctr, "pairs": [], "t": 99.0,
		"wary": false, "main": true, "plan": "pairs"}
	var ws := ["knife", "knife", "axe", "uzi"]
	for i in 4:
		var hb := Human.new()
		game.level_root.add_child(hb)
		var c2 := L.nearest_walkable(floori(ctr.x + (i % 2) * 1.2 - 0.6), floori(ctr.z + 6.0 + (i / 2) * 1.0), 3)
		hb.setup_human(game, L, Vector3(c2.x + 0.5, 0, c2.y + 0.5), 0.0, ws[i], sq2, "hunt" if i % 2 == 0 else "follow")
		hb.pair_i = i / 2
		game.enemies.append(hb)
		sq2.members.append(hb)
	sq2.leader = sq2.members[0]
	sq2.pairs = [[sq2.members[0], sq2.members[1]], [sq2.members[2], sq2.members[3]]]
	game.squads.append(sq2)
	await _frames(10)
	shots = [_grab()]
	game.emit_noise(p.position, 14.0, "gun", true)
	for i in 7:
		await _frames(15)
		shots.append(_grab())
	_sheet(dir, "v12_bandits_locate", shots)
	print("[v12] окружение: бандиты в бою ", sq2.members.filter(func(m): return m.is_hostile()).size(), "/4")
	game.get_tree().quit()


## Щелкун крупно: с четырёх сторон, рывок на звук, хватает бандита, ест. Лист anim_clicker.png.
func run_clicker(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 7
	game._load_floor(5, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.frozen = true
	p.visible = false
	var L: OfficeLevel = game.L
	# светлое просторное место
	var ctr := Vector3.ZERO
	var best := -1.0
	for z0 in range(4, L.H - 4):
		for x0 in range(4, L.W - 4):
			if not L.walkable(x0, z0): continue
			var score := 0.0
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if L.walkable(x0 + dx, z0 + dz): score += 1.0
			score += 20.0 * L.visibility_at(x0 + 0.5, z0 + 0.5)
			if score > best:
				best = score
				ctr = Vector3(x0 + 0.5, 0, z0 + 0.5)
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	p.position = ctr + Vector3(0.8, 0, 0)
	game.cam_dist = 3.2
	var c := Clicker.new()
	game.level_root.add_child(c)
	c.setup_clicker(game, L, ctr, 0.0)
	game.enemies.append(c)
	var shots: Array = []
	# 1) стоит, слушает — с четырёх сторон
	for k in 4:
		game.cam_yaw = k * PI * 0.5 + 0.4
		for _f in 25:
			c.state = Enemy.S.LOOK
			c.t = 99.0
			c.angle = 0.0
			c.rotation.y = 0.0
			await _frames(1)
		shots.append(_grab())
	# 2) щёлкает (волна) и рывок на звук
	game.cam_yaw = 0.9
	game.clicker_click(c)
	await _frames(4)
	shots.append(_grab())
	game.emit_noise(ctr + Vector3(0, 0, 3.0), 6.0, "distract", true)
	for k in 2:
		for _f in 12:
			p.position = c.position + Vector3(0.8, 0, 0)   # камера едет за щелкуном
			await _frames(1)
		shots.append(_grab())
	# 3) хватает бандита, ест (обратно на светлое место)
	c.position = ctr
	c.state = Enemy.S.LOOK
	c.t = 99.0
	var sq := {"members": [], "phase": "settled", "dest": ctr}
	var h := Human.new()
	game.level_root.add_child(h)
	h.setup_human(game, L, ctr + Vector3(0, 0, 1.0), PI, "knife", sq, "guard")
	game.enemies.append(h)
	h.state = Enemy.S.GUARD
	p.position = ctr + Vector3(0.8, 0, 0)
	game.cam_yaw = PI * 0.5 + 0.3
	await _frames(15)
	c._start_grab(h)
	for i in 3:
		await _frames(10)
		shots.append(_grab())
	for _w in 40:
		await _frames(1)
		if c.state == Enemy.S.FEED:
			break
	await _frames(20)
	shots.append(_grab())
	_sheet(dir, "clicker", shots)
	print("[clicker] кадров ", shots.size(), " состояние ", Enemy.S.keys()[c.state])
	game.get_tree().quit()


## Раскадровки: герой душит бандита; бандит тихо режет зомби (подход, рывок, удар).
## Кадры — каждые step кадров, склеиваются в лист anim_<tag>.png (4 в ряд, центр экрана).
func run_anim(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 2026
	game._load_floor(4, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	# открытое место: полоса вдоль z (−2…+4 клетки) без стен — для подхода; по бокам — чем свободнее, тем лучше
	var L: OfficeLevel = game.L
	var ctr := Vector3.ZERO
	var best := -1
	for z0 in range(3, L.H - 5):
		for x0 in range(2, L.W - 2):
			var ok := true
			for dz in range(-2, 5):
				if not L.walkable(x0, z0 + dz): ok = false
			if not ok: continue
			var score := 0
			for dz in range(-5, 8):
				for dx in range(-5, 6):
					if L.walkable(x0 + dx, z0 + dz): score += 1
			if score > best:
				best = score
				ctr = Vector3(x0 + 0.5, 0, z0 + 0.5)
	print("[anim] место ", ctr, " свободно ", best, "/143")
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	var sq := {"members": [], "phase": "settled", "dest": ctr}
	# 1) удушение: бандит стоит спиной к герою
	p.position = ctr - Vector3(0, 0, 1.2)   # пока камера наезжает — дальше 1.5 м (вплотную бандит чует)
	p.angle = 0.0
	p.rotation.y = 0.0
	game.cam_yaw = PI * 0.5
	game.cam_dist = 4.0
	var h := Human.new()
	game.level_root.add_child(h)
	h.setup_human(game, game.L, ctr + Vector3(0, 0, 0.9), 0.0, "axe", sq, "guard")
	game.enemies.append(h)
	h.state = Enemy.S.GUARD
	h.look_base = 0.0
	h.t = 0.0
	for _w in 40:
		h.angle = 0.0
		h.rotation.y = 0.0
		h.t = 0.0
		await _frames(1)
	p.position = ctr
	await _frames(1)
	var shots: Array = []
	shots.append(_grab())
	p.cd = 0.0
	p.selected = ""
	p.melee()
	for i in 11:
		await _frames(5)
		shots.append(_grab())
	_sheet(dir, "choke", shots)
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	await _frames(5)
	# 2) тихое убийство: зомби стоит спиной, бандит с ножом крадётся сзади и режет (герой в стороне, не мешает)
	p.frozen = true
	p.position = ctr + Vector3(0.9, 0, 1.0)
	p.visible = false
	game.cam_yaw = PI * 0.5
	game.cam_dist = 4.5
	game._add_enemy("zombie", ctr + Vector3(0, 0, 3.0), 0.0, false)
	var z: Enemy = game.enemies[0]
	z.state = Enemy.S.LOOK
	z.t = 99.0
	z.look_base = 0.0
	var hk := Human.new()
	game.level_root.add_child(hk)
	hk.setup_human(game, game.L, ctr + Vector3(0, 0, -1.5), 0.0, "knife", sq, "hunt")
	game.enemies.append(hk)
	hk.stalk = z
	hk.state = Enemy.S.STALK
	hk.t = 0.0
	shots = []
	var after := -1
	for i in 40:
		for _f in 4:
			if z.state == Enemy.S.LOOK:
				z.t = 99.0
				z.angle = 0.0
				z.rotation.y = 0.0
				z.model.head.rotation.y = 0.0
			await _frames(1)
		shots.append(_grab())
		if z.is_dead() and after < 0:
			after = i
		if after >= 0 and i - after >= 4:
			break
	# оставим 12 кадров: последние (подход → рывок → удар → падение)
	_sheet(dir, "stealth_kill", shots.slice(maxi(0, shots.size() - 12)))
	print("[anim] зомби убит: ", z.is_dead(), " бандит ", Enemy.S.keys()[hk.state], " зомби ", Enemy.S.keys()[z.state], " угол зомби ", z.angle, " dbg ", Human.dbg)
	game.get_tree().quit()


func _grab() -> Image:
	var img: Image = game.get_viewport().get_texture().get_image()
	var w := img.get_width()
	var hh := img.get_height()
	var cw := mini(w, hh * 4 / 3)
	var cut := img.get_region(Rect2i((w - cw) / 2, 0, cw, hh))
	cut.resize(400, 300, Image.INTERPOLATE_NEAREST)
	return cut


func _sheet(dir: String, tag: String, shots: Array) -> void:
	var cols := 4
	var rows := (shots.size() + cols - 1) / cols
	var sheet := Image.create(cols * 404, rows * 304, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(im, Rect2i(0, 0, 400, 300), Vector2i((i % cols) * 404 + 2, (i / cols) * 304 + 2))
	sheet.save_png("%s/anim_%s.png" % [dir, tag])


## Главное меню с «Играть с этажа…» и экран выбора этажа (max_reached подставляем).
func run_menu(g: Node, dir: String, mx: int) -> void:
	game = g
	game.max_reached = mx
	game._go_title()
	await _frames(30)
	_shot(dir, "menu", "title")
	game.cheat_kind = "lair"   # 0.18.2: с --cheatmenu виден выбор типа этажа
	game.on_button("floors", true)
	await _frames(10)
	_shot(dir, "menu", "floors")
	game.get_tree().quit()


func _shot(dir: String, id: String, tag: String) -> void:
	var img: Image = game.get_viewport().get_texture().get_image()
	img.save_png("%s/pose_%s_%s.png" % [dir, id, tag])


func _frames(n: int) -> void:
	for i in n:
		await game.get_tree().process_frame


## 0.16: логово бандитов — общий вид, костёр, «у стены», хозяин ключ-карты со спины, охранник у комнаты с маскировкой,
## герой в куртке бандита среди своих. Бандиты живут 60 с, герой «в маскировке» (его не трогают), камера — к каждому.
## anim_lair.png (лист) + pose_lair_<что>.png (крупно).
func run_lair(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 7
	game.floor_num = 5
	game._load_floor(5, false, "lair")
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.disguised = true          # для съёмки: бандиты свои, никто не дёргается
	p.visible = false
	p.frozen = true
	var L: OfficeLevel = game.L
	for _s in 60 * 30:
		game._update_world(1.0 / 30.0, false)
	var shots: Array = []
	var look := func(pos: Vector3, yaw: float, dist: float, tag: String) -> void:
		p.position = pos
		game.cam_yaw = yaw
		game.cam_dist = dist
		game.cam_pos = pos
		game.state = "play"   # окно теряет фокус — игра встаёт на паузу; для съёмки не нужно
		for _w in 25:
			game.state = "play"
			await _frames(1)
		shots.append(_grab())
		var img: Image = game.get_viewport().get_texture().get_image()
		img.save_png("%s/pose_lair_%s.png" % [dir, tag])
	var hs: Array = game.enemies.filter(func(e): return e is Human and not e.is_dead())
	var by := func(kind: String) -> Human:
		for h: Human in hs:
			if h.state == Enemy.S.REST and h.rest_kind == kind:
				return h
		return null
	# общий вид: комната с первой бочкой
	var f0: Dictionary = L.fires[0]
	await look.call(Vector3(f0.x + 0.5, 0, f0.z + 0.5), 0.0, 9.0, "room")
	# опенспейс — разбитые столы, граффити
	for r in L.rooms:
		if r.type == "openspace":
			var oc := L.nearest_walkable((r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2, 4)
			await look.call(Vector3(oc.x + 0.5, 0, oc.y + 0.5), 0.6, 9.0, "openspace")
			break
	var fh: Human = by.call("fire")
	if fh != null:
		await look.call(fh.position, fh.angle - PI * 0.6, 4.5, "fire")
	if by.call("pee") == null:
		# за минуту никто не пошёл «к стене» — ставим одного (для кадра)
		for h: Human in hs:
			if h.role == "lair" and h != game.key_holder and h != by.call("fire"):
				var w := Vector2i(-1, -1)
				for _k in 20:
					if w.x < 0: w = h._wall_spot()
				if w.x >= 0:
					h.position = Vector3(w.x + 0.5, 0, w.y + 0.5)
					h.goal_kind = "lair_pee"
					h._lair_arrive()
					break
	var ph: Human = by.call("pee")
	if ph != null:
		await look.call(ph.position, ph.angle + PI, 5.5, "pee")
	if game.key_holder != null:
		var kh: Human = game.key_holder
		# для кадра — в комнату с бочкой, на открытое место, спиной к камере
		var kc := L.nearest_walkable(f0.x + 2, f0.z, 3)
		kh.position = Vector3(kc.x + 0.5, 0, kc.y + 0.5)
		kh._enter_rest()
		kh.rest_kind = "fire"   # стоит неподвижно (поза у костра)
		kh.rest_len = 999.0
		kh.angle = 0.0
		kh.look_base = 0.0
		kh.rotation.y = 0.0
		await look.call(kh.position, PI, 4.5, "keycard")   # камера — в стороне yaw от цели: PI — за спиной у смотрящего на 0
	var guard: Human = null
	for h: Human in hs:
		if h.has_post:
			guard = h
	if guard != null:
		await look.call(guard.position.lerp(L.loot.pos, 0.5), guard.post_ang, 7.0, "guard")
	# герой в куртке бандита рядом с костром
	p.visible = true
	p.set_look("human")
	var spot: Vector3 = Vector3(f0.x + 0.5, 0, f0.z + 2.0)
	var c := L.nearest_walkable(floori(spot.x), floori(spot.z), 3)
	await look.call(Vector3(c.x + 0.5, 0, c.y + 0.5), PI, 4.0, "disguise")
	_sheet(dir, "lair", shots)
	print("[lair] бандитов %d, бочек %d, у костра %s, у стены %s, ключ у %s, охранник %s" % [hs.size(), L.fires.size(),
		fh != null, ph != null, game.key_holder != null, guard != null])
	print("[lair] занятия: ", hs.map(func(h): return "%s:%s/%s" % [h.role, Enemy.S.keys()[h.state], h.rest_kind if h.state == Enemy.S.REST else h.goal_kind]))
	game.get_tree().quit()


## 0.17: укреплённый офис — баррикады в коридоре, двое болтают, слушатель радио, охранник у комнаты с пакетами,
## кража пакетов на глазах (гонит взашей), герой в пакетах. anim_fort.png + pose_fort_<что>.png.
func run_fort(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 11
	game.floor_num = 10
	game._load_floor(10, false, "fort")
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.visible = false
	p.frozen = true
	var L: OfficeLevel = game.L
	var far := Vector3(-60, 0, -60)
	p.position = far
	for _s in 40 * 30:
		game._update_world(1.0 / 30.0, false)
	var shots: Array = []
	var look := func(pos: Vector3, yaw: float, dist: float, tag: String) -> void:
		p.position = pos
		game.cam_yaw = yaw
		game.cam_dist = dist
		game.cam_pos = pos
		for _w in 25:
			game.state = "play"
			await _frames(1)
		shots.append(_grab())
		var img: Image = game.get_viewport().get_texture().get_image()
		img.save_png("%s/pose_fort_%s.png" % [dir, tag])
	var hs: Array = game.enemies.filter(func(e): return e is Human)
	for r in L.rooms:
		if r.corridor and r.area > 30:
			var c := L.nearest_walkable((r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2, 4)
			await look.call(Vector3(c.x + 0.5, 0, c.y + 0.5), 0.6, 9.0, "corridor")
			break
	var mid: Vector3 = (L.talk.a + L.talk.b) * 0.5
	await look.call(mid, L.talk.ang_a + PI * 0.5, 4.5, "talk")
	await look.call(L.radio.pos, L.radio.ang + PI * 0.8, 4.0, "radio")
	var guard: Human = null
	for h: Human in hs:
		if h.role == "guard": guard = h
	await look.call(L.loot.guard.lerp(L.loot.pos, 0.5), L.loot.guard_ang, 7.0, "guard")
	# кража на глазах у охранника: герой у пакетов, охранник смотрит на него
	p.visible = true
	p.frozen = false
	p.invuln = 0.0
	p.position = L.loot.pos
	guard.position = L.loot.pos + (L.loot.guard - L.loot.pos).normalized() * 2.0
	guard.angle = guard.angle_to_point(p.px(), p.pz())
	guard.rotation.y = guard.angle
	game._update_pickups(1.0 / 30.0)
	for k in 4:
		await look.call(p.position, guard.angle + PI * 0.6, 4.5, "theft%d" % k)
	print("[fort] офисников %d, болтают: %s, радио: %s, гонит: %s (angry %.1f), враги все: %s, hp героя %d, пакеты: %s" % [hs.size(),
		hs.filter(func(h): return h.role == "talk" and h.state == Enemy.S.REST and h.rest_kind == "talk").size(),
		hs.filter(func(h): return h.role == "radio" and h.state == Enemy.S.REST).size() == 1, guard.is_hostile(), guard.angry_t,
		game.office_hostile, int(p.hp), p.inv.get("bags", 0)])
	# герой в пакетах
	p.selected = "bags"
	p.cd = 0.0
	p.use_item()
	guard.angry_t = 0.0
	p.position = mid + Vector3(1.5, 0, 1.0)
	await look.call(p.position, PI, 3.5, "bags")
	_sheet(dir, "fort", shots)
	game.get_tree().quit()


## 0.18: поле битвы — общий вид (завалы, копоть, огонь), стороны сходятся, перестрелка, победители палят в воздух.
## Камера держится у середины боя. anim_battle.png + pose_battle_<что>.png.
func run_battle(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 13
	game.floor_num = 15
	game._load_floor(15, false, "battle")
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.visible = false
	p.frozen = true
	p.disguised = false
	var L: OfficeLevel = game.L
	var shots: Array = []
	var look := func(pos: Vector3, yaw: float, dist: float, tag: String) -> void:
		p.position = pos
		game.cam_yaw = yaw
		game.cam_dist = dist
		game.cam_pos = pos
		for _w in 20:
			game.state = "play"
			await _frames(1)
		shots.append(_grab())
		var img: Image = game.get_viewport().get_texture().get_image()
		img.save_png("%s/pose_battle_%s.png" % [dir, tag])
	await look.call(L.ammo_pos, 0.7, 9.0, "ammo")
	await look.call(L.sides[0].pos, 0.3, 9.0, "side0")
	# герой «вне игры» (за картой), а камера — у центра событий: где больше живых людей в бою / рядом друг с другом
	var hero_far := Vector3(-60, 0, -60)
	var t := 0.0
	var k := 0
	while t < 240.0 and k < 10:
		p.position = hero_far
		for _s in 30:
			game._update_world(1.0 / 30.0, false)
			t += 1.0 / 30.0
		var busy: Array = game.enemies.filter(func(e): return e is Human and not e.is_dead() and (e.is_hostile() or e.cheer_t > 0.0))
		if busy.size() >= 1 and int(t) % 3 == 0:
			var c := Vector3.ZERO
			for e in busy: c += e.position
			c /= busy.size()
			await look.call(c, 0.5 + k * 0.4, 8.0, "fight%d" % k)
			k += 1
	print("[battle] фаза %s, победили %s, стволов подобрали %d, живы: %s, за %d с" % [game.battle_phase, game.npc_stats.battle_winner,
		game.npc_stats.battle_guns_taken, game.enemies.filter(func(e): return not e.is_dead()).map(func(e): return e.faction + ":" + e.weapon), int(t)])
	_sheet(dir, "battle", shots)
	game.get_tree().quit()


## 0.19: крыша (финал) — общий вид, курящий у парапета, площадка; герой подходит → вертолёт садится → элита выходит
## (бронежилеты, M4A1-S); элита лежит → «В ВЕРТОЛЁТ» → взлёт → экран победы. anim_roof.png + pose_roof_<что>.png.
func run_roof(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 17
	game.floor_num = 30
	game.stats = {"kills": 12, "knockouts": 5, "hacked": 140, "floors": 29, "time": 3725.0, "alerts": 9, "from": 1}
	game._load_floor(30, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.invuln = 99999.0
	var L: OfficeLevel = game.L
	var shots: Array = []
	var look := func(pos: Vector3, yaw: float, dist: float, tag: String, frames: int = 20) -> void:
		game.cam_yaw = yaw
		game.cam_dist = dist
		game.cam_pos = pos
		for _w in frames:
			if game.state == "pause": game.state = "play"
			await _frames(1)
		shots.append(_grab())
		var img: Image = game.get_viewport().get_texture().get_image()
		img.save_png("%s/pose_roof_%s.png" % [dir, tag])
	# бандиты живут 40 с (герой спрятан за картой — их никто не тревожит)
	p.visible = false
	p.frozen = true
	p.position = Vector3(-60, 0, -60)
	for _s in 40 * 30:
		game._update_world(1.0 / 30.0, false)
	p.position = L.start_elev.stand
	await look.call(Vector3(L.W * 0.5, 0, L.H * 0.5), 0.5, 16.0, "overview")
	var hs: Array = game.enemies.filter(func(e): return e is Human)
	for h: Human in hs:
		if h.state == Enemy.S.REST and h.rest_kind == "smoke":
			p.position = h.position
			await look.call(h.position, h.angle + PI * 0.7, 4.5, "smoke")
			break
	# герой у площадки — вертолёт садится
	p.visible = true
	p.frozen = false
	game.player_disguised()   # (для вида без маскировки)
	p.position = L.helipad + Vector3(-9.0, 0, 3.0)
	for k in 3:
		await look.call(L.helipad, 0.4, 11.0, "landing%d" % k, 45)
	for _w in 90:
		await _frames(1)
	await look.call(L.helipad + Vector3(-2, 0, 0), 0.6, 7.0, "elites")
	print("[roof] бандитов %d, фаза %s, элита %d (hp %s, оружие %s), выход открыт: %s" % [hs.size(), game.heli_phase, game.elites.size(),
		game.elites.map(func(e): return int(e.hp)), game.elites.map(func(e): return e.weapon), game.exit_open()])
	for e in game.elites:
		e.take_damage(999.0, p, "gun")
	await _frames(5)
	print("[roof] элита лежит — выход открыт: ", game.exit_open())
	p.position = L.exit_elev.stand
	game._board_heli()
	for k in 3:
		await look.call(game.heli_node.position, game.cam_yaw, 10.0 + k * 3, "takeoff%d" % k, 30)
	for _w in 130:
		await _frames(1)
	shots.append(_grab())
	game.get_viewport().get_texture().get_image().save_png("%s/pose_roof_victory.png" % dir)
	_sheet(dir, "roof", shots)
	print("[roof] состояние %s, пройдено раз %d" % [game.state, game.beaten])
	game.get_tree().quit()


## 0.19.1: свидетель — герой душит бандита, второй (с ножом) видит, бежит с криком к своим, приводит их обыскивать
## место. Камера следует за свидетелем. anim_witness.png.
func run_witness(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 9
	game._load_floor(4, false)
	await _frames(20)
	game.state = "play"
	var p: Player = game.player
	p.hp = 99999.0
	p.invuln = 99999.0
	_clear_enemies()
	var L: OfficeLevel = game.L
	# открытая прямая 8 клеток: герой — в начале, жертва — в 1.2 м, свидетель — в 6 м
	var ctr := Vector3.ZERO
	var fwd := Vector3(0, 0, 1)
	var found := false
	for z in range(3, L.H - 3):
		for x in range(3, L.W - 3):
			if found or not L.walkable(x, z): continue
			for k in 4:
				var ok := true
				for s in range(1, 9):
					if not L.walkable(x + OfficeLevel.DX[k] * s, z + OfficeLevel.DZ[k] * s): ok = false
				if ok and not L.line_blocked(x + 0.5, z + 0.5, x + OfficeLevel.DX[k] * 8 + 0.5, z + OfficeLevel.DZ[k] * 8 + 0.5, 0):
					ctr = Vector3(x + 0.5, 0, z + 0.5)
					fwd = Vector3(OfficeLevel.DX[k], 0, OfficeLevel.DZ[k])
					found = true
					break
	p.position = ctr
	p.angle = atan2(fwd.x, fwd.z)
	p.rotation.y = p.angle
	var mk := func(wid: String, pos: Vector3, ang: float) -> Human:
		var h := Human.new()
		game.level_root.add_child(h)
		var c := L.nearest_walkable(floori(pos.x), floori(pos.z), 3)
		h.setup_human(game, L, Vector3(c.x + 0.5, 0, c.y + 0.5), ang, wid, {"members": [], "dest": pos}, "guard")
		game.enemies.append(h)
		h.state = Enemy.S.GUARD
		h.look_base = ang
		h.attn = 1.0
		return h
	var v: Human = mk.call("knife", p.position + fwd * 1.2, p.angle)
	var w: Human = mk.call("axe", p.position + fwd * 6.0, p.angle + PI)
	# свои — подальше (≥ 12 м от свидетеля по прямой)
	var dw := L.bfs_dist(floori(w.px()), floori(w.pz()))
	var best := -1
	for i in L.W * L.H:
		if dw[i] > 0 and L.cells[i] == OfficeLevel.FLOOR and Vector2(i % L.W + 0.5 - w.px(), i / L.W + 0.5 - w.pz()).length() >= 12.0 \
				and (best < 0 or dw[i] < dw[best]):
			best = i
	var ap := Vector3(best % L.W + 0.5, 0, best / L.W + 0.5)
	mk.call("uzi", ap, 0.0)
	mk.call("knife", ap + Vector3(0.9, 0, 0), 0.0)
	game.cam_dist = 9.0
	await _frames(10)
	p.cd = 0.0
	p.angle = p.angle_to_point(v.px(), v.pz())
	p.melee()
	var shots: Array = []
	for k in 12:
		for _w in 12:
			if game.state == "pause": game.state = "play"
			if k >= 2: game.cam_target = w
			await _frames(1)
		shots.append(_grab())
	_sheet(dir, "witness", shots)
	print("[witness] бежал: %d, обыск: %d, свидетель %s" % [game.npc_stats.witness_runs, game.npc_stats.witness_searches, Enemy.S.keys()[w.state]])
	game.get_tree().quit()


## 0.20: пожарная лестница — люк в стене, после 3-го взлома спускаются бандиты; герой держит «ЗАКРЫТЬ» 3 с — люк
## заколочен. anim_escape.png + pose_escape_<что>.png.
func run_escape(g: Node, dir: String) -> void:
	game = g
	game.rng.seed = 21
	game.floor_num = 25
	game._load_floor(25, false, "normal")
	await _frames(20)
	game.state = "play"
	game.waves = []
	var p: Player = game.player
	p.hp = 99999.0
	p.invuln = 99999.0
	var L: OfficeLevel = game.L
	var es: Dictionary = L.escapes[0]
	var shots: Array = []
	var look := func(tag: String, frames: int = 20) -> void:
		for _w in frames:
			if game.state == "pause": game.state = "play"
			await _frames(1)
		shots.append(_grab())
		game.get_viewport().get_texture().get_image().save_png("%s/pose_escape_%s.png" % [dir, tag])
	var cam_node := Node3D.new()
	game.level_root.add_child(cam_node)
	cam_node.position = es.stand + es.normal * 1.5
	game.cam_target = cam_node
	game.cam_yaw = atan2(es.normal.x, es.normal.z)
	game.cam_dist = 6.0
	p.visible = false
	p.frozen = true
	p.position = Vector3(-60, 0, -60)
	await look.call("hatch")
	game.hacked = 3
	game.esc_t = 0.5
	for k in 4:
		await look.call("wave%d" % k, 12)
	# герой подходит и заколачивает люк
	for e in game.enemies:
		if e is Human: e.die(null)
	p.visible = true
	p.frozen = false
	p.position = es.stand
	game.ctx_held = true
	for k in 3:
		await look.call("lock%d" % k, 32)
	game.ctx_held = false
	await look.call("locked")
	_sheet(dir, "escape", shots)
	print("[escape] люков %d, волн %d, бандитов с лестницы %d, заблокирован: %s" % [L.escapes.size(), game.npc_stats.escape_waves, game.npc_stats.escape_bandits, es.locked])
	game.get_tree().quit()


## Кадры для README: обычный этаж (зомби за компьютерами), логово (бочка), укреплённый офис (разговор), люк пожарной
## лестницы, крыша с вертолётом. Без боя (нет пятен крови), здоровье героя 100. readme_<что>.png.
func run_readme(g: Node, dir: String) -> void:
	game = g
	await _frames(20)
	var shot := func(tag: String, frames: int = 30) -> void:
		for _w in frames:
			if game.state == "pause": game.state = "play"
			await _frames(1)
		game.get_viewport().get_texture().get_image().save_png("%s/readme_%s.png" % [dir, tag])
	var cam := Node3D.new()
	var setup := func(n: int, kind: String, seed_v: int) -> void:
		game.rng.seed = seed_v
		game.floor_num = n
		game._load_floor(n, false, kind)
		game.state = "play"
		game.waves = []
		game.player.invuln = 99999.0
		game.player.frozen = true
		if cam.get_parent() == null:
			game.add_child(cam)   # не в level_root — переживает смену этажа
		game.cam_target = cam
	# 1) обычный этаж: у компьютера, рядом зомби за ПК
	await setup.call(4, "normal", 31)
	var p: Player = game.player
	var pc: Dictionary = game.L.pcs[0]
	for e in game.enemies:
		if e.state == Enemy.S.WORK:
			pc = game.L.pcs.reduce(func(a, b): return a if Vector2(a.sx - e.px(), a.sz - e.pz()).length() < Vector2(b.sx - e.px(), b.sz - e.pz()).length() else b)
			break
	p.position = Vector3(pc.sx + 0.5, 0, pc.sz + 0.5)
	p.crouch = true
	cam.position = p.position
	game.cam_dist = 7.5
	game.cam_yaw = 0.6
	await shot.call("office")
	# 2) логово: бочка, бандиты греются
	await setup.call(5, "lair", 7)
	p = game.player
	p.visible = false
	p.position = Vector3(-60, 0, -60)
	for _s in 40 * 30:
		game._update_world(1.0 / 30.0, false)
	var f0: Dictionary = game.L.fires[0]
	cam.position = Vector3(f0.x + 0.5, 0, f0.z + 0.5)
	game.cam_dist = 6.5
	game.cam_yaw = 0.5
	await shot.call("lair")
	# 3) укреплённый офис: двое болтают
	await setup.call(10, "fort", 11)
	p = game.player
	p.visible = false
	p.position = Vector3(-60, 0, -60)
	for _s in 30 * 30:
		game._update_world(1.0 / 30.0, false)
	cam.position = (game.L.talk.a + game.L.talk.b) * 0.5
	game.cam_dist = 5.5
	game.cam_yaw = game.L.talk.ang_a + PI * 0.5
	await shot.call("fort")
	# 4) люк пожарной лестницы
	await setup.call(25, "normal", 21)
	p = game.player
	var es: Dictionary = game.L.escapes[0]
	p.position = es.stand + es.normal * 1.2
	p.angle = atan2(-es.normal.x, -es.normal.z)
	p.rotation.y = p.angle
	cam.position = es.stand + es.normal * 1.5
	game.cam_yaw = atan2(es.normal.x, es.normal.z)
	game.cam_dist = 6.0
	await shot.call("escape")
	# 5) крыша: вертолёт садится
	await setup.call(30, "", 17)
	p = game.player
	p.position = game.L.helipad + Vector3(-10.0, 0, 2.5)
	p.angle = PI * 0.5
	p.rotation.y = p.angle
	p.crouch = true
	cam.position = game.L.helipad + Vector3(-4.0, 0, 1.0)
	game.cam_dist = 11.0
	game.cam_yaw = 0.35
	p.frozen = false
	for _w in 4 * 30:
		await _frames(1)
	p.frozen = true
	await shot.call("roof", 5)
	print("[readme] готово")
	game.get_tree().quit()
