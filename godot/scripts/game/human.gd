class_name Human
extends Enemy
## Люди-мародёры («бандиты»): приезжают отрядом на лифте с 3-го этажа (см. game._spawn_squad).
##  - Видят ТОЛЬКО лучом фонарика (узкий конус, но далеко) + чуют вплотную. Игрок видит луч на полу.
##  - Заметив врага (зомби или игрока) — КРИЧАТ: на крик сбегаются до двух напарников… и зомби.
##  - Воюют с зомби и с игроком; умнее зомби: стрелок держит дистанцию, все обыскивают место,
##    где потеряли цель, потом возвращаются к отряду.
##  - Оружие: стрелок (не больше одного в отряде) — узи или болтовка; остальные — нож или пожарный топор.
##  - С трупа падает оружие (лут, которого нет в компьютерах) и всегда что-то ещё (бросок/кофе).
## 0.7 — отряд зачистки: пришли тихо вырезать зомби.
##  - Растерянность (STARTLED): заметив героя, 0.6–0.8 с стоит с «!», разворачивается — ещё не кричит и не бьёт.
##    Убили/вырубили за это время — крика нет. Удар по человеку — сразу бой (без растерянности).
##  - Удушение (CHOKED): герой кулаком сзади по человеку, который его не видит, — захват ~1 с, потом нокаут 8 с.
##  - Пары: основной отряд из 4 — две пары (ведущий с холодным + напарник). Ведущий пары охотится (hunt):
##    подкрадывается к одинокому зомби со спины (STALK) и режет; толстяков и группы обходит.
##    Заметил толстяк/группа — отходит, кричит второй паре; дерётся, если зажали.

## Урон: dmg_p — по игроку, dmg_z — по зомби, dmg_h — по людям другой стороны (0.18.1; нет — как dmg_z).
## Баланс: человек 1 на 1 побеждает обычного зомби,
## но толстяка в одиночку — вряд ли. Пули узи медленные — от очереди можно увернуться бегом.
## Болтовка: долго целится (красный луч), по зомби — насмерть, по игроку — сильно, но не добивает.
const WEAPONS := {
	"knife": {"melee": true, "dmg_p": 13.0, "dmg_z": 26.0, "reach": 0.95, "windup": 0.22, "cd": 0.75},
	"axe": {"melee": true, "dmg_p": 28.0, "dmg_z": 45.0, "reach": 1.1, "windup": 0.5, "cd": 1.35},
	"knuckles": {"melee": true, "dmg_p": 13.0, "dmg_z": 24.0, "reach": 0.85, "windup": 0.18, "cd": 0.7},
	# узи (0.5): быстрее пули, короче прицел, очередь 4–5; перед очередью — щелчок и вспышка (телеграф);
	# перезарядка длинная — окно для игрока
	# 0.12.1: узи точнее (разброс 0.1 → 0.07, упреждение 0.6 → 0.75) — но зигзаг всё ещё спасает
	"uzi": {"melee": false, "dmg_p": 8.0, "dmg_z": 16.0, "aim": 0.35, "lock": 0.12, "lead": 0.75, "burst": 4, "burst_max": 5,
		"gap": 0.09, "cd": 0.85, "mag": 10, "reload": 2.2, "speed": 30.0, "spread": 0.07, "near": 3.0, "far": 8.0, "noise": 14.0},
	# 0.15 — оружие офисников: труба (ближний бой), револьвер, гвоздомёт (очередь гвоздей), арбалет (тихо, мгновенно)
	"pipe": {"melee": true, "dmg_p": 12.0, "dmg_z": 24.0, "reach": 1.0, "windup": 0.3, "cd": 0.85},
	"revolver": {"melee": false, "dmg_p": 26.0, "dmg_z": 70.0, "dmg_h": 40.0, "aim": 0.55, "lock": 0.15, "lead": 0.5, "burst": 1, "gap": 0.0,
		"cd": 1.0, "mag": 6, "reload": 2.6, "speed": 40.0, "spread": 0.03, "near": 3.0, "far": 9.0, "noise": 16.0},
	"nailgun": {"melee": false, "dmg_p": 6.0, "dmg_z": 14.0, "aim": 0.4, "lock": 0.12, "lead": 0.5, "burst": 3, "burst_max": 4,
		"gap": 0.13, "cd": 1.0, "mag": 12, "reload": 2.4, "speed": 24.0, "spread": 0.08, "near": 3.0, "far": 7.0, "noise": 6.0},
	"crossbow": {"melee": false, "dmg_p": 40.0, "dmg_z": 999.0, "dmg_h": 60.0, "aim": 1.0, "lock": 0.25, "lead": 0.0, "burst": 1, "gap": 0.0,
		"cd": 2.0, "mag": 1, "reload": 2.2, "speed": 0.0, "spread": 0.0, "near": 4.0, "far": 12.0, "noise": 2.0},
	# 0.19: M4A1-S элиты — тихая очередь (глушитель), точнее узи
	"m4": {"melee": false, "dmg_p": 9.0, "dmg_z": 30.0, "aim": 0.35, "lock": 0.12, "lead": 0.75, "burst": 3, "burst_max": 4,
		"gap": 0.1, "cd": 0.8, "mag": 15, "reload": 2.4, "speed": 34.0, "spread": 0.045, "near": 3.0, "far": 9.0, "noise": 3.0},
	"rifle": {"melee": false, "dmg_p": 45.0, "dmg_z": 999.0, "aim": 1.2, "lock": 0.28, "lead": 0.0, "burst": 1, "gap": 0.0, "cd": 1.9,
		"mag": 5, "reload": 3.0, "speed": 0.0, "spread": 0.0, "near": 4.5, "far": 13.0, "noise": 20.0},
}
const SHOUT_R := 13.0
const SHOUT_CD := 12.0
const FAN_RAYS := 9

var weapon := "knife"
var W: Dictionary
var squad: Dictionary = {}
var role := "pair"          # guard — сторожит точку отряда; pair — держится рядом; wide — патрулирует шире
var goal_kind := ""         # куда идём: guard / patrol
var shout_cd := 0.0
var ammo := 0
var burst_left := 0
var burst_t := 0.0
var aim_ang := 0.0
var aim_mult := 1.0           # 0.12.1: реакция стрелка (0.7 резкий … 1.15 медлительный), постоянная
var quick_aim := false        # 0.12.1: только что дал очередь по этой цели и видит её — следующая быстрее
var aim_k := 0.0
var recoil := 0.0
var swing_t := 0.0
var fan: MeshInstance3D
var fan_t := 0.0
var lamp: MeshInstance3D
var laser: MeshInstance3D
var calm_t := 0.0
var wait_t := 0.0             # засада: сколько ждём, пока зомби отвернётся
var lunge_t := 0.0            # рывок из засады
var rest_len := 0.0           # пара заняла комнату: сколько отдыхать (0 — отдых отряда, до команды)
var fear_t := 0.0             # недавно слышал щелчки щелкуна рядом — тишина
var grabbed_by: Enemy = null  # схвачен щелкуном
var pair_lead: Human = null   # за кем идёт напарник в паре (null — ведёт сам или идёт за ведущим отряда)
var pair_i := -1              # номер пары в отряде (0.10: маршрут зачистки squad.routes[pair_i])
var stalk: Enemy = null       # зомби, к которому подкрадывается
var door_cell := -1           # засада у двери (0.10): дверь на пути бродячего зомби (-1 — обычная засада)
var door_spot := Vector3.ZERO # где ждать у двери (у стены, сбоку от выхода)
var duo_used := false         # «вдвоём»: напарник уже шумнул в сторону
var stabbing := false         # сейчас режет из засады (для счётчика тихих убийств)
var evade_t := 0.0            # 0.11: уходит от зомби в укрытие (не ввязывается в открытый бой)
var evade_cd := 0.0           # недавно уходил — следующая стычка уже бой
var hide_t := 0.0             # прячется в укрытии вприсядку (зомби не видят за мебелью / неподвижного)
var cover := Vector3.ZERO     # куда бежит прятаться
var skip_z: Enemy = null      # 0.11.1: зомби, засада на которого сорвалась, — к нему пока не возвращаемся
var skip_t := 0.0
var vault_t := 0.0            # 0.14: перелезает через стол/перегородку (в погоне и при обходе)
var vault_dur := 0.5
var vault_from := Vector3.ZERO
var vault_to := Vector3.ZERO
var vault_n := 1
var vault_land := 0           # индекс клетки приземления в path
var hit_by_hero := false      # 0.15: лояльный (офисник / бандит при маскировке) пострадал от героя — очнётся и доложит
var has_key := false          # 0.16: у него ключ-карта логова (зелёная, светится на спине)
var post := Vector3.ZERO      # 0.16: свой пост (охранник логова у комнаты с маскировкой)
var has_post := false
var post_ang := 0.0
var fire_i := -1              # 0.16: у какой бочки греется (≤ 2 у одной)
var angry_t := 0.0            # 0.17: лояльный офисник гонит героя взашей (кража пакетов) — бьёт кулаком, не насмерть
var cheer_t := 0.0            # 0.18: победили на поле битвы — палит в воздух пару секунд
var cheer_shot := 0.0
var loot_pk: Dictionary = {}  # 0.18: за каким стволом идёт после победы
var elite := false             # 0.19: элита из вертолёта (крыша) — hp ×1.5, M4A1-S, маскировку не принимает
var glance_t := 0.0            # 0.19.1: лояльный услышал шаги героя — только повернул голову (~1 с)
var glance_ang := 0.0
var report_t := 0.0            # 0.19.1: свидетель-ближник бежит к своим с криком (не дерётся один)
var report_pos := Vector3.ZERO # где видел героя
var report_ally: Human = null  # к кому бежит
var report_shout := 0.0
var search_pts: Array = []     # 0.19.1: точки обыска вокруг места, где видели героя
var know_t := 0.0           # 0.12: «знает», где герой (громкий шум рядом) — целится/идёт туда, даже не видя
var flank_t := 0.0            # 0.12: обходит с фланга (вторая пара при окружении)
var flank_pos := Vector3.ZERO
var fight_t := 0.0            # 0.11.1: сколько бой идёт без ран (ни мы, ни цель)
var fight_hp := 0.0
var hunt_cd := 0.0            # пауза между охотами (чтобы этаж не пустел слишком быстро)
var hunt_scan := 0.0
var retreat_t := 0.0          # отход от толстяка/группы зомби
var look_amp := 1.0           # 1 — оглядывается; 0.2 — уставился в угол (пауза в патруле)
var _instant_alert := false
var rest_kind := "stand"      # отдых: sit — сидит на полу, lean — прислонился к стене, stand — стоит
var from_rest := false        # растерянность началась с отдыха (вскакивает, выхватывает оружие)
var was_resting := false      # отдыхал (и ещё не вернулся к роли) — даже если уже насторожился
var startle_dur := 0.7
const DIM_VIEW := 7.0         # фонарь опущен — видит и светит только на 7 м
const PLAYER_FOV := 54.0       # 0.16.1: луч бандита против героя шире (46° — против зомби и офисников)
const SHOO_DMG := 6.0         # 0.17: удар кулаком «гонят взашей» (не насмерть)
static var dbg: Dictionary = {}   # счётчики для --aitest (почему охотник не нашёл цель)


func setup_human(g: Node, level: OfficeLevel, pos: Vector3, ang: float, weapon_id: String, sq: Dictionary, r: String, fac: String = "human") -> void:
	# 0.15: fac "office" — офисники (живые сотрудники): та же логика, что у бандитов, но свой вид и лояльность к герою
	setup(g, level, "office" if fac == "office" else "human", pos, ang, false)
	faction = fac
	weapon = weapon_id
	W = WEAPONS[weapon]
	ammo = W.get("mag", 0)
	aim_mult = randf_range(0.7, 1.15)
	squad = sq
	role = r
	view_mult = 1.0
	_build_flashlight()
	_resume_role()


