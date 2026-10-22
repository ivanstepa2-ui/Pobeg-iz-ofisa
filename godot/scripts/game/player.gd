class_name Player
extends Actor
## Александр Вадимович Дзвиник: ходьба/бег/присед, удар, предметы, взлом.

const RUN := 4.6
const WALK := 2.2
const CROUCH := 1.8   # 0.14.2: было 1.5 — крадущиеся бандиты (1.3–1.6) обгоняли; всё ещё медленнее шага (2.2)
const LOCK_RANGE := 24.0   # дальше захват цели сам слетает
const THROW_RANGE := 10.0
const FIST_DMG := 15.0          # 0.12: зомби — 7 ударов, бухгалтерша — 5 (было 20)
const FIST_KNOCK := 1.2
const FIST_DOWN_HUMAN := 50.0   # кулак по лежачему человеку
const FAT_PUNCHES := 8          # 0.12: толстяка кулаком не убить — после 8 ударов подряд выбывает на FAT_KNOCK
const FAT_KNOCK := 5.0
const CHOKE_TIME := 1.0         # захват при удушении (герой на месте и уязвим)
const CHOKE_LONG := 2.0         # 0.12: держишь кнопку дальше — ещё 2 с, и насмерть
const CHOKE_KNOCK := 8.0        # после удушения без сознания
const TAKEDOWN_TIME := 0.45     # 0.12: нож/топор со спины — быстрое убийство (зажал рот, удар, оседает)

var crouch := false
var inv: Dictionary = {}
var selected := ""
var cd := 0.0
var invuln := 0.0
var boost := 0.0
var punch_t := 0.0
var throw_t := 0.0
var shoot_t := 0.0
var hacking := false
var dead := false
var dead_t := 0.0
var step_acc := 0.0
var running := false
var frozen := false     # в катсцене лифта
var lock: Enemy = null  # цель, захваченная тапом (работает и сквозь стены)
var aim_k := 0.0        # 0 — оружие опущено, 1 — на изготовке
var recoil := 0.0
var use_t := 0.0        # анимация лечения
var swing_t := 0.0      # удар ножом/топором
var swing_dur := 0.3
var twist := 0.0        # поворот корпуса к автоцели
var vel2 := Vector2.ZERO  # скорость по полу (для упреждения стрелков)
var choke_t := 0.0        # идёт удушение (сек осталось)
var choke_victim: Enemy = null
var choke_long := false   # 0.12: удушение насмерть (кнопку держали дольше)
var choke_len := CHOKE_TIME
var melee_hold := false   # кнопка УДАР зажата (HUD / клавиша; бот может ставить сам)
var takedown_t := 0.0     # 0.12: идёт быстрое убийство ножом/топором со спины
var takedown_victim: Enemy = null
const GRAB_MOVE := 0.2    # 0.14: приём сбоку — заход за спину
var grab_move_t := 0.0
var grab_from := Vector3.ZERO
var grab_to := Vector3.ZERO
var choke_seated := false # 0.14: жертва сидела за ПК — остаётся на стуле
# 0.14: перелезание через LOW (стол, перегородка, ксерокс, стойка, низкие коробки)
const VAULT_ONE := 0.55   # один блок (тихо — осторожнее: ×1.2; в тревоге — рывок: ×0.85)
const VAULT_CD := 1.5
var vault_t := 0.0
var vault_dur := 0.0
var vault_from := Vector3.ZERO
var vault_to := Vector3.ZERO
var vault_n := 1          # сколько блоков
var vault_loud := false
var vault_cd := 0.0
var vault_was_crouch := false   # 0.14.1: присед до перелезания — вернуть после
var disguised := false    # 0.16: надета куртка бандита (до конца этажа; game.disguise_blown — раскрыт)
var bags := false         # 0.17: пакеты на ногах — шаги и бег бесшумны (до конца этажа)


func setup(g: Node, level: OfficeLevel, pos: Vector3, ang: float) -> void:
	init_actor(g, level, "player", pos, ang)
	radius = 0.3


func reset_for_level(g: Node, level: OfficeLevel, pos: Vector3, ang: float) -> void:
	game = g
	L = level
	position = Vector3(pos.x, 0, pos.z)
	angle = ang
	rotation.y = ang
	crouch = false
	hacking = false
	frozen = false
	cd = 0.0
	invuln = 1.0


# ---------------------------------------------------------------- инвентарь
## Положить в инвентарь не больше потолка (Items.cap). Возвращает, сколько реально взяли.
## Сколько взяли (не больше потолка). 0.13: слот занят ДРУГИМ предметом — не берём (нужна замена, game.do_swap).
func add_item(id: String, n: int) -> int:
	if slot_blocker(id) != "":
		return 0
	var have: int = inv.get(id, 0)
	var take := clampi(Items.cap(id) - have, 0, n)
	if take <= 0:
		return 0
	inv[id] = have + take
	if selected == "" or inv.get(selected, 0) <= 0:
		selected = id
	return take


## 0.13: какой ДРУГОЙ предмет занимает слот предмета id ("" — слот свободен или там тот же предмет).
func slot_blocker(id: String) -> String:
	var s := Items.slot_of(id)
	if s == "":
		return ""
	for other in Items.SLOTS[s]:
		if other != id and inv.get(other, 0) > 0:
			return other
	return ""


## 0.13: что лежит в слоте ("" — пусто).
func slot_item(slot: String) -> String:
	for id in Items.SLOTS.get(slot, []):
		if inv.get(id, 0) > 0:
			return id
	return ""


func owned() -> Array:
	var out: Array = []
	for id in Items.ORDER:
		if inv.get(id, 0) > 0:
			out.append(id)
	return out


