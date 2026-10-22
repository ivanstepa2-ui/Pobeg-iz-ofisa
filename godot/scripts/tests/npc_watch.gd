extends Node
## Наблюдение за NPC без игрока: отряд людей зачищает этаж от зомби, камера следит за самым активным.
##   godot --path . --rendering-driver opengl3 --resolution 854x480 --write-movie out.avi --fixed-fps 30 -- --npcwatch 5 240
## (этаж, секунд). Без --write-movie можно и --headless — тогда только лог.
## Печатает события: кто кого убил, сколько зомби/людей осталось; в конце — итог.

const DT := 1.0 / 30.0

var game: Node
var focus: Enemy = null
var focus_t := 0.0


func run(g: Node, floor_n: int, secs: float) -> void:
	game = g
	await _frames(5)
	game.floor_num = floor_n
	game._load_floor(floor_n, false)
	game.state = "npcwatch"          # _process игры ничего не делает в этом состоянии — мир крутим сами
	game.hud.visible = false
	var p: Player = game.player
	p.frozen = true
	p.visible = false
	p.position = Vector3(-60, 0, -60)  # вне этажа — никого не тревожит
	# отряды как в игре: основной 4 (с DEEP_FLOOR — 6); «--office» — вместо подкрепления офисники у старта
	# (1–3 до 6-го этажа, дальше 2–5), иначе подкрепление бандитов с 6-го (3, с DEEP_FLOOR — 4)
	var office: bool = "--office" in OS.get_cmdline_user_args()
	var deep: bool = floor_n >= int(game.DEEP_FLOOR)
	game._spawn_squad(6 if deep else 4)
	if office:
		game._spawn_office(randi_range(1, 3) if floor_n <= 6 else randi_range(2, 5))
	elif floor_n >= 6:
		game._spawn_squad(4 if deep else 3, false)
	var zs: Array = game.enemies.filter(func(e): return not e is Human)
	var hs: Array = game.enemies.filter(func(e): return e is Human)
	print("[npc] этаж %d: зомби %d, людей %d (%s)" % [floor_n, zs.size(), hs.size(),
		hs.map(func(h): return ("оф:" if h.faction == "office" else "") + h.weapon)])
	var war_t := -1.0
	var vaulting := {}
	var vaults := {"human": 0, "office": 0}
	var tm := 0.0
	var log_t := 0.0
	var dead_z := 0
	var dead_h := 0
	var cam_pos := Vector3.ZERO
	while tm < secs:
		game._update_world(DT, false)
		tm += DT
		focus_t -= DT
		# начало войны фракций засекаем сами: game.floor_t здесь не идёт (его двигает только _update_play)
		if war_t < 0.0 and game.faction_war_on:
			war_t = tm
			print("[npc] %3d с: началась война фракций" % int(tm))
		# считаем перелезания по фракциям (vault_t > 0 — начало перелезания)
		for h in hs:
			var v: bool = not h.is_dead() and h.vault_t > 0.0
			if v and not vaulting.get(h, false):
				vaults[h.faction] = int(vaults.get(h.faction, 0)) + 1
			vaulting[h] = v
		var dz := zs.filter(func(z): return z.is_dead()).size()
		var dh: int = game.enemies.filter(func(e): return e is Human and e.is_dead()).size()
		if dz != dead_z or dh != dead_h:
			print("[npc] %3d с: зомби убито %d/%d (людьми со спины %d), людей погибло %d" % [int(tm), dz, zs.size(), game.human_kills, dh])
			dead_z = dz
			dead_h = dh
		# камера — на самого «интересного» живого человека: в бою > крадётся > остальные
		if focus == null or focus.is_dead() or focus_t <= 0.0:
			focus = _pick_focus()
			focus_t = 15.0
		if focus != null:
			cam_pos = focus.position
		game._place_camera(cam_pos, game.cam_yaw, game.cam_dist, DT, false)
		log_t -= DT
		if log_t <= 0.0:
			log_t = 20.0
			var states: Array = game.enemies.filter(func(e): return e is Human and not e.is_dead()).map(
				func(h): return "%s%s:%s" % ["оф:" if h.faction == "office" else "", h.weapon, Enemy.S.keys()[h.state]])
			print("[npc] %3d с: люди %s" % [int(tm), states])
			print("[npc] %3d с: живы бандитов %d, офисников %d, зомби %d" % [int(tm),
				hs.filter(func(h): return h.faction == "human" and not h.is_dead()).size(),
				hs.filter(func(h): return h.faction == "office" and not h.is_dead()).size(),
				zs.filter(func(z): return not z.is_dead()).size()])
		await game.get_tree().process_frame
		if game.enemies.filter(func(e): return e is Human and not e.is_dead()).is_empty():
			print("[npc] все люди погибли на %d с" % int(tm))
			break
	print("[npc] ИТОГ: за %d с зомби убито %d из %d (людьми со спины %d), людей погибло %d из %d" % [
		int(tm), dead_z, zs.size(), game.human_kills, dead_h,
		game.enemies.filter(func(e): return e is Human).size()])
	print("[npc] ИТОГ фракций: война с %s, бандитов живо %d из %d, офисников живо %d из %d, перелезаний: бандиты %d, офисники %d" % [
		("%d с" % int(war_t)) if war_t >= 0.0 else "— (не было)",
		hs.filter(func(h): return h.faction == "human" and not h.is_dead()).size(), hs.filter(func(h): return h.faction == "human").size(),
		hs.filter(func(h): return h.faction == "office" and not h.is_dead()).size(), hs.filter(func(h): return h.faction == "office").size(),
		vaults.get("human", 0), vaults.get("office", 0)])
	# 0.9: счётчики — тихие убийства, засады, крики, щелкуны
	print("[npc] счётчики: ", game.npc_stats)
	game.get_tree().quit()


func _pick_focus() -> Enemy:
	var best: Enemy = null
	var best_s := -1
	for e: Enemy in game.enemies:
		if not e is Human or e.is_dead(): continue
		var s := 0
		if e.is_hostile(): s = 3
		elif e.state == Enemy.S.STALK: s = 2
		elif e.speed_now > 0.3: s = 1
		if s > best_s:
			best_s = s
			best = e
	return best


func _frames(n: int) -> void:
	for i in n:
		await game.get_tree().process_frame
