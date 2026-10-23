class_name Enemy
extends Actor
## Зомби-офисники. Три типа:
##  zombie — «Зомби-менеджер»: медленный, но упорный (долго «чует» игрока после потери из виду);
##  woman  — «Зомби-бухгалтерша»: быстрее, бьёт слабо, но часто;
##  fat    — «Толстяк из продаж»: быстрый и сильный, делает рывки, потом задыхается.
## Фракции: зомби охотятся на игрока И на людей (Human), люди — на зомби и игрока.
## foe — текущая цель (игрок или враг другой фракции).

enum S { WORK, WANDER, LOOK, SUSPICIOUS, INVESTIGATE, CHASE, ATTACK, CHARGE, PANT, KNOCKED, GETUP, DEAD,
	GUARD, PATROL, AIM, RELOAD, STARTLED, CHOKED, STALK, REST, GRAB, FEED }

const TYPES := {
	"zombie": {"name": "Зомби-менеджер", "hp": 100.0, "walk": 0.9, "chase": 2.3, "dmg": 18.0, "windup": 0.45, "cd": 1.3,
		"fov": 100.0, "view": 9.0, "hear": 1.0, "alert_r": 8.0, "track": 2.5, "knock": 1.0, "radius": 0.3, "alertness": 1.0, "snd": "groan"},
	"woman": {"name": "Зомби-бухгалтерша", "hp": 70.0, "walk": 1.2, "chase": 3.8, "dmg": 9.0, "windup": 0.2, "cd": 0.55,
		"fov": 120.0, "view": 10.0, "hear": 1.2, "alert_r": 12.0, "track": 1.5, "knock": 1.0, "radius": 0.28, "alertness": 1.2, "snd": "scream"},
	"fat": {"name": "Толстяк из продаж", "hp": 220.0, "walk": 1.0, "chase": 3.3, "dmg": 34.0, "windup": 0.5, "cd": 1.2,
		"fov": 90.0, "view": 8.0, "hear": 0.8, "alert_r": 6.0, "track": 0.8, "knock": 0.6, "radius": 0.42, "alertness": 0.9, "snd": "roar"},
	# щелкун (0.9): слепой (видит только вплотную), слух ×2, идёт на звук рывками; укус героя 20, бандита — насмерть
	"clicker": {"name": "Щелкун", "hp": 120.0, "walk": 0.8, "chase": 4.0, "dmg": 20.0, "windup": 0.4, "cd": 1.4,
		"fov": 0.0, "view": 1.0, "hear": 1.5, "alert_r": 10.0, "track": 0.0, "knock": 1.0, "radius": 0.3, "alertness": 1.0, "snd": "clicker_scream"},
	# человек: fov/view — это луч фонарика (узкий, но дальний); урон — у оружия (Human.WEAPONS)
	# 0.15: офисник (живой сотрудник) — как человек, своя модель
	"office": {"name": "Офисник", "hp": 100.0, "walk": 1.4, "chase": 3.5, "dmg": 0.0, "windup": 0.3, "cd": 1.0,
		"fov": 46.0, "view": 11.0, "hear": 1.1, "alert_r": 0.0, "track": 2.0, "knock": 0.8, "radius": 0.3, "alertness": 0.8, "snd": "shout"},
	"human": {"name": "Мародёр", "hp": 100.0, "walk": 1.4, "chase": 3.5, "dmg": 0.0, "windup": 0.3, "cd": 1.0,
		"fov": 46.0, "view": 11.0, "hear": 1.1, "alert_r": 0.0, "track": 2.0, "knock": 0.8, "radius": 0.3, "alertness": 0.8, "snd": "shout"},
}

var type := "zombie"
var T: Dictionary
var state: S = S.WANDER
var home_state: S = S.WANDER
var t := 0.0
var susp := 0.0
var path := PackedInt32Array()
var path_i := 0
var path_goal := Vector2i(-1, -1)
var repath_t := 0.0
var target := Vector3.ZERO
var last_seen := Vector3.ZERO
var lost_t := 0.0
var sees := false
var atk_cd := 0.0
var charge_cd := 0.0
var charge_dir := Vector2.ZERO
var knock_t := 0.0
var stagger_t := 0.0
var hot := false
var look_base := 0.0
var perceive_t := 0.0
var icon := ""
var icon_t := 0.0
var velocity := Vector3.ZERO
var work_ang := 0.0
var seed_f := 0.0
var groan_t := 0.0
var view_mult := 1.0
var faction := "zombie"
var foe: Actor = null
var work_pos := Vector3.ZERO   # место за компьютером (работник встаёт размяться и возвращается)
var desk_trip := 0             # 0 — сидит/бродит, 1 — отошёл от стола, 2 — возвращается к столу
var stuck_t := 0.0             # сколько упираемся (в дверях друг в друга)
var stagger_cd := 0.0          # после оглушения кулаком — короткая неуязвимость к новому (нет станлока)
var choked_seated := false     # 0.14: душат/режут сидящего за ПК — поза на стуле
var help_cd := 0.0            # 0.12: сам пришёл на подмогу — 15 с не зовёт других (нет лавины по цепочке)
var punch_n := 0               # 0.12: удары кулаком по толстяку подряд (8 — выбывает на 5 с; после подъёма — заново)
var attn := 1.0                # 0.11: внимательность — постоянная черта (0.65 сонный … 1.35 чуткий)
var search_t := 0.0            # 0.11: ПОИСК — сколько ещё обыскивать район, где цель видели последний раз
var search_pos := Vector3.ZERO # где цель видели последний раз (центр поиска)
const CROUCH_SEE := 5.0        # крадущегося вприсядку по открытому месту видят ближе 5 м (0.12; в 0.11 было 3)
const GLIMPSE_R := 8.0         # 0.13: дальше этого замершего присевшего на открытом не замечают даже краем глаза
const CROUCH_STILL_SEE := 2.5 # 0.12: присевшего неподвижно на открытом месте видят вблизи (прямо перед собой)
const SEARCH_R := 6.0          # радиус обыска вокруг search_pos


