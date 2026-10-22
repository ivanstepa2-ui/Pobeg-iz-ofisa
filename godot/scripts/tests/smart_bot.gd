extends RefCounted
## «Умный» бот автотеста («-- --autotest --smart»). Не часть игры — только для проверки и видео.
## Сам решает, что делать:
##  - рядом враг, который может заметить, — крадётся вприсядку;
##  - за ним охотятся — отстреливается или кидает, что есть; если нечем или враг близко — убегает
##    туда, где стены закрывают его от преследователей;
##  - враг стоит спиной вплотную — бьёт сзади (нож/топор/кулак);
##  - мало здоровья — лечится; рядом лут — подбирает;
##  - к ПК, возле которых толпятся враги, идёт в последнюю очередь.

const GUNS := ["rifle", "silenced", "pistol", "uzi", "shotgun"]
const HEALS := ["medkit", "coffee", "energy"]

var mode := ""
var flee_cell := Vector2i(-1, -1)
var flee_t := 0.0
var fight_t := 0.0
var plan := "flee"
var plan_t := 0.0
var approach_best := 1e9
var approach_t := 0.0
var evade_cell := Vector2i(-1, -1)
var evade_total := 0.0
var evade_cool := 0.0
var loot_t := {}   # сколько секунд пытались подобрать лут (по id узла)

## Против людей бот выбирает способ по ситуации (что в инвентаре, дистанция, сколько их, заметили ли)
## и по «стилю» на этаж — со случайностью, чтобы забеги отличались:
##  stealth — чаще обходит, режет сзади, стреляет только в спину;
##  hunter — охотится: стреляет, кидает, болтовка;
##  trickster — стравливает людей с зомби бутылкой/будильником, потом добивает выживших.
## Каждое убийство человека пишется «[kill] способ … итого {…}» — по последней строке видно распределение.
const STYLES := {"stealth": 0.4, "hunter": 0.35, "trickster": 0.25}
var style := ""
var style_floor := -1
var now := 0.0
var engage_cd := 0.0
var stalk: Enemy = null      # кого выслеживаем, чтобы ударить сзади
var stalk_t := 0.0
var last_hit := {}           # id человека -> [способ, время]
var humans_alive := {}
var lure_t := -100.0         # когда последний раз стравливали
var kills := {}              # способ -> число убитых людей

## 0.9: щелкуны и учёт урона по источникам ([hit] источник урон | итого {…})
var ck_cool := 0.0           # пауза после броска-приманки
var ck_hunt_t := 0.0         # сколько уже крадёмся к щелкуну
var flee_prev := false       # замер бега: прошлый кадр бот убегал
var run_frames := 0
var run_speed := 0.0
var run_slow := 0            # кадров бегства медленнее бухгалтерши (3.8 м/с)
var run_why := {}
var bags_t := 0.0           # 0.17: сколько уже идём за пакетами
var bags_wait := 0.0        # сколько ждали, пока офисники отвернутся
var flips: Array = []       # моменты переключения «убегаю → к цели» (против метания)
var choke_lethal := false   # 0.12: держать удушение до смерти
var zstalk: Enemy = null     # 0.12: к какому зомби крадёмся со спины
var zstalk_t := 0.0
var freeze_t := 0.0       # сколько подряд стоим замерев (0.11)
var calm_t := 0.0          # после бегства: сколько ещё переждать в укрытии, прежде чем идти к цели
var avoid_pc := {}           # ПК, к которым временно не идём (щелкун рядом): Vector2i -> до какого времени
var last_hp := -1.0
var dmg_by := {}
# сводка этажа: «[floor] N | урон … | люди убиты … | npc …»
var floor_dmg := {}
var floor_kills := {}
var npc_snap := {}
var snap_t := 0.0
var summed_floor := -1
var snap_n := 0

## Арена («--arena»): бессмертный бот с полным арсеналом охотится на отряды людей.
## После каждого убитого человека берёт следующее оружие из KIT — чтобы посмотреть, как стреляет каждое.
const KIT := ["rifle", "uzi", "pistol", "shotgun", "silenced", "axe", "knife", "pipe", "knuckles", "shuriken", "grenade", "brick", "extinguisher"]
const ARENA_ROUNDS := 1
const ARENA_SQUADS := 3
var arena := false
# «--witness» (для видео 0.19.1): душить людей и на глазах у других — проверить свидетелей (бегут за своими)
var witness_mode := "--witness" in OS.get_cmdline_user_args()
var arena_round := 0
var arena_wi := 0
var arena_alive := {}   # id живых людей
var arena_kills := 0
var arena_down := {}    # id людей в нокауте


func think(g: Node, dt: float, goal: Vector2i) -> Vector2:
	if arena:
		return _hunt(g, dt)
	var p: Player = g.player
	now += dt
	flee_avoid = Vector2.INF
	if g.floor_kind == "roof" and g.heli_phase == "wait" and roof_cell.x >= 0 and roof_floor == g.floor_num:
		flee_avoid = Vector2(g.L.helipad.x, g.L.helipad.z)
	if witness_mode and g.floor_kind == "lair":
		var wv: Variant = _witness_stage(g, p, dt)
		if wv != null:
			return wv
	# снимок счётчиков этажа (game.npc_stats обнуляется при загрузке следующего — печатаем свой снимок)
	snap_t -= dt
	if snap_t <= 0.0:
		snap_t = 1.0
		npc_snap = g.npc_stats.duplicate()
		# раз в 20 с — снимок в лог: если бот погибнет на этаже, последний снимок покажет, что было
		snap_n += 1
		if snap_n % 20 == 0:
			var hs: Array = g.enemies.filter(func(e): return e is Human and not e.is_dead())
			print("[npc_t] этаж %d, %d с | бандитов живо %d %s | %s" % [g.floor_num, snap_n, hs.size(),
				hs.map(func(h): return "%s:%s" % [h.weapon, Enemy.S.keys()[h.state]]), npc_snap])
	# сводку печатаем у лифта с полным паролем (после переезда последний этаж игра может уже закрыть)
	if g.exit_open() and g.ctx.get("kind", "") == "elevator" and summed_floor != g.floor_num:
		summed_floor = g.floor_num
		_floor_summary(g.floor_num)
	if g.floor_num != style_floor:
		if style_floor >= 0 and summed_floor != style_floor:
			_floor_summary(style_floor)
		npc_snap = {}
		floor_dmg = {}
		bags_t = 0.0
		bags_wait = 0.0
		floor_kills = {}
		style_floor = g.floor_num
		style = _pick_style()
		stalk = null
		humans_alive.clear()
		avoid_pc.clear()
		print("[bot] стиль на этаж %d: %s" % [g.floor_num, style])
	_count_kills(g)
	_log_hits(g, p)
	# 0.9: щелкун — слепой, идёт на звук. Ближайший живой:
	var ck: Clicker = null
	var ck_d := 1e9
	for e: Enemy in g.enemies:
		if e is Clicker and not e.is_dead() and not e.is_down() and p.dist_to(e) < ck_d:
			ck_d = p.dist_to(e)
			ck = e
	ck_cool -= dt
	if ck != null and not p.is_choking():
		var act: Variant = _clicker_plan(g, p, ck, ck_d, goal)
		if act != null:
			return act
	var mv := _think(g, dt, goal)
	var capped := false
	# рядом щелкун — не шуметь: ближе 7 м только вприсядку (шагов не слышно), ближе 12 м — без бега.
	# Если он уже несётся на нас или нас грызёт — бежать можно (он 4 м/с, бег 4.6).
	# за нами уже гонятся (не щелкун) — шуметь не страшно, бег на полной скорости важнее тишины
	var chased := false
	for e: Enemy in g.enemies:
		if not e is Clicker and not e.is_dead() and not e.is_down() and e.hunts_player():
			chased = true
			break
	if ck != null and not p.hacking and not chased:
		var chasing := (ck.hunts_player() or ck.mode() == "rush") and ck_d < 4.0
		if not chasing:
			if ck_d < 7.0:
				p.crouch = true
				capped = true
			elif ck_d < 12.0 and mv.length() > 0.6:
				mv = mv.normalized() * 0.6
				capped = true
	_track_flee(p, mv, capped)
	return mv


## Замер: с какой скоростью бот реально бежит, когда убегает, и что его тормозит.
func _track_flee(p: Player, mv: Vector2, capped: bool) -> void:
	if flee_prev:
		run_frames += 1
		run_speed += p.speed_now
		if p.speed_now < 3.8:
			run_slow += 1
	flee_prev = mode in ["убегаю", "бегу", "за", "оторвался"]
	if flee_prev:
		if p.crouch: run_why["присед"] = int(run_why.get("присед", 0)) + 1
		if capped: run_why["щелкун рядом"] = int(run_why.get("щелкун рядом", 0)) + 1
		if p.punch_t > 0.2: run_why["после удара"] = int(run_why.get("после удара", 0)) + 1
		if mv.length() < 0.7 and not p.crouch: run_why["шагом"] = int(run_why.get("шагом", 0)) + 1