func is_gunner() -> bool:
	return not W.melee


## 0.18.1: урон по цели e — по людям другой стороны свой (dmg_h; у револьвера и арбалета офисников он ниже),
## по зомби — dmg_z. Оружие героя (Items.DEFS) это не трогает.
func dmg_vs(e: Node) -> float:
	return float(W.get("dmg_h", W.dmg_z)) if e is Human else float(W.dmg_z)


## 0.16.1: угол луча против цели a — бандит видит героя шире (PLAYER_FOV), остальных — как раньше.
func fov_vs(a: Actor) -> float:
	return PLAYER_FOV if a is Player and faction == "human" else T.fov


## Ширина нарисованного луча (и подсветки героя в нём) — та, что против героя: игрок видит, где опасно.
func beam_fov() -> float:
	return PLAYER_FOV if faction == "human" else T.fov


# ================================================================ восприятие
## Видим только в луче фонарика (и вплотную — чуем). Темнота не спасает в луче.
func _see_factor(a: Actor) -> float:
	if not alive(a) or is_down():
		return 0.0
	var crouch := a is Player and (a as Player).crouch
	var dx := a.px() - px()
	var dz := a.pz() - pz()
	var d := sqrt(dx * dx + dz * dz)
	# вплотную чует с любой стороны (0.12: 1 м / присевшего 0.6 м; было 1.5 — со спины было не подойти на захват)
	if d < (0.6 if crouch else 1.0):
		return 0.0 if L.line_blocked(px(), pz(), a.px(), a.pz(), 2) else 0.6
	var alerted := is_hostile() or hot
	var rng: float = (DIM_VIEW if is_dim() else T.view) * (1.15 if alerted else 1.0) * (0.85 if crouch else 1.0)
	if d > rng:
		return 0.0
	var ang := absf(wrapf(atan2(dx, dz) - angle, -PI, PI))
	if ang > deg_to_rad(fov_vs(a)) * 0.5 * (1.25 if alerted else 1.0):
		return 0.0
	if L.line_blocked(px(), pz(), a.px(), a.pz(), 1 if crouch else 0):
		return 0.0
	return maxf(0.1, 1.0 - d / rng)


## Точка в луче фонарика? (для подсветки героя)
func lights(p: Vector3) -> bool:
	if is_down():
		return false
	var dx := p.x - px()
	var dz := p.z - pz()
	var d := sqrt(dx * dx + dz * dz)
	if d > (DIM_VIEW if is_dim() else T.view) or d < 0.2:
		return false
	if absf(wrapf(atan2(dx, dz) - angle, -PI, PI)) > deg_to_rad(beam_fov()) * 0.5:
		return false
	return not L.line_blocked(px(), pz(), p.x, p.z, 0)


func hear(pos: Vector3, r: float, kind: String, extra: Vector3) -> void:
	if is_down() or is_hostile() or kind == "shout" or state == S.CHOKED or state == S.STARTLED:
		return   # на крик реагируют через game.human_shout (с ограничением числа бегущих)
	if state == S.STALK and kind != "gun" and kind != "boom":
		return   # в засаде не отвлекается на шорохи
	var d := Vector2(pos.x - px(), pos.z - pz()).length()
	var eff: float = r * T.hear
	if L.line_blocked(px(), pz(), pos.x, pos.z, 0):
		eff *= 0.6
	if d > eff:
		return
	# 0.19.1: лояльный (офисник; бандит, пока герой в куртке) на шаги героя только оглядывается — без «?» и не идёт
	if kind == "step" and game.noise_from_player and is_loyal() and angry_t <= 0.0:
		glance_t = 1.0
		glance_ang = angle_to_point(pos.x, pos.z)
		return
	match kind:
		"step":
			susp = minf(0.9, susp + 0.3)
			if susp > 0.45:
				_investigate(pos, false)
			else:
				state = S.SUSPICIOUS
				t = 0.0
				target = pos
				_set_icon("?")
		"gun", "boom":
			susp = maxf(susp, 0.8)
			_investigate(pos, true)
		"alert":
			_investigate(extra, false)
		_:
			susp = maxf(susp, 0.5)
			_investigate(pos, false)


## 0.14: бандиты перелезают через LOW — в погоне, при обходе с фланга и когда знают, где герой (цена в пути ≈ время).
func _low_cost() -> float:
	return 2.0 if is_hostile() or flank_t > 0.0 or know_t > 0.0 else -1.0


## Путь упёрся в стол/перегородку: перелезаем через 1–2 LOW-клетки подряд на следующую клетку пути.
func _vault_path() -> bool:
	var i := path_i
	var n := 0
	while i < path.size() and L.cells[path[i]] == OfficeLevel.LOW:
		i += 1
		n += 1
	if n == 0 or n > 2 or i >= path.size():
		path = PackedInt32Array()
		return false
	var land: int = path[i]
	vault_n = n
	vault_dur = 0.5 * n
	vault_t = vault_dur
	vault_from = position
	vault_to = Vector3(land % L.W + 0.5, 0, land / L.W + 0.5)
	vault_land = i
	angle = angle_to_point(vault_to.x, vault_to.z)
	rotation.y = angle
	game.npc_stats.bandit_vaults += 1
	return true


func _update_vault(dt: float) -> void:
	vault_t -= dt
	var k := clampf(1.0 - vault_t / vault_dur, 0.0, 1.0)
	var flat := vault_from.lerp(vault_to, k)
	position = Vector3(flat.x, 0, flat.z)
	speed_now = 0.0
	model.position.y = sin(k * PI) * (0.55 if vault_n == 1 else 0.75)
	# быстрый перемах; оружие в руках не убирают
	var p: Dictionary
	if k < 0.3:
		p = {"arm_l": -1.25, "arm_r": -1.25, "lean": 0.45, "drop": 0.15, "knee_l": 0.6, "knee_r": 0.6}
	elif k < 0.75:
		p = {"arm_l": -1.0, "arm_r": -0.6, "roll": 0.5, "leg_l": -1.3, "leg_r": -1.0, "knee_l": 0.9, "knee_r": 0.6, "lean": 0.2}
	else:
		p = {"arm_l": -0.6, "arm_r": -0.6, "knee_l": 0.8, "knee_r": 0.8, "leg_l": -0.4, "leg_r": -0.4, "drop": 0.25}
	model.apply_pose(p)
	model.place_held(weapon, 0.0, 0.0, false)
	if vault_t <= 0.0:
		vault_t = 0.0
		model.position.y = 0.0
		position = vault_to
		path_i = vault_land


## 0.12: громкий шум героя рядом с отрядом — бандит ЗНАЕТ, где герой: сразу в бой (без растерянности);
## flank — обойти с фланга (вторая пара), остальные идут в лоб, стрелок разворачивается и стреляет.
func locate_player(flank: bool) -> void:
	if is_down() or state == S.CHOKED or grabbed_by != null:
		return
	var p: Player = game.player
	foe = p
	last_seen = p.position
	lost_t = 0.0
	know_t = 4.0
	flank_t = 0.0
	if flank:
		var dir := Vector2(p.px() - px(), p.pz() - pz()).normalized()
		var side := Vector2(-dir.y, dir.x) * (1.0 if randf() < 0.5 else -1.0)
		var c := L.nearest_walkable(floori(p.px() + side.x * 4.0), floori(p.pz() + side.y * 4.0), 2)
		if c.x >= 0:
			flank_pos = Vector3(c.x + 0.5, 0, c.y + 0.5)
			flank_t = 7.0
	if not is_hostile():
		_instant_alert = true
		alert()
		_instant_alert = false


## Позвали на помощь (крик напарника).
func respond(shouter: Human) -> void:
	if is_down() or is_hostile():
		return
	if alive(shouter.foe):
		foe = shouter.foe
	_investigate(shouter.position, true)
	_set_icon("!", 1.5)


## Заметил врага — сперва растерянность: вскакивает, разворачивается, выхватывает оружие (0.6–0.8 с,
## с отдыха ~1 с); на героя — с «!», на зомби — без. Потом крик и бой. Удар по нему/зов — сразу бой.
func alert() -> void:
	if report_t > 0.0 and not _instant_alert:
		return   # 0.19.1: бежит за своими — на героя не отвлекается (ударили — тогда дерётся)
	report_t = 0.0
	search_pts.clear()
	if state == S.STARTLED and not _instant_alert:
		return
	if not _instant_alert and not is_hostile():
		from_rest = was_resting
		was_resting = false
		state = S.STARTLED
		startle_dur = 0.9 if from_rest else randf_range(0.5, 0.7)   # 0.16.1: было 1.0 / 0.6–0.8
		t = startle_dur
		susp = 1.0
		path = PackedInt32Array()
		if _foe() is Player:
			_set_icon("!", 1.0)
		return
	super.alert()


## Фонарь опущен: крадётся на зачистке или отдыхает. Луч тусклее и короче, видит сам хуже, зомби замечают плохо.
func is_dim() -> bool:
	return state == S.STALK or state == S.REST or sneaking()


## Крадётся (0.9): пара на зачистке идёт по этажу вприсядку с опущенным фонарём; или рядом щёлкал щелкун.
func sneaking() -> bool:
	if is_hostile() or is_down():
		return false
	if fear_t > 0.0 or hide_t > 0.0:
		return true
	return state in [S.PATROL, S.LOOK] and _pairs_phase() \
		and (role == "hunt" or (role == "follow" and pair_lead != null))


## Отряд разбит на пары: зачистка из лифта (sweep, 0.10) или после отдыха (settled).
func _pairs_phase() -> bool:
	var ph: String = squad.get("phase", "")
	return ph == "settled" or ph == "sweep"


## Пара идёт своим маршрутом зачистки (фаза sweep).
func on_sweep() -> bool:
	return squad.get("phase", "") == "sweep" and pair_i >= 0


## Услышал щелчок щелкуна (game.clicker_click): ~6 с полной тишины — но только если щелкун БЛИЗКО по пути
## (≤ 8 м по прямой и ≤ ~10 клеток пути). Иначе бандиты полэтажа сидели в страхе и не охотились.
func hear_click(pos: Vector3) -> void:
	if is_dead():
		return
	var d := Vector2(pos.x - px(), pos.z - pz()).length()
	if d > 8.0:
		return
	if d > 3.0 and L.line_blocked(px(), pz(), pos.x, pos.z, 2):
		var pth := L.find_path(floori(px()), floori(pz()), floori(pos.x), floori(pos.z), 250)
		if pth.is_empty() or pth.size() > 10:
			return   # за стеной и в обход далеко — не страшно
	fear_t = 6.0


## Присел (0.11, для правила приседа в Enemy._see_factor): крадётся, в засаде, сидит на отдыхе, прячется.
func is_crouched() -> bool:
	if is_down() or is_hostile():
		return false
	return state == S.STALK or sneaking() or hide_t > 0.0 or (state == S.REST and rest_kind == "sit")


func is_resting() -> bool:
	return state == S.REST


## Оружие убрано (за спиной / на поясе) — человек спокоен.
func weapon_stowed() -> bool:
	return state == S.REST or (state == S.STARTLED and from_rest and t > startle_dur * 0.5)


## Кого высматриваем для тревоги: героя и зомби, которые уже в бою или вплотную.
## Спокойных зомби отряд зачистки не «пугается» — их выслеживают и режут со спины (_hunt_scan).
func _candidates() -> Array:
	# 0.15: лояльные офисники героя не высматривают
	var out: Array = [game.player] if is_foe(game.player) else []
	for e: Enemy in game.enemies:
		if e.faction == faction or e.is_dead() or e == stalk:
			continue
		if absf(e.px() - px()) > 16.0 or absf(e.pz() - pz()) > 16.0:
			continue
		# щелкуна замечают всегда (в луче) — чтобы уйти от него, а не ждать, пока схватит;
		# людей другой стороны (бандит ↔ офисник) — всегда (0.15)
		if e.is_hostile() or dist_to(e) < 1.6 or e is Clicker or e is Human:
			out.append(e)
	return out