func _consume(id: String) -> void:
	inv[id] = inv.get(id, 0) - 1
	if inv[id] <= 0:
		inv.erase(id)
		var o := owned()
		selected = o[0] if o.size() > 0 else ""


# ---------------------------------------------------------------- обновление
## mv — направление в мире (x,z), длина 0..1 (слабо наклонил стик — крадёмся, сильно — бег).
func update(dt: float, mv: Vector2) -> void:
	cd = maxf(0.0, cd - dt)
	invuln = maxf(0.0, invuln - dt)
	boost = maxf(0.0, boost - dt)
	punch_t = maxf(0.0, punch_t - dt)
	throw_t = maxf(0.0, throw_t - dt)
	shoot_t = maxf(0.0, shoot_t - dt)
	use_t = maxf(0.0, use_t - dt)
	swing_t = maxf(0.0, swing_t - dt)
	recoil = maxf(0.0, recoil - dt * 5.0)
	if dead:
		dead_t += dt
		model.apply_pose({"fall": -minf(1.0, dead_t * 2.5) * 1.5, "arm_l": -0.5, "arm_r": -0.3, "arm_out": 0.6})
		model.set_held("")
		update_light(dt)
		return
	vault_cd = maxf(0.0, vault_cd - dt)
	if vault_t > 0.0:
		_update_vault(dt)
		update_light(dt)
		return
	if choke_t > 0.0:
		_update_choke(dt)
		update_light(dt)
		return
	if takedown_t > 0.0:
		_update_takedown(dt)
		update_light(dt)
		return
	# захваченная цель: герой разворачивается к ней и идёт, целясь (стрейф)
	var lk := valid_lock()
	var face_lock := lk != null and can_aim() and not hacking and not frozen
	var old := position
	var mag := minf(1.0, mv.length())
	var speed := 0.0
	running = false
	if not hacking and not frozen and mag > 0.12:
		if crouch: speed = CROUCH
		elif mag > 0.7:
			speed = RUN
			running = true
		else: speed = WALK
		if boost > 0.0: speed *= 1.3
		if punch_t > 0.2: speed *= 0.35
		var dir := mv.normalized()
		var moved := move(dir.x * speed * dt, dir.y * speed * dt)
		speed_now = moved / maxf(dt, 0.0001)
		if not face_lock:
			turn_to(atan2(dir.x, dir.y), 12.0 * dt)
		walk_phase += moved * (3.2 if running else 4.2)
		step_acc += moved
		var stride := 1.5 if running else 1.0
		if step_acc > stride:
			step_acc = 0.0
			var nr := 6.5 if running else (0.0 if crouch else 1.8)
			if bags:
				nr = 0.0   # 0.17: пакеты на ногах — шагов не слышно, даже на бегу
			if nr > 0.0:
				game.emit_noise(position, nr, "step", true)
			game.sfx.play("step", 0.1 if bags else (0.7 if running else (0.15 if crouch else 0.35)))
	else:
		speed_now = 0.0
	vel2 = Vector2(position.x - old.x, position.z - old.z) / maxf(dt, 0.0001)
	if face_lock:
		turn_to(angle_to_point(lk.px(), lk.pz()), 12.0 * dt)
	# на изготовке, когда есть цель (захват или автоприцел) или только что стрелял/бросал
	var tgt: Enemy = null
	if not hacking and not frozen:
		tgt = aim_target(selected)
	var want := 1.0 if tgt != null or shoot_t > 0.0 or throw_t > 0.0 or swing_t > 0.0 else 0.0
	aim_k = move_toward(aim_k, want, dt * 7.0)
	var tw := 0.0
	if tgt != null and tgt != lk:
		tw = clampf(wrapf(angle_to_point(tgt.px(), tgt.pz()) - angle, -PI, PI), -0.9, 0.9)
	twist = lerpf(twist, tw * aim_k, minf(1.0, dt * 10.0))
	_animate()
	update_light(dt)


func can_aim() -> bool:
	return selected != "" and not Items.def(selected).cat in [Items.Cat.HEAL, Items.Cat.SPECIAL]


func _grip() -> String:
	return HeldItems.grip(selected)


func _animate() -> void:
	var p := walk_pose(0.9 if running else 1.0)
	if crouch:
		_crouch_pose(p)
	if running:
		p.lean = 0.15
	p["twist"] = twist
	if hacking:
		var j := sin(Time.get_ticks_msec() * 0.03) * 0.08
		p.arm_l = -1.2 + j
		p.arm_r = -1.2 - j
		p.head_pitch = 0.25
	else:
		_pose_item(p)
	if punch_t > 0.0:
		# рука занята предметом — бьём левой
		var k := sin((1.0 - punch_t / 0.35) * PI)
		var arm := "arm_l" if _hand_busy() else "arm_r"
		p[arm] = lerpf(p[arm], -1.6, k)
		p["out_l" if arm == "arm_l" else "out_r"] = -0.15 * k
		p.lean = p.get("lean", 0.0) + 0.15 * k
	model.apply_pose(p)
	_place_item()