func _think(g: Node, dt: float, goal: Vector2i) -> Vector2:
	var p: Player = g.player
	var L: OfficeLevel = g.L
	var me := Vector2(p.px(), p.pz())
	g.bot_hold = true
	flee_t -= dt
	fight_t -= dt
	engage_cd -= dt
	# 0.7/0.12: душим — стоим, пока захват не кончится. Насмерть держим, если рядом никого (герой уязвим 3 с)
	if p.is_choking() or p.takedown_t > 0.0 or p.grab_move_t > 0.0:
		p.melee_hold = choke_lethal
		return Vector2.ZERO
	p.melee_hold = false
	# 0.14: перелезает — ждём приземления
	if p.is_vaulting():
		return Vector2.ZERO

	# --- кто вокруг
	var hunters: Array = []
	var near: Enemy = null
	var near_d := 1e9
	var watched := false
	var victim: Enemy = null
	var threats: Array = []
	for e: Enemy in g.enemies:
		if e.is_dead() or e.is_down(): continue
		# 0.15: лояльные офисники — не враги и не цели (тронешь на глазах у своих — весь отряд против до конца этажа)
		if _loyal(e): continue
		var d := p.dist_to(e)
		var los := not L.line_blocked(me.x, me.y, e.px(), e.pz(), 0)
		# щелкун слепой: пока он не вплотную, это не погоня — от него не бегут (бег шумит), а затихают
		if e is Clicker and d > 4.0:
			continue
		if e.hunts_player():
			hunters.append(e)
			if d < near_d:
				near_d = d
				near = e
			continue
		var sight: float = (13.0 if e is Human else 8.0) * (1.4 if p.hp < 40.0 else 1.0)
		if d < sight and los:
			watched = true
		# патруль людей рядом — уходим из-под фонаря заранее, до тревоги
		# 0.8: с опущенным фонарём (крадётся/отдыхает) человек видит только ~7 м — можно подойти ближе
		var see_r: float = 6.0 if e is Human and (e as Human).is_dim() else 8.0
		if e is Human and d < see_r and (los or d < 3.5):
			threats.append(e)
		# стоит спиной вплотную — удар сзади
		var to_e := Vector2(e.px() - me.x, e.pz() - me.y).normalized()
		if d < 1.5 and not e.is_hostile() and e.facing().dot(to_e) > 0.3:
			victim = e
	if g.in_flashlight(p.position):
		watched = true
	# 0.14: приём из слепой зоны — не только со спины, но и сбоку (игра сама решает через sneak_target)
	var st0: Enemy = p.sneak_target()
	if st0 != null and not _loyal(st0):
		victim = st0
	elif st0 != null and victim == st0:
		victim = null

	# --- лечение
	if p.hp < 50.0 and p.cd <= 0.0 and not p.hacking:
		for id in HEALS:
			if p.inv.get(id, 0) > 0:
				p.selected = id
				p.use_item()
				_say("лечусь: " + Items.def(id).name)
				break

	# --- 0.12: кто-то стоит к нам спиной и не видит — тихий приём (зомби, бухгалтерша, бандит; не толстяк/щелкун)
	if victim != null and hunters.is_empty() and p.cd <= 0.0 and not p.hacking:
		p.turn_to(p.angle_to_point(victim.px(), victim.pz()), 10.0)
		if _takedown(g, p, victim):
			return Vector2.ZERO

	if hunters.is_empty():
		fight_t = 0.0
		flee_cell = Vector2i(-1, -1)
		# вырубленного рядом — добить, пока не встал
		# 0.7: лежачего человека — кулаком (50 урона, бесплатно), зомби — ножом/топором
		var fin := _first(p, ["knife", "axe"])
		if not p.hacking:
			for e: Enemy in g.enemies:
				if e.is_dead() or not e.is_down() or p.dist_to(e) > 4.0: continue
				if not e is Human and fin == "": continue
				if e is Human and (e as Human).state == Enemy.S.CHOKED: continue
				p.lock = e
				if p.dist_to(e) < 1.3:
					if p.cd <= 0.0:
						p.turn_to(p.angle_to_point(e.px(), e.pz()), 10.0)
						if e is Human:
							p.melee()
						else:
							p.selected = fin
							p.use_item()
						if not last_hit.has(e.get_instance_id()) or now - float(last_hit[e.get_instance_id()][1]) > 8.0:
							_mark(e, "добил лежачего")
						_say("добиваю " + e.type)
					return Vector2.ZERO
				_say("иду добить " + e.type)
				return g._bot_walk(Vector2i(floori(e.px()), floori(e.pz())), 0.6)
		p.lock = null
		p.crouch = watched and not p.hacking
		# 0.11: присевшего неподвижного зомби не видят. Зомби рядом смотрит в нашу сторону и начинает
		# подозревать — присесть и замереть, пока не отвернётся (не дольше ~4 с подряд)
		var gz: Enemy = _zombie_gaze(g, p, L, me)
		var gaze := gz != null
		if gaze and freeze_t < 4.0 and not p.hacking:
			freeze_t += dt
			p.crouch = true
			# 0.13.1: замер на открытом зомби «покажется» — уже прикрыты столом от него → сидим; иначе
			# вприсядку за ближайший стол (закрывающий от него), нет такого — отползаем из его взгляда
			if L.line_blocked(gz.px(), gz.pz(), me.x, me.y, 1):
				_say("замер за столом — зомби смотрит")
				return Vector2.ZERO
			var cover := _desk_cover(L, me, gz)
			if cover.x >= 0:
				_say("ныряю за стол от зомби")
				return g._bot_walk(cover, 0.6)
			_say("отползаю из взгляда зомби")
			return (me - Vector2(gz.px(), gz.pz())).normalized().rotated(PI * 0.5 * (1.0 if randf() < 0.5 else -1.0)).lerp((me - Vector2(gz.px(), gz.pz())).normalized(), 0.5).normalized() * 0.6
		if not gaze:
			freeze_t = maxf(0.0, freeze_t - dt * 2.0)
		# люди рядом, но ещё не заметили — тихо уходим за стену (бросаем и взлом)
		# 0.16: логово — куртка, потом хозяин ключ-карты
		var lact: Variant = _lair(g, p, me)
		if lact != null:
			return lact
		# 0.17: укреплённый офис — тихо взять пакеты (пока никто из офисников не смотрит) и надеть
		var fact: Variant = _fort(g, p, L, me, dt)
		if fact != null:
			return fact
		# 0.12: зомби мешает (у цели или рядом) и нас не видит — подкрасться со спины и тихо убрать
		var zact: Variant = _zombie_stalk(g, p, L, me, goal, dt)
		if zact != null:
			return zact
		# люди: выбрать способ — выстрел, бросок, стравить с зомби, подкрасться сзади — или обойти
		var act: Variant = _engage(g, p, L, me)
		if act != null:
			return act
		# прятаться не дольше 10 с подряд: если патруль сторожит место — потом идём всё равно
		evade_cool -= dt
		if threats.is_empty() or evade_cool > 0.0:
			evade_total = maxf(0.0, evade_total - dt * 0.5)
		else:
			evade_total += dt
			if evade_total > 10.0:
				evade_total = 0.0
				evade_cool = 8.0
		# крыша до вертолёта: укрытие выбирает roof_goal (засада), второе «прячусь» только мешает — мечется на виду
		if not threats.is_empty() and victim == null and evade_cool <= 0.0 and flee_avoid == Vector2.INF:
			g.bot_hold = false
			p.crouch = true
			if evade_cell.x < 0 or Vector2(evade_cell.x + 0.5 - me.x, evade_cell.y + 0.5 - me.y).length() < 1.0:
				evade_cell = _pick_flee(L, me, threats, g.enemies)
			if evade_cell.x >= 0:
				_say("прячусь от патруля")
				return g._bot_walk(evade_cell, 0.6)
		evade_cell = Vector2i(-1, -1)
		var k: String = g.ctx.get("kind", "")
		if k == "hack" or k == "hatch" or (k == "elevator" and g.exit_open()):
			_say({"hack": "взламываю", "hatch": "заколачиваю люк"}.get(k, "жду лифт"))
			return Vector2.ZERO
		# лут рядом — подобрать
		for pk in g.pickups:
			var node: Node3D = pk.node
			# уже несём по потолку (0.6: Items.cap) или не унести — не идём; до чего не добрались за 6 с — бросаем
			if p.inv.get(pk.id, 0) >= Items.cap(pk.id): continue
			# 0.13: слот занят другим предметом — берём ЗАМЕНОЙ, только если новое лучше того, что в руках
			var blocker: String = p.slot_blocker(pk.id)
			var swap := blocker != ""
			if swap and _item_value(g, pk.id, int(pk.n)) <= _item_value(g, blocker, int(p.inv.get(blocker, 0))) + 0.3:
				continue
			if not swap and pk.get("blocked", false): continue
			var tried: float = loot_t.get(node.get_instance_id(), 0.0)
			if tried > 6.0: continue
			# за лечением при малом здоровье — идём дальше
			var far: float = 16.0 if p.hp < 60.0 and Items.def(pk.id).cat == Items.Cat.HEAL else 8.0
			var dpk := Vector2(node.position.x - me.x, node.position.z - me.y).length()
			if dpk < far:
				loot_t[node.get_instance_id()] = tried + dt
				if swap and dpk < 0.9 and g.do_swap(pk):
					_say("меняю %s → %s" % [Items.def(blocker).name, Items.def(pk.id).name])
					return Vector2.ZERO
				_say(("иду менять на " if swap else "подбираю ") + Items.def(pk.id).name)
				return g._bot_walk(Vector2i(floori(node.position.x), floori(node.position.z)), 0.6)
		# только что оторвались от погони — пересидеть в укрытии вприсядку, а не бежать к цели в того же зомби
		if calm_t > 0.0:
			calm_t -= dt
			p.crouch = true
			_say("пережидаю после погони")
			return Vector2.ZERO
		if flee_avoid != Vector2.INF:
			p.crouch = true   # крыша до вертолёта: только вприсядку
		_say("крадусь" if p.crouch else "иду к цели")
		return g._bot_walk(goal, 0.6)

	# --- за нами охотятся
	p.crouch = false
	# дожимаем взлом, только если ближайший охотник не успеет добежать до конца взлома
	if g.ctx.get("kind", "") == "hack":
		var pcd: Dictionary = g.ctx.pc
		var left: float = (1.0 - float(pcd.progress)) * (g.HACK_TIME + g.hacked * 0.3)
		var arrive := 1e9
		for e: Enemy in hunters:
			var spd: float = float(Enemy.TYPES[e.type].chase) if Enemy.TYPES.has(e.type) else 3.5
			var reach: float = 9.0 if e is Human and (e as Human).weapon in ["uzi", "rifle"] else 1.3
			arrive = minf(arrive, maxf(0.0, p.dist_to(e) - reach) / maxf(0.5, spd))
		if arrive > left + 0.3:
			_say("дожимаю взлом, %.1f с до конца, враг через %.1f с" % [left, arrive])
			return Vector2.ZERO
	g.bot_hold = false
	var shot := false
	if p.cd <= 0.0:
		shot = _attack(g, p, L, me, hunters)
	# есть из чего стрелять и враг на мушке — стоим и стреляем
	if shot or (_ranged(p) != "" and p.cd > 0.0 and fight_t > 0.0 and near_d > 2.0):
		fight_t = 0.6
		return Vector2.ZERO
	# драться врукопашную или бежать? Решение держим 2 с, иначе бот мечется туда-сюда.
	# Совсем мало здоровья — только бежать.
	plan_t -= dt
	# (пороги здоровья — внутри _melee_ok: с одиночным зомби/бухгалтершей дерёмся до конца)
	var ok_fight := _melee_ok(p, hunters, near, near_d)
	if plan_t <= 0.0 or (plan == "fight" and not ok_fight):
		plan = "fight" if ok_fight else "flee"
		plan_t = 2.0
	if plan == "flee":
		calm_t = 7.0   # после бегства не лезть сразу обратно к цели
	if plan != "fight":
		approach_best = 1e9
		approach_t = 0.0
	if plan == "fight":
		fight_t = 1.0
		flee_cell = Vector2i(-1, -1)
		var mw := _best_melee(p, near)
		var reach: float = (float(Items.def(mw).reach) if mw != "" else 1.35) + near.radius * 0.5
		p.lock = near
		if near_d <= reach:
			if p.cd <= 0.0:
				if mw != "":
					p.selected = mw
					p.use_item()
				else:
					p.melee()
				_mark(near, "рукопашная: " + (Items.def(mw).name if mw != "" else "кулак"))
				_say("дерусь: %s → %s" % [Items.def(mw).name if mw != "" else "кулак", near.type])
			return Vector2.ZERO
		# не приближаемся 4 с (враг за мебелью, не дойти) — бросаем и уходим
		if near_d < approach_best - 0.3:
			approach_best = near_d
			approach_t = 0.0
		approach_t += dt
		if approach_t > 4.0:
			plan = "flee"
			plan_t = 3.0
			approach_t = 0.0
			approach_best = 1e9
		_say("сближаюсь с " + near.type)
		# только по пути: «вижу» стоя и поверх столов, напрямик упрёмся в мебель
		return g._bot_walk(Vector2i(floori(near.px()), floori(near.pz())), 1.0)
	fight_t = 0.0
	p.lock = null
	# 0.14: зомби близко — перелезть через стол/ксерокс, если приземлимся заметно дальше от них (зомби не лазят)
	if near_d < 4.0 and _try_vault(p, hunters):
		return Vector2.ZERO
	# бежим: до точки бегства добегаем, а не дёргаемся туда-сюда; к цели — только если оторвались далеко
	if near_d > 14.0 and flee_cell.x < 0:
		# метание «убегаю ↔ к цели»: цель за преследователем — отложить этот ПК, идти к другому
		if mode == "убегаю":
			flips.append(now)
		while not flips.is_empty() and now - float(flips[0]) > 30.0:
			flips.pop_front()
		if flips.size() > 6:
			flips.clear()
			avoid_pc[goal] = now + 30.0
			g._bot_task = Vector2i(-1, -1)
			_say("цель за погоней — к другому ПК")
		_say("бегу к цели, погоня в %.0f м" % near_d)
		return g._bot_walk(goal, 1.0)
	if flee_cell.x < 0 or flee_t <= -4.0 or Vector2(flee_cell.x + 0.5 - me.x, flee_cell.y + 0.5 - me.y).length() < 1.2:
		flee_cell = _pick_flee(L, me, hunters, g.enemies) if near_d < 14.0 else Vector2i(-1, -1)
		flee_t = 0.0
		if flee_cell.x < 0:
			return g._bot_walk(goal, 1.0)
	# 0.11: оторвались за угол — никто из погони нас не видит и вплотную никого нет:
	# присесть и тихо отходить (зомби ищут только там, где видели последний раз; присевшего не видят)
	var seen := false
	for e: Enemy in hunters:
		# от быстрых (бухгалтерша, человек) вприсядку не уйти — только бегом, пока не отстанут совсем
		if e.type == "woman" or e is Human:
			seen = true
			break
		# зомби ещё ~1 с «чуют за угол», бухгалтерша быстрая — замедляемся, только когда все дальше 7 м
		if p.dist_to(e) < 7.0 or not L.line_blocked(e.px(), e.pz(), me.x, me.y, 1):
			seen = true
			break
	if not seen:
		p.crouch = true
		# погоня далеко и нас не видит — тихо крадёмся дальше к цели (иначе метание «отход ↔ к цели»)
		if near_d > 10.0:
			_say("оторвался — крадусь к цели")
			return g._bot_walk(goal, 0.6)
		calm_t = 7.0
		_say("за углом — отхожу тихо")
		return g._bot_walk(flee_cell, 0.6)
	_say("убегаю от " + near.type)
	return g._bot_walk(flee_cell, 1.0)