## 0.15: офисник и герой — свои, пока герой не напал на их группу на глазах (game.office_hostile).
## 0.16: в куртке бандита (game.player_disguised) — свои бандиты (пока не раскрыт), а офисники — враги.
func is_loyal() -> bool:
	if faction == "office":
		return not game.office_hostile and not game.player_disguised()
	return faction == "human" and not elite and game.player_disguised() and not game.disguise_blown


func is_foe(a: Actor) -> bool:
	if a is Player:
		return not is_loyal() or angry_t > 0.0
	return super.is_foe(a)


## Лояльный офисник никогда не берёт героя целью (по умолчанию цель — герой; у них — «никого», бой окончен).
func _loyal_vs_player() -> bool:
	return is_loyal() and angry_t <= 0.0 and (foe == null or foe is Player or not alive(foe))


## Щелкун рядом (≤ 5 м, не ест и не лежит) — тихо отходим от него (вприсядку).
func _avoid_clicker(dt: float) -> bool:
	if is_hostile() or is_down():
		return false
	for e: Enemy in game.enemies:
		if e is Clicker and not e.is_down() and (e as Clicker).mode() != "feed" and dist_to(e) < 5.0:
			fear_t = maxf(fear_t, 3.0)
			_step_away(e, 1.4, dt)
			turn_to(angle_to_point(px() + (px() - e.px()), pz() + (pz() - e.pz())), 6.0 * dt)
			return true
	return false


func is_startled() -> bool:
	return state == S.STARTLED


func take_damage(dmg: float, from: Node3D, kind: String) -> void:
	# 0.15: герой напал на офисника — враждебны, если кто-то из своих видел или раненый в сознании (доложит сразу);
	# вырубленный доложит, когда очнётся (update); убитый тихо и без свидетелей — никто не знает
	if from is Player and is_loyal():
		hit_by_hero = true
		var conscious := hp - dmg > 0.0 and not is_down() and state != S.CHOKED and kind != "sneak"
		if game.loyal_witnessed(self) or conscious:
			game.loyal_betrayed(self, conscious)   # 0.19.1: только видели — реагируют свидетели (hero_violence)
	_instant_alert = true
	super.take_damage(dmg, from, kind)
	_instant_alert = false


## Можно ли задушить: не в тревоге, не растерян (не видит героя), стоит на ногах.
func can_be_choked() -> bool:
	return not is_hostile() and not is_down() and state != S.STARTLED and state != S.CHOKED


func start_choke() -> void:
	# 0.15: душат/режут лояльного — враждебны, если кто-то из своих видит; иначе доложит, когда очнётся
	if is_loyal():
		hit_by_hero = true
		if game.loyal_witnessed(self):
			game.loyal_betrayed(self, false)
	state = S.CHOKED
	t = 0.0
	path = PackedInt32Array()
	icon = ""
	stalk = null


func _on_alert(f: Actor) -> void:
	if f is Player:
		game.on_enemy_alert(self)
	if f is Human:
		# 0.15: увидел человека другой стороны — обе фракции узнают друг о друге, бой
		game.faction_war(self, f as Human)
		_shout()
		return
	# толстяк или группа зомби — сначала отходим (кроме топорщика против обычного зомби)
	if f is Enemy:
		var z := f as Enemy
		if z.type == "clicker":
			retreat_t = 4.0   # со щелкуном не дерёмся — уходим
		elif z.type == "fat" or _zombies_near(z.position, 4.0) >= 2:
			if not (weapon == "axe" and z.type != "fat"):
				retreat_t = 3.0
		else:
			# один обычный зомби (0.11): на зачистке и стрелок — уходят в укрытие и пережидают, если он не вплотную;
			# иначе разбираемся тихо, без крика (крик сзывает толпу)
			if (on_sweep() or is_gunner()) and dist_to(z) > 2.2 and evade_cd <= 0.0:
				_start_evade(z)
			return
	_shout()


## Уйти от зомби в укрытие (0.11): место в 2–8 м, дальше от зомби, закрытое от него мебелью или стеной.
func _start_evade(z: Enemy) -> void:
	evade_t = 6.0
	evade_cd = 12.0
	cover = _cover_from(z)
	path = PackedInt32Array()
	game.npc_stats.bandit_evades += 1


func _cover_from(z: Enemy) -> Vector3:
	var best := Vector3.ZERO
	var bs := 1e9
	var dz0 := dist_to(z)
	for _try in 28:
		var x := floori(px()) + randi_range(-7, 7)
		var y := floori(pz()) + randi_range(-7, 7)
		if not L.walkable(x, y):
			continue
		var p := Vector3(x + 0.5, 0, y + 0.5)
		var dme := Vector2(p.x - px(), p.z - pz()).length()
		if dme < 2.0 or dme > 8.0:
			continue
		if Vector2(p.x - z.px(), p.z - z.pz()).length() < dz0 + 1.0:
			continue   # не навстречу зомби
		if not L.line_blocked(z.px(), z.pz(), p.x, p.z, 1):
			continue   # зомби увидит и присевшего
		var s := dme
		for k in 4:
			if L.cell(x + OfficeLevel.DX[k], y + OfficeLevel.DZ[k]) == OfficeLevel.LOW:
				s -= 1.5   # прямо за столом — лучше
		if s < bs:
			bs = s
			best = p
	if best == Vector3.ZERO:
		var away := Vector2(px() - z.px(), pz() - z.pz()).normalized() * 5.0
		var c := L.nearest_walkable(floori(px() + away.x), floori(pz() + away.y), 3)
		best = Vector3(c.x + 0.5, 0, c.y + 0.5) if c.x >= 0 else position
	return best


## Сколько зомби рядом с целью могут заметить подкрадывающегося (сидящие за ПК не считаются).
func _watchers_near(z: Enemy) -> int:
	var n := 0
	for e: Enemy in game.enemies:
		if e == z or e.faction != "zombie" or e.is_down() or e.state == S.WORK:
			continue
		if e.dist_to(z) < 4.0:
			n += 1
	return n


func _zombies_near(p: Vector3, r: float) -> int:
	var n := 0
	for e: Enemy in game.enemies:
		if e.faction == "zombie" and not e.is_down() and Vector2(e.px() - p.x, e.pz() - p.z).length() < r:
			n += 1
	return n


func _shout() -> void:
	if shout_cd > 0.0:
		return
	if fear_t > 0.0:
		# рядом щелкун — не кричим, молча зовём напарника
		shout_cd = SHOUT_CD
		_set_icon("!", 1.5)
		if pair_lead != null and alive(pair_lead):
			pair_lead.respond(self)
		else:
			for m in squad.get("members", []):
				var h := m as Human
				if h != null and h != self and h.pair_lead == self and alive(h):
					h.respond(self)
		return
	game.npc_stats.stealth_breaks += 1
	shout_cd = SHOUT_CD
	_set_icon("!", 2.0)
	game.sfx.play_at("shout", position, game.player.position, 1.0, 24.0)
	game.human_shout(self)


# ================================================================ поведение
func update(dt: float) -> void:
	shout_cd = maxf(0.0, shout_cd - dt)
	recoil = maxf(0.0, recoil - dt * 5.0)
	swing_t = maxf(0.0, swing_t - dt)
	hunt_cd = maxf(0.0, hunt_cd - dt)
	evade_cd = maxf(0.0, evade_cd - dt)
	skip_t = maxf(0.0, skip_t - dt)
	know_t = maxf(0.0, know_t - dt)
	glance_t = maxf(0.0, glance_t - dt)
	if report_t > 0.0 and not is_dead() and not is_down() and state != S.CHOKED and vault_t <= 0.0:
		_report(dt)
	if cheer_t > 0.0 and not is_down() and not is_hostile():
		# 0.18: салют победы — короткие выстрелы вверх (стрелок) раз в ~0.3 с, потом осматривать этаж
		cheer_t -= dt
		cheer_shot -= dt
		aim_k = 1.0
		if cheer_shot <= 0.0 and is_gunner():
			cheer_shot = randf_range(0.22, 0.4)
			recoil = 1.0
			game.fx.flash(muzzle())
			game.sfx.play_at(weapon, position, game.player.position, 0.8, 30.0)
			game.emit_noise(position, W.noise, "gun", true, Vector3.ZERO, self)
	if angry_t > 0.0:
		# гонит, пока герой рядом; ушёл дальше 10 м — остывает втрое быстрее
		angry_t -= dt * (3.0 if dist_to(game.player) > 10.0 else 1.0)
		if angry_t <= 0.0 and foe == game.player and is_loyal():
			foe = null
			hot = false
			_resume_role()
	if hit_by_hero and is_loyal() and not is_dead() and not is_down() \
			and state != S.CHOKED:
		game.loyal_betrayed(self)   # очнулся — доложил своим
	if has_key and (is_dead() or is_down()):
		game.drop_keycard(self)   # 0.16: упал (убит/вырублен/задушен) — ключ-карта на полу
	hide_t = maxf(0.0, hide_t - dt)
	fear_t = maxf(0.0, fear_t - dt)
	if fear_t > 0.0:
		game.npc_stats.fear_time += dt
	if vault_t > 0.0 and not is_down() and grabbed_by == null and state != S.CHOKED:
		_update_vault(dt)
		_update_flashlight(dt)
		update_light(dt)
		return
	if grabbed_by != null:
		# схвачен щелкуном — не двигается (ведёт Clicker)
		_animate(dt)
		update_light(dt)
		_update_flashlight(dt)
		return
	var was_stalk := state == S.STALK
	super.update(dt)
	if was_stalk and state != S.STALK and stalk != null:
		var key: String = "выход из засады → " + S.keys()[state]
		dbg[key] = dbg.get(key, 0) + 1
		stalk = null
	# вне боя перевязываются: через 5 с спокойствия +3 hp/с (отряд не тает от случайных стычек с зомби)
	if is_hostile() or is_down():
		calm_t = 0.0
	else:
		calm_t += dt
		if calm_t > 5.0 and not is_dead():
			hp = minf(max_hp, hp + 3.0 * dt)
	aim_k = move_toward(aim_k, 1.0 if is_hostile() or cheer_t > 0.0 else 0.0, dt * 5.0)
	_update_flashlight(dt)
	_update_laser()


## Болтовка целится — виден красный луч (предупреждение игроку: уйди с линии).
func _update_laser() -> void:
	if weapon != "rifle":
		return
	if laser == null:
		laser = MeshInstance3D.new()
		laser.top_level = true
		laser.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 0.15, 0.1)
		laser.material_override = m
		add_child(laser)
	var on := state == S.AIM and burst_left <= 0 and not is_down()
	laser.visible = on
	if not on:
		return
	var dir := Vector2(sin(aim_ang), cos(aim_ang))
	var s := 0.3
	while s < 26.0:
		var c := L.cell(floori(px() + dir.x * s), floori(pz() + dir.y * s))
		if c == OfficeLevel.WALL or c == OfficeLevel.TALL:
			break
		s += 0.2
	var im: ImmediateMesh = laser.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(muzzle())
	im.surface_add_vertex(Vector3(px() + dir.x * s, 1.2, pz() + dir.y * s))
	im.surface_end()


func _ambient_sounds(_dt: float) -> void:
	pass


## Свой фонарик немного освещает и самого человека — его видно в темноте.
func update_light(dt: float) -> void:
	flash = maxf(0.0, flash - dt * 6.0)
	var c := L.light_color_at(position.x, position.z)
	model.set_light(Color(maxf(c.r, 0.42), maxf(c.g, 0.4), maxf(c.b, 0.36)), flash)