func setup(g: Node, level: OfficeLevel, kind: String, pos: Vector3, ang: float, working: bool) -> void:
	type = kind
	T = TYPES[kind]
	init_actor(g, level, kind, pos, ang)
	radius = T.radius
	hp = T.hp
	max_hp = hp
	seed_f = randf() * 100.0
	attn = randf_range(0.65, 1.35)
	view_mult = 1.0 + minf(0.3, level.floor_num * 0.03)
	perceive_t = randf() * 0.1
	groan_t = randf_range(4.0, 12.0)
	work_pos = position
	if working:
		state = S.WORK
		home_state = S.WORK
		work_ang = ang
		t = randf_range(8.0, 30.0)
	else:
		state = S.LOOK
		t = randf_range(0.5, 3.0)


func is_dead() -> bool:
	return state == S.DEAD


func is_down() -> bool:
	return state == S.KNOCKED or state == S.GETUP or state == S.DEAD


func is_hostile() -> bool:
	return state == S.CHASE or state == S.ATTACK or state == S.CHARGE or state == S.PANT \
		or state == S.AIM or state == S.RELOAD


## Охотится именно на игрока (для «ТРЕВОГИ» на экране).
func hunts_player() -> bool:
	return is_hostile() and foe == game.player


static func alive(a: Actor) -> bool:
	if a == null or not is_instance_valid(a):
		return false
	if a is Player:
		var p := a as Player
		return not p.dead and not p.frozen
	return not (a as Enemy).is_dead()


## Враг ли нам этот персонаж.
func is_foe(a: Actor) -> bool:
	if a is Player:
		return true
	return a is Enemy and (a as Enemy).faction != faction


## Текущая цель (если умерла — снова игрок).
func _foe() -> Actor:
	if not alive(foe):
		foe = game.player
	return foe


## Кого высматриваем: игрока и врагов другой фракции поблизости.
func _candidates() -> Array:
	var out: Array = [game.player] if not game.hero_hidden() else []   # 0.20.3/0.21: только приехал или в вентиляции — не замечают
	for e: Enemy in game.enemies:
		if e.faction != faction and not e.is_dead() and absf(e.px() - px()) < 16.0 and absf(e.pz() - pz()) < 16.0:
			out.append(e)
	return out


## Удар по цели: игроку — через game (бессмертие в автотесте и т.п.), остальным — напрямую.
func _hit(a: Actor, dmg: float, kind: String) -> void:
	if kind == "melee" or kind == "bite":
		game.add_noise(0.25)   # драка — в шум этажа (0.10)
	if a is Player:
		game.damage_player(dmg, self)
	elif a is Enemy:
		(a as Enemy).take_damage(dmg, self, kind)


func _set_icon(s: String, dur: float = 1.5) -> void:
	icon = s
	icon_t = dur


# ================================================================ обновление
func update(dt: float) -> void:
	icon_t = maxf(0.0, icon_t - dt)
	if icon_t <= 0.0 and state != S.KNOCKED:
		icon = ""
	atk_cd = maxf(0.0, atk_cd - dt)
	charge_cd = maxf(0.0, charge_cd - dt)
	stagger_cd = maxf(0.0, stagger_cd - dt)
	help_cd = maxf(0.0, help_cd - dt)
	if search_t > 0.0:
		search_t -= dt
		if search_t <= 0.0 and state in [S.LOOK, S.INVESTIGATE, S.SUSPICIOUS]:
			_calm()   # обыскали — никого, успокоились
	var old := position
	match state:
		S.DEAD:
			t += dt
			_animate(dt)
			update_light(dt)
			return
		S.KNOCKED:
			knock_t -= dt
			icon = "z"
			if knock_t <= 0.0:
				state = S.GETUP
				t = 0.9
				icon = ""
		S.GETUP:
			t -= dt
			if t <= 0.0:
				punch_n = 0
				# встал — ищет обидчика там, где тот был (0.12)
				if alive(foe) and foe == game.player:
					_start_search(foe.position)
				else:
					_investigate(position, true)
				susp = 0.6
		S.CHOKED:
			pass   # героя душат — жертва не думает и не видит (длительность ведёт Player)
		_:
			if stagger_t > 0.0:
				stagger_t -= dt
			else:
				perceive_t -= dt
				if perceive_t <= 0.0:
					_perceive(0.1)
					perceive_t = 0.1
				_think(dt)
	velocity = (position - old) / maxf(dt, 0.0001)
	speed_now = Vector2(velocity.x, velocity.z).length()
	walk_phase += speed_now * dt * 3.6
	_ambient_sounds(dt)
	_animate(dt)
	update_light(dt)


