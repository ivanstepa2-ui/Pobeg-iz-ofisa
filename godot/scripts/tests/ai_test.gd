extends Node
## Тест поведения ИИ без игрока (герой «вне игры»): 3 минуты жизни этажа.
##   godot --headless --path . -- --aitest
## Печатает: сколько зомби бродили, вставали ли работники из-за компьютеров, были ли толпы и клинчи,
## как отряд людей занял комнату и патрулировал (обычный и настороженный отряд).

const DT := 1.0 / 30.0
var SIM := 180.0   # --sim N — секунд на этаж

var game: Node


func run(g: Node) -> void:
	game = g
	var args := OS.get_cmdline_user_args()
	if "--sim" in args:
		SIM = float(args[args.find("--sim") + 1])
	await _frames(10)
	if "--battlestat" in OS.get_cmdline_user_args():
		await _battle_stat()
		game.get_tree().quit()
		return
	if "--ambush" in OS.get_cmdline_user_args():
		await _ambush_debug()
		game.get_tree().quit()
		return
	for wary in [false, true]:
		for trial in 3:
			await _floor_run(wary, trial)
	print("[aitest] охотники, разбор кандидатов: ", Human.dbg)
	print("[aitest] ГОТОВО")
	game.get_tree().quit()


func _floor_run(wary: bool, trial: int) -> void:
	game.spotted_by_humans = wary
	game._load_floor(_floor(), false)
	game.state = "gameover"
	var p: Player = game.player
	p.frozen = true
	p.position = Vector3(-50, 0, -50)    # подальше — никого не тревожит
	game._spawn_squad(6 if _floor() >= game.DEEP_FLOOR else 4)
	if "--office" in OS.get_cmdline_user_args():
		game._spawn_office(3)   # 0.15: офисники с другой стороны этажа
	var zs: Array = game.enemies.filter(func(e): return not e is Human)
	var start := {}
	var max_d := {}
	for z in zs:
		start[z] = z.position
		max_d[z] = 0.0
	var workers: Array = zs.filter(func(z): return z.home_state == Enemy.S.WORK)
	var stood := {}
	var crowd_max := 0
	var crowd_samples := 0
	var crowd_hits := 0
	var tm := 0.0
	var fights := 0
	var zs_alive0 := zs.filter(func(z): return not z.is_dead()).size()
	var pair_d_sum := 0.0
	var in_pair_sum := 0.0
	var pair_n := 0
	var stalks := 0
	var was_stalking := {}
	var sq: Dictionary = game.squads[0]
	var hs: Array = sq.members
	var walk_t := {}
	var spread_sum := 0.0
	var spread_n := 0
	var plans: Array = []
	var arrived_at := -1.0
	var left_room := {}
	for h in hs:
		walk_t[h] = 0.0
	# 0.10: маршруты пар (сколько комнат в списке), когда сошлись у стартового лифта
	var routes0: Array = sq.get("routes", []).map(func(r): return r.size())
	var meet_at := -1.0
	var kills0: Dictionary = Human.dbg.duplicate()
	while tm < SIM:
		for _k in 30:
			game._update_world(DT, false)
			tm += DT
			for h in hs:
				if h.speed_now > 0.3: walk_t[h] += DT
		for z in zs:
			max_d[z] = maxf(max_d[z], Vector2(z.position.x - start[z].x, z.position.z - start[z].z).length())
			if z.home_state == Enemy.S.WORK and z.state != Enemy.S.WORK:
				stood[z] = true
		# толпа: сколько зомби в радиусе 2.5 м от каждого (берём максимум)
		var mx := 0
		for a in zs:
			var n := 0
			for b in zs:
				if Vector2(a.px() - b.px(), a.pz() - b.pz()).length() < 2.5: n += 1
			mx = maxi(mx, n)
		crowd_max = maxi(crowd_max, mx)
		crowd_samples += 1
		if mx >= 4: crowd_hits += 1
		for h in hs:
			if h.is_hostile(): fights += 1
			if h.state == Enemy.S.STALK and not was_stalking.get(h, false): stalks += 1
			was_stalking[h] = h.state == Enemy.S.STALK
		if meet_at < 0.0 and sq.get("plan", "") == "sweep" and sq.phase == "rest":
			meet_at = tm
		if sq.get("plan", "") in ["pairs", "sweep"] and sq.phase != "rest" and sq.pairs.size() == 2:
			var p1: Array = sq.pairs[0].filter(func(m): return not m.is_dead())
			var p2: Array = sq.pairs[1].filter(func(m): return not m.is_dead())
			if p1.size() > 0 and p2.size() > 0:
				pair_d_sum += p1[0].dist_to(p2[0])
				var ip := 0.0
				if p1.size() > 1: ip = maxf(ip, p1[0].dist_to(p1[1]))
				if p2.size() > 1: ip = maxf(ip, p2[0].dist_to(p2[1]))
				in_pair_sum += ip
				pair_n += 1
		if sq.phase == "settled":
			if arrived_at < 0.0:
				arrived_at = tm
			if plans.is_empty() or plans[-1] != sq.plan:
				plans.append(sq.plan)
			var sp := 0.0
			for a in hs:
				for b in hs:
					sp = maxf(sp, a.dist_to(b))
			spread_sum += sp
			spread_n += 1
			var room: Dictionary = sq.room
			for h in hs:
				if game.L.room_at(h.px(), h.pz()) != room:
					left_room[h] = true
		await game.get_tree().process_frame
	var moved := zs.filter(func(z): return max_d[z] > 2.0).size()
	var roles := hs.map(func(h): return ("†" if h.is_dead() else "") + h.role)
	print("[aitest] %s #%d | зомби бродили: %d/%d | работников вставало: %d/%d | макс. толпа %d (≥4 рядом: %d%% времени)" % [
		"НАСТОРОЖЕ" if wary else "обычный", trial + 1, moved, zs.size(), stood.size(), workers.size(), crowd_max,
		100 * crowd_hits / maxi(1, crowd_samples)])
	print("[aitest]            отряд: занял комнату на %ds, планы %s, роли сейчас %s, выходили из комнаты %d/%d, в движении %s, средний разброс отряда %.1f м, в бою с зомби %d с" % [
		int(arrived_at), plans, roles, left_room.size(), hs.size(), hs.map(func(h): return "%d%%" % int(100 * walk_t[h] / SIM)),
		spread_sum / maxf(1, spread_n), fights])
	var ns: Dictionary = game.npc_stats
	print("[aitest]            0.9: засад %d → тихих убийств %d (%d%%), срывов стелса %d, щелкун убил бандитов %d (отбили %d), крик подтянул %d раз, страх %d с, бандитов живо %d, щелкунов %d" % [
		ns.ambush_started, ns.stealth_kills, 100 * ns.stealth_kills / maxi(1, ns.ambush_started), ns.stealth_breaks,
		ns.clicker_kills, ns.clicker_saves, ns.scream_pulls, int(ns.fear_time), hs.filter(func(h): return not h.is_dead()).size(),
		game.enemies.filter(func(e): return e is Clicker).size()])
	var kinds := {}
	for k in Human.dbg:
		if String(k).begins_with("убит "):
			kinds[k] = Human.dbg[k] - kills0.get(k, 0)
	var left: Array = sq.get("routes", []).map(func(r): return r.size())
	print("[aitest]            0.10: комнат на пару %s (осталось %s), сошлись у старта %s, дошли %d | у двери %d, «вдвоём» %d, тихие по видам %s | зомби тихо %d / в открытую %d | бандитов убили: зомби %d, щелкун %d (+приманка %d) | шум %.1f (всего %.1f), щелкунов на шум %d" % [
		routes0, left, ("на %d с" % int(meet_at)) if meet_at >= 0.0 else "нет", ns.meet_arrived, ns.door_ambush, ns.duo_distract, kinds,
		ns.zombies_quiet, ns.zombies_open, ns.humans_by_zombies, ns.humans_by_clicker, ns.humans_by_clicker_lured,
		ns.noise, ns.noise_total, ns.noise_clickers])
	var offs: Array = game.enemies.filter(func(e): return e is Human and e.faction == "office")
	if not offs.is_empty():
		print("[aitest]            0.15: офисников живо %d/%d, война с %s, убили бандитов %d, погибли: от бандитов %d, от зомби %d" % [
			offs.filter(func(e): return not e.is_dead()).size(), offs.size(), ("%d с" % int(ns.faction_war_t)) if ns.faction_war_t >= 0.0 else "нет",
			ns.bandits_by_office, ns.office_by_bandits, ns.office_by_zombies])
	print("[aitest]            0.11: бандит уходил от зомби %d, прятался %d, зомби начинали поиск %d, бандитов живо %d/%d" % [
		ns.bandit_evades, ns.bandit_hides, ns.zombie_searches, hs.filter(func(h): return not h.is_dead()).size(), hs.size()])
	print("[aitest]            пары: между парами в среднем %.1f м, внутри пары %.1f м | подкрадывались %d раз, зарезали со спины %d, всего зомби погибло %d из %d" % [
		pair_d_sum / maxf(1, pair_n), in_pair_sum / maxf(1, pair_n), stalks, game.human_kills,
		zs_alive0 - zs.filter(func(z): return not z.is_dead()).size(), zs_alive0])