func _think(dt: float) -> void:
	if state in [S.PATROL, S.LOOK, S.GUARD, S.REST, S.SUSPICIOUS, S.INVESTIGATE] and _avoid_clicker(dt):
		if state == S.REST:
			_resume_role()
		return
	match state:
		S.STARTLED:
			# растерялся: разворачивается к герою, но ещё не кричит и не бьёт
			if _loyal_vs_player():
				_resume_role()
				return
			var fs := _foe()
			turn_to(angle_to_point(fs.px(), fs.pz()), 6.0 * dt)
			t -= dt
			if t <= 0.0:
				_instant_alert = true
				alert()
				_instant_alert = false
		S.STALK:
			_stalk(dt)
		S.REST:
			# отдыхает: оружие убрано, фонарь опущен; изредка поворачивает голову (поворот корпуса — чуть-чуть)
			t += dt
			if rest_kind == "stand":
				turn_to(look_base + sin(t * 0.35) * 0.5, 0.8 * dt)
			if rest_len > 0.0 and t > rest_len:
				rest_len = 0.0
				_resume_role()
		S.GUARD:
			t += dt
			turn_to(look_base + sin(t * 0.7) * 1.1, 2.0 * dt)
		S.PATROL:
			if goal_kind == "follow":
				_follow_leader(dt)
			else:
				if role == "hunt":
					_hunt_scan(dt)
					if state != S.PATROL:
						return
				if _follow(1.3 if sneaking() else T.walk, dt):
					if goal_kind == "sweep":
						# дошли до комнаты маршрута — она зачищена, оглядываемся и идём к следующей
						var rt: Array = squad.routes[pair_i]
						if not rt.is_empty():
							rt.remove_at(0)
						_look_pause()
						return
					if goal_kind == "meet":
						# пришли к стартовому лифту — ждём вторую пару (отдых без срока, до game.squad_meet)
						_enter_rest()
						rest_len = 0.0
						goal_kind = "meet"
						return
					# пара на зачистке иногда занимает комнату и отдыхает в ней 15–40 с
					if role == "hunt" and goal_kind == "patrol" and randf() < 0.25:
						_enter_rest()
						rest_len = randf_range(15.0, 40.0)
						return
					match goal_kind:
						"guard":
							state = S.GUARD
							t = 0.0
							look_base = post_ang if has_post else angle
							return
						"loot":
							game.battle_take(self)
							return
						"post":
							_post_arrive()
							return
						"lair_fire", "lair_pee":
							_lair_arrive()
							return
						"rest":
							_enter_rest()
							return
						"dest":
							if squad.get("phase", "") == "travel":
								# пришли занимать комнату — отряд решает, как дальше патрулировать
								game.squad_arrived(squad)
								return
					_look_pause()
		S.LOOK:
			t -= dt
			turn_to(look_base + sin(t * 1.4) * look_amp, 2.5 * dt)
			if role == "hunt":
				_hunt_scan(dt)
				if state != S.LOOK:
					return
			if t <= 0.0:
				if not search_pts.is_empty():
					_investigate(search_pts.pop_back(), true)   # 0.19.1: обыск — следующая точка
					return
				hot = false
				look_amp = 1.0
				_resume_role()
		S.SUSPICIOUS:
			t += dt
			turn_to(angle_to_point(target.x, target.z), 4.0 * dt)
			if susp < 0.08:
				_resume_role()
			elif t > 2.0:
				_investigate(target, false)
		S.INVESTIGATE:
			if path.is_empty() or path_goal != Vector2i(floori(target.x), floori(target.z)):
				_set_goal(target)
			if _follow(T.chase * 0.85 if hot else T.walk * 1.3, dt):
				state = S.LOOK
				t = randf_range(3.0, 5.0)
				look_base = angle
		S.CHASE:
			_combat(dt)
		S.ATTACK:
			if _loyal_vs_player():
				state = S.CHASE
				return
			if angry_t > 0.0 and is_loyal():
				turn_to(angle_to_point(game.player.px(), game.player.pz()), 8.0 * dt)
				t -= dt
				if t <= 0.0:
					if dist_to(game.player) < radius + game.player.radius + 1.0:
						game.damage_player(SHOO_DMG, self, true)
						game.sfx.play_at("punch", position, game.player.position, 0.8)
					swing_t = 0.25
					atk_cd = 1.1
					state = S.CHASE
				return
			var f := _foe()
			turn_to(angle_to_point(f.px(), f.pz()), 8.0 * dt)
			t -= dt
			if t <= 0.0:
				var d := dist_to(f)
				var a := absf(wrapf(angle_to_point(f.px(), f.pz()) - angle, -PI, PI))
				if f is Human:
					game.battle_log(self, "shot")   # замах по человеку
				if d < radius + f.radius + W.reach + 0.25 and a < 1.2:
					if f is Human:
						game.battle_log(self, "hit")
					_hit(f, W.dmg_p if f is Player else W.dmg_z, "melee")
					game.sfx.play_at("hit" if weapon == "axe" else "stab", position, game.player.position, 0.9)
				swing_t = 0.25
				atk_cd = W.cd
				state = S.CHASE
		S.AIM:
			_aim(dt)
		S.RELOAD:
			t -= dt
			var f2 := _foe()
			if dist_to(f2) < 3.0:
				_step_away(f2, T.walk * 1.2, dt)
			if t <= 0.0:
				ammo = W.mag
				state = S.CHASE


## Дошёл до точки патруля — оглядывается. Иногда (30%) 3–6 с стоит, уставившись в стену/угол и светя туда:
## окно для удушения или удара сзади.
func _look_pause() -> void:
	state = S.LOOK
	look_base = angle
	look_amp = 1.0
	t = randf_range(1.5, 3.0) if role == "room" else randf_range(2.0, 4.0)
	if role != "follow" and randf() < 0.3:
		var best := -1.0
		for k in 8:
			var a := k * TAU / 8.0
			var dir := Vector2(sin(a), cos(a))
			var s := 0.5
			while s < 3.5:
				var c := L.cell(floori(px() + dir.x * s), floori(pz() + dir.y * s))
				if c == OfficeLevel.WALL or c == OfficeLevel.TALL: break
				s += 0.25
			if s < 3.5 and (best < 0.0 or randf() < 0.4):
				best = a
		if best >= 0.0:
			look_base = best
			look_amp = 0.2
			t = randf_range(3.0, 6.0)


## Охотник пары высматривает одинокого зомби, который его не видит (не толстяк, рядом нет других).
func _hunt_scan(dt: float) -> void:
	hunt_scan -= dt
	if hunt_scan > 0.0 or hunt_cd > 0.0:
		return
	hunt_scan = 0.5
	var cands: Array = []
	for e: Enemy in game.enemies:
		if e.faction != "zombie" or e.is_down() or e.is_hostile() or e.type == "fat" or e.type == "clicker" or (e == skip_z and skip_t > 0.0):
			continue
		var d := dist_to(e)
		if d > (15.0 if e.state == S.WORK else 14.0): continue
		dbg["рядом"] = dbg.get("рядом", 0) + 1
		if _watchers_near(e) > 0:
			dbg["группа"] = dbg.get("группа", 0) + 1
			continue        # не лезем к группе (соседи-работники за ПК не в счёт — смотрят в мониторы)
		if e._see_factor(self) > 0.0:
			dbg["видит нас"] = dbg.get("видит нас", 0) + 1
			continue                 # он нас видит — не подкрадёмся
		# приоритет: сидящие за ПК (лицом к монитору) → стоящие → бродячие
		var score := d - (6.0 if e.state == S.WORK else (3.0 if e.state == S.LOOK else 0.0))
		cands.append([score, e])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	# за стеной — можно, если дойти недалеко (путь не длиннее ~20 клеток)
	var best: Enemy = null
	var door := {}
	# один короткий поиск пути за раз (глубокий поиск только даёт пики нагрузки)
	var e2: Enemy = cands[0][1]
	# (почти дошёл — скоро встанет оглядеться: к нему обычный подход со спины)
	if not is_gunner() and e2.state != S.WORK and e2.speed_now > 0.2 and e2.path.size() - e2.path_i >= 6:
		# 0.10: за бродячим не гоняемся — ждём у двери на его пути
		door = _door_ambush(e2)
		if door.is_empty():
			dbg["бродит, нет двери"] = dbg.get("бродит, нет двери", 0) + 1
			return
		best = e2
	else:
		# сидящий за ПК (спина предсказуема) — путь до ~15 м; стоящий — до 28 клеток
		var max_len := 16 if e2.state == S.WORK else 28
		var pth := L.find_path(floori(px()), floori(pz()), floori(e2.px()), floori(e2.pz()), 700 if e2.state == S.WORK else 900)
		if not pth.is_empty() and pth.size() <= max_len:
			best = e2
		else:
			dbg["далеко идти"] = dbg.get("далеко идти", 0) + 1
	if best == null:
		return
	if is_gunner() and on_sweep():
		return   # 0.11: на зачистке стрелок не стреляет по зомби — шум зовёт щелкунов
	if is_gunner():
		# стрелок снимает выстрелом (шумно — притянет других)
		foe = best
		_instant_alert = true
		alert()
		_instant_alert = false
		hunt_cd = randf_range(15.0, 25.0)
		return
	stalk = best
	state = S.STALK
	t = 0.0
	wait_t = 0.0
	lunge_t = 0.0
	duo_used = false
	path = PackedInt32Array()
	door_cell = -1
	if not door.is_empty():
		door_cell = door.cell
		door_spot = door.spot
		_set_goal(door_spot)
		game.npc_stats.door_ambush += 1
	game.npc_stats.ambush_started += 1


## Засада у двери (0.10): дверь в ближайших ~16 клетках пути зомби; встаём сбоку от выхода у стены (в 2 клетках
## от прохода — вне его поля зрения), если успеваем дойти раньше него.
func _door_ambush(z: Enemy) -> Dictionary:
	var n := z.path.size()
	for i in range(z.path_i + 2, mini(n - 1, z.path_i + 16)):
		var c: int = z.path[i]
		if L.door[c] == 0:
			continue
		var nx: int = z.path[i + 1]
		var dx: int = nx % L.W - c % L.W
		var dz: int = nx / L.W - c / L.W
		var after: Array = Array(z.path.slice(i, mini(n, i + 7)))
		for sgn in [1, -1]:
			var sx: int = nx % L.W - dz * sgn * 2
			var sz: int = nx / L.W + dx * sgn * 2
			if not L.walkable(sx, sz) or L.door[sz * L.W + sx] != 0 or after.has(sz * L.W + sx):
				continue
			if after.has(sz * L.W + sx + dx + dz * L.W):
				continue
			if L.line_blocked(sx + 0.5, sz + 0.5, nx % L.W + 0.5, nx / L.W + 0.5, 2):
				continue
			var my := L.find_path(floori(px()), floori(pz()), sx, sz, 700)
			var zl := i - z.path_i
			if my.is_empty() or my.size() > 22 or my.size() > zl * 1.4 + 2:
				continue
			return {"cell": c, "spot": Vector3(sx + 0.5, 0, sz + 0.5)}
		break   # первая дверь на пути не подходит — дальше дверей не ищем
	# двери нет (бродит по комнате) — ждём сбоку от его пути, в 2 клетках от точки в 4–10 шагах впереди
	for i in range(z.path_i + 3, mini(n - 1, z.path_i + 13)):
		var c: int = z.path[i]
		var nx: int = z.path[i + 1]
		var dx: int = nx % L.W - c % L.W
		var dz: int = nx / L.W - c / L.W
		var near: Array = Array(z.path.slice(maxi(0, i - 3), mini(n, i + 5)))
		for sgn in [1, -1]:
			var sx: int = c % L.W - dz * sgn * 2
			var sz: int = c / L.W + dx * sgn * 2
			if not L.walkable(sx, sz) or near.has(sz * L.W + sx):
				continue
			if L.line_blocked(sx + 0.5, sz + 0.5, c % L.W + 0.5, c / L.W + 0.5, 2):
				continue
			var my := L.find_path(floori(px()), floori(pz()), sx, sz, 600)
			var zl := i - z.path_i
			if my.is_empty() or my.size() > 22 or my.size() > zl * 2.0 + 3:
				dbg["не успеть на путь"] = dbg.get("не успеть на путь", 0) + 1
				continue
			return {"cell": c, "spot": Vector3(sx + 0.5, 0, sz + 0.5)}
	return {}