## Есть ли смысл драться врукопашную с охотниками.
func _melee_ok(p: Player, hunters: Array, near: Enemy, near_d: float) -> bool:
	var close := 0
	var fat := false
	var gunner := false
	for e: Enemy in hunters:
		if p.dist_to(e) < 7.0:
			close += 1
			if e.type == "fat": fat = true
			if e is Human and (e as Human).weapon in ["uzi", "rifle"]: gunner = true
	var mw := _best_melee(p, near)
	var strong := mw in ["knuckles", "axe", "knife"]
	if fat or near is Clicker:
		return false   # толстяка и щелкуна (120 hp, кулак сзади не валит) врукопашную спереди не берём
	# 0.6: человек 120 hp — кулаком, ножом или трубой не забить; только кастет или топор
	if near is Human:
		return close == 1 and mw in ["knuckles", "axe"] and p.hp > 40.0
	# кулаком — один на один при хорошем здоровье. Проверено на 0.9: если от одиночного зомби только убегать,
	# он долго держит след, бот кружит по этажу и теряет больше (8/20 смертей на 1-м этаже против 2/20)
	# Разбор (0.9, 12 прогонов): на 1-м этаже бот гибнет, убегая от одиночки — бухгалтерша
	# догоняет на углах, менеджер — когда бот возвращается к ПК. Драться с одиночкой дешевле, чем бегать.
	if mw == "":
		if close == 1 and near.type in ["zombie", "woman"]:
			return p.hp > 22.0
		return close == 1 and p.hp > 60.0
	# стрелок держит дистанцию — гоняться за ним без ствола бесполезно, уходим из-под огня
	if gunner:
		return close == 1 and near_d < 2.5
	if close <= 1:
		return p.hp > 35.0 or strong
	if close == 2:
		return strong and p.hp > 60.0
	return false


## Лучшее холодное против этого врага (кастет толстяка не валит).
func _best_melee(p: Player, e: Enemy) -> String:
	var order := ["axe", "knife", "pipe"] if e.type == "fat" else ["knuckles", "axe", "knife", "pipe"]
	return _first(p, order)


func _ranged(p: Player) -> String:
	return _first(p, GUNS + ["shuriken", "brick", "extinguisher", "grenade"])