## Присед на корточках, как в Hitman: колени глубоко согнуты, корпус наклонён, голова смотрит вперёд.
## Стоя — асимметрично (одна нога впереди); на ходу — крадущийся шаг с подъёмом колена.
func _crouch_pose(p: Dictionary) -> void:
	var k := clampf(speed_now / CROUCH, 0.0, 1.0)          # 0 — стоит, 1 — идёт
	var s := sin(walk_phase)
	var lift_l := maxf(0.0, -s)                             # нога идёт вперёд — колено поднимается
	var lift_r := maxf(0.0, s)
	var th_l := lerpf(-1.3, -1.0 + s * 0.5, k)
	var th_r := lerpf(-0.55, -1.0 - s * 0.5, k)
	var kn_l := lerpf(1.95, 1.85 + lift_l * 0.35, k)
	var kn_r := lerpf(1.75, 1.85 + lift_r * 0.35, k)
	p["leg_l"] = th_l
	p["leg_r"] = th_r
	p["knee_l"] = kn_l
	p["knee_r"] = kn_r
	# опускаем таз так, чтобы нижняя нога стояла на полу
	var seg: float = model.spec.leg.y / 2
	var h := maxf(seg * (cos(th_l) + cos(th_l + kn_l)), seg * (cos(th_r) + cos(th_r + kn_r)))
	p["drop"] = model.spec.hip - h - 0.03
	p["lean"] = 0.4 + s * 0.03 * k
	p["head_pitch"] = -0.3
	p["arm_l"] = -0.45 + s * 0.15 * k
	p["arm_r"] = -0.4 - s * 0.15 * k
	p["arm_out"] = 0.16


func _hand_busy() -> bool:
	var g := _grip()
	return g != "" and not (g == "rifle" and aim_k < 0.5)


## Прогресс текущего действия предметом (бросок/удар/питьё) 0..1, или -1.
func _act() -> float:
	if throw_t > 0.0: return 1.0 - throw_t / 0.4
	if swing_t > 0.0: return 1.0 - swing_t / swing_dur
	if use_t > 0.0: return 1.0 - use_t / 0.6
	return -1.0


## Стойка под предмет в руках: опущено (aim_k=0) <-> на изготовке (aim_k=1).
func _pose_item(p: Dictionary) -> void:
	CharModel.pose_held(p, selected, aim_k, recoil, _act())


func _place_item() -> void:
	model.place_held(selected, aim_k, recoil, hacking)


func update_light(dt: float) -> void:
	flash = maxf(0.0, flash - dt * 6.0)
	# герой чуть подсвечен даже в темноте, чтобы его было видно на маленьком экране
	var c := L.light_color_at(position.x, position.z)
	c = Color(maxf(c.r, 0.36), maxf(c.g, 0.36), maxf(c.b, 0.34))
	# попал в луч фонарика — подсвечен (и его видно)
	if game.in_flashlight(position):
		c = c.lerp(Color(1.0, 0.92, 0.7), 0.6)
	model.set_light(c, flash)
	model.visible = true if invuln <= 0.0 or dead else (int(invuln * 14.0) % 2 == 0)


# ---------------------------------------------------------------- прицел
## Захваченная цель, если она ещё актуальна (жива и не слишком далеко).
func valid_lock() -> Enemy:
	if lock != null and (not is_instance_valid(lock) or lock.is_dead() or dist_to(lock) > LOCK_RANGE):
		lock = null
	return lock


## Тап по врагу: захватить; тап по уже захваченному — снять захват.
func toggle_lock(e: Enemy) -> void:
	if e == valid_lock() or e.is_dead():
		lock = null
	else:
		lock = e


## На кого полетит предмет id: захваченная цель (даже за стеной) или автоприцел — враг в конусе перед героем.
func aim_target(id: String) -> Enemy:
	if id == "" or Items.def(id).cat in [Items.Cat.HEAL, Items.Cat.SPECIAL]:
		return null
	var lk := valid_lock()
	if lk != null:
		return lk
	var df := Items.def(id)
	if df.cat == Items.Cat.WEAPON:
		return find_target(df.range, 0.9)
	if df.cat == Items.Cat.MELEE:
		return find_target(df.reach + 1.2, 1.0, false)
	if id in Items.HITS_ENEMY:
		return find_target(THROW_RANGE, 0.75)
	return null


# ---------------------------------------------------------------- действия
## Ближайший видимый враг в конусе перед игроком.
func find_target(rng: float, cone: float, standing_only: bool = true) -> Enemy:
	var best: Enemy = null
	var best_s := 1e9
	for e: Enemy in game.enemies:
		if e.is_dead() or (standing_only and e.is_down()) or _friendly(e):
			continue
		var d := dist_to(e)
		if d > rng: continue
		var a := absf(wrapf(angle_to_point(e.px(), e.pz()) - angle, -PI, PI))
		if a > cone: continue
		if L.line_blocked(px(), pz(), e.px(), e.pz(), 0): continue
		var s := d + a * 3.0
		if s < best_s:
			best_s = s
			best = e
	return best


## 0.15: лояльный офисник — не цель для автоприцела и случайного удара (бить его можно только намеренно:
## захватом цели тапом или приёмом со спины).
func _friendly(e: Enemy) -> bool:
	return e is Human and (e as Human).is_loyal()


## Ближайший враг перед героем в пределах reach (или захваченная цель). include_loyal — и лояльных офисников.
func _melee_target(reach: float, include_loyal: bool = false) -> Enemy:
	var target: Enemy = null
	var best := 99.0
	for e: Enemy in game.enemies:
		if e.is_dead() or (not include_loyal and _friendly(e)): continue
		var d := dist_to(e)
		if d > reach + e.radius: continue
		var a := absf(wrapf(angle_to_point(e.px(), e.pz()) - angle, -PI, PI))
		if a > 1.1: continue
		if d < best:
			best = d
			target = e
	var lk := valid_lock()
	if lk != null and dist_to(lk) <= reach + lk.radius:
		target = lk
	return target


func _is_behind(e: Enemy) -> bool:
	return absf(wrapf(e.angle - angle_to_point(e.px(), e.pz()), -PI, PI)) < 1.2