## Засада (0.9): подкрадываемся на ~2 м за спину, ждём, пока зомби отвернётся (до 8 с), — рывок ~2 м за 0.4 с (0.10)
## и удар (нож/топор — насмерть, кастет — вырубить и добить). Пошёл прямо на нас — отходим, не стоим столбом.
func _stalk(dt: float) -> void:
	var z := stalk
	t += dt
	# у двери: зомби свернул и больше не идёт через неё (и уже не рядом) или ждём дольше 14 с — срыв
	var door_lost := false
	if door_cell >= 0 and z != null and alive(z) and dist_to(z) > 3.0:
		door_lost = t > 14.0 or not Array(z.path.slice(z.path_i)).has(door_cell)
	if z == null or not alive(z) or z.is_hostile() or dist_to(z) > 16.0 or t > 20.0 or wait_t > 8.0 or door_lost:
		var why := "убит/упал" if z == null or not alive(z) else ("заметил" if z.is_hostile() else ("ушёл" if dist_to(z) > 16.0 else ("не отвернулся" if wait_t > 8.0 else ("мимо двери" if door_lost else "долго"))))
		if why == "долго":
			why += " (%s, %d м)" % ["за ПК" if z.state == S.WORK else S.keys()[z.state], int(dist_to(z))]
		door_cell = -1
		dbg["срыв: " + why] = dbg.get("срыв: " + why, 0) + 1
		stalk = null
		hunt_cd = randf_range(6.0, 10.0)
		skip_z = z   # 0.11.1: к этому зомби 30 с не возвращаемся (охотник «залипал» на одной цели)
		skip_t = 30.0
		_resume_role()
		return
	var to_me := Vector2(px() - z.px(), pz() - z.pz())
	var d := to_me.length()
	var dir_me := to_me / maxf(d, 0.001)
	var behind := dir_me.dot(z.facing()) < -0.2 or z.state == S.WORK
	var unseen := z._see_factor(self) <= 0.0
	# рывок
	if lunge_t > 0.0:
		lunge_t -= dt
		_step_toward(z.position, 5.0, dt)
		if dist_to(z) < radius + z.radius + 0.6:
			_stab(z)
		elif lunge_t <= 0.0:
			lunge_t = 0.0
		return
	if d < 3.0 and unseen:
		turn_to(angle_to_point(z.px(), z.pz()), 6.0 * dt)
		path = PackedInt32Array()
		# он нас не видит (спиной/боком или сидит за ПК) — рывок; сзади — сразу, сбоку — тоже, раз не видит
		if (behind or dir_me.dot(z.facing()) < 0.4) and not L.line_blocked(px(), pz(), z.px(), z.pz(), 2):
			lunge_t = 0.4
			return
		# ждём в засаде; идёт прямо на нас — пятимся
		wait_t += dt
		_duo_distract(z)
		if z.facing().dot(dir_me) > 0.5 and d < 2.0 and z.speed_now > 0.2:
			_step_away(z, 1.3, dt)
		return
	if door_cell >= 0:
		# засада у двери: идём к месту сбоку от выхода и ждём вприсядку, глядя на проход
		if Vector2(door_spot.x - px(), door_spot.z - pz()).length() > 0.35:
			if path.is_empty() or path_goal != Vector2i(floori(door_spot.x), floori(door_spot.z)):
				_set_goal(door_spot)
			if _follow(1.8, dt):
				_step_toward(door_spot, 1.2, dt)
		else:
			path = PackedInt32Array()
			turn_to(angle_to_point(door_cell % L.W + 0.5, door_cell / L.W + 0.5), 5.0 * dt)
		return
	# зомби повернулся к нам на подходе — отступаем из его поля зрения, пока не отвернётся (напарник шумит в сторону)
	if d < 5.0 and z.facing().dot(dir_me) > 0.5 and z.state != S.WORK:
		_duo_distract(z)
		_step_away(z, 1.3, dt)
		path = PackedInt32Array()
		return
	# подход: издалека — к самому зомби (стабильная цель), последние ~4 м — обходим к спине на ~2 м
	var back := Vector2(z.px(), z.pz()) - z.facing() * 2.0
	repath_t -= dt
	var goal := Vector3(back.x, 0, back.y) if d < 4.0 else z.position
	var c := L.nearest_walkable(floori(goal.x), floori(goal.z), 1)
	if c.x < 0:
		c = Vector2i(floori(z.px()), floori(z.pz()))
	# путь пересчитываем, только если точка за спиной сместилась (иначе топчемся на месте);
	# упёрлись в угол — не пересчитываем, пока _follow не обойдёт (иначе стоим столбом: 0.10)
	if path.is_empty() or (repath_t <= 0.0 and c != path_goal and stuck_t < 0.1):
		_set_goal(Vector3(c.x + 0.5, 0, c.y + 0.5))
		repath_t = 1.2
	# крадётся быстрее, чем бредёт зомби (1.6 против 0.9–1.2); вблизи и на виду — напрямую
	if d < 4.0 and not L.line_blocked(px(), pz(), back.x, back.y, 2):
		_step_toward(Vector3(back.x, 0, back.y), 1.7, dt)
		path = PackedInt32Array()
	elif _follow(1.8, dt):
		_step_toward(z.position, 1.8, dt)


## «Вдвоём» (0.10): зомби смотрит на ведущего или не отворачивается — напарник (в ~12 м) звякает чем-нибудь
## по ту сторону зомби; тот поворачивается и идёт на звук — спиной к ведущему. Один раз за засаду.
func _duo_distract(z: Enemy) -> void:
	if duo_used or z.state == S.WORK:
		return
	var mate: Human = null
	for m in squad.get("members", []):
		var h := m as Human
		if h != null and h.pair_lead == self and alive(h) and not h.is_hostile() and h.dist_to(self) < 12.0:
			mate = h
	if mate == null:
		return
	duo_used = true
	var away := Vector2(z.px() - px(), z.pz() - pz()).normalized() * 3.0
	var c := L.nearest_walkable(floori(z.px() + away.x), floori(z.pz() + away.y), 2)
	if c.x < 0:
		return
	var p := Vector3(c.x + 0.5, 0, c.y + 0.5)
	mate.turn_to(mate.angle_to_point(p.x, p.z), 20.0)
	game.sfx.play_at("clink", p, game.player.position, 0.7, 14.0)
	game.emit_noise(p, 4.0, "distract", true, Vector3.ZERO, mate)
	game.npc_stats.duo_distract += 1
	dbg["вдвоём: шум"] = dbg.get("вдвоём: шум", 0) + 1


func _stab(z: Enemy) -> void:
	var how := "у двери" if door_cell >= 0 else ("вдвоём" if duo_used else ("за ПК" if z.state == S.WORK else "со спины"))
	turn_to(angle_to_point(z.px(), z.pz()), 20.0)
	swing_t = 0.25
	if weapon == "knuckles" and not z.is_down():
		z.knockdown(4.0, true)
	stabbing = true
	z.take_damage(999.0, self, "sneak")
	stabbing = false
	game.sfx.play_at("stab", position, game.player.position, 0.6, 14.0)
	game.human_kills += 1
	game.npc_stats.stealth_kills += 1
	dbg["убит " + how] = dbg.get("убит " + how, 0) + 1
	door_cell = -1
	stalk = null
	lunge_t = 0.0
	hunt_cd = randf_range(10.0, 18.0)
	_look_pause()


## Роли в отряде:
##  hunt   — ведущий пары: патрулирует этаж и охотится на одиноких зомби со спины (напарник — follow);
##  lead   — ведёт: к занимаемой комнате (фаза travel) или по этажу (остальные с ролью follow идут за ним);
##  follow — держится рядом с ведущим, смотрит в свою сторону;
##  guard  — сторожит занятую комнату;
##  room   — бродит по занятой комнате;
##  wide   — в одиночку патрулирует этаж (другие комнаты) и возвращается.
func _resume_role() -> void:
	hot = false
	was_resting = false
	state = S.PATROL
	var dest: Vector3 = post if has_post else squad.get("dest", position)
	match role:
		"guard":
			if Vector2(dest.x - px(), dest.z - pz()).length() < 1.0:
				state = S.GUARD
				t = 0.0
				look_base = post_ang if has_post else angle
				return
			goal_kind = "guard"
			_set_goal(dest)
		"follow":
			goal_kind = "follow"
			path = PackedInt32Array()
		"lead":
			if squad.get("phase", "") == "travel":
				goal_kind = "dest"
				_set_goal(dest)
			else:
				goal_kind = "patrol"
				_set_goal(_patrol_point())
		"room":
			goal_kind = "patrol"
			_set_goal(_room_point())
		"hunt":
			if on_sweep():
				_sweep_goal()
				return
			goal_kind = "patrol"
			_set_goal(_patrol_point())
		"talk", "radio":
			# 0.17: свой пост — болтает на кухне / сидит у радио
			if Vector2(post.x - px(), post.z - pz()).length() < 0.6:
				_post_arrive()
				return
			goal_kind = "post"
			_set_goal(post)
		"elite":
			# 0.19: элита прочёсывает окрестности вертолётной площадки
			goal_kind = "patrol"
			_set_goal(_near_point(L.helipad, 9))
		"advance":
			# 0.18: поле битвы — продвигается к середине этажа (там встречаются стороны)
			goal_kind = "patrol"
			_set_goal(_front_point())
		"loot":
			# 0.18: победитель идёт за стволом убитого
			if loot_pk.is_empty() or not game.pickups.has(loot_pk):
				loot_pk = {}
				game.battle_cheer(self)
				return
			goal_kind = "loot"
			_set_goal((loot_pk.node as Node3D).position)
		"fort":
			goal_kind = "patrol"
			_set_goal(_lair_walk_point())
		"lair":
			_lair_goal()
		"rest":
			goal_kind = "rest"
			_set_goal(_rest_spot())
		_:
			goal_kind = "patrol"
			_set_goal(_patrol_point())


## Зачистка (0.10): следующая комната своего списка (опасные — толстяк/щелкун/группа — пропускаем);
## список кончился — к стартовому лифту героя, место встречи у стены.
func _sweep_goal() -> void:
	var rt: Array = squad.routes[pair_i]
	while not rt.is_empty():
		var r: Dictionary = rt[0]
		for _try in 8:
			var x := randi_range(r.x0 + 1, maxi(r.x0 + 1, r.x1 - 1))
			var z := randi_range(r.z0 + 1, maxi(r.z0 + 1, r.z1 - 1))
			if not L.walkable(x, z):
				continue
			var p := Vector3(x + 0.5, 0, z + 0.5)
			if _dangerous(p) or _crowded(p):
				continue
			goal_kind = "sweep"
			_set_goal(p)
			if not path.is_empty():
				return
		rt.remove_at(0)
	goal_kind = "meet"
	_set_goal(_meet_spot())


## Место у стартового лифта, где пара ждёт вторую: в ~4 м от точки встречи, лучше у стены, не впритык к своим.
func _meet_spot() -> Vector3:
	var m: Vector3 = squad.get("meet", position)
	var best := m
	for _try in 16:
		var x := floori(m.x) + randi_range(-4, 4)
		var z := floori(m.z) + randi_range(-4, 4)
		if not L.walkable(x, z):
			continue
		var p := Vector3(x + 0.5, 0, z + 0.5)
		if _crowded(p):
			continue
		best = p
		for k in 4:
			if L.cell(x + OfficeLevel.DX[k], z + OfficeLevel.DZ[k]) == OfficeLevel.WALL:
				return p
	return best


