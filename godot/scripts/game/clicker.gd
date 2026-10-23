class_name Clicker
extends Enemy
## Щелкун (0.9): слепой зомби, который идёт на звук.
##  - Видит только вплотную (~1 м), зато слышит вдвое лучше обычного: бег героя, выстрелы, броски, крики, взлом.
##  - Каждые 3–6 с щёлкает (слышно ~12 м; на экране — волна на радаре и над ним). Бандиты, услышав щелчок
##    рядом, затихают (Human.hear_click).
##  - На звук — рывок 4 м/с на 2.5 с (быстрее шага героя, медленнее бега), потом замирает и слушает.
##  - Добыча вплотную: героя кусает на 20 БЕЗ захвата; бандита хватает за шею (1.2 с, оба на месте) — насмерть.
##    Напарник рядом с 50% отбивает (щелкун падает на 3 с, схваченный выживает раненым).
##  - После убийства 6–8 с ест на месте — окно, чтобы подойти сзади. Найдя добычу, кричит: с шансом 40%
##    подтягивает зомби в радиусе ~10 м.
##  - Убить: сзади нож/топор — насмерть, труба сзади — валит, кулак ничего не делает; 120 hp (пистолет — 3 выстрела).

const RUSH_SPEED := 4.0
const GRAB_TIME := 1.2

var click_t := 0.0
var rush_t := 0.0
var victim: Human = null
var rescue := false
var scream_cd := 0.0
var sated_t := 0.0     # сыт после убийства бандита — 15 с не хватает людей
var lure_t := 0.0      # недавно шёл на шум героя (приманка) — для счётчика humans_by_clicker_lured


func setup_clicker(g: Node, level: OfficeLevel, pos: Vector3, ang: float) -> void:
	setup(g, level, "clicker", pos, ang, false)
	click_t = randf_range(1.0, 5.0)
	state = S.LOOK
	t = randf_range(1.0, 3.0)


## Состояние для бота/HUD: listen — слушает, rush — идёт на звук, grab — держит бандита, feed — ест, bite — кусает.
func mode() -> String:
	match state:
		S.INVESTIGATE: return "rush"
		S.GRAB: return "grab"
		S.FEED: return "feed"
		S.ATTACK: return "bite"
		S.KNOCKED, S.GETUP: return "down"
		S.DEAD: return "dead"
	return "listen"


func is_hostile() -> bool:
	return state == S.ATTACK or state == S.GRAB or (state == S.INVESTIGATE and hot)


func _see_factor(a: Actor) -> float:
	if a is Player and game.hero_hidden():
		return 0.0
	if not alive(a):
		return 0.0
	return 1.0 if dist_to(a) < 1.0 else 0.0


func _perceive(_dt: float) -> void:
	pass   # слепой: добычу «чует» вплотную в _think


func _ambient_sounds(_dt: float) -> void:
	pass   # вместо стонов — щелчки (_think)


## Ударили/подстрелили — идёт туда, откуда ударили (на звук).
func alert() -> void:
	var f := _foe()
	_rush_to(f.position)


func hear(pos: Vector3, r: float, kind: String, _extra: Vector3) -> void:
	if is_down() or state in [S.GRAB, S.FEED, S.ATTACK]:
		return
	var d := Vector2(pos.x - px(), pos.z - pz()).length()
	var eff: float = r * T.hear
	if L.line_blocked(px(), pz(), pos.x, pos.z, 0):
		eff *= 0.7
	if d > eff:
		return
	if game.noise_from_player:
		lure_t = 12.0
	_rush_to(pos)


func _rush_to(pos: Vector3) -> void:
	state = S.INVESTIGATE
	hot = true
	target = pos
	rush_t = 2.5
	path = PackedInt32Array()


func _think(dt: float) -> void:
	scream_cd = maxf(0.0, scream_cd - dt)
	sated_t = maxf(0.0, sated_t - dt)
	lure_t = maxf(0.0, lure_t - dt)
	click_t -= dt
	if click_t <= 0.0 and state != S.FEED:
		click_t = randf_range(3.0, 6.0)
		game.clicker_click(self)
	match state:
		S.GRAB:
			_grab(dt)
			return
		S.FEED:
			t -= dt
			if t <= 0.0:
				state = S.LOOK
				t = randf_range(2.0, 3.0)
				hot = false
			return
		S.ATTACK:
			var p: Player = game.player
			turn_to(angle_to_point(p.px(), p.pz()), 8.0 * dt)
			t -= dt
			if t <= 0.0:
				if dist_to(p) < radius + p.radius + 0.9 and alive(p):
					game.damage_player(T.dmg, self)   # укус без захвата: можно вырваться и бежать
					game.npc_stats.clicker_bites += 1
				atk_cd = T.cd
				state = S.LOOK
				t = 1.5
			return
	# добыча вплотную — хватаем/кусаем (чует, хоть и слепой)
	if atk_cd <= 0.0 and _catch():
		return
	match state:
		S.INVESTIGATE:
			rush_t -= dt
			if path.is_empty() or path_goal != Vector2i(floori(target.x), floori(target.z)):
				_set_goal(target)
			if _follow(RUSH_SPEED if rush_t > 0.0 else T.walk, dt):
				state = S.LOOK
				t = randf_range(2.0, 3.0)   # дошёл — замер и слушает
				hot = false
		S.LOOK:
			t -= dt
			# слушает: голова дёргается
			if t <= 0.0:
				state = S.WANDER
				_set_goal(_wander_point(randf() < 0.6))
		S.WANDER:
			if _follow(T.walk, dt):
				state = S.LOOK
				t = randf_range(2.0, 4.0)
		S.CHASE:
			_rush_to(_foe().position)
		_:
			state = S.LOOK
			t = 2.0