func _ambient_sounds(dt: float) -> void:
	groan_t -= dt
	if groan_t <= 0.0:
		groan_t = randf_range(6.0, 14.0)
		if not is_down():
			game.sfx.play_at(T.snd if type != "woman" else "groan", position, game.player.position, 0.35, 12.0)


# ---------------------------------------------------------------- восприятие
## Присел ли персонаж (0.11): герой вприсядку; бандит крадётся / в засаде / сидит на отдыхе / прячется.
static func crouched(a: Actor) -> bool:
	if a is Player:
		return (a as Player).crouch
	if a is Human:
		return (a as Human).is_crouched()
	return false


## Насколько хорошо видим персонажа a (0 — не видим). Люди с фонариками видны всегда как на свету.
## 0.11 — присед, одно правило для героя и бандитов: присевший за мебелью (стол, перегородка) или неподвижный —
## не виден вовсе (только вплотную, ≤ 1 м); крадущийся вприсядку по открытому месту — только ближе CROUCH_SEE.
## Внимательность (attn) меняет дальность ±15%; цель с краю поля зрения видна хуже, чем по центру.
func _see_factor(a: Actor) -> float:
	if a is Player and game.hero_hidden():
		return 0.0   # 0.21: в вентиляции / только приехал
	if not alive(a):
		return 0.0
	var crouch := crouched(a)
	var dx := a.px() - px()
	var dz := a.pz() - pz()
	var d := sqrt(dx * dx + dz * dz)
	# человек в бою (фонарь мечется) виден всегда; спокойный — как все, по освещённости; с опущенным фонарём — хуже
	var vis := L.visibility_at(a.px(), a.pz())
	if a is Human:
		var h := a as Human
		if h.is_hostile():
			vis = 1.0
		elif h.is_dim():
			vis *= 0.25   # фонарь опущен (крадётся / отдыхает); 0.10: было 0.35
		else:
			vis *= 0.6   # отряд зачистки ходит осторожно — зомби замечают его ближе, чем героя
	var alerted := is_hostile() or hot
	var keen := 0.85 + 0.3 * clampf((attn - 0.65) / 0.7, 0.0, 1.0)
	var rng: float = T.view * view_mult * (0.45 + 0.55 * vis) * (1.3 if alerted else 1.0) * keen
	if crouch:
		rng = minf(rng, CROUCH_SEE * keen)
	if d > rng:
		return 0.0
	var ang := absf(wrapf(atan2(dx, dz) - _view_angle(), -PI, PI))
	var half: float = deg_to_rad(T.fov) * 0.5 * (1.3 if alerted else 1.0)
	if ang > half:
		# вне поля зрения «чует» только вплотную (0.12: 1 м / присевшего 0.6 м; было 1.6 / 0.9 — со спины
		# было не подойти на длину захвата, удушение зомби не работало)
		if d > 1.0 or (crouch and d > 0.6):
			return 0.0
	if L.line_blocked(px(), pz(), a.px(), a.pz(), 1 if crouch else 0):
		return 0.0
	if crouch and d > CROUCH_STILL_SEE * keen and a.speed_now < 0.2:
		return 0.0   # присел и замер на открытом месте — виден только вблизи (за мебелью — не виден вовсе, выше)
	var edge := 1.0 if half <= 0.0 else clampf(1.0 - 0.4 * ang / half, 0.6, 1.0)
	return maxf(0.05, (1.0 - d / rng) * edge)


func _view_angle() -> float:
	# сидящий за компьютером смотрит в монитор, иногда оборачивается
	return angle + model.head.rotation.y