func _hunt(g: Node, dt: float) -> Vector2:
	var p: Player = g.player
	var L: OfficeLevel = g.L
	var me := Vector2(p.px(), p.pz())
	g.bot_hold = false
	p.crouch = false
	# кто из людей погиб с прошлого кадра — засчитываем текущему оружию и берём следующее
	var w: String = KIT[arena_wi]
	var humans: Array = []
	for e: Enemy in g.enemies:
		if not e is Human: continue
		var id := e.get_instance_id()
		if e.is_dead():
			if arena_alive.has(id):
				arena_alive.erase(id)
				arena_kills += 1
				print("[arena] человек (%s) убит, в руках было: %s, всего убито %d" % [(e as Human).weapon, Items.def(w).name, arena_kills])
				arena_wi = (arena_wi + 1) % KIT.size()
				w = KIT[arena_wi]
				print("[arena] беру ", Items.def(w).name)
			continue
		arena_alive[id] = true
		# нокаут (труба, кастет, кирпич, огнетушитель) — тоже результат: следующим оружием добьём
		if e.is_down() and not arena_down.has(id):
			arena_down[id] = true
			print("[arena] человек (%s) вырублен: %s" % [(e as Human).weapon, Items.def(w).name])
			arena_wi = (arena_wi + 1) % KIT.size()
			w = KIT[arena_wi]
			print("[arena] беру ", Items.def(w).name)
		elif not e.is_down():
			arena_down.erase(id)
		humans.append(e)
	if humans.is_empty():
		if arena_round >= ARENA_ROUNDS:
			print("[arena] OK: раундов %d, людей убито %d" % [arena_round, arena_kills])
			g.get_tree().quit()
			return Vector2.ZERO
		arena_round += 1
		print("[arena] раунд %d: приезжают %d отряда" % [arena_round, ARENA_SQUADS])
		for i in ARENA_SQUADS:
			g._spawn_squad(4)
		return Vector2.ZERO
	# арсенал не кончается
	var df := Items.def(w)
	p.inv[w] = maxi(p.inv.get(w, 0), mini(3, Items.cap(w)))
	p.selected = w
	# цель: зомби, который уже вцепился, иначе ближайший человек
	var tgt: Enemy = null
	var td := 1e9
	for e: Enemy in g.enemies:
		if e is Human or e.is_dead() or e.is_down() or not e.hunts_player(): continue
		var d := p.dist_to(e)
		if d < 2.5 and d < td:
			td = d
			tgt = e
	if tgt == null:
		for e: Enemy in humans:
			var d := p.dist_to(e)
			if d < td:
				td = d
				tgt = e
	var reach := 1.3
	match int(df.cat):
		Items.Cat.WEAPON:
			reach = 5.0 if w == "shotgun" else float(df.range) * 0.7
		Items.Cat.MELEE:
			reach = float(df.get("reach", 1.2)) + 0.1
		_:
			reach = 8.0
	var los := not L.line_blocked(me.x, me.y, tgt.px(), tgt.pz(), 0)
	# граната ранит и бессмертного (взрыв бьёт по игроку напрямую) — не кидаем под ноги
	var too_close := w == "grenade" and td < 4.8
	if td <= reach and los and not too_close:
		p.lock = tgt
		if p.cd <= 0.0:
			p.use_item()
		return Vector2.ZERO
	p.lock = null
	if too_close and los:
		# отходим от цели на дистанцию броска
		return (me - Vector2(tgt.px(), tgt.pz())).normalized()
	return g._bot_walk(Vector2i(floori(tgt.px()), floori(tgt.pz())), 1.0)


## Стрелять или кидать в видимого охотника. Сначала опасные (толстяк, стрелок), потом ближайший.
## Болтовку бережём для толстяка и стрелков; граната и огнетушитель — по толпе; кирпич — по толстяку.
func _attack(g: Node, p: Player, L: OfficeLevel, me: Vector2, hunters: Array) -> bool:
	var tgt: Enemy = null
	var best := 1e9
	var td := 0.0
	for e: Enemy in hunters:
		var d := p.dist_to(e)
		if d > 16.0 or L.line_blocked(me.x, me.y, e.px(), e.pz(), 0): continue
		var s := d
		if e.type == "fat": s -= 4.0
		if e is Human and (e as Human).weapon in ["uzi", "rifle"]: s -= 5.0
		if s < best:
			best = s
			td = d
			tgt = e
	if tgt == null:
		return false
	var crowd := 0
	for e: Enemy in hunters:
		if Vector2(e.px() - tgt.px(), e.pz() - tgt.pz()).length() < 3.0:
			crowd += 1
	var big: bool = tgt.type == "fat" or (tgt is Human and (tgt as Human).weapon in ["uzi", "rifle"])
	var pick := ""
	var guns: Array = ["rifle", "shotgun", "pistol", "uzi", "silenced"] if big else ["silenced", "pistol", "uzi", "shotgun", "rifle"]
	for id in guns:
		if p.inv.get(id, 0) > 0 and td <= float(Items.def(id).range) * 0.85 and not (id == "shotgun" and td > 6.0):
			pick = id
			break
	if pick == "":
		if p.inv.get("grenade", 0) > 0 and td > 4.8 and td <= Player.THROW_RANGE and crowd >= 2 and not _loyal_near(g, Vector2(tgt.px(), tgt.pz()), 4.0):
			pick = "grenade"
		elif p.inv.get("extinguisher", 0) > 0 and td <= 6.0 and td > 3.2 and crowd >= 2 and not _loyal_near(g, Vector2(tgt.px(), tgt.pz()), 3.5):
			pick = "extinguisher"
		elif p.inv.get("brick", 0) > 0 and td <= 8.0 and tgt.type == "fat":
			pick = "brick"
		elif p.inv.get("shuriken", 0) > 0 and td <= Player.THROW_RANGE:
			pick = "shuriken"
		elif p.inv.get("brick", 0) > 0 and td <= 8.0 and td > 2.0:
			pick = "brick"
		elif p.inv.get("grenade", 0) > 0 and td > 4.8 and td <= Player.THROW_RANGE and big and not _loyal_near(g, Vector2(tgt.px(), tgt.pz()), 4.0):
			pick = "grenade"
	if pick == "":
		return false
	p.lock = tgt
	p.selected = pick
	p.use_item()
	_mark(tgt, "в бою: " + Items.def(pick).name)
	_say("%s → %s (%.1f м)" % [Items.def(pick).name, tgt.type, td])
	return true