## Добыча в пределах вытянутой руки: бандит — захват за шею, герой — укус.
func _catch() -> bool:
	var p: Player = game.player
	if alive(p) and dist_to(p) < radius + p.radius + 0.7 and not p.is_choking():
		state = S.ATTACK
		t = T.windup
		foe = p
		_scream()
		return true
	if sated_t > 0.0:
		return false   # сыт после убийства — бандитов не хватает
	for e: Enemy in game.enemies:
		if not (e is Human) or e.is_down() or (e as Human).grabbed_by != null:
			continue
		if dist_to(e) < radius + e.radius + 0.7:
			_start_grab(e as Human)
			return true
	return false


func _start_grab(h: Human) -> void:
	victim = h
	h.grabbed_by = self
	state = S.GRAB
	t = GRAB_TIME
	angle = angle_to_point(h.px(), h.pz())
	rotation.y = angle
	_scream()
	game.sfx.play_at("bite", position, game.player.position, 1.0, 20.0)
	# напарник рядом — шанс отбить (50%; с клинком — нож/топор — 70%)
	rescue = false
	for e: Enemy in game.enemies:
		if e is Human and e != h and not e.is_down() and (e as Human).grabbed_by == null and e.dist_to(h) < 2.5:
			rescue = randf() < (0.7 if (e as Human).weapon in ["knife", "axe"] else 0.5)
			break


func _grab(dt: float) -> void:
	var h := victim
	if h == null or not is_instance_valid(h) or h.is_dead():
		victim = null
		state = S.LOOK
		t = 1.0
		return
	t -= dt
	# держим жертву перед собой
	var f := facing()
	h.position = Vector3(px() + f.x * 0.5, 0, pz() + f.y * 0.5)
	h.angle = angle + PI
	h.rotation.y = h.angle
	if rescue and t <= GRAB_TIME * 0.5:
		# напарник ударил щелкуна — тот падает, схваченный вырывается раненым
		h.grabbed_by = null
		victim = null
		h.take_damage(40.0, self, "bite")
		knockdown(3.0, true)
		game.npc_stats.clicker_saves += 1
		game.sfx.play_at("hit", position, game.player.position, 0.9)
		return
	if t <= 0.0:
		h.grabbed_by = null
		victim = null
		h.take_damage(999.0, self, "bite")
		game.npc_stats.clicker_kills += 1
		state = S.FEED
		t = randf_range(6.0, 8.0)
		hot = false
		sated_t = 15.0 + t


## Крик: с шансом 40% подтягивает зомби в радиусе ~10 м (не со всего этажа).
func _scream() -> void:
	if scream_cd > 0.0:
		return
	scream_cd = 8.0
	game.sfx.play_at("clicker_scream", position, game.player.position, 1.0, 26.0)
	if randf() < 0.4:
		game.npc_stats.scream_pulls += 1
		for e: Enemy in game.enemies:
			if e == self or e.faction != "zombie" or e is Clicker or e.is_down() or e.is_hostile():
				continue
			if e.dist_to(self) < T.alert_r:
				e._investigate(position, true)


func knockdown(dur: float, exact: bool = false) -> void:
	if victim != null and is_instance_valid(victim):
		victim.grabbed_by = null
	victim = null
	super.knockdown(dur, exact)


func die(from) -> void:
	if victim != null and is_instance_valid(victim):
		victim.grabbed_by = null
	victim = null
	super.die(from)


func _animate(dt: float) -> void:
	var tm := Time.get_ticks_msec() * 0.001 + seed_f
	var p := walk_pose(1.2 if state == S.INVESTIGATE and rush_t > 0.0 else 1.0)
	match state:
		S.KNOCKED:
			p = {"fall": -1.5, "arm_l": -2.5, "arm_r": -2.2, "arm_out": 0.5}
		S.GETUP:
			p = {"fall": -1.5 * clampf(t / 0.9, 0.0, 1.0), "arm_l": -0.5, "arm_r": -0.5}
		S.DEAD:
			p = {"fall": -minf(1.0, t * 3.0) * 1.55, "arm_l": -2.7, "arm_r": -0.4, "arm_out": 0.6}
		S.GRAB:
			# вцепился в шею: руки на плечах жертвы, голова опущена к шее
			p = {"arm_l": -1.7, "arm_r": -1.7, "out_l": -0.35, "out_r": -0.35, "lean": 0.35, "head_pitch": 0.5,
				"head_roll": 0.3 + sin(tm * 30.0) * 0.08}
		S.FEED:
			# ест: на коленях, сгорбился
			p = {"drop": 0.45, "leg_l": -1.4, "leg_r": -1.4, "knee_l": 2.0, "knee_r": 2.0, "lean": 0.7,
				"arm_l": -1.0 + sin(tm * 9.0) * 0.2, "arm_r": -1.0 - sin(tm * 9.0) * 0.2, "head_pitch": 0.6}
		S.ATTACK:
			var k := 1.0 - clampf(t / T.windup, 0.0, 1.0)
			p.arm_l = lerpf(-2.4, -1.1, k)
			p.arm_r = p.arm_l
			p.lean = 0.4 * k
		_:
			# сгорбленный, руки полусогнуты, голова дёргается (слушает)
			p["lean"] = 0.32
			p["arm_l"] = -0.7 + sin(tm * 2.0) * 0.1
			p["arm_r"] = -0.6 + sin(tm * 2.3) * 0.1
			p["head_yaw"] = sin(tm * 7.0) * 0.25 if state == S.LOOK else 0.0
			p["head_roll"] = 0.35
	model.apply_pose(p)