func _perceive(dt: float) -> void:
	# лучший видимый кандидат
	var best: Actor = null
	var bf := 0.0
	for a: Actor in _candidates():
		var f := _see_factor(a)
		if f > bf:
			bf = f
			best = a
	if is_hostile():
		# в погоне: держим цель, но переключаемся на заметно более близкую
		var cur := _foe()
		var ff := _see_factor(cur)
		if best != null and best != cur and (ff <= 0.0 or dist_to(best) + 2.0 < dist_to(cur)):
			foe = best
			cur = best
			ff = bf
		sees = ff > 0.0
		if sees:
			last_seen = cur.position
			lost_t = 0.0
		return
	sees = best != null
	if sees:
		foe = best
		last_seen = best.position
		lost_t = 0.0
		# крадущийся бандит (засада, вприсядку, фонарь опущен) замечается медленно — ~2 с пристального взгляда
		var stealth_k := 0.18 if best is Human and (best as Human).is_dim() else 1.0
		# 0.11: замечает быстрее чуткий и если цель движется; стоящую цель — вдвое медленнее
		var move_k := 1.0 if best.speed_now > 0.3 or faction != "zombie" else 0.5   # в луче фонаря — сразу
		susp += dt * (0.8 + 3.0 * bf) * T.alertness * 2.5 * stealth_k * attn * move_k
		if susp > 0.12 and icon == "":
			_set_icon("?", 0.6)   # начинает замечать — «?» над головой (видно, почему тебя заметили)
		if susp >= 1.0:
			alert()
		elif susp > 0.3 and state != S.SUSPICIOUS and state != S.INVESTIGATE:
			state = S.SUSPICIOUS
			t = 0.0
			target = best.position
			_set_icon("?")
		elif state == S.SUSPICIOUS:
			target = best.position
	else:
		# 0.13: герой замер вприсядку на ОТКРЫТОМ месте в поле зрения до ~8 м — не тревога,
		# но «что-то показалось»: подозрение растёт медленно, «?», зомби идёт проверить ТО место (не следит за героем);
		# вблизи (CROUCH_STILL_SEE) — уже тревога обычным путём; ушёл тихо — на месте начнёт поиск.
		var g := _glimpse(game.player) if faction == "zombie" and not game.hero_hidden() else 0.0
		if g > 0.0:
			susp = minf(0.95, susp + dt * (0.25 + 1.5 * g) * T.alertness * attn)
			if susp > 0.12 and icon == "":
				_set_icon("?", 0.8)
			if susp > 0.3 and state in [S.WORK, S.WANDER, S.LOOK]:
				var spot: Vector3 = game.player.position
				_investigate(spot, false)
				search_pos = spot
				search_t = randf_range(12.0, 18.0)   # дойдёт — пусто: обыщет вокруг (LOOK → _search_next)
				if not game.npc_stats.is_empty():
					game.npc_stats.zombie_glimpses += 1
			return
		susp = maxf(0.0, susp - dt * 0.25)


## 0.13: «показалось» — присевший неподвижный герой на открытом месте (не за мебелью), в поле зрения,
## дальше CROUCH_STILL_SEE и ближе GLIMPSE_R. 0 — не видно вовсе. Чем ближе и светлее, тем больше.
func _glimpse(a: Actor) -> float:
	if not alive(a) or not crouched(a) or a.speed_now >= 0.2:
		return 0.0
	var d := dist_to(a)
	var keen := 0.85 + 0.3 * clampf((attn - 0.65) / 0.7, 0.0, 1.0)
	if d > GLIMPSE_R * keen or d <= CROUCH_STILL_SEE * keen:
		return 0.0
	var ang := absf(wrapf(angle_to_point(a.px(), a.pz()) - _view_angle(), -PI, PI))
	if ang > deg_to_rad(T.fov) * 0.5:
		return 0.0
	if L.line_blocked(px(), pz(), a.px(), a.pz(), 1):
		return 0.0   # за столом/шкафом — не видно вовсе
	var vis := L.visibility_at(a.px(), a.pz())
	return (1.0 - d / (GLIMPSE_R * keen)) * (0.45 + 0.55 * vis)


func alert() -> void:
	var was := is_hostile()
	var f := _foe()
	state = S.CHASE
	search_t = 0.0
	susp = 1.0
	hot = true
	_set_icon("!", 2.0)
	lost_t = 0.0
	if not sees:
		last_seen = f.position
	path = PackedInt32Array()
	if not was:
		_on_alert(f)


## Первая тревога: рык и «зов» соседей.
func _on_alert(f: Actor) -> void:
	var lp: Vector3 = game.player.position
	game.sfx.play_at(T.snd, position, lp, 0.9)
	if f is Player:
		game.sfx.play("alert", 0.6)
		game.on_enemy_alert(self)
	game.emit_noise(position, T.alert_r, "alert", false, f.position, self)
	if faction == "zombie" and type != "clicker" and help_cd <= 0.0:
		_call_help(f)


## ТРЕВОГА (0.12): заметивший зовёт 1–3 ближних зомби (в alert_r, не толпу на весь этаж) — они идут туда, где цель,
## и потом ищут ВМЕСТЕ вокруг этого места (каждый своими точками).
func _call_help(f: Actor) -> void:
	var near: Array = []
	for e: Enemy in game.enemies:
		if e == self or e.faction != "zombie" or e.type == "clicker" or e.is_down() or e.is_hostile() or e.state == S.CHOKED:
			continue
		var d := dist_to(e)
		if d < T.alert_r:
			near.append([d, e])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(near.size(), randi_range(1, 3))
	for i in n:
		var z: Enemy = near[i][1]
		z.foe = f
		z.help_cd = 15.0
		z.susp = maxf(z.susp, 0.7)
		z._start_search(f.position)
		z._set_icon("!", 1.2)
	if n > 0 and not game.npc_stats.is_empty():
		game.npc_stats.zombie_helpers += n


## Можно ли задушить / зарезать со спины (0.12): обычный зомби и бухгалтерша, не в тревоге и не видят героя.
## Толстяка и щелкуна — нельзя. У бандитов своя проверка (Human.can_be_choked).
## «Не видит» = ещё не заметил (подозрение не набрано): вплотную зомби героя «чует», но заметить не успевает,
## если тот подошёл со спины (что герой сзади — проверяет Player._is_behind).
func can_be_choked() -> bool:
	return (type == "zombie" or type == "woman") and not is_down() and not is_hostile() and state != S.CHOKED \
		and susp < 0.6