## Куда бежать: подальше от охотников, лучше — за стену.
func _pick_flee(L: OfficeLevel, me: Vector2, hunters: Array, others: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_s := -1e9
	var away := Vector2.ZERO
	for e: Enemy in hunters:
		away += (me - Vector2(e.px(), e.pz())).normalized()
	away = away.normalized()
	for i in 14:
		var c := L.random_reachable(me.x, me.y, 5, 14)
		if c.x < 0: continue
		var cp := Vector2(c.x + 0.5, c.y + 0.5)
		var md := 1e9
		var hidden := true
		for e: Enemy in hunters:
			md = minf(md, cp.distance_to(Vector2(e.px(), e.pz())))
			if not L.line_blocked(cp.x, cp.y, e.px(), e.pz(), 0):
				hidden = false
		# 0.11: за углом (не видно никому из погони) — главное; потом подальше и прочь от них
		var s := md + (cp - me).normalized().dot(away) * 5.0 + (12.0 if hidden else 0.0)
		# не вбегать в других врагов: разбудим новых
		for e: Enemy in others:
			if e.is_dead() or e.is_down() or e in hunters: continue
			if cp.distance_to(Vector2(e.px(), e.pz())) < 6.0:
				s -= 6.0
		# крыша: пока не готовы — не вбегать в зону вертолёта (≤ 12 м — он садится, выходит элита)
		if flee_avoid != Vector2.INF and cp.distance_to(flee_avoid) < 15.0:
			s -= 40.0
		if s > best_s:
			best_s = s
			best = c
	return best


func _first(p: Player, ids: Array) -> String:
	for id in ids:
		if p.inv.get(id, 0) > 0:
			return id
	return ""


# ---------------------------------------------------------------- щелкун (0.9)
## Щелкун у цели (ПК ближе 5 м к нему) — убрать его до взлома: сзади ножом/топором, приманить бутылкой
## подальше или идти к другому ПК. Щелкун «ест» рядом — окно ударить сзади. null — ничего особенного.
func _clicker_plan(g: Node, p: Player, ck: Clicker, ck_d: float, goal: Vector2i) -> Variant:
	var me := Vector2(p.px(), p.pz())
	for e: Enemy in g.enemies:
		if not e is Clicker and not e.is_dead() and e.hunts_player():
			return null   # нас гонят — обычная логика боя/бегства
	var cpos := Vector2(ck.px(), ck.pz())
	var pc := Vector2(goal.x + 0.5, goal.y + 0.5)
	var blade := _first(p, ["knife", "axe"])
	var mode := ck.mode()
	var blocking: bool = g.hacked < 5 and pc.distance_to(cpos) < 5.0 and pc.distance_to(me) < 10.0
	var feeding: bool = mode == "feed" and ck_d < 9.0
	if not blocking and not feeding:
		ck_hunt_t = 0.0
		return null
	g.bot_hold = false
	p.crouch = true
	# сзади ножом/топором — насмерть (слепой: подойти вприсядку можно вплотную)
	if blade != "" and (mode == "listen" or mode == "feed") and ck_hunt_t < 12.0:
		ck_hunt_t += 1.0 / 30.0
		if ck_d < 1.4 and (_behind(p, ck) or mode == "feed"):
			if p.cd <= 0.0:
				p.lock = ck
				p.turn_to(p.angle_to_point(ck.px(), ck.pz()), 10.0)
				p.selected = blade
				p.use_item()
				p.lock = null
				_say("режу щелкуна сзади: " + Items.def(blade).name)
			return Vector2.ZERO
		var f := ck.facing()
		_say("крадусь к щелкуну" + (" (ест)" if feeding else ""))
		return g._bot_walk(Vector2i(floori(ck.px() - f.x), floori(ck.pz() - f.y)), 0.6)
	if feeding:
		return null
	# приманить: бутылку/будильник за щелкуна, подальше от ПК
	var lure := _first(p, ["bottle", "alarm"])
	if lure != "" and ck_cool <= 0.0 and mode == "listen":
		if p.cd > 0.0:
			return Vector2.ZERO
		var away := (cpos - pc).normalized()
		if away == Vector2.ZERO:
			away = (cpos - me).normalized()
		var spot := cpos + away * 6.0
		p.lock = null
		p.angle = p.angle_to_point(spot.x, spot.y)
		p.selected = lure
		p.use_item()
		ck_cool = 8.0
		_say("кидаю %s, увожу щелкуна от ПК" % Items.def(lure).name)
		return Vector2.ZERO
	if ck_cool > 0.0 and mode == "rush":
		return Vector2.ZERO   # ушёл на звук — ждём, потом взломаем
	# ничего не помогло — к другому ПК, к этому вернёмся позже
	avoid_pc[goal] = now + 25.0
	g._bot_task = Vector2i(-1, -1)
	ck_hunt_t = 0.0
	_say("у ПК щелкун — иду к другому")
	return null


## Сводка пройденного этажа: урон герою по источникам (и доли по силам), как погибли люди, счётчики NPC.
func _floor_summary(n: int) -> void:
	var total := 0
	var by_force := {"зомби": 0, "бандиты": 0, "щелкун": 0, "?": 0}
	for k in floor_dmg:
		var v: int = floor_dmg[k]
		total += v
		var force := "?"
		if String(k).begins_with("human"): force = "бандиты"
		elif k == "clicker": force = "щелкун"
		elif k in ["zombie", "woman", "fat"]: force = "зомби"
		by_force[force] += v
	var shares := []
	for f in by_force:
		if by_force[f] > 0:
			shares.append("%s %d%%" % [f, int(100.0 * by_force[f] / maxi(1, total))])
	print("[floor] %d | урон %d (%s) %s | люди убиты %s | npc %s" % [n, total, ", ".join(shares), floor_dmg, floor_kills, npc_snap])
	print("[run] кадров бегства %d, средняя скорость %.2f м/с, медленнее 3.8: %d%% | тормоза %s" % [
		run_frames, run_speed / maxf(1.0, run_frames), 100 * run_slow / maxi(1, run_frames), run_why])


## Учёт урона по источникам: ближайший враг, который бьёт, или стрелок-человек.
func _log_hits(g: Node, p: Player) -> void:
	if last_hp < 0.0:
		last_hp = p.hp
	if p.hp < last_hp - 0.5:
		var dmg := last_hp - p.hp
		var src := "?"
		var bd := 2.6
		for e: Enemy in g.enemies:
			if e.is_dead(): continue
			var d := p.dist_to(e)
			if d < bd and (e.is_hostile() or e is Clicker):
				bd = d
				src = ("human:" + (e as Human).weapon) if e is Human else e.type
		if src == "?":
			for e: Enemy in g.enemies:
				if e is Human and not e.is_dead() and e.hunts_player() and (e as Human).weapon in ["uzi", "rifle"]:
					src = "human:" + (e as Human).weapon
					break
		dmg_by[src] = int(dmg_by.get(src, 0)) + int(round(dmg))
		floor_dmg[src] = int(floor_dmg.get(src, 0)) + int(round(dmg))
		print("[hit] %s %d | итого %s" % [src, int(round(dmg)), dmg_by])
	last_hp = p.hp


# ---------------------------------------------------------------- люди: разные способы
func _pick_style() -> String:
	var r := randf()
	for k in STYLES:
		r -= float(STYLES[k])
		if r <= 0.0:
			return k
	return "stealth"


## Запомнить, чем последний раз достали этого человека (и всех рядом — для гранаты).
func _mark(e: Enemy, how: String, radius: float = 0.0) -> void:
	last_hit[e.get_instance_id()] = [how, now]
	if radius > 0.0 and e.game != null:
		for o: Enemy in e.game.enemies:
			if o is Human and not o.is_dead() and Vector2(o.px() - e.px(), o.pz() - e.pz()).length() < radius:
				last_hit[o.get_instance_id()] = [how, now]


## Кто из людей умер с прошлого кадра — записываем способ.
func _count_kills(g: Node) -> void:
	for e: Enemy in g.enemies:
		if not e is Human: continue
		var id := e.get_instance_id()
		if not e.is_dead():
			humans_alive[id] = true
			continue
		if not humans_alive.has(id): continue
		humans_alive.erase(id)
		var how := "чужие (зомби/свои)"
		var lh: Array = last_hit.get(id, [])
		var by_ck := false
		for c: Enemy in g.enemies:
			if c is Clicker and not c.is_dead() and c.dist_to(e) < 2.5:
				by_ck = true
		if not lh.is_empty() and now - float(lh[1]) < 8.0:
			how = lh[0]
		elif by_ck:
			how = "щелкун (стравил)" if now - lure_t < 30.0 else "щелкун (сам)"
		elif now - lure_t < 40.0:
			how = "стравил с зомби"
		kills[how] = int(kills.get(how, 0)) + 1
		floor_kills[how] = int(floor_kills.get(how, 0)) + 1
		print("[kill] %s | итого %s" % [how, kills])


## 0.12: одиночный обычный зомби/бухгалтерша у ПК-цели (≤8 м) или рядом с нами (≤6 м), спокойный и без соседей —
## крадёмся к его спине и тихо убираем. Не дольше 12 с; заметил нас или ушёл — бросаем.
func _zombie_stalk(g: Node, p: Player, L: OfficeLevel, me: Vector2, goal: Vector2i, dt: float) -> Variant:
	if p.hacking:
		return null
	if zstalk != null and (not is_instance_valid(zstalk) or zstalk.is_dead() or zstalk.is_down() \
			or zstalk.is_hostile() or zstalk_t > 12.0):
		zstalk = null
	if zstalk == null:
		zstalk_t = 0.0
		var pc := Vector2(goal.x + 0.5, goal.y + 0.5)
		var best := 1e9
		for e: Enemy in g.enemies:
			if e is Human or e is Clicker or e.type == "fat" or e.is_dead() or e.is_down() or e.is_hostile(): continue
			if not e.can_be_choked(): continue
			var d := p.dist_to(e)
			var zp := Vector2(e.px(), e.pz())
			if d > 6.0 and zp.distance_to(pc) > 8.0: continue
			if d > 14.0: continue
			var lonely := true
			for o: Enemy in g.enemies:
				if o != e and not o.is_dead() and not o.is_down() and o.dist_to(e) < 5.0:
					lonely = false
					break
			if lonely and d < best:
				best = d
				zstalk = e
		if zstalk == null:
			return null
	zstalk_t += dt
	p.crouch = true
	if p.dist_to(zstalk) < 1.5 and p.cd <= 0.0 and _takedown(g, p, zstalk):
		zstalk = null
		return Vector2.ZERO
	var f := zstalk.facing()
	_say("крадусь со спины к " + zstalk.type)
	return g._bot_walk(Vector2i(floori(zstalk.px() - f.x * 1.1), floori(zstalk.pz() - f.y * 1.1)), 0.6)


## 0.14: перелезание от погони. Перебираем 8 направлений (поворачиваемся), берём то, где точка приземления
## дальше всего от ближайшего охотника-зомби (бандиты тоже лазят — от них не спасает). Нужен выигрыш ≥ 1.5 м.
func _try_vault(p: Player, hunters: Array) -> bool:
	if p.vault_cd > 0.0 or p.is_vaulting():
		return false
	var zs: Array = hunters.filter(func(e): return not e is Human)
	if zs.is_empty() or zs.size() < hunters.size():
		return false
	var me := Vector2(p.px(), p.pz())
	var cur := 1e9
	for e: Enemy in zs:
		cur = minf(cur, me.distance_to(Vector2(e.px(), e.pz())))
	var a0 := p.angle
	var best_a := 0.0
	var best_s := cur + 1.5
	var found := false
	for i in 8:
		p.angle = i * PI / 4.0
		var vt: Dictionary = p.vault_target()
		if vt.is_empty(): continue
		var to: Vector3 = vt.to
		var s := 1e9
		for e: Enemy in zs:
			s = minf(s, Vector2(to.x, to.z).distance_to(Vector2(e.px(), e.pz())))
		if s > best_s:
			best_s = s
			best_a = p.angle
			found = true
	if not found:
		p.angle = a0
		return false
	p.angle = best_a
	p.rotation.y = best_a
	if p.start_vault():
		_say("перелезаю от " + (zs[0] as Enemy).type)
		calm_t = 5.0
		return true
	p.angle = a0
	return false


## 0.13: насколько предмет хорош для бота сейчас (для решения о замене в слоте). Стиль этажа и угрозы:
## болтовка — если на этаже толстяки или стрелки-бандиты; ПБ — в стелсе; дробовик — охотнику. Запас добавляет до +50%.
func _item_value(g: Node, id: String, n: int) -> float:
	var fat := false
	var gunners := false
	for e: Enemy in g.enemies:
		if e.is_dead(): continue
		if e.type == "fat": fat = true
		if e is Human and (e as Human).weapon in ["uzi", "rifle"]: gunners = true
	var base := 1.0
	match id:
		"silenced": base = 3.2 if style != "hunter" else 2.6
		"pistol": base = 2.8 if style == "hunter" else 2.4
		"rifle": base = 3.5 if fat or gunners else 2.2
		"shotgun": base = 3.3 if style == "hunter" else 2.4
		"uzi": base = 2.8
		"knife": base = 3.0
		"axe": base = 2.9
		"knuckles": base = 2.0
		"pipe": base = 1.6
		"grenade": base = 3.0 if style == "hunter" else 2.6
		"shuriken": base = 3.0 if style != "hunter" else 2.7
		"brick": base = 3.0 if fat else 2.4
		"extinguisher": base = 2.6
		"bottle": base = 2.2 if style == "trickster" else 1.8
		"alarm": base = 1.6
		"medkit": base = 3.0
		"coffee": base = 2.2
		"energy": base = 1.6
	return base * (1.0 + 0.5 * minf(1.0, float(n) / maxf(1.0, float(Items.cap(id)))))


## 0.15: лояльный к герою офисник (пока game.office_hostile == false) — не трогаем.
## 0.16: и бандиты, когда на герое куртка бандита (is_loyal() у обеих сторон).
func _loyal(e: Enemy) -> bool:
	return e is Human and (e as Human).is_loyal()


## 0.16 логово бандитов: 1) куртка есть в рюкзаке — надеть; 2) куртка лежит (≤25 м) — сходить за ней вприсядку;
## 3) хозяин ключ-карты жив и стоит — выследить и задушить/зарезать со спины (ключ падает, когда он упал),
## дальше ключ-карту ведёт цель _bot_task_goal. null — ничего особенного.
func _lair(g: Node, p: Player, me: Vector2) -> Variant:
	if g.floor_kind != "lair" or g.key_taken or p.hacking:
		return null
	if p.inv.get("disguise", 0) > 0 and not p.disguised and not g.disguise_blown and p.cd <= 0.0:
		p.selected = "disguise"
		p.use_item()
		if p.disguised:
			_say("надел куртку бандита")
			return Vector2.ZERO
	if not p.disguised and p.inv.get("disguise", 0) == 0:
		# куртку сторожит бандит (L.loot.guard) — сначала тихо убрать его, потом брать куртку
		# L.loot.guard — это ТОЧКА поста; сам охранник — бандит с ролью guard ближе всех к ней
		var gd: Human = null
		if g.L.loot is Dictionary and g.L.loot.has("guard"):
			var gp: Vector3 = g.L.loot.guard
			var bd := 4.0
			for e: Enemy in g.enemies:
				if e is Human and e.faction == "human" and not e.is_dead() and (e as Human).role == "guard":
					var dd := Vector2(e.px() - gp.x, e.pz() - gp.z).length()
					if dd < bd:
						bd = dd
						gd = e
		if gd != null and not gd.is_down() and stalk != gd:
			if (gd as Human).can_be_choked():
				stalk = gd
				stalk_t = now + 30.0
				_say("выслеживаю охранника куртки")
			return null
		for pk in g.pickups:
			if pk.id != "disguise": continue
			var n: Node3D = pk.node
			var dd := Vector2(n.position.x - me.x, n.position.z - me.y).length()
			if dd > 25.0 or float(loot_t.get(n.get_instance_id(), 0.0)) > 20.0: break
			loot_t[n.get_instance_id()] = float(loot_t.get(n.get_instance_id(), 0.0)) + 1.0 / 30.0
			p.crouch = true
			_say("крадусь за курткой бандита")
			return g._bot_walk(Vector2i(floori(n.position.x), floori(n.position.z)), 0.6)
	var kh: Human = g.key_holder
	if kh != null and is_instance_valid(kh) and not kh.is_dead() and not kh.is_down() and stalk != kh:
		if kh.can_be_choked():
			stalk = kh
			stalk_t = now + 40.0
			_say("выслеживаю хозяина ключ-карты")
	return null


## 0.17 укреплённый офис: пакеты в рюкзаке — надеть на следующем обычном этаже; лежат (≤30 м) — красться к ним, а если кто-то из офисников
## (≤12 м, без стен, смотрит в нашу сторону ±60°) видит — сидеть и ждать, пока отвернётся (не дольше 20 с, потом
## берём всё равно: кража на глазах — только тумаки, не смерть). На всё про всё ~75 с, дальше — к лифту.
func _fort(g: Node, p: Player, L: OfficeLevel, me: Vector2, dt: float) -> Variant:
	if p.hacking:
		return null
	# пакеты действуют один этаж — в укреплённом офисе (зомби нет) их не тратим, надеваем на следующем обычном
	if g.floor_kind == "normal" and p.inv.get("bags", 0) > 0 and not p.bags and p.cd <= 0.0:
		p.selected = "bags"
		p.use_item()
		if p.bags:
			_say("надел пакеты на ноги (этаж %d)" % g.floor_num)
			return Vector2.ZERO
	if g.floor_kind != "fort":
		return null
	if p.bags or p.inv.get("bags", 0) > 0 or bags_t > 75.0:
		return null
	for pk in g.pickups:
		if pk.id != "bags": continue
		var n: Node3D = pk.node
		if Vector2(n.position.x - me.x, n.position.z - me.y).length() > 30.0:
			return null
		bags_t += dt
		p.crouch = true
		var seen := false
		for e: Enemy in g.enemies:
			if not e is Human or e.is_dead() or e.is_down() or p.dist_to(e) > 12.0: continue
			if L.line_blocked(e.px(), e.pz(), me.x, me.y, 1): continue
			var to_me := Vector2(me.x - e.px(), me.y - e.pz()).normalized()
			if e.facing().dot(to_me) > 0.5 or p.dist_to(e) < 2.0:
				seen = true
				break
		if seen and bags_wait < 20.0:
			bags_wait += dt
			_say("жду, пока офисник отвернётся")
			return Vector2.ZERO
		_say("крадусь за пакетами")
		return g._bot_walk(Vector2i(floori(n.position.x), floori(n.position.z)), 0.6)
	return null


## Рядом с точкой (r м) есть лояльный офисник — туда нельзя гранату/огнетушитель.
func _loyal_near(g: Node, pos: Vector2, r: float) -> bool:
	for o: Enemy in g.enemies:
		if not o.is_dead() and _loyal(o) and Vector2(o.px(), o.pz()).distance_to(pos) < r:
			return true
	return false


## 0.12: тихий приём по sneak_target(): нож/топор в руках — быстрое убийство; иначе удушение
## (насмерть — держим кнопку, если в 7 м нет других врагов, кто бы нас увидел, пока мы уязвимы).
func _takedown(g: Node, p: Player, e: Enemy) -> bool:
	var st: Enemy = p.sneak_target()
	if st == null or st != e or _loyal(e):
		return false
	var blade := _first(p, ["knife", "axe"])
	if blade != "":
		p.selected = blade
	var others := 0
	for o: Enemy in g.enemies:
		if o != e and not o.is_dead() and not o.is_down() and p.dist_to(o) < 7.0:
			others += 1
	choke_lethal = others == 0
	p.lock = e
	p.melee()
	p.lock = null
	var how := ("нож сзади" if blade != "" else ("удушение насмерть" if choke_lethal else "удушение"))
	_mark(e, how)
	_say("%s: %s" % [how, e.type])
	return true


## 0.19 крыша: пока вертолёт не вызван — цель не площадка, а точка за спиной бандита, которого легче всего убрать
## тихо (один, отдыхает, ближе к нам); дальше работает _engage (подкрасться и задушить). К площадке (≤ 14 м) не
## подходим, пока на ногах больше ROOF_LEFT бандитов или не вышло время. (-1, -1) — пора к вертолёту.
const ROOF_LEFT := 2
const ROOF_TIME := 420.0
var roof_t := 0.0
var roof_floor := -1
var roof_pick_t := 0.0
var roof_cell := Vector2i(-1, -1)
var flee_avoid := Vector2.INF   # точка, к которой не бежать (крыша: вертолётная площадка)

func roof_goal(g: Node) -> Vector2i:
	var L: OfficeLevel = g.L
	var p: Player = g.player
	if roof_floor != g.floor_num:
		roof_floor = g.floor_num
		roof_t = now
		roof_cell = Vector2i(-1, -1)
	var left: Array = g.enemies.filter(func(e): return e is Human and not (e as Human).elite and not e.is_dead() and not e.is_down())
	if left.size() <= ROOF_LEFT or now - roof_t > ROOF_TIME:
		roof_cell = Vector2i(-1, -1)
		return roof_cell
	if now < roof_pick_t and roof_cell.x >= 0:
		return roof_cell
	roof_pick_t = now + 1.0
	var pad := Vector2(L.helipad.x, L.helipad.z)
	var me := Vector2(p.px(), p.pz())
	# засада: клетка за укрытием (присевшего не видно ни одному бандиту в 16 м), подальше от площадки
	var cx := floori(me.x)
	var cz := floori(me.y)
	var best := 1e9
	var pick := Vector2i(-1, -1)
	for r in [0, 1, 2, 3, 4, 5]:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r: continue
				var x := cx + dx
				var y := cz + dz
				if not L.walkable(x, y): continue
				var cp := Vector2(x + 0.5, y + 0.5)
				if cp.distance_to(pad) < 15.0: continue
				var open := 0
				for h: Human in left:
					var hd := cp.distance_to(Vector2(h.px(), h.pz()))
					if hd < 16.0 and not L.line_blocked(h.px(), h.pz(), cp.x, cp.y, 1):
						open += 1 if hd > 8.0 else 3
				var s := float(open) * 10.0 + cp.distance_to(me)
				if s < best:
					best = s
					pick = Vector2i(x, y)
		if best < 10.0:
			break   # нашли закрытую клетку рядом
	roof_cell = pick if pick.x >= 0 else Vector2i(cx, cz)
	return roof_cell


## «--witness» в логове — постановка для видео 0.19.1: ближник отдыхает (фонарь опущен, видит 7 м), ни одного своего
## в 5 м; жертву ставим в 8 м перед ним, героя — за спину жертве. Герой душит, свидетель бежит за своими; бот потом
## 25 с сидит на месте вприсядку — в кадр попадают и беглец, и пришедшие искать.
var wit_state := 0       # 0 — ищем сцену, 1 — душим, 2 — ждём, 3 — дальше как обычно
var wit_t := 0.0
var wit_v: Human = null

func _witness_stage(g: Node, p: Player, dt: float) -> Variant:
	var L: OfficeLevel = g.L
	match wit_state:
		0:
			if now < 2.0:
				return null
			for w: Enemy in g.enemies:
				if not w is Human or w.is_dead() or w.is_hostile() or (w as Human).is_gunner() or w == g.key_holder:
					continue
				var lonely := true
				for o: Enemy in g.enemies:
					if o != w and o is Human and not o.is_dead() and o.dist_to(w) < 5.5:
						lonely = false
				if not lonely:
					continue
				var f := w.facing()
				var w_ang := w.angle
				for dd in [8.0, 8.5, 9.0, 7.5]:
					var c := L.nearest_walkable(floori(w.px() + f.x * dd), floori(w.pz() + f.y * dd), 1)
					if c.x < 0: continue
					var vp := Vector2(c.x + 0.5, c.y + 0.5)
					var hp := vp + f * 1.0   # герой — дальше от свидетеля, за спиной жертвы
					if not L.walkable(floori(hp.x), floori(hp.y)): continue
					if L.line_blocked(w.px(), w.pz(), vp.x, vp.y, 0): continue
					var wpos := Vector2(w.px(), w.pz())
					if vp.distance_to(wpos) < 6.5 or hp.distance_to(wpos) < 7.5: continue
					var v: Human = null
					for o: Enemy in g.enemies:
						if o is Human and o != w and not o.is_dead() and not o.is_down() and o != g.key_holder \
								and (o as Human).can_be_choked() and o.dist_to(w) > 6.0 and (v == null or o.dist_to(w) > v.dist_to(w)):
							v = o
					if v == null: continue
					# свидетель «отдыхает» стоя (фонарь опущен, видит 7 м) лицом к жертве
					var wh := w as Human
					wh._enter_rest()
					wh.rest_kind = "stand"
					wh.rest_len = 40.0
					wh.angle = w_ang
					wh.rotation.y = w_ang
					wh.look_base = w_ang
					v.position = Vector3(vp.x, 0, vp.y)
					v.path = PackedInt32Array()
					v.state = Enemy.S.LOOK
					v.t = 6.0
					v.angle = atan2(-f.x, -f.y)    # смотрит на свидетеля — спиной к герою
					p.position = Vector3(hp.x, 0, hp.y)
					p.crouch = true
					p.angle = atan2(-f.x, -f.y)
					wit_v = v
					wit_state = 1
					wit_t = 0.0
					_say("постановка: свидетель %s в %.1f м" % [w.weapon, v.dist_to(w)])
					return Vector2.ZERO
			return null
		1:
			wit_t += dt
			p.crouch = true
			if p.is_choking() or wit_t > 3.0:
				if p.is_choking():
					_say("душу на глазах у свидетеля")
				wit_state = 2
				wit_t = 0.0
				return Vector2.ZERO
			if is_instance_valid(wit_v) and p.cd <= 0.0 and p.sneak_target() == wit_v:
				choke_lethal = true
				p.melee_hold = true
				p.lock = wit_v
				p.melee()
				p.lock = null
			return Vector2.ZERO
		2:
			wit_t += dt
			p.crouch = true
			if wit_t > 25.0 or p.hp < 60.0:
				wit_state = 3
				p.melee_hold = false
				return null
			if wit_t > 3.5:
				p.melee_hold = false
			return Vector2.ZERO
	return null


## Удушение (0.7): кулак сзади по человеку, который нас не видит; потом он лежит 8 с — добиваем кулаком.
func _choke(p: Player, h: Enemy) -> void:
	var rested: bool = (h as Human).is_resting()
	# 0.16: душим насмерть, если рядом никого (7 м) или это хозяин ключ-карты в логове — очнувшийся доложит своим
	var others := 0
	for o: Enemy in h.game.enemies:
		if o != h and not o.is_dead() and not o.is_down() and p.dist_to(o) < 7.0:
			others += 1
	choke_lethal = others == 0 or h == h.game.key_holder
	p.lock = h
	p.turn_to(p.angle_to_point(h.px(), h.pz()), 10.0)
	p.melee()
	p.lock = null
	_mark(h, "удушение отдыхающего + добил" if rested else "удушение + добил")
	_say("душу human (стиль %s)" % style)


## Обычный зомби (не охотится на нас) в 8 м, видит нас (линия без стен) и смотрит в нашу сторону.
func _zombie_gaze(g: Node, p: Player, L: OfficeLevel, me: Vector2) -> Enemy:
	for e: Enemy in g.enemies:
		if e is Human or e is Clicker or e.is_dead() or e.is_down() or e.is_hostile(): continue
		var d := p.dist_to(e)
		# 0.12: присевшего-замершего на открытом видно с 2.5 м — замирать есть смысл только дальше 3 м
		if d > 8.0 or d < 3.0: continue
		var to_me := Vector2(me.x - e.px(), me.y - e.pz()).normalized()
		if e.facing().dot(to_me) < 0.5: continue
		if L.line_blocked(e.px(), e.pz(), me.x, me.y, 0): continue
		return e
	return null


## 0.13.1: ближайшая проходимая клетка в 3 м, где присевшего от зомби z закрывает мебель.
func _desk_cover(L: OfficeLevel, me: Vector2, z: Enemy) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1e9
	var cx := floori(me.x)
	var cz := floori(me.y)
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var x := cx + dx
			var y := cz + dz
			if not L.walkable(x, y): continue
			if not L.line_blocked(z.px(), z.pz(), x + 0.5, y + 0.5, 1): continue
			var d := Vector2(x + 0.5 - me.x, y + 0.5 - me.y).length()
			if d < bd:
				bd = d
				best = Vector2i(x, y)
	return best


func _behind(p: Player, e: Enemy) -> bool:
	var to_e := Vector2(e.px() - p.px(), e.pz() - p.pz()).normalized()
	return e.facing().dot(to_e) > 0.5


## Что сделать с людьми поблизости, пока они нас не ищут. null — ничего, идём по своим делам.
func _engage(g: Node, p: Player, L: OfficeLevel, me: Vector2) -> Variant:
	if p.hacking:
		return null
	# уже крадёмся к кому-то за спину
	if stalk != null:
		if not is_instance_valid(stalk) or stalk.is_dead() or stalk.is_down() or stalk.is_hostile() or (_loyal(stalk) and stalk != g.key_holder) or now > stalk_t:
			stalk = null
		else:
			var d := p.dist_to(stalk)
			p.crouch = true
			if d < 1.4 and _behind(p, stalk):
				if p.cd <= 0.0:
					# 0.7: удушение бесплатное; нож/топор — в стиле «охотник» иногда сразу насмерть
					var blade := _first(p, ["knife", "axe"])
					if blade != "" and style == "hunter" and randf() < 0.5:
						p.lock = stalk
						p.turn_to(p.angle_to_point(stalk.px(), stalk.pz()), 10.0)
						p.selected = blade
						p.use_item()
						p.lock = null
						_mark(stalk, "подкрался сзади: " + Items.def(blade).name)
						_say("режу сзади: " + Items.def(blade).name)
					elif (stalk as Human).can_be_choked():
						_choke(p, stalk)
				return Vector2.ZERO
			# точка за спиной цели
			var f := stalk.facing()
			var bx := stalk.px() - f.x * 1.0
			var bz := stalk.pz() - f.y * 1.0
			_say("подкрадываюсь сзади к human")
			return g._bot_walk(Vector2i(floori(bx), floori(bz)), 0.6)
	# 0.7: человек нас заметил и растерялся (0.6–0.8 с) — успеть убить до крика
	if p.cd <= 0.0:
		for h: Enemy in g.enemies:
			if not h is Human or h.is_dead() or _loyal(h) or not (h as Human).is_startled(): continue
			var d := p.dist_to(h)
			if L.line_blocked(me.x, me.y, h.px(), h.pz(), 0): continue
			var quick := ""
			for gun in ["silenced", "pistol", "rifle", "uzi", "shotgun"]:
				if p.inv.get(gun, 0) > 0 and d <= float(Items.def(gun).range) * (0.45 if gun == "shotgun" else 0.8):
					quick = gun
					break
			if quick == "" and p.inv.get("shuriken", 0) > 0 and d <= 9.0:
				quick = "shuriken"
			if quick == "": continue
			p.lock = h
			p.selected = quick
			p.use_item()
			p.lock = null
			_mark(h, "пока растерялся: " + Items.def(quick).name)
			_say("успел, пока растерялся: " + Items.def(quick).name)
			return Vector2.ZERO
	if engage_cd > 0.0 or p.cd > 0.0:
		return null
	engage_cd = 0.4
	# варианты: [вес, способ, цель, предмет]
	var opts: Array = []
	var skip_w: float = {"stealth": 3.0, "hunter": 0.6, "trickster": 1.2}[style]
	for h: Enemy in g.enemies:
		if not h is Human or h.is_dead() or h.is_down() or h.is_hostile() or _loyal(h): continue
		var d := p.dist_to(h)
		if d > 16.0: continue
		var los := not L.line_blocked(me.x, me.y, h.px(), h.pz(), 0)
		var behind := _behind(p, h)
		var mates := 0
		for o: Enemy in g.enemies:
			if o != h and o is Human and not o.is_dead() and o.dist_to(h) < 6.0:
				mates += 1
		if los:
			# огнестрел: в спину — всегда насмерть; болтовка — любого
			for gun in ["silenced", "pistol", "uzi", "shotgun"]:
				if p.inv.get(gun, 0) > 0 and d <= float(Items.def(gun).range) * (0.45 if gun == "shotgun" else 0.8):
					if behind:
						opts.append([{"stealth": 2.0, "hunter": 4.0, "trickster": 1.5}[style] * (1.6 if gun == "silenced" else 1.0), "выстрел в спину", h, gun])
					elif mates == 0 and style == "hunter":
						opts.append([1.5, "перестрелка", h, gun])
					break
			if p.inv.get("rifle", 0) > 0 and d <= 20.0:
				opts.append([{"stealth": 1.0, "hunter": 4.0, "trickster": 1.0}[style], "болтовка", h, "rifle"])
			if p.inv.get("grenade", 0) > 0 and d > 5.0 and d <= Player.THROW_RANGE and mates >= 1 and not _loyal_near(g, Vector2(h.px(), h.pz()), 4.0):
				opts.append([3.0, "граната", h, "grenade"])
			if p.inv.get("shuriken", 0) > 0 and d <= 9.0:
				opts.append([{"stealth": 2.0, "hunter": 2.5, "trickster": 1.5}[style], "сюрикен", h, "shuriken"])
			if _first(p, ["knife", "axe"]) != "":
				for kb in ["brick", "extinguisher"]:
					if p.inv.get(kb, 0) > 0 and d <= 8.0 and d > 2.5 and (kb == "brick" or mates >= 1):
						opts.append([1.5, "сбил и добил", h, kb])
						break
		# подкрасться сзади и задушить (0.7) — одиночку или того, чей напарник смотрит в другую сторону
		# 0.8: отдыхающий (оружие за спиной, видит 7 м) — лучшая цель, даже рядом с отрядом,
		# если никто из своих не смотрит в нашу сторону в пределах своего зрения
		var resting := (h as Human).is_resting()
		var partner_blind := true
		for o: Enemy in g.enemies:
			if o == h or not o is Human or o.is_dead() or o.is_down(): continue
			if o.dist_to(h) > (9.0 if resting else 6.0): continue
			var see: float = 7.0 if (o as Human).is_dim() else 11.0
			var to_me := Vector2(me.x - o.px(), me.y - o.pz()).normalized()
			if witness_mode:
				# смотрит в нашу сторону, но нас ещё не разглядит — пусть увидит сам приём
				if (o.facing().dot(to_me) > 0.2 and o.dist_to(p) < see * 0.8) or o.dist_to(p) < 3.0:
					partner_blind = false
			elif (o.facing().dot(to_me) > 0.2 and o.dist_to(p) < see + 2.0) or o.dist_to(p) < 3.0:
				partner_blind = false
		# крыша до вертолёта: из засады — только к тому, кто рядом и стоит к нам спиной (иначе заметят на открытом)
		var ambush_ok: bool = not (g.floor_kind == "roof" and g.heli_phase == "wait") \
			or (behind and d < 9.0 and (h.state != Enemy.S.PATROL or d < 4.0))
		if (h as Human).can_be_choked() and d < 11.0 and partner_blind and ambush_ok and (mates <= 1 or resting or witness_mode):
			var lone := 1.0 if mates == 0 else 0.6
			if resting:
				lone = 1.5
			if witness_mode:
				# свидетель: свой в 6–12 м смотрит на жертву
				for o: Enemy in g.enemies:
					if o != h and o is Human and not o.is_dead() and not o.is_down() and o.dist_to(h) > 6.0 and o.dist_to(h) < 12.0 \
							and o.facing().dot(Vector2(h.px() - o.px(), h.pz() - o.pz()).normalized()) > 0.5:
						lone = 8.0
			opts.append([{"stealth": 4.0, "hunter": 2.0, "trickster": 1.5}[style] * lone, "подкрасться", h, ""])
		# стравить: бутылка/будильник к зомби, который недалеко от людей
		var lure := _first(p, ["bottle", "alarm"])
		if lure != "" and now - lure_t > 20.0:
			for z: Enemy in g.enemies:
				if z is Human or z.is_dead() or z.is_down() or z.hunts_player(): continue
				# 0.9: щелкун рядом с бандитом — бутылку прямо к бандиту: щелкун придёт на звук и схватит его
				if z is Clicker and z.dist_to(h) < 13.0 and (z as Clicker).mode() == "listen" and (z as Clicker).sated_t <= 0.0 \
						and d <= Player.THROW_RANGE and los:
					opts.append([{"stealth": 2.0, "hunter": 1.5, "trickster": 8.0}[style], "стравить со щелкуном", h, lure])
					break
				var zd := p.dist_to(z)
				if zd <= Player.THROW_RANGE and z.dist_to(h) < 9.0 and z.dist_to(h) > 2.0 \
						and not L.line_blocked(me.x, me.y, z.px(), z.pz(), 0):
					opts.append([{"stealth": 1.0, "hunter": 1.0, "trickster": 5.0}[style], "стравить", z, lure])
					break
	if opts.is_empty():
		return null
	opts.append([skip_w, "обойти", null, ""])
	var total := 0.0
	for o in opts: total += float(o[0])
	var r := randf() * total
	var pick: Array = opts[-1]
	for o in opts:
		r -= float(o[0])
		if r <= 0.0:
			pick = o
			break
	var how: String = pick[1]
	if how == "обойти":
		engage_cd = 4.0   # решили не связываться — какое-то время не передумываем
		return null
	var tgt: Enemy = pick[2]
	if how == "подкрасться":
		stalk = tgt
		stalk_t = now + 14.0
		_say("выслеживаю human (стиль %s)" % style)
		return Vector2.ZERO
	var item: String = pick[3]
	p.lock = tgt
	p.selected = item
	p.use_item()
	p.lock = null
	if how.begins_with("стравить"):
		lure_t = now
		engage_cd = 6.0
	else:
		_mark(tgt, how + ": " + Items.def(item).name, 3.6 if item == "grenade" else 0.0)
	_say("%s → %s (%s, стиль %s)" % [how, tgt.type, Items.def(item).name, style])
	return Vector2.ZERO


## Печатаем решение, только когда оно сменилось.
func _say(s: String) -> void:
	var key := s.get_slice(" ", 0)
	if key != mode:
		mode = key
		print("[bot] ", s)