## 0.14: герой в «слепой зоне» цели — вне её поля зрения. Зомби — по его fov (100° / 120°, с поворотом головы);
## бандит — «боковое зрение» 120° (его луч узкий, 46°, — иначе сбоку было бы слишком легко).
func _in_blind_zone(e: Enemy) -> bool:
	var half := deg_to_rad(60.0) if e is Human else deg_to_rad(e.T.fov) * 0.5
	var view: float = e.angle if e is Human else e._view_angle()
	return absf(wrapf(e.angle_to_point(px(), pz()) - view, -PI, PI)) > half


## Кого сейчас можно задушить / зарезать (для подсказки ДУШИТЬ / УБИТЬ на кнопке и для бота).
## 0.14: не только строго со спины — из любой точки вне поля зрения цели (_in_blind_zone), если она героя не заметила.
## Зомби и бухгалтерша; бандит — can_be_choked. Не толстяк и не щелкун.
func sneak_target() -> Enemy:
	if dead or hacking or choke_t > 0.0 or takedown_t > 0.0 or vault_t > 0.0:
		return null
	var e := _melee_target(1.35, true)   # и лояльного офисника — герой волен душить кого захочет
	if e != null and not e.is_down() and _in_blind_zone(e) and e.can_be_choked():
		return e
	return null


## 0.14: приём сбоку — короткий заход за спину (GRAB_MOVE с), потом обычная анимация. Сидящего за ПК — обхват
## через спинку стула (жертва остаётся на стуле, потом сползает на пол).
func _begin_grab(v: Enemy) -> void:
	choke_seated = v.state == Enemy.S.WORK
	v.choked_seated = choke_seated
	var back := Vector2(v.px(), v.pz()) - v.facing() * (0.6 if choke_seated else 0.45)
	grab_from = position
	grab_to = Vector3(back.x, 0, back.y)
	grab_move_t = 0.0
	if L.walkable(floori(back.x), floori(back.y)) and Vector2(back.x - px(), back.y - pz()).length() > 0.15:
		grab_move_t = GRAB_MOVE


## true — ещё заходим за спину (приём не идёт). Жертва пропала — заход прерван (приём сорвётся дальше сам).
func _grab_moving(v, dt: float) -> bool:
	if grab_move_t <= 0.0:
		return false
	if v == null or not is_instance_valid(v):
		grab_move_t = 0.0
		return false
	grab_move_t -= dt
	var k := clampf(1.0 - grab_move_t / GRAB_MOVE, 0.0, 1.0)
	position = grab_from.lerp(grab_to, k)
	angle = lerp_angle(angle, (v as Enemy).angle, k)
	rotation.y = angle
	walk_phase += dt * 9.0
	model.apply_pose({"arm_l": -1.0, "arm_r": -1.0, "lean": 0.25, "drop": 0.15, "knee_l": 0.5, "knee_r": 0.5,
		"leg_l": sin(walk_phase) * 0.5 - 0.3, "leg_r": -sin(walk_phase) * 0.5 - 0.3})
	return true


## Нож или топор в руке — со спины быстрое убийство («УБИТЬ»), иначе удушение («ДУШИТЬ»).
func blade_ready() -> bool:
	return selected in ["knife", "axe"] and inv.get(selected, 0) > 0


func melee() -> void:
	if dead or cd > 0.0 or hacking or choke_t > 0.0 or takedown_t > 0.0 or vault_t > 0.0: return
	cd = 0.45
	punch_t = 0.35
	var target := _melee_target(1.35)
	# со спины по тому, кто не видит: с ножом/топором — быстрое убийство, иначе удушение (почти бесшумно)
	var st := sneak_target()
	if st != null:
		if blade_ready():
			_start_takedown(st, selected)
		else:
			_start_choke(st)
		return
	game.emit_noise(position, 3.5, "step", true)
	if target == null:
		game.sfx.play("whoosh", 0.4)
		return
	turn_to(angle_to_point(target.px(), target.pz()), 10.0)
	game.bandits_locate(position)   # 0.12: драка — громко, бандиты рядом знают, где ты
	# кулак слабый: 15 урона (обычный зомби — 7 ударов, бухгалтерша — 5), без станлока
	if target.is_down():
		# лежачий человек уязвим: 50 урона
		target.take_damage(FIST_DOWN_HUMAN if target is Human else FIST_DMG, self, "punch")
		game.sfx.play("hit", 0.9)
		return
	if target.type == "fat":
		# толстяка кулаком не убить: 8 ударов подряд — выбывает на 5 с, потом ищет обидчика
		target.take_damage(0.0, self, "punch")
		target.punch_n += 1
		if target.punch_n >= FAT_PUNCHES and not target.is_dead():
			target.knockdown(FAT_KNOCK, true)
			game.stats.knockouts += 1
			game.hud.toast("Толстяк выбит из сил!", Color(1, 0.9, 0.4), 1.5)
			game.sfx.play("thud", 0.8)
		else:
			target.stagger(0.15, position)
			game.sfx.play("punch", 0.9)
		return
	var behind := _is_behind(target)
	if not target.is_hostile() and behind and target.type != "fat" and target.type != "clicker":
		# скрытный удар сзади — валит на 1.2 с (толстяка кулаком не свалить)
		target.take_damage(FIST_DMG, self, "sneak")
		if not target.is_dead():
			target.knockdown(FIST_KNOCK, true)
		game.sfx.play("hit", 1.0)
		game.hud.toast("Сбит с ног ударом сзади!", Color(1, 0.9, 0.4), 1.5)
		game.stats.knockouts += 1
	else:
		target.take_damage(FIST_DMG, self, "punch")
		target.stagger(0.15, position)
		game.sfx.play("punch", 0.9)