## Героя душат / режут со спины — жертва не думает и не видит (длительность ведёт Player).
func start_choke() -> void:
	state = S.CHOKED
	t = 0.0
	susp = 0.0
	path = PackedInt32Array()
	icon = ""


## Реакция на шум (вызывается из Game.emit_noise).
func hear(pos: Vector3, r: float, kind: String, extra: Vector3) -> void:
	if is_down() or is_hostile() or state == S.CHOKED:
		return
	if kind == "alert" and faction == "zombie":
		return   # 0.12: на тревогу сородича идут 1–3 ближних (_call_help), а не все, кто слышал
	var d := Vector2(pos.x - px(), pos.z - pz()).length()
	var eff: float = r * T.hear
	if L.line_blocked(px(), pz(), pos.x, pos.z, 0):
		eff *= 0.6
	if d > eff:
		return
	match kind:
		"step":
			susp = minf(0.95, susp + 0.35)
			if susp > 0.5:
				_investigate(pos, false)
			else:
				state = S.SUSPICIOUS
				t = 0.0
				target = pos
				_set_icon("?")
		"alert":
			susp = maxf(susp, 0.7)
			_investigate(extra, true)
		"gun", "boom", "shout":
			susp = maxf(susp, 0.8)
			_investigate(pos, true)
		_:
			susp = maxf(susp, 0.5)
			_investigate(pos, false)


## Куда побрести: по своей комнате взад-вперёд (in_room) или подальше; подальше от других, чтобы не сбиваться в толпу.
func _wander_point(in_room: bool) -> Vector3:
	var r := L.room_at(px(), pz())
	var best := Vector3(px(), 0, pz())
	for _try in 8:
		var c := Vector2i(-1, -1)
		if in_room and not r.is_empty():
			var x := randi_range(r.x0, r.x1)
			var z := randi_range(r.z0, r.z1)
			if L.walkable(x, z) and Vector2(x + 0.5 - px(), z + 0.5 - pz()).length() > 2.0:
				c = Vector2i(x, z)
		else:
			c = L.random_reachable(px(), pz(), 5, 14)
		if c.x < 0:
			continue
		best = Vector3(c.x + 0.5, 0, c.y + 0.5)
		if not _crowded(best):
			return best
	return best


func _crowded(p: Vector3) -> bool:
	for e: Enemy in game.enemies:
		if e == self or e.is_dead():
			continue
		if Vector2(e.px() - p.x, e.pz() - p.z).length() < 2.2:
			return true
		if e.path_goal == Vector2i(floori(p.x), floori(p.z)) and not e.path.is_empty():
			return true
	return false


func _investigate(pos: Vector3, is_hot: bool) -> void:
	state = S.INVESTIGATE
	hot = is_hot
	# каждый идёт проверить «рядом с» источником — не стекаются в одну точку
	var c := L.nearest_walkable(floori(pos.x + randf_range(-1.3, 1.3)), floori(pos.z + randf_range(-1.3, 1.3)), 2)
	if c.x >= 0 and not L.line_blocked(pos.x, pos.z, c.x + 0.5, c.y + 0.5, 2):
		pos = Vector3(c.x + 0.5, 0, c.y + 0.5)
	target = pos
	path = PackedInt32Array()
	_set_icon("?", 2.0)