## Место отдыха в занятой комнате: лучше у стены (сесть/прислониться), подальше от своих.
func _rest_spot() -> Vector3:
	var r: Dictionary = squad.get("room", {})
	if r.is_empty():
		return position
	var best := position
	for _try in 14:
		var x := randi_range(r.x0, r.x1)
		var z := randi_range(r.z0, r.z1)
		if not L.walkable(x, z): continue
		var p := Vector3(x + 0.5, 0, z + 0.5)
		if _crowded(p): continue
		best = p
		for k in 4:
			if L.cell(x + OfficeLevel.DX[k], z + OfficeLevel.DZ[k]) == OfficeLevel.WALL:
				return p
	return best


## Пришёл на место отдыха: садится на пол / прислоняется к стене (спиной к ней) / стоит.
func _enter_rest() -> void:
	state = S.REST
	was_resting = true
	t = 0.0
	path = PackedInt32Array()
	var wall_dir := -1
	for k in 4:
		if L.cell(floori(px()) + OfficeLevel.DX[k], floori(pz()) + OfficeLevel.DZ[k]) == OfficeLevel.WALL:
			wall_dir = k
			break
	var r := randf()
	if wall_dir >= 0:
		rest_kind = "sit" if r < 0.5 else ("lean" if r < 0.85 else "stand")
		# спиной к стене, лицом в комнату
		angle = atan2(-OfficeLevel.DX[wall_dir], -OfficeLevel.DZ[wall_dir])
		rotation.y = angle
		if rest_kind != "stand":
			var back := Vector2(OfficeLevel.DX[wall_dir], OfficeLevel.DZ[wall_dir])
			move(back.x * 0.25, back.y * 0.25)
	else:
		rest_kind = "sit" if r < 0.35 else "stand"
	look_base = angle


## Точка в занятой отрядом комнате.
func _room_point() -> Vector3:
	var r: Dictionary = squad.get("room", {})
	if r.is_empty():
		return _wander_point(true)
	for _try in 10:
		var x := randi_range(r.x0, r.x1)
		var z := randi_range(r.z0, r.z1)
		if L.walkable(x, z) and Vector2(x + 0.5 - px(), z + 0.5 - pz()).length() > 1.8:
			return Vector3(x + 0.5, 0, z + 0.5)
	return _wander_point(true)


## Патруль по этажу: случайная другая комната в 6–26 м от занятой.
func _patrol_point() -> Vector3:
	var dest: Vector3 = squad.get("dest", position)
	var cands: Array = []
	for r in L.rooms:
		var c := Vector2((r.x0 + r.x1) * 0.5 + 0.5, (r.z0 + r.z1) * 0.5 + 0.5)
		var d := c.distance_to(Vector2(dest.x, dest.z))
		if d > 6.0 and d < 26.0 and c.distance_to(Vector2(px(), pz())) > 4.0:
			cands.append(r)
	cands.shuffle()
	for r in cands:
		for _try in 6:
			var x := randi_range(r.x0, r.x1)
			var z := randi_range(r.z0, r.z1)
			if L.walkable(x, z):
				var p := Vector3(x + 0.5, 0, z + 0.5)
				if not _crowded(p) and not _dangerous(p) and not _other_pair_near(p):
					return p
	var cell := L.random_reachable(dest.x, dest.z, 6, 20)
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)


## Охотники разных пар зачищают разные части этажа: не идём туда, куда идёт/где стоит другая пара.
func _other_pair_near(p: Vector3) -> bool:
	if role != "hunt" or on_sweep():
		return false
	for m in squad.get("members", []):
		var h := m as Human
		if h == self or h == null or h.is_dead() or h.role != "hunt":
			continue
		var g := Vector2(h.path_goal.x + 0.5, h.path_goal.y + 0.5)
		if g.distance_to(Vector2(p.x, p.z)) < 10.0 or Vector2(h.px(), h.pz()).distance_to(Vector2(p.x, p.z)) < 10.0:
			return true
	return false


## Опасное место для патруля: рядом толстяк или группа зомби — обходим.
func _dangerous(p: Vector3) -> bool:
	var n := 0
	for e: Enemy in game.enemies:
		if e.faction != "zombie" or e.is_dead():
			continue
		var d := Vector2(e.px() - p.x, e.pz() - p.z).length()
		if e.type == "fat" and d < 6.0:
			return true
		if e.type == "clicker" and d < 9.0:
			return true
		if d < 5.0:
			n += 1
	return n >= 2


## Идём за ведущим (своей пары или отряда), держась в 1.5–2 м; на месте — смотрим каждый в свою сторону.
## Ведущий погиб — напарник сам становится охотником (или патрульным).
func _follow_leader(dt: float) -> void:
	var ld: Human = pair_lead if pair_lead != null and _pairs_phase() else squad.get("leader")
	if ld == null or ld == self or not alive(ld):
		pair_lead = null
		role = "hunt" if _pairs_phase() else "wide"
		_resume_role()
		return
	var d := dist_to(ld)
	# ведущий подкрадывается к зомби — напарник ждёт вприсядку в ~6 м, чтобы не попасться зомби на глаза
	if ld.state == S.STALK and d < 7.0:
		path = PackedInt32Array()
		turn_to(angle_to_point(ld.px(), ld.pz()), 3.0 * dt)
		return
	if d > 2.0:
		repath_t -= dt
		if path.is_empty() or (repath_t <= 0.0 and stuck_t < 0.1):
			_set_goal(ld.position)
			repath_t = 0.6
		var spd: float = (1.6 if d > 4.0 else 1.35) if sneaking() else T.walk * (1.3 if d > 4.0 else 1.05)
		_follow(spd, dt)
	else:
		path = PackedInt32Array()
		# ведущий пары занял комнату и отдыхает — отдыхаем рядом
		if ld.state == S.REST and ld.goal_kind == "meet":
			_enter_rest()
			rest_len = 0.0
			goal_kind = "meet"
			return
		if ld.state == S.REST and ld.rest_len > 0.0:
			_enter_rest()
			rest_len = maxf(5.0, ld.rest_len - ld.t)
			return
		var i: int = squad.members.find(self)
		turn_to(ld.angle + (0.9 if i % 2 == 0 else -0.9), 2.0 * dt)


func _combat(dt: float) -> void:
	if _loyal_vs_player():
		# 0.15: лояльный офисник: врага рядом нет — бой окончен (на героя не переключается)
		foe = null
		hot = false
		_resume_role()
		return
	if angry_t > 0.0 and is_loyal():
		# 0.17: гонит вора взашей — догоняет и бьёт кулаком (оружие в ход не идёт, не насмерть)
		var pl: Player = game.player
		if dist_to(pl) < radius + pl.radius + 0.8 and atk_cd <= 0.0:
			state = S.ATTACK
			t = 0.3
			return
		_approach(pl.position, T.chase, dt)
		return
	if not alive(foe) and foe != game.player:
		foe = null
		_investigate(last_seen, true)
		return
	var f := _foe()
	if not alive(f):
		_resume_role()
		return
	if sees:
		target = f.position
	else:
		lost_t += dt
		if know_t > 0.0:
			lost_t = 0.0   # 0.12: знает, где герой (громкий шум) — не теряет
		target = f.position if lost_t < T.track else last_seen
		if lost_t > T.track + 4.0:
			_investigate(last_seen, true)   # обыскать место, где потеряли
			return
	# 0.11.1: 20 с никто никого не ранил (цель за мебелью/недостижима) — бросаем бой (стрелок «залипал» в погоне)
	var hsum: float = hp + f.hp
	if absf(hsum - fight_hp) > 0.01:
		fight_hp = hsum
		fight_t = 0.0
	fight_t += dt
	if fight_t > 20.0 and evade_t <= 0.0:
		fight_t = 0.0
		dbg["бросил бой (20 с без ран)"] = dbg.get("бросил бой (20 с без ран)", 0) + 1
		if f is Player:
			_investigate(last_seen, true)
		else:
			foe = null
			hot = false
			evade_cd = 10.0
			_resume_role()
		return
	var d := dist_to(f)
	# 0.15: война фракций — ранен или зажат зомби (2+ рядом) при враге-человеке: перебежать в укрытие
	if game.faction_war_on and f is Human and evade_t <= 0.0 and evade_cd <= 0.0 \
			and (hp < 40.0 or _zombies_near(position, 4.0) >= 2):
		_start_evade(f as Enemy)
	# 0.11: уходим в укрытие; дошли и зомби нас не видит — присели и пережидаем (бой окончен); догнал — дерёмся
	if evade_t > 0.0 and f is Enemy:
		evade_t -= dt
		var dc := Vector2(cover.x - px(), cover.z - pz()).length()
		if dc > 0.5 and evade_t > 0.0 and d > radius + f.radius + 0.4:
			if path.is_empty() or path_goal != Vector2i(floori(cover.x), floori(cover.z)):
				_set_goal(cover)
			if _follow(T.chase, dt):
				_step_toward(cover, T.chase, dt)
			return
		evade_t = 0.0
		if d > 2.0 and (f as Enemy)._see_factor(self) <= 0.0 or dc <= 0.6 and d > 2.5:
			foe = null
			hot = false
			hide_t = randf_range(4.0, 6.0)
			hunt_cd = maxf(hunt_cd, hide_t)
			state = S.LOOK
			t = hide_t
			look_base = angle_to_point(f.px(), f.pz())
			look_amp = 0.3
			path = PackedInt32Array()
			game.npc_stats.bandit_hides += 1
			return
	# толстяк/группа зомби: сперва отходим (к стене/в коридор), кричим своим; зажали — дерёмся
	if retreat_t > 0.0 and f is Enemy:
		retreat_t -= dt
		var before := position
		_step_away(f, T.chase, dt)
		if before.distance_to(position) < T.chase * dt * 0.3 or d < radius + f.radius + 0.3:
			retreat_t = 0.0   # упёрлись — зажали
		turn_to(angle_to_point(f.px(), f.pz()), 6.0 * dt)
		return
	if W.melee:
		if sees and d < radius + f.radius + W.reach and atk_cd <= 0.0:
			state = S.ATTACK
			t = W.windup
			return
		if d < radius + f.radius + 0.45:
			turn_to(angle_to_point(f.px(), f.pz()), 8.0 * dt)
			return
		# 0.12: окружение — вторая пара сперва заходит с фланга
		if flank_t > 0.0 and not sees:
			flank_t -= dt
			if Vector2(flank_pos.x - px(), flank_pos.z - pz()).length() > 0.8:
				_approach(flank_pos, T.chase, dt)
				return
			flank_t = 0.0
		_approach(target, T.chase, dt)
		return
	# стрелок: держит дистанцию, стреляет, когда видит
	if ammo <= 0:
		state = S.RELOAD
		t = W.reload
		game.sfx.play_at("reload", position, game.player.position, 0.6)
		return
	# 0.12: знает, где герой (громкий шум), и стен между ними нет — разворачивается и стреляет, даже не высветив
	var knows := know_t > 0.0 and f is Player and not L.line_blocked(px(), pz(), f.px(), f.pz(), 0)
	if sees or knows:
		turn_to(angle_to_point(f.px(), f.pz()), 8.0 * dt)
		if d < W.near:
			_step_away(f, T.walk * 1.3, dt)
		elif d > W.far:
			_approach(target, T.chase * 0.8, dt)
		# рядом щелкун — стрелок не стреляет, пока его не зажали
		if atk_cd <= 0.0 and d <= W.far + 1.5 and (fear_t <= 0.0 or d < W.near):
			state = S.AIM
			# 0.12.1: у каждого своя реакция; повторная очередь по цели, которая на виду, — вдвое быстрее (узи) /
			# на четверть (болтовка). Не короче фиксации направления + 0.08 с: щелчок и блик успеваешь заметить
			var k := aim_mult * ((0.5 if weapon == "uzi" else 0.75) if quick_aim and sees else 1.0)
			t = maxf(W.aim * k, W.lock + 0.08)
			aim_ang = angle_to_point(f.px(), f.pz())
			burst_left = 0
			# телеграф: щелчок затвора и блик на стволе — «сейчас выстрелит»
			game.sfx.play_at("click", position, game.player.position, 1.0, 20.0)
			game.fx.spawn(muzzle(), Vector3.ZERO, 0.3, 0.45, "p_dot", Color(1, 0.35, 0.2, 0.9), true)
	else:
		_approach(target, T.chase * 0.8, dt)