## Удушение: кулак сзади по человеку, который героя не видит. Захват ~1 с (оба на месте, герой уязвим),
## потом человек без сознания 8 с — можно добить (лежачий уязвим) или уйти. Прочность не тратит, почти бесшумно.
func _start_choke(v: Enemy) -> void:
	choke_victim = v
	choke_t = CHOKE_TIME
	choke_len = CHOKE_TIME
	choke_long = false
	punch_t = 0.0
	_begin_grab(v)
	if grab_move_t <= 0.0:
		angle = angle_to_point(v.px(), v.pz())
		rotation.y = angle
	v.start_choke()
	if v is Human:
		game.hero_violence(v as Human)   # 0.19.1: свои, кто видел, реагируют (бегут за своими / стреляют)
	game.emit_noise(position, 1.0, "step", false, Vector3.ZERO, v)
	game.sfx.play("whoosh", 0.3)


func _update_choke(dt: float) -> void:
	var v := choke_victim
	speed_now = 0.0
	vel2 = Vector2.ZERO
	if _grab_moving(v, dt):
		return
	choke_t -= dt
	if v == null or not is_instance_valid(v) or v.is_dead() or v.state != Enemy.S.CHOKED:
		# жертву убили/вырвали — захват сорван
		choke_t = 0.0
		choke_victim = null
	else:
		# жертва прижата спиной к герою (сидящий — остаётся на стуле, герой за спинкой)
		if not choke_seated:
			var f := facing()
			v.position = Vector3(px() + f.x * 0.45, 0, pz() + f.y * 0.45)
			v.angle = angle
			v.rotation.y = angle
		# для позы жертвы: 0 — только схватили (бьётся), 1 — обмякла
		v.t = (1.0 - choke_t / choke_len) * (1.0 if choke_long else 0.5) + (0.5 if choke_long else 0.0)
		if choke_t <= 0.0:
			var held := melee_hold or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_J)
			if not choke_long and held:
				# кнопку держат — душим дальше, насмерть (ещё 2 с, герой всё так же уязвим)
				choke_long = true
				choke_t = CHOKE_LONG
				choke_len = CHOKE_LONG
				game.hud.toast("Держишь — душишь насмерть…", Color(1, 0.6, 0.4), 1.2)
			elif choke_long:
				v.take_damage(999.0, self, "sneak")
				game.hud.toast("Задушен насмерть", Color(1, 0.6, 0.4), 1.6)
				game.sfx.play("thud", 0.6)
				choke_victim = null
				choke_t = 0.0
			else:
				v.knockdown(CHOKE_KNOCK, true)
				game.stats.knockouts += 1
				game.hud.toast("Задушен — без сознания %d с" % int(CHOKE_KNOCK), Color(1, 0.9, 0.4), 1.6)
				game.sfx.play("thud", 0.5)
				choke_victim = null
				choke_t = 0.0
	# поза: руки сомкнуты на шее жертвы, корпус откинут назад; насмерть — сильнее тянет назад
	var j := sin(Time.get_ticks_msec() * (0.04 if choke_long else 0.025)) * (0.1 if choke_long else 0.06)
	model.apply_pose({"arm_l": -1.85 + j, "arm_r": -1.85 - j, "out_l": -0.55, "out_r": -0.55, "lean": -0.12,
		"head_pitch": 0.15, "leg_l": -0.25, "leg_r": 0.3, "knee_l": 0.35, "knee_r": 0.2, "drop": 0.05})
	model.place_held(selected, 0.0, 0.0, true)


func is_choking() -> bool:
	return choke_t > 0.0


# ---------------------------------------------------------------- 0.14: перелезание
## Куда можно перелезть: герой вплотную к LOW-клетке (стол, перегородка, ксерокс, стойка, низкие коробки — НЕ фикус,
## НЕ шкаф и не стена) и смотрит/идёт на неё; 1 или 2 блока подряд. Приземление — напрямик на обратную сторону;
## занято (стена, персонаж) — ближайшая свободная клетка с той стороны (две равные — случайная). {} — некуда.
## {"to": Vector3, "n": int, "dir": Vector2i}
func vault_target() -> Dictionary:
	if dead or hacking or frozen or choke_t > 0.0 or takedown_t > 0.0 or vault_t > 0.0 or vault_cd > 0.0:
		return {}
	var f := vel2 if vel2.length() > 0.5 else facing()
	var d := Vector2i(signi(roundi(f.x * 1.2)), 0) if absf(f.x) > absf(f.y) else Vector2i(0, signi(roundi(f.y * 1.2)))
	if d == Vector2i.ZERO:
		return {}
	var hc := Vector2i(floori(px()), floori(pz()))
	var c1 := hc + d
	if L.cell(c1.x, c1.y) != OfficeLevel.LOW:
		return {}
	# вплотную к краю: до границы клетки ≤ 0.65
	var edge: float = (c1.x if d.x > 0 else c1.x + 1) if d.x != 0 else (c1.y if d.y > 0 else c1.y + 1)
	var me: float = px() if d.x != 0 else pz()
	if absf(edge - me) > 0.65:
		return {}
	var n := 1
	var last := c1
	if L.cell(c1.x + d.x, c1.y + d.y) == OfficeLevel.LOW:
		n = 2
		last = c1 + d
		if L.cell(last.x + d.x, last.y + d.y) == OfficeLevel.LOW:
			return {}   # три и больше — не перелезть
	var land := last + d
	var cands: Array = [land]
	var perp := Vector2i(d.y, d.x)
	var side: Array = [land + perp, land - perp]
	side.shuffle()
	cands.append_array(side)
	for c in cands:
		if L.walkable(c.x, c.y) and _cell_free(c):
			return {"to": Vector3(c.x + 0.5, 0, c.y + 0.5), "n": n, "dir": d}
	return {}