# ---------------------------------------------------------------- поведение
func _think(dt: float) -> void:
	var p := _foe()
	match state:
		S.WORK:
			# сидит, печатает; время от времени оглядывается, иногда встаёт и бродит по комнате
			t -= dt
			if t <= 0.0:
				if randf() < 0.35:
					desk_trip = 1
					state = S.WANDER
					_set_goal(_wander_point(true))
				else:
					t = randf_range(10.0, 25.0)
		S.LOOK:
			t -= dt
			turn_to(look_base + sin(t * 1.6) * 1.2, 2.5 * dt)
			if t <= 0.0 and search_t > 0.0:
				_search_next()   # ПОИСК: осмотрелись — к следующему месту рядом
				return
			if t <= 0.0:
				hot = false
				state = S.WANDER
				if home_state == S.WORK and desk_trip != 0 or (home_state == S.WORK and not hot and randf() < 0.6):
					desk_trip = 2   # пора обратно за компьютер
					_set_goal(work_pos)
				else:
					_set_goal(_wander_point(randf() < 0.55))
		S.WANDER:
			if _follow(T.walk, dt):
				if desk_trip == 2:
					if Vector2(work_pos.x - px(), work_pos.z - pz()).length() < 0.6:
						position = work_pos
						state = S.WORK
						t = randf_range(15.0, 40.0)
						desk_trip = 0
						return
					_set_goal(work_pos)
					if path.is_empty():
						# до стула не дойти — пусть просто бродит
						desk_trip = 0
						home_state = S.WANDER
					return
				state = S.LOOK
				t = randf_range(2.0, 4.5)
				look_base = angle
				hot = false
		S.SUSPICIOUS:
			t += dt
			turn_to(angle_to_point(target.x, target.z), 3.0 * dt)
			if t > 1.2:
				_step_toward(target, T.walk * 0.6, dt)
			if susp < 0.08:
				_calm()
			elif t > 3.0:
				_investigate(target, false)
		S.INVESTIGATE:
			if path.is_empty() or path_goal != Vector2i(floori(target.x), floori(target.z)):
				_set_goal(target)
			var spd: float = T.chase * 0.8 if hot else T.walk * 1.4
			if _follow(spd, dt):
				state = S.LOOK
				t = randf_range(3.0, 5.0) if not hot else randf_range(5.0, 7.0)
				if search_t > 0.0:
					t = randf_range(2.0, 3.5)
				look_base = angle
		S.CHASE:
			_chase(dt)
		S.ATTACK:
			turn_to(angle_to_point(p.px(), p.pz()), 8.0 * dt)
			t -= dt
			if t <= 0.0:
				var d := dist_to(p)
				var a := absf(wrapf(angle_to_point(p.px(), p.pz()) - angle, -PI, PI))
				if d < radius + p.radius + 0.95 and a < 1.25:
					_hit(p, T.dmg, "bite")
				atk_cd = T.cd
				state = S.CHASE
		S.CHARGE:
			t -= dt
			var want: float = 5.8 * dt
			var moved := move(charge_dir.x * want, charge_dir.y * want)
			if dist_to(p) < radius + p.radius + 0.35:
				_hit(p, T.dmg, "bite")
				_pant()
			elif t <= 0.0 or moved < want * 0.4:
				_pant()
		S.PANT:
			t -= dt
			if dist_to(p) > 1.2:
				_step_toward(p.position, 0.8, dt)
			if t <= 0.0:
				state = S.CHASE


func _calm() -> void:
	susp = 0.0
	hot = false
	search_t = 0.0
	state = S.LOOK
	t = randf_range(1.5, 3.0)
	look_base = angle


func _pant() -> void:
	state = S.PANT
	t = 1.6
	charge_cd = 4.0
	game.sfx.play_at("pant", position, game.player.position, 0.6)


func _chase(dt: float) -> void:
	if not alive(foe) and foe != game.player:
		# цель погибла — ищем дальше там, где была
		foe = null
		_investigate(last_seen, true)
		return
	var p := _foe()
	if not alive(p):
		_calm()
		return
	var d := dist_to(p)
	# 0.11: ТРЕВОГА держится, пока видим; потеряли — коротко «чуем» (за угол), потом ПОИСК там, где видели последний раз
	var track: float = minf(T.track, 1.0)
	if sees:
		target = p.position
	else:
		lost_t += dt
		if lost_t < track:
			target = p.position   # успел заметить, куда свернул
		else:
			target = last_seen
		if lost_t > track + 1.5:
			_start_search(last_seen)
			return
	if d < radius + p.radius + 0.75 and sees and atk_cd <= 0.0:
		state = S.ATTACK
		t = T.windup
		return
	if type == "fat" and sees and d > 2.5 and d < 9.0 and charge_cd <= 0.0:
		state = S.CHARGE
		t = 1.6
		charge_dir = Vector2(p.px() - px(), p.pz() - pz()).normalized()
		angle = atan2(charge_dir.x, charge_dir.y)
		rotation.y = angle
		_set_icon("!!", 1.6)
		game.sfx.play_at("roar", position, p.position, 1.0)
		return
	if d < radius + p.radius + 0.5:
		turn_to(angle_to_point(p.px(), p.pz()), 8.0 * dt)
		return
	if sees and d < 6.0 and not L.line_blocked(px(), pz(), p.px(), p.pz(), 2):
		_step_toward(p.position, T.chase, dt)
		path = PackedInt32Array()
	else:
		repath_t -= dt
		var goal := Vector2i(floori(target.x), floori(target.z))
		if path.is_empty() or (repath_t <= 0.0 and goal != path_goal):
			_set_goal(target)
			repath_t = 0.4
		if _follow(T.chase, dt) and not sees and lost_t >= track:
			_start_search(last_seen)


## ПОИСК (0.11): 20–30 с обыскиваем район вокруг места, где цель видели последний раз (не где она сейчас),
## потом успокаиваемся. На экране — «? ПОИСК ?» (hot), если искали героя.
func _start_search(pos: Vector3) -> void:
	search_pos = pos
	search_t = randf_range(20.0, 30.0)
	if not game.npc_stats.is_empty():
		game.npc_stats.zombie_searches += 1
	_investigate(pos, true)


## Следующая точка обыска — рядом с search_pos, куда можно дойти.
func _search_next() -> void:
	for _try in 6:
		var c := L.nearest_walkable(floori(search_pos.x + randf_range(-SEARCH_R, SEARCH_R)),
			floori(search_pos.z + randf_range(-SEARCH_R, SEARCH_R)), 2)
		if c.x >= 0 and Vector2(c.x + 0.5 - px(), c.y + 0.5 - pz()).length() > 1.5:
			state = S.INVESTIGATE
			hot = true
			target = Vector3(c.x + 0.5, 0, c.y + 0.5)
			path = PackedInt32Array()
			return
	_calm()