func _approach(pos: Vector3, spd_in: float, dt: float) -> void:
	var spd := minf(spd_in, 1.8) if fear_t > 0.0 else spd_in   # рядом щелкун — не бегаем
	if sees and dist_to(_foe()) < 6.0 and not L.line_blocked(px(), pz(), pos.x, pos.z, 2):
		_step_toward(pos, spd, dt)
		path = PackedInt32Array()
		return
	repath_t -= dt
	var goal := Vector2i(floori(pos.x), floori(pos.z))
	if path.is_empty() or (repath_t <= 0.0 and goal != path_goal):
		_set_goal(pos)
		repath_t = 0.5
	_follow(spd, dt)


func _step_away(f: Actor, spd: float, dt: float) -> void:
	var dir := Vector2(px() - f.px(), pz() - f.pz()).normalized()
	move(dir.x * spd * dt, dir.y * spd * dt)


## Прицеливание: ведём цель, за lock секунд до выстрела направление фиксируется (можно уйти с линии).
func _aim(dt: float) -> void:
	if _loyal_vs_player():
		state = S.CHASE
		burst_left = 0
		return
	var f := _foe()
	if burst_left > 0:
		burst_t -= dt
		if burst_t <= 0.0:
			_fire()
			burst_left -= 1
			ammo -= 1
			burst_t = W.gap
			if burst_left <= 0 or ammo <= 0:
				atk_cd = W.cd
				state = S.CHASE
				quick_aim = sees   # цель на виду — следующая очередь быстрее
		return
	t -= dt
	if not alive(f) or (not sees and know_t <= 0.0 and t > W.lock):
		state = S.CHASE
		atk_cd = 0.3
		quick_aim = false
		return
	if t > W.lock:
		# узи чуть упреждает движение цели: бег по прямой не спасает, а смена направления — да
		var v := Vector2.ZERO
		if f is Player:
			v = (f as Player).vel2
		elif f is Enemy:
			v = Vector2((f as Enemy).velocity.x, (f as Enemy).velocity.z)
		# упреждение = доля от времени полёта пули до цели
		var lead: float = W.lead * dist_to(f) / W.speed if W.speed > 0.0 else 0.0
		aim_ang = angle_to_point(f.px() + v.x * lead, f.pz() + v.y * lead)
	turn_to(aim_ang, 12.0 * dt)
	if t <= 0.0:
		burst_left = randi_range(W.burst, W.get("burst_max", W.burst))
		burst_t = 0.0


func muzzle() -> Vector3:
	if model.held != null:
		return model.held.to_global(HeldItems.muzzle(weapon))
	return position + Vector3(sin(angle) * 0.5, 1.3, cos(angle) * 0.5)


func _fire() -> void:
	var a := aim_ang + randf_range(-W.spread, W.spread)
	var dir := Vector2(sin(a), cos(a))
	angle = aim_ang
	rotation.y = angle
	recoil = 1.0
	_animate(0.0)
	var m := muzzle()
	game.fx.flash(m)
	game.sfx.play_at(weapon, position, game.player.position, 1.0, 30.0)
	game.battle_log(self, "shot")
	game.emit_noise(position, W.noise, "gun", true, Vector3.ZERO, self)
	if weapon == "rifle" or weapon == "crossbow":
		var hit: Dictionary = game.trace_shot(Vector2(px(), pz()), dir, 26.0, self)
		var ht: float = hit.t
		var end := Vector3(px() + dir.x * ht, 1.2, pz() + dir.y * ht)
		game.fx.tracer(m, end)
		if hit.actor != null:
			if hit.actor is Player:
				game.damage_player(W.dmg_p, self, weapon == "rifle")   # болтовка не добивает; арбалет — может
			elif (hit.actor as Enemy).faction == faction:
				(hit.actor as Enemy).take_damage(W.dmg_p, self, "friendly")   # 0.12.1: по своему
				game.npc_stats.friendly_hits += 1
				game.battle_log(self, "friendly")
			else:
				game.battle_log(self, "hit")
				(hit.actor as Enemy).take_damage(dmg_vs(hit.actor), self, "gun")
			game.fx.blood(end, 6)
		else:
			game.fx.sparks(end)
	else:
		game.spawn_bullet(m, dir, W.speed, W.dmg_p, W.dmg_z, self)


func die(from) -> void:
	grabbed_by = null
	super.die(from)
	if fan != null:
		fan.visible = false
	if lamp != null:
		lamp.visible = false
	game.drop_loot(self)
	if has_key:
		game.drop_keycard(self)


# ================================================================ фонарик
func _build_flashlight() -> void:
	fan = MeshInstance3D.new()
	fan.top_level = true
	fan.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	fan.material_override = m
	fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fan)
	lamp = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	lamp.mesh = q
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	lm.albedo_texture = OfficeTex.get_tex("p_dot")
	lm.albedo_color = Color(1, 0.95, 0.7, 0.9)
	lamp.material_override = lm
	model.torso.add_child(lamp)
	lamp.position = Vector3(model.spec.torso.x * 0.22, model.spec.torso.y * 0.72, model.spec.torso.z / 2 + 0.1)


## Пятно света на полу: веер лучей до стен (как фонарик в PS1-играх — без настоящего света).
func _update_flashlight(dt: float) -> void:
	if is_down():
		fan.visible = false
		return
	fan.visible = true
	fan_t -= dt
	if fan_t > 0.0:
		return
	fan_t = 0.05
	var im: ImmediateMesh = fan.mesh
	im.clear_surfaces()
	var half := deg_to_rad(beam_fov()) * 0.5
	var rng: float = DIM_VIEW if is_dim() else T.view
	var o := Vector2(px() + sin(angle) * 0.25, pz() + cos(angle) * 0.25)
	var pts: Array = []
	for i in FAN_RAYS:
		var a := angle - half + 2.0 * half * i / (FAN_RAYS - 1)
		var dir := Vector2(sin(a), cos(a))
		var s := 0.3
		while s < rng:
			var c := L.cell(floori(o.x + dir.x * s), floori(o.y + dir.y * s))
			if c == OfficeLevel.WALL or c == OfficeLevel.TALL:
				break
			s += 0.25
		pts.append([o + dir * s, s / rng])
	var hot_col := Color(1.0, 0.85, 0.5, 0.55 if is_hostile() else 0.42)
	if is_dim():
		hot_col.a *= 0.4   # фонарь опущен — луч тусклый, но игроку виден
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in FAN_RAYS - 1:
		var a2: Vector2 = pts[i][0]
		var b2: Vector2 = pts[i + 1][0]
		im.surface_set_color(hot_col)
		im.surface_add_vertex(Vector3(o.x, 0.05, o.y))
		im.surface_set_color(Color(hot_col, hot_col.a * (1.0 - pts[i][1]) * 0.5))
		im.surface_add_vertex(Vector3(a2.x, 0.05, a2.y))
		im.surface_set_color(Color(hot_col, hot_col.a * (1.0 - pts[i + 1][1]) * 0.5))
		im.surface_add_vertex(Vector3(b2.x, 0.05, b2.y))
	im.surface_end()


# ================================================================ анимация
func _animate(_dt: float) -> void:
	var p := walk_pose()
	if grabbed_by != null and not is_dead():
		# щелкун вцепился в шею: голова набок, руки бьются, колени подкашиваются
		var j := sin(Time.get_ticks_msec() * 0.04) * 0.25
		p = {"arm_l": -2.2 + j, "arm_r": -1.6 - j, "out_l": -0.3, "out_r": 0.5, "head_roll": 0.6, "head_pitch": -0.3,
			"lean": -0.2, "knee_l": 0.7, "knee_r": 0.5, "leg_l": -0.3, "leg_r": -0.1, "drop": 0.15}
		model.apply_pose(p)
		model.place_held(weapon, 0.0, 0.0, false)
		return
	match state:
		S.KNOCKED:
			p = {"fall": -1.5, "arm_l": -2.5, "arm_r": -2.2, "arm_out": 0.5, "leg_l": 0.2, "leg_r": -0.1}
		S.GETUP:
			p = {"fall": -1.5 * clampf(t / 0.9, 0.0, 1.0), "arm_l": -0.5, "arm_r": -0.5}
		S.DEAD:
			p = {"fall": -minf(1.0, t * 3.0) * 1.55, "arm_l": -2.7, "arm_r": -0.4, "arm_out": 0.6, "leg_l": 0.15}
		S.CHOKED:
			# душат: руки к горлу, голова запрокинута, ноги подкашиваются
			var j := sin(Time.get_ticks_msec() * 0.03) * 0.15
			p = {"arm_l": -2.35 + j, "arm_r": -2.35 - j, "out_l": -0.48, "out_r": -0.48, "head_pitch": -0.55,
				"lean": -0.25, "leg_l": -0.25 + j, "leg_r": 0.15 - j, "knee_l": 0.5, "knee_r": 0.3, "drop": 0.08}
		_:
			var act := -1.0
			if state == S.ATTACK:
				# замах: держим оружие занесённым, удар — в конце
				act = 0.0 if weapon == "axe" else -1.0
			elif swing_t > 0.0:
				act = 1.0 - swing_t / 0.25
			var ak := aim_k
			if state == S.RELOAD:
				ak = 0.4
			if state == S.STALK or (sneaking() and state != S.REST):
				# крадётся на корточках, как герой в приседе: холодное в руке наготове, стрелок — ствол опущен
				_crouch_walk(p)
				ak = 0.0 if is_gunner() else 0.6
			if state == S.REST:
				p = _rest_pose()
			elif state == S.STARTLED:
				# выхватывает оружие: с отдыха — вскакивает (поза отдыха → боевая), иначе — отшатнулся
				var k := clampf(1.0 - t / startle_dur, 0.0, 1.0)
				ak = k
				CharModel.pose_held(p, weapon, ak, recoil, act)
				if from_rest:
					var rp := _rest_pose()
					for key in rp.keys():
						p[key] = lerpf(rp[key], p.get(key, 0.0), k)
				else:
					p["lean"] = -0.18 * (1.0 - k)
					p["arm_l"] = lerpf(-1.0, p.get("arm_l", 0.0), k)
					p["head_pitch"] = -0.1
				model.apply_pose(p)
				model.place_held(weapon, ak, recoil, false, weapon_stowed())
				return
			else:
				CharModel.pose_held(p, weapon, ak, recoil, act)
			if stagger_t > 0.0:
				p["lean"] = -0.35
	_glance_pose(p)
	model.apply_pose(p)
	model.place_held(weapon, 0.0 if state == S.STALK and is_gunner() else aim_k, recoil, is_down() and state != S.DEAD, weapon_stowed())
	if state == S.DEAD and model.held != null:
		model.held.visible = false


## Крадущийся шаг на корточках (как присед героя): колени глубоко согнуты, корпус наклонён.
func _crouch_walk(p: Dictionary) -> void:
	var s := sin(walk_phase)
	var k := clampf(speed_now / 1.6, 0.0, 1.0)
	var th_l := lerpf(-1.2, -1.0 + s * 0.45, k)
	var th_r := lerpf(-0.7, -1.0 - s * 0.45, k)
	var kn_l := 1.8 + maxf(0.0, -s) * 0.3 * k
	var kn_r := 1.8 + maxf(0.0, s) * 0.3 * k
	p["leg_l"] = th_l
	p["leg_r"] = th_r
	p["knee_l"] = kn_l
	p["knee_r"] = kn_r
	var seg: float = model.spec.leg.y / 2
	p["drop"] = model.spec.hip - maxf(seg * (cos(th_l) + cos(th_l + kn_l)), seg * (cos(th_r) + cos(th_r + kn_r))) - 0.03
	p["lean"] = 0.38
	p["head_pitch"] = -0.28
	p["arm_l"] = -0.5 + s * 0.12 * k