func _cell_free(c: Vector2i) -> bool:
	var p := Vector2(c.x + 0.5, c.y + 0.5)
	for e: Enemy in game.enemies:
		if not e.is_dead() and Vector2(e.px(), e.pz()).distance_to(p) < 0.55:
			return false
	return true


## Перелезть. Без тревоги (и в ПОИСКЕ) — бесшумно и осторожно (сел на край, перекинул ноги); в ТРЕВОГЕ — быстрый
## рывок-перемах и шум как от ходьбы. Враг, видевший героя, идёт туда, где тот окажется.
func start_vault() -> bool:
	var v := vault_target()
	if v.is_empty():
		return false
	vault_loud = game.any_hostile()
	vault_n = v.n
	vault_dur = VAULT_ONE * vault_n * (0.9 if vault_loud else 1.1)
	vault_t = vault_dur
	vault_from = position
	vault_to = v.to
	angle = atan2(float(v.dir.x), float(v.dir.y))
	rotation.y = angle
	# 0.14.1: лез присевшим — после перелезания снова присел (на столе — виден, это честно)
	vault_was_crouch = crouch
	crouch = false
	if vault_loud and not bags:
		game.emit_noise(position, 2.5, "step", true)
	for e: Enemy in game.enemies:
		if e.foe == self and e.sees and not e.is_down():
			e.last_seen = vault_to
			e.target = vault_to
	return true


func is_vaulting() -> bool:
	return vault_t > 0.0


func _update_vault(dt: float) -> void:
	vault_t -= dt
	speed_now = 0.0
	var k := clampf(1.0 - vault_t / vault_dur, 0.0, 1.0)
	var flat := vault_from.lerp(vault_to, k)
	vel2 = Vector2(vault_to.x - vault_from.x, vault_to.z - vault_from.z) / maxf(vault_dur, 0.01)
	position = Vector3(flat.x, 0, flat.z)
	var p: Dictionary
	var h := 0.0
	if vault_n == 1:
		h = sin(k * PI) * (0.55 if vault_loud else 0.45)
		if k < 0.3:
			# упор руками о край
			p = {"arm_l": -1.25, "arm_r": -1.25, "lean": 0.45, "drop": 0.15, "knee_l": 0.6, "knee_r": 0.6}
		elif k < 0.75:
			# перемах ногами сбоку (как через забор); тихо — сел на край и перекинул ноги
			p = {"arm_l": -1.0, "arm_r": -0.4, "roll": 0.5 if vault_loud else 0.3, "leg_l": -1.3, "leg_r": -1.0,
				"knee_l": 0.9, "knee_r": 0.6, "lean": 0.2, "drop": 0.0 if vault_loud else 0.2}
		else:
			# приземление на обе ноги с лёгким приседом
			p = {"arm_l": -0.6, "arm_r": -0.6, "knee_l": 0.8, "knee_r": 0.8, "leg_l": -0.4, "leg_r": -0.4, "drop": 0.25}
	else:
		# стол из двух клеток: залез на колено → шаг по столу → спрыгнул (тихо — слез, без прыжка)
		h = 0.75 * clampf(k / 0.25, 0.0, 1.0) * clampf((1.0 - k) / 0.25, 0.0, 1.0)
		if k < 0.25:
			p = {"arm_l": -1.1, "arm_r": -1.1, "leg_l": -1.5, "knee_l": 1.6, "leg_r": 0.1, "lean": 0.35, "drop": 0.1}
		elif k < 0.75:
			var w := sin(k * 18.0) * 0.5
			p = {"arm_l": -0.3 - w * 0.4, "arm_r": -0.3 + w * 0.4, "leg_l": w, "leg_r": -w, "knee_l": 0.3, "knee_r": 0.3, "lean": 0.1}
		else:
			p = {"arm_l": -2.0 if vault_loud else -0.8, "arm_r": -2.0 if vault_loud else -0.8, "leg_l": -0.5, "leg_r": -0.3,
				"knee_l": 0.9, "knee_r": 0.7, "drop": 0.2}
	model.position.y = h
	model.apply_pose(p)
	model.place_held(selected, 0.0, 0.0, true)
	if vault_t <= 0.0:
		vault_t = 0.0
		model.position.y = 0.0
		position = vault_to
		vault_cd = VAULT_CD
		crouch = vault_was_crouch


## 0.12: нож/топор со спины — быстрое убийство (~0.45 с): зажал рот, удар, жертва оседает. Тратит удар.
func _start_takedown(v: Enemy, id: String) -> void:
	_consume(id)
	takedown_victim = v
	takedown_t = TAKEDOWN_TIME
	punch_t = 0.0
	swing_t = 0.0
	_begin_grab(v)
	if grab_move_t <= 0.0:
		angle = angle_to_point(v.px(), v.pz())
		rotation.y = angle
	v.start_choke()
	if v is Human:
		game.hero_violence(v as Human)   # 0.19.1: свои, кто видел, реагируют (бегут за своими / стреляют)
	game.emit_noise(position, 1.0, "step", false, Vector3.ZERO, v)
	game.sfx.play("whoosh", 0.35)