## Разбор одной засады: зомби бродит/стоит, охотник в ~8 м, герой вне игры. Лог раз в 0.5 с.
func _ambush_debug() -> void:
	for trial in 4:
		game._load_floor(4, false)
		game.state = "gameover"
		var p: Player = game.player
		p.frozen = true
		p.position = Vector3(-50, 0, -50)
		for e in game.enemies:
			e.queue_free()
		game.enemies.clear()
		# открытое место
		var L: OfficeLevel = game.L
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		var found := false
		for z in range(2, L.H - 2):
			for x in range(2, L.W - 2):
				if found or not L.walkable(x, z): continue
				for k in 4:
					var ex: int = x + OfficeLevel.DX[k] * 8
					var ez: int = z + OfficeLevel.DZ[k] * 8
					if L.walkable(ex, ez) and not L.line_blocked(x + 0.5, z + 0.5, ex + 0.5, ez + 0.5, 2):
						a = Vector3(x + 0.5, 0, z + 0.5)
						b = Vector3(ex + 0.5, 0, ez + 0.5)
						found = true
						break
		game._add_enemy("zombie", b, randf() * TAU, trial == 0)
		var z0: Enemy = game.enemies[0]
		var h := Human.new()
		game.level_root.add_child(h)
		h.setup_human(game, L, a, 0.0, "knife", {"members": [], "phase": "settled", "dest": a}, "hunt")
		game.enemies.append(h)
		var tm := 0.0
		var log := ""
		while tm < 25.0 and not z0.is_dead():
			for _k in 15:
				game._update_world(1.0 / 30.0, false)
				tm += 1.0 / 30.0
			var to_me := Vector2(h.px() - z0.px(), h.pz() - z0.pz())
			log += " %.1f:%s d=%.1f dot=%.2f зс=%s ж=%s susp=%.2f |" % [tm, Enemy.S.keys()[h.state], to_me.length(),
				to_me.normalized().dot(z0.facing()), z0._see_factor(h) > 0.0, Enemy.S.keys()[z0.state], z0.susp]
			await game.get_tree().process_frame
		print("[ambush] #%d %s → зомби %s за %.1f с\n%s" % [trial, "работник" if trial == 0 else "бродячий", "УБИТ" if z0.is_dead() else "жив", tm, log])