## Поза отдыха. Раненый (hp < максимума) — перевязывается: рука у бедра/плеча, голова опущена.
func _rest_pose() -> Dictionary:
	var tm := Time.get_ticks_msec() * 0.001 + seed_f
	var p: Dictionary
	match rest_kind:
		"sit":
			# сидит на полу: ноги вперёд, колени чуть согнуты, руки на коленях
			p = {"drop": 0.66, "leg_l": -1.5, "leg_r": -1.35, "knee_l": 0.35, "knee_r": 0.6, "lean": 0.12,
				"arm_l": -0.85, "arm_r": -0.75, "out_l": 0.12, "out_r": 0.12, "head_pitch": 0.1 + sin(tm * 0.4) * 0.05}
		"lean":
			# прислонился спиной к стене: руки скрещены, одна нога согнута и упирается в стену
			p = {"lean": -0.12, "arm_l": -1.15, "arm_r": -1.2, "out_l": -0.55, "out_r": -0.5,
				"leg_r": -0.35, "knee_r": 0.7, "drop": 0.03, "head_yaw": sin(tm * 0.3) * 0.4}
		"fire":
			# 0.16: греется у бочки — руки вперёд к огню, потирает ладони
			var rb := sin(tm * 3.1) * 0.08
			p = {"arm_l": -1.25 + rb, "arm_r": -1.25 - rb, "out_l": -0.3, "out_r": -0.3, "lean": 0.1,
				"head_pitch": 0.25, "head_yaw": sin(tm * 0.25) * 0.25}
		"talk":
			# 0.17: болтает — жестикулирует правой рукой, кивает
			p = {"arm_l": -0.15, "arm_r": -0.7 + sin(tm * 2.3) * 0.35, "out_r": -0.25 + sin(tm * 1.7) * 0.15,
				"head_pitch": sin(tm * 3.1) * 0.08, "head_yaw": sin(tm * 0.6) * 0.2}
		"smoke":
			# 0.19: курит у парапета — облокотился, рука с сигаретой к лицу и обратно
			var sm := maxf(0.0, sin(tm * 0.9)) * 1.0
			p = {"arm_l": -0.9, "out_l": -0.4, "arm_r": -0.5 - sm * 1.6, "out_r": -0.2 - sm * 0.4, "lean": 0.18,
				"head_pitch": 0.15, "head_yaw": sin(tm * 0.3) * 0.25}
		"pee":
			# 0.16: стоит лицом к стене, руки внизу перед собой, голова опущена — удобная спина для удушения
			p = {"arm_l": -0.4, "arm_r": -0.4, "out_l": -0.35, "out_r": -0.35, "head_pitch": 0.4,
				"leg_l": 0.06, "leg_r": -0.06, "head_yaw": sin(tm * 0.5) * 0.15}
		_:
			p = {"arm_l": 0.05, "arm_r": -0.05, "arm_out": 0.1, "head_yaw": sin(tm * 0.35) * 0.5}
	if hp < max_hp - 1.0:
		# перевязка: правая рука ходит у левого бедра (сидя) или у плеча (стоя)
		var b := sin(tm * 7.0) * 0.18
		if rest_kind == "sit":
			p["arm_r"] = -1.05 + b
			p["out_r"] = -0.45
			p["arm_l"] = -0.7
		else:
			p["arm_r"] = -2.0 + b
			p["out_r"] = -0.65
			p["arm_l"] = -0.25
		p["head_pitch"] = 0.45
	return p


# ================================================================ 0.16: логово
## Бандит логова без поста сам выбирает, чем заняться: погреться у бочки (не больше двоих у одной), отлить у стены
## или пройтись по соседней комнате. У бочки стоит 20–45 с, у стены 8–14 с, после прогулки осматривается — и дальше.
func _lair_goal() -> void:
	fire_i = -1
	var r := randf()
	if r < 0.5:
		var fi := _free_fire()
		if fi >= 0:
			var f: Dictionary = L.fires[fi]
			for _try in 12:
				var c := Vector2i(f.x + randi_range(-1, 1), f.z + randi_range(-1, 1))
				if c == Vector2i(f.x, f.z) or not L.walkable(c.x, c.y) or _spot_taken(c):
					continue
				fire_i = fi
				goal_kind = "lair_fire"
				_set_goal(Vector3(c.x + 0.5, 0, c.y + 0.5))
				if not path.is_empty():
					return
				fire_i = -1
	elif r < 0.72 or (L.roof and r < 0.95):   # 0.19: на крыше чаще курят у парапета
		var w := _wall_spot()
		if w.x >= 0:
			goal_kind = "lair_pee"
			_set_goal(Vector3(w.x + 0.5, 0, w.y + 0.5))
			if not path.is_empty():
				return
	goal_kind = "patrol"
	_set_goal(_lair_walk_point())


## Бочка, у которой греются меньше двоих (из живых и спокойных), — ближайшая из таких; -1 — нет.
func _free_fire() -> int:
	var best := -1
	var bd := 1e9
	for i in L.fires.size():
		var n := 0
		for e: Enemy in game.enemies:
			if e != self and e is Human and not e.is_dead() and not e.is_hostile() and (e as Human).fire_i == i:
				n += 1
		if n >= 2:
			continue
		var f: Dictionary = L.fires[i]
		var d := Vector2(f.x + 0.5 - px(), f.z + 0.5 - pz()).length() + randf() * 8.0
		if d < bd:
			bd = d
			best = i
	return best


func _spot_taken(c: Vector2i) -> bool:
	for e: Enemy in game.enemies:
		if e == self or e.is_dead():
			continue
		if Vector2(e.px() - c.x - 0.5, e.pz() - c.y - 0.5).length() < 0.9 or (e.path_goal == c and not e.path.is_empty()):
			return true
	return false


## Место «отлить»: клетка у стены (лучше в туалете или на складе), без людей рядом, в 4–20 м.
func _wall_spot() -> Vector2i:
	var best := Vector2i(-1, -1)
	var bs := -1e9
	for _try in 24:
		var x := floori(px()) + randi_range(-14, 14)
		var z := floori(pz()) + randi_range(-14, 14)
		if not L.walkable(x, z) or L.door[z * L.W + x]:
			continue
		var wall := false
		for k in 4:
			if L.cell(x + OfficeLevel.DX[k], z + OfficeLevel.DZ[k]) == OfficeLevel.WALL and L.elev[(z + OfficeLevel.DZ[k]) * L.W + x + OfficeLevel.DX[k]] == 0:
				wall = true
		if not wall or _spot_taken(Vector2i(x, z)):
			continue
		var d := Vector2(x + 0.5 - px(), z + 0.5 - pz()).length()
		if d < 4.0 or d > 20.0:
			continue
		var rm := L.room_at(x + 0.5, z + 0.5)
		var s := randf() * 4.0 + (8.0 if not rm.is_empty() and rm.type in ["toilet", "storage"] else 0.0)
		if s > bs:
			bs = s
			best = Vector2i(x, z)
	return best


## Прогулка: точка в соседней (не той же) комнате в 5–16 м.
func _lair_walk_point() -> Vector3:
	var here := L.room_at(px(), pz())
	for _try in 16:
		var x := floori(px()) + randi_range(-14, 14)
		var z := floori(pz()) + randi_range(-14, 14)
		if not L.walkable(x, z):
			continue
		var p := Vector3(x + 0.5, 0, z + 0.5)
		var d := Vector2(p.x - px(), p.z - pz()).length()
		if d < 5.0 or d > 16.0 or L.room_at(p.x, p.z) == here or _crowded(p):
			continue
		return p
	return _wander_point(false)


## Дошёл до бочки / стены: встаёт лицом к огню / к стене и стоит (REST, фонарь опущен — видит хуже).
func _lair_arrive() -> void:
	_enter_rest()
	if goal_kind == "lair_fire" and fire_i >= 0:
		var f: Dictionary = L.fires[fire_i]
		angle = angle_to_point(f.x + 0.5, f.z + 0.5)
		rest_kind = "fire"
		rest_len = randf_range(20.0, 45.0)
	else:
		rest_kind = "smoke" if L.roof else "pee"
		rest_len = randf_range(15.0, 35.0) if L.roof else randf_range(8.0, 14.0)
		for k in 4:
			if L.cell(floori(px()) + OfficeLevel.DX[k], floori(pz()) + OfficeLevel.DZ[k]) == OfficeLevel.WALL:
				angle = atan2(OfficeLevel.DX[k], OfficeLevel.DZ[k])
				break
	rotation.y = angle
	look_base = angle


# ================================================================ 0.17: укреплённый офис
## Пришёл на свой пост: болтун встаёт лицом к собеседнику, слушатель радио садится на пол лицом к радио. Без срока.
func _post_arrive() -> void:
	_enter_rest()
	rest_len = 0.0
	angle = post_ang
	rotation.y = angle
	look_base = angle
	rest_kind = "talk" if role == "talk" else "sit"


# ================================================================ 0.18: поле битвы
## Точка у линии фронта: в ~6 клетках от середины между сторонами (squad.front), не в толпе.
func _front_point() -> Vector3:
	var fr: Vector3 = squad.get("front", position)
	for _try in 16:
		var x := floori(fr.x) + randi_range(-6, 6)
		var z := floori(fr.z) + randi_range(-6, 6)
		if L.walkable(x, z):
			var p := Vector3(x + 0.5, 0, z + 0.5)
			if not _crowded(p):
				return p
	return _wander_point(false)


# ================================================================ 0.19: крыша
## Случайная проходимая точка в r клетках от c, не в толпе.
func _near_point(c: Vector3, r: int) -> Vector3:
	for _try in 16:
		var x := floori(c.x) + randi_range(-r, r)
		var z := floori(c.z) + randi_range(-r, r)
		if L.walkable(x, z):
			var p := Vector3(x + 0.5, 0, z + 0.5)
			if not _crowded(p):
				return p
	return _wander_point(false)


## 0.19.1: оглянулся на шаги — голова к звуку (в пределах ±70°), корпус и занятие не меняются.
func _glance_pose(p: Dictionary) -> void:
	if glance_t > 0.0:
		p["head_yaw"] = clampf(wrapf(glance_ang - angle, -PI, PI), -1.2, 1.2)


# ================================================================ 0.19.1: свидетель
## Бежит к своим (report_ally, ближайший живой своей стороны) с криком раз в 1,5 с. Добежал (≤ 3 м) или свой в 10 м
## услышал — game.raise_search: 2–3 ближних + он идут обыскивать место, где видели героя. Не добежал за 25 с — тоже.
func _report(dt: float) -> void:
	report_t -= dt
	if not alive(report_ally) or report_ally.is_down():
		report_ally = game.nearest_ally(self)
		if report_ally == null:
			report_t = 0.0
			foe = game.player
			_instant_alert = true
			alert()   # своих не осталось — дерётся сам
			_instant_alert = false
			return
	report_shout -= dt
	if report_shout <= 0.0:
		report_shout = 1.5
		_set_icon("!", 1.0)
		game.sfx.play_at("shout", position, game.player.position, 0.9, 25.0)
	var heard := false
	for e: Enemy in game.enemies:
		if e != self and e is Human and e.faction == faction and not e.is_dead() and not e.is_down() and e.state != S.CHOKED and dist_to(e) < 10.0:
			heard = true
			break
	if heard or dist_to(report_ally) < 3.0 or report_t <= 0.0:
		report_t = 0.0
		game.raise_search(self, report_pos)
		return
	state = S.INVESTIGATE
	hot = true
	target = report_ally.position