func _update_takedown(dt: float) -> void:
	var v := takedown_victim
	speed_now = 0.0
	vel2 = Vector2.ZERO
	if _grab_moving(v, dt):
		return
	takedown_t -= dt
	var k := 1.0 - takedown_t / TAKEDOWN_TIME
	if v == null or not is_instance_valid(v) or v.is_dead() or v.state != Enemy.S.CHOKED:
		takedown_t = 0.0
		takedown_victim = null
	else:
		if not choke_seated:
			var f := facing()
			v.position = Vector3(px() + f.x * 0.45, 0, pz() + f.y * 0.45)
			v.angle = angle
			v.rotation.y = angle
		v.t = k
		if takedown_t <= 0.0:
			v.take_damage(999.0, self, "sneak")
			game.hud.toast("Со спины — насмерть", Items.CAT_COLORS[Items.def(selected if selected != "" else "knife").cat], 1.2)
			game.sfx.play("stab", 1.0)
			takedown_victim = null
			takedown_t = 0.0
	# поза: левая рука зажимает рот, правая с клинком — замах (первая половина) и удар (вторая)
	var stab := clampf((k - 0.45) * 4.0, 0.0, 1.0)
	model.apply_pose({"arm_l": -1.9, "out_l": -0.6, "arm_r": lerpf(-2.6, -1.2, stab), "out_r": -0.25,
		"lean": 0.08, "head_pitch": 0.2, "leg_l": -0.25, "leg_r": 0.3, "knee_l": 0.3, "knee_r": 0.2})
	model.place_held(selected, 0.0, 0.0, false)


func use_item() -> void:
	if dead or cd > 0.0 or hacking or selected == "" or choke_t > 0.0 or takedown_t > 0.0 or vault_t > 0.0: return
	var id := selected
	var df := Items.def(id)
	match df.cat:
		Items.Cat.HEAL:
			hp = minf(max_hp, hp + df.heal)
			if df.has("boost"): boost = df.boost
			game.sfx.play("heal")
			game.hud.toast("%s: +%d здоровья" % [df.name, df.heal], Items.CAT_COLORS[df.cat])
			game.fx.burst(position + Vector3(0, 1.2, 0), Color(0.4, 1, 0.5), 10, 2.0)
			use_t = 0.6
			_consume(id)
			cd = 0.4
		Items.Cat.WEAPON:
			var shots: int = mini(df.get("burst", 1), inv.get(id, 0))
			_shoot(id, df)
			for i in shots - 1:
				# очередь (узи): остальные пули — с небольшим интервалом
				get_tree().create_timer(0.09 * (i + 1), false).timeout.connect(func():
					if not dead and is_inside_tree(): _shoot(id, df))
			for i in shots:
				_consume(id)
			cd = df.cd
		Items.Cat.SPECIAL:
			# 0.16: надеть куртку бандита — до конца этажа (game решает, можно ли сейчас)
			if id == "disguise" and game.wear_disguise():
				_consume(id)
			elif id == "bags":
				game.wear_bags()
				_consume(id)
			cd = 0.5
		Items.Cat.MELEE:
			_swing(id, df)
			cd = df.cd
		_:
			_throw(id)
			_consume(id)
			cd = 0.55


func _shoot(id: String, df: Dictionary) -> void:
	var t := aim_target(id)
	if t != null:
		angle = angle_to_point(t.px(), t.pz())
		rotation.y = angle
	# выстрел без прицеливания — оружие вскидывается мгновенно, без задержки
	shoot_t = 0.6
	aim_k = 1.0
	twist = 0.0
	recoil = 1.0 if id == "shotgun" else 0.7
	_animate()
	var muzzle := position + Vector3(sin(angle) * 0.55, 1.3, cos(angle) * 0.55)
	if model.held != null and model.held_id == id:
		muzzle = model.held.to_global(HeldItems.muzzle(id))
	for i in df.pellets:
		var a: float = angle + randf_range(-df.spread, df.spread)
		var dir := Vector2(sin(a), cos(a))
		var max_t: float = df.range
		# стена
		var wall_t := max_t
		var s := 0.3
		while s < max_t:
			var cx := floori(px() + dir.x * s)
			var cz := floori(pz() + dir.y * s)
			var c := L.cell(cx, cz)
			if c == OfficeLevel.WALL or c == OfficeLevel.TALL:
				wall_t = s
				break
			s += 0.1
		var hit: Enemy = null
		var hit_t := wall_t
		for e: Enemy in game.enemies:
			if e.is_dead(): continue
			var f := Vector2(px() - e.px(), pz() - e.pz())
			var b := f.dot(dir)
			var cc := f.dot(f) - e.radius * e.radius * 1.4
			var disc := b * b - cc
			if disc < 0.0: continue
			var tt := -b - sqrt(disc)
			if tt < 0.0: tt = -b + sqrt(disc)
			if tt > 0.0 and tt < hit_t:
				hit_t = tt
				hit = e
		var end := Vector3(px() + dir.x * hit_t, 1.2, pz() + dir.y * hit_t)
		game.fx.tracer(muzzle, end)
		if hit:
			var fall: float = 1.0 - (hit_t / df.range) * 0.5 if id == "shotgun" else 1.0
			var dmg: float = df.dmg * fall
			# выстрел в спину из огнестрела — всегда насмерть
			if hit.facing().dot(dir) > 0.5 and not hit.is_down():
				dmg = 999.0
				if hit.hp > df.dmg * fall:
					game.hud.toast("Выстрел в спину!", Color(1, 0.4, 0.4), 1.2)
			hit.take_damage(dmg, self, "gun")
			game.fx.blood(end, 6)
		else:
			game.fx.sparks(end)
	game.fx.flash(muzzle)
	game.shake(0.25 if id == "shotgun" else 0.12)
	game.sfx.play(id if id != "pistol" else "gun", 1.0)
	game.emit_noise(position, df.noise, "gun", true)