func _frames(n: int) -> void:
	for i in n:
		await game.get_tree().process_frame


## Этаж для --aitest: `--floor N` (по умолчанию 4).
func _floor() -> int:
	var args := OS.get_cmdline_user_args()
	if "--floor" in args:
		return int(args[args.find("--floor") + 1])
	return 4


## 0.18: замер боёв на поле битвы (без героя): `--aitest --battlestat [--n N]` — N боёв (по умолчанию 20), до конца боя
## (+10 с) или 6 мин. Итог: победители, длительность, выстрелы/попадания/по своим/убийства по оружию, кто кого убил.
func _battle_stat() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[args.find("--n") + 1]) if "--n" in args else 20
	var total := {}
	var wins := {}
	var lines: Array = []
	for i in n:
		game._load_floor(10, false, "battle")
		game.state = "gameover"
		var p: Player = game.player
		p.frozen = true
		p.position = Vector3(-60, 0, -60)
		var no: int = game.npc_stats.battle_office
		var nb: int = game.npc_stats.battle_bandits
		var guns := {"office": [], "human": []}
		for e in game.enemies:
			if e is Human and not e.W.melee:
				guns[e.faction].append(e.weapon)
		var t := 0.0
		var end_t := -1.0
		while t < 360.0:
			for _k in 30:
				game._update_world(DT, false)
				t += DT
			if game.battle_phase == "after" and end_t < 0.0:
				end_t = t
			if end_t >= 0.0 and t > end_t + 10.0:
				break
			await game.get_tree().process_frame
		var st: Dictionary = game.npc_stats
		var w: String = st.battle_winner if st.battle_winner != "" else "нет (6 мин)"
		wins[w] = wins.get(w, 0) + 1
		var alive := {"office": 0, "human": 0}
		for e in game.enemies:
			if e is Human and not e.is_dead():
				alive[e.faction] += 1
		for k in st.blog:
			total[k] = total.get(k, 0) + st.blog[k]
		lines.append("#%d офис %d %s / банд %d %s → %s за %d с, живы офис %d банд %d, по своим %d" % [i + 1, no, guns.office, nb,
			guns.human, w, int(end_t), alive.office, alive.human, st.friendly_hits])
	for l in lines:
		print("[battlestat] ", l)
	print("[battlestat] ПОБЕДЫ: ", wins)
	# по оружию: выстрелы/замахи, попадания во врага, по своим, убийства врагов / своих
	var by := {}
	for k in total:
		var parts: PackedStringArray = String(k).split(":")
		var wk := parts[0] + ":" + parts[1]
		if not by.has(wk):
			by[wk] = {"shot": 0, "hit": 0, "friendly": 0, "kill→human": 0, "kill→office": 0}
		by[wk][parts[2]] = by[wk].get(parts[2], 0) + total[k]
	var keys := by.keys()
	keys.sort()
	for wk in keys:
		var b: Dictionary = by[wk]
		print("[battlestat] %-18s выстр/замах %4d  попал во врага %4d (%2d%%)  по своим %3d  убил бандитов %2d  убил офисников %2d" % [wk,
			b.shot, b.hit, 100 * b.hit / maxi(1, b.shot), b.friendly, b["kill→human"], b["kill→office"]])