func _step_toward(pos: Vector3, spd: float, dt: float) -> void:
	var dir := Vector2(pos.x - px(), pos.z - pz())
	var l := dir.length()
	if l < 0.05:
		return
	dir /= l
	var step := minf(spd * dt, l)
	move(dir.x * step, dir.y * step)
	turn_to(atan2(dir.x, dir.y), 7.0 * dt)


func _set_goal(pos: Vector3) -> void:
	path_goal = Vector2i(floori(pos.x), floori(pos.z))
	path = L.find_path(floori(px()), floori(pz()), path_goal.x, path_goal.y, 4000, _low_cost())
	path_i = 0


## 0.14: можно ли идти через LOW (перелезая) и во что это обходится в пути. Зомби — нет (обходят), бандиты — да.
func _low_cost() -> float:
	return -1.0


## 0.14: путь упёрся в LOW-клетку — перелезть (бандиты). true — перелезание началось.
func _vault_path() -> bool:
	path = PackedInt32Array()
	return false


## Срезать угол до точки можно, только если проходит всё тело: луч по центру и два по краям (±радиус).
## Тонкий луч пропускал путь впритирку к столу — персонаж цеплял угол и стоял (0.10).
func _cut_blocked(tx: float, tz: float) -> bool:
	if L.line_blocked(px(), pz(), tx, tz, 2):
		return true
	var d := Vector2(tx - px(), tz - pz())
	if d.length() < 0.01:
		return false
	var n := Vector2(-d.y, d.x).normalized() * radius * 0.9
	return L.line_blocked(px() + n.x, pz() + n.y, tx + n.x, tz + n.y, 2) \
		or L.line_blocked(px() - n.x, pz() - n.y, tx - n.x, tz - n.y, 2)


## Идём по пути; true — дошли (или пути нет).
func _follow(spd: float, dt: float) -> bool:
	if path_i >= path.size():
		return true
	# срезаем углы, если напрямую проходимо
	var skips := 0
	while path_i + 1 < path.size() and skips < 2:
		var nxt := path[path_i + 1]
		if L.cells[path[path_i]] != OfficeLevel.FLOOR or L.cells[nxt] != OfficeLevel.FLOOR \
				or _cut_blocked(nxt % L.W + 0.5, nxt / L.W + 0.5):
			break
		path_i += 1
		skips += 1
	var c := path[path_i]
	if L.cells[c] == OfficeLevel.LOW:
		# 0.14: дальше по пути стол/перегородка — перелезаем (бандиты), когда дошли до края
		if Vector2(c % L.W + 0.5 - px(), c / L.W + 0.5 - pz()).length() < 1.15:
			_vault_path()
			return false
	var tx := c % L.W + 0.5
	var tz := c / L.W + 0.5
	var dir := Vector2(tx - px(), tz - pz())
	var l := dir.length()
	if l < 0.25:
		path_i += 1
		return path_i >= path.size()
	dir /= l
	var step := minf(spd * dt, l)
	var moved := move(dir.x * step, dir.y * step)
	turn_to(atan2(dir.x, dir.y), 7.0 * dt)
	if moved < step * 0.3:
		# упёрлись (в другого в дверях) — шагнём вбок; долго упираемся — уступаем и ищем другой путь
		# вбок — к середине своей клетки (а не всегда в одну сторону: так упирались в угол стола насовсем)
		var mid := Vector2(floori(px()) + 0.5 - px(), floori(pz()) + 0.5 - pz())
		var side := mid.dot(Vector2(-dir.y, dir.x))
		var sgn := (1.0 if side > 0.0 else -1.0) if absf(side) > 0.05 else (1.0 if fmod(seed_f, 2.0) > 1.0 else -1.0)
		move(-dir.y * 0.6 * dt * sgn, dir.x * 0.6 * dt * sgn)
		stuck_t += dt
		if stuck_t > 0.7:
			stuck_t = 0.0
			move(-dir.x * 0.25, -dir.y * 0.25)
			path = PackedInt32Array()
			return not is_hostile()
	else:
		stuck_t = maxf(0.0, stuck_t - dt)
	return false


# ---------------------------------------------------------------- урон
func take_damage(dmg: float, from: Node3D, kind: String) -> void:
	if is_dead():
		return
	if from is Player and (kind == "punch" or kind == "melee"):
		game.add_noise(0.25)   # драка — в шум этажа (0.10)
	hp -= dmg
	flash = 1.0
	game.fx.blood(position + Vector3(0, 1.2, 0), 4)
	if hp <= 0.0:
		die(from)
		return
	# кто ударил — тот и цель (свои не в счёт)
	if from is Actor and from != self and is_foe(from as Actor):
		if not is_hostile() or not sees:
			foe = from as Actor
		last_seen = from.position
	if not is_down() and kind != "sneak" and kind != "friendly":
		alert()   # 0.12.1: задели свои — не тревога (иначе бандит, раненый напарником, бросался на героя)