## Точка броска: цель (захват/автоприцел) или точка перед игроком.
## Бутылка и будильник во врага не попадают — с захватом они летят к нему, чтобы отвлечь именно его.
func throw_target(id: String) -> Dictionary:
	var dist := 7.5
	var dir := facing()
	var t := aim_target(id)
	if t != null:
		if dist_to(t) <= THROW_RANGE:
			return {"pos": Vector3(t.px(), 0, t.pz()), "enemy": t if id in Items.HITS_ENEMY else null}
		# цель дальше броска — кидаем в её сторону насколько хватит
		dir = Vector2(t.px() - px(), t.pz() - pz()).normalized()
		dist = THROW_RANGE
	var s := 0.5
	while s < dist:
		var c := L.cell(floori(px() + dir.x * s), floori(pz() + dir.y * s))
		if c == OfficeLevel.WALL or c == OfficeLevel.TALL:
			break
		s += 0.25
	s = maxf(0.6, s - 0.4)
	return {"pos": Vector3(px() + dir.x * s, 0, pz() + dir.y * s), "enemy": null}


func _throw(id: String) -> void:
	var tg := throw_target(id)
	var target_pos: Vector3 = tg.pos
	if Vector2(target_pos.x - px(), target_pos.z - pz()).length() > 0.3:
		angle = angle_to_point(target_pos.x, target_pos.z)
		rotation.y = angle
	if tg.enemy != null:
		var e: Enemy = tg.enemy
		target_pos += e.velocity * 0.3
	throw_t = 0.4
	aim_k = 1.0
	twist = 0.0
	game.sfx.play("whoosh", 0.6)
	game.spawn_projectile(id, position + Vector3(sin(angle) * 0.4, 1.5, cos(angle) * 0.4), target_pos)


## Удар холодным оружием. Что делает удар сзади/спереди — в Items.DEFS (back/front: kill/knock/dmg).
## Толстяка ударом не свалить (только бросками). Удары (кол-во) тратятся только при попадании.
func _swing(id: String, df: Dictionary) -> void:
	swing_dur = df.swing
	swing_t = swing_dur
	aim_k = 1.0
	var reach: float = df.reach
	var target: Enemy = null
	var best := 99.0
	for e: Enemy in game.enemies:
		if e.is_dead() or _friendly(e): continue
		var d := dist_to(e)
		if d > reach + e.radius: continue
		var a := absf(wrapf(angle_to_point(e.px(), e.pz()) - angle, -PI, PI))
		if a > 1.1: continue
		if d < best:
			best = d
			target = e
	var lk := valid_lock()
	if lk != null and dist_to(lk) <= reach + lk.radius:
		target = lk
	# 0.12: нож/топор со спины по тому, кто не видит, — быстрое убийство с анимацией (почти бесшумно)
	if id in ["knife", "axe"] and target != null and not target.is_down() and _in_blind_zone(target) and target.can_be_choked():
		_start_takedown(target, id)
		return
	game.emit_noise(position, df.noise, "step", df.noise > 2.0)
	if target == null:
		game.sfx.play("whoosh", 0.5)
		return
	_consume(id)
	turn_to(angle_to_point(target.px(), target.pz()), 10.0)
	var behind := absf(wrapf(target.angle - angle_to_point(target.px(), target.pz()), -PI, PI)) < 1.2
	var effect: String = df.back if behind else df.front
	var col: Color = Items.CAT_COLORS[df.cat]
	# лежачего добивают: нож/топор — всех, труба — людей (кастет только вырубает)
	if effect == "kill" or (target.is_down() and (df.back == "kill" or (target is Human and id == "pipe"))):
		target.take_damage(999.0, self, "sneak")
		if behind:
			game.hud.toast("%s: удар сзади — насмерть" % df.name, col, 1.4)
	elif effect == "knock" and target.type != "fat":
		target.take_damage(0.0 if id == "knuckles" else df.dmg * 0.4, self, "sneak")
		if not target.is_dead():
			target.knockdown(df.knock, true)
			game.stats.knockouts += 1
			game.hud.toast("%s: вырубил!" % df.name, col, 1.4)
	else:
		target.take_damage(df.dmg, self, "melee")
		target.stagger(0.5 if id == "axe" else 0.25, position)
	game.sfx.play("hit" if id in ["axe", "pipe", "knuckles"] else "stab", 1.0)


## nonlethal — удар не может добить (болтовка по игроку: сильно ранит, но не убивает).
func hurt(dmg: float, from: Vector3, nonlethal: bool = false) -> void:
	if dead or invuln > 0.0 or frozen: return
	if nonlethal:
		dmg = minf(dmg, maxf(0.0, hp - 1.0))
	hp -= dmg
	invuln = 0.6
	flash = 1.0
	hacking = false
	var away := Vector2(position.x - from.x, position.z - from.z).normalized()
	move(away.x * 0.35, away.y * 0.35)
	game.sfx.play("hurt")
	game.sfx.play("hit", 0.7)
	game.shake(0.3)
	game.hud.damage_flash()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		dead_t = 0.0
		# погиб, держа жертву, — отпускаем её (иначе стоит «задушенной» вечно)
		for v in [choke_victim, takedown_victim]:
			if v != null and is_instance_valid(v) and v.state == Enemy.S.CHOKED:
				v.state = Enemy.S.LOOK
				v.t = 1.0
		choke_t = 0.0
		takedown_t = 0.0
		choke_victim = null
		takedown_victim = null
		game.on_player_dead()


## 0.16: сменить вид героя (куртка бандита — модель «human»; раскрыли/новый этаж — обратно «player»).
func set_look(kind: String) -> void:
	if model.kind == kind:
		return
	var old := model
	model = CharModel.new()
	add_child(model)
	model.setup(kind)
	if bags:
		model.add_bags()
	old.queue_free()