func stagger(dur: float, from: Vector3) -> void:
	if is_down() or stagger_cd > 0.0: return
	stagger_t = dur
	stagger_cd = 0.9
	var away := Vector2(px() - from.x, pz() - from.z).normalized()
	move(away.x * 0.3, away.y * 0.3)


## exact — длительность ровно dur (удары: кулак 1.2 с, труба 2.5 с, кастет); иначе с поправкой на тип (броски).
func knockdown(dur: float, exact: bool = false) -> void:
	if is_dead(): return
	choked_seated = false   # сползает со стула на пол
	state = S.KNOCKED
	knock_t = dur if exact else dur * T.knock
	susp = 0.0
	hot = false
	icon = "z"
	icon_t = knock_t
	path = PackedInt32Array()


func die(from) -> void:
	state = S.DEAD
	t = 0.0
	icon = ""
	game.on_enemy_killed(self, from)


# ---------------------------------------------------------------- анимация
func _animate(dt: float) -> void:
	var tm := Time.get_ticks_msec() * 0.001 + seed_f
	var p := walk_pose()
	match type:
		"zombie":
			p.arm_l = -1.35 + sin(tm * 2.0) * 0.1
			p.arm_r = -1.3 + sin(tm * 2.3) * 0.1
			p.lean = 0.12
			p.head_roll = 0.25
			p.roll = sin(walk_phase) * 0.06
		"woman":
			p.arm_l = -1.0 + sin(walk_phase) * 0.3
			p.arm_r = -1.0 - sin(walk_phase) * 0.3
			p.lean = 0.2 if speed_now > 2.0 else 0.08
			p.head_roll = -0.2
		"fat":
			p.lean = -0.05
			p.arm_out = 0.35
			p.roll = sin(walk_phase) * 0.08
	match state:
		S.WORK:
			var j := sin(tm * 18.0) * 0.08
			p = {"drop": 0.45, "leg_l": -1.45, "leg_r": -1.45, "knee_l": 1.4, "knee_r": 1.4, "arm_l": -1.2 + j, "arm_r": -1.2 - j, "head_pitch": 0.15}
			# иногда оборачивается от монитора
			var glance := sin(tm * 0.45)
			p.head_yaw = clampf((glance - 0.75) * 6.0, 0.0, 1.3) * (1.0 if fmod(seed_f, 2.0) > 1.0 else -1.0)
			angle = work_ang
			rotation.y = angle
		S.LOOK:
			p.head_yaw = sin(tm * 1.3) * 0.6
		S.ATTACK:
			var k := 1.0 - clampf(t / T.windup, 0.0, 1.0)
			match type:
				"fat":
					p.arm_l = lerpf(-2.8, -0.9, k); p.arm_r = p.arm_l; p.lean = 0.3 * k
				"woman":
					p.arm_r = lerpf(-2.2, -0.6, k)
				_:
					p.arm_l = lerpf(-2.6, -1.2, k); p.arm_r = p.arm_l
		S.CHARGE:
			p.lean = 0.35; p.arm_l = 0.6; p.arm_r = 0.6
		S.PANT:
			p.lean = 0.45; p.head_pitch = 0.3; p.arm_l = -0.3; p.arm_r = -0.3
		S.KNOCKED:
			p = {"fall": -1.5, "arm_l": -2.5, "arm_r": -2.2, "arm_out": 0.5, "leg_l": 0.2, "leg_r": -0.1}
		S.GETUP:
			p = {"fall": -1.5 * clampf(t / 0.9, 0.0, 1.0), "arm_l": -0.5, "arm_r": -0.5}
		S.DEAD:
			p = {"fall": -minf(1.0, t * 3.0) * 1.55, "arm_l": -2.7, "arm_r": -0.4, "arm_out": 0.6, "leg_l": 0.15}
		S.CHOKED:
			# душат / держат со спины: руки к горлу, голова запрокинута, дёргается; к концу обмякает (t — от Player)
			var j := sin(tm * 30.0) * 0.18 * (1.0 - t)
			if choked_seated:
				# 0.14: на стуле через спинку — сидит, руки к горлу, бьётся, к концу обмякает вперёд
				p = {"drop": 0.45, "leg_l": -1.45 + j, "leg_r": -1.45 - j, "knee_l": 1.4, "knee_r": 1.4,
					"arm_l": -2.3 + j, "arm_r": -2.3 - j, "arm_out": 0.2, "head_pitch": lerpf(-0.55, 0.6, t), "lean": lerpf(-0.15, 0.35, t)}
				angle = work_ang
				rotation.y = angle
				model.apply_pose(p)
				return
			p = {"arm_l": -2.3 + j, "arm_r": -2.3 - j, "arm_out": 0.2, "head_pitch": lerpf(-0.55, 0.45, t),
				"lean": lerpf(-0.15, 0.25, t), "leg_l": -0.2 + j, "leg_r": 0.25 - j, "knee_l": 0.3 + 0.6 * t, "knee_r": 0.3 + 0.6 * t,
				"drop": 0.25 * t}
	if stagger_t > 0.0:
		p.lean = -0.35
		p.head_pitch = -0.3
	model.apply_pose(p)
