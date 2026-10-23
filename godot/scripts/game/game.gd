extends Node
## «Побег из офиса» — главный контроллер.
## Мир рендерится в SubViewport с высотой 240 строк (PS1), HUD — поверх в нормальном разрешении.
## Цикл: этаж -> взломать 5 ПК (каждый = цифра пароля + случайная награда) -> лифт -> следующий этаж.

const CAM_PITCH := deg_to_rad(56.0)
const CAM_DIST := 10.5
const LOW_RES_H := 240
const HACK_TIME := 3.0
const C_DIM_TOAST := Color(0.75, 0.75, 0.7)
const FLOOR_HEAL := 10.0   # +hp при переезде на следующий этаж (0.6: было 15)

const QUOTES := [
	"«Я просто хотел уйти домой в 18:00...»", "«Этот опенспейс не кончается.»",
	"«Кто вообще придумал стендапы в 9 утра?»", "«Коллеги не моргают уже третий квартал.»",
	"«Если меня сожрут — это не баг, это фича.»", "«Ctrl+Alt+Del на реальность не работает.»",
	"«В вакансии было написано: дружный коллектив.»", "«Мне обещали удалёнку.»",
	"«Кажется, этот этаж я уже видел. Или нет.»", "«Эйчар говорила: у нас как семья. Теперь понятно.»",
	"«Тимлид снова голоден. В плохом смысле.»", "«Дедлайн был вчера. Как и все они.»",
	"«Сколько ещё этажей? Бесконечность минус один.»", "«Кофемашина — единственный живой коллега.»",
	"«Тикет „сбежать из офиса“ висит в статусе „в работе“.»", "«Главное — не попасться толстяку из продаж.»",
]
const DEATH_LINES := [
	"Александр Вадимович уволен. Посмертно.", "Офис принял вас в штат. Навсегда.",
	"Вас перевели в отдел зомби.", "Вы задержались на работе. Навсегда.",
]

var state := "boot"      # title, howto, intro, play, pause, elevator, dead, gameover
var state_t := 0.0
var floor_num := 1
var best_floor := 0
var L: OfficeLevel
var view: LevelView
var player: Player
var enemies: Array = []
var projectiles: Array = []
var bullets: Array = []
var pickups: Array = []     # [{id, n, node}] — лут с людей
var squads: Array = []      # отряды людей: {members, anchor, mode, t}
var waves: Array = []       # когда приедут люди: {hack, time, size, done}
var floor_t := 0.0
var arrive_t := -1.0        # анимация дверей лифта при приезде людей
## 0.20.3: только приехал на этаж (вступление + ARRIVE_GRACE с начала игры) — враги героя не видят и не слышат.
## Тихо, без подсказок: игрок об этом знать не должен.
const ARRIVE_GRACE := 3.0
var arrive_grace := 0.0
var grace_off := false   # тесты-сцены
var spotted_by_humans := false  # на этом этаже люди тебя заметили
var human_kills := 0            # сколько зомби люди вырезали со спины (для --aitest)
var click_waves: Array = []     # волны щелчков щелкунов для HUD: {pos, t}
## Счётчики поведения NPC за этаж (для --aitest / --npcwatch / бота).
var npc_stats := {}


func _reset_npc_stats() -> void:
	npc_stats = {"stealth_kills": 0, "ambush_started": 0, "stealth_breaks": 0, "clicker_kills": 0,
		"clicker_saves": 0, "clicker_bites": 0, "scream_pulls": 0, "fear_time": 0.0,
		# 0.10: засады, баланс фракций, шум этажа
		"door_ambush": 0, "duo_distract": 0,
		"zombies_quiet": 0, "zombies_open": 0,
		"humans_by_zombies": 0, "humans_by_clicker": 0, "humans_by_clicker_lured": 0, "humans_by_hero": 0,
		"noise": 0.0, "noise_total": 0.0, "noise_clickers": 0,
		"first_contact": -1.0, "meet_arrived": 0,
		# 0.11: бандит ушёл от зомби в укрытие / спрятался там; зомби начали ПОИСК
		"bandit_evades": 0, "bandit_hides": 0, "zombie_searches": 0,
		# 0.12: зомби пришли на тревогу сородича; бандиты «узнали», где герой, по громкому шуму рядом
		"zombie_helpers": 0, "bandit_locates": 0,
		"friendly_hits": 0,   # 0.12.1: бандит попал по своему
		"zombie_glimpses": 0,
		"bandit_vaults": 0,
		"vents_used": 0, "vent_escapes": 0,   # 0.21: залез в вентиляцию / залез, когда за ним гнались
		# 0.15: офисники
		"office_spawned": 0, "office_hostile": 0, "faction_war_t": -1.0,
		"office_by_hero": 0, "office_by_zombies": 0, "office_by_bandits": 0, "bandits_by_office": 0,
		# 0.16: логово (key_* — секунда этажа, -1 — не было), маскировка
		"lair_bandits": 0, "key_dropped_t": -1.0, "key_taken_t": -1.0, "disguise_worn": 0, "disguise_blown": 0,
		# 0.17: укреплённый офис, пакеты
		"fort_office": 0, "bags_worn": 0, "bags_theft_seen": 0,
		# 0.18: поле битвы (winner — "office" / "human" / "none", "" — не кончилось; *_t — секунда этажа)
		"battle_office": 0, "battle_bandits": 0, "battle_start_t": -1.0, "battle_end_t": -1.0, "battle_winner": "",
		"battle_guns_taken": 0,
		"witnesses": 0, "witness_runs": 0, "witness_searches": 0,   # 0.19.1: свидетели
		"escape_waves": 0, "escape_bandits": 0, "hatches_locked": 0,   # 0.20: пожарные лестницы
		"blog": {}}   # 0.18: замер боёв — «фракция:оружие:shot/hit/friendly/kill→жертва» → сколько
## 0.10 — шум этажа: громкие события (выстрелы, взрывы, крики, драки) копятся независимо от того, кто шумел.
## Порог → через 10–20 с «Где-то в вентиляции защёлкало…» и +1 щелкун подальше от героя (этажи 3+).
var office_hostile := false     # 0.15: офисники против героя (видели нападение / доложили); сброс на этаже
var faction_war_on := false     # 0.15: бандиты и офисники заметили друг друга
# 0.16: спецэтажи — каждый 5-й с 5-го: 50% обычный, 50% спец (пока только логово; 0.17 — укреплённый офис,
# 0.18 — поле битвы, тогда — поровну). Логово: без зомби и ПК, 6–10 бандитов, выход — по ключ-карте.
const SPECIALS := ["lair", "fort", "battle"]   # 0.17: + укреплённый офис; 0.18: + поле битвы
const FINAL_FLOOR := 30           # 0.19: последний этаж — крыша с вертолётом (финал)
var heli_phase := ""              # 0.19: крыша — "wait" / "landing" / "landed" / "leaving"
var heli_node: Node3D = null
var heli_rotor: Node3D = null
var heli_t := 0.0
var heli_snd_t := 0.0
var elites: Array = []
var beaten := 0                     # 0.19: сколько раз игра пройдена (save)
var esc_t := -1.0                  # 0.20: до следующей волны с пожарных лестниц (-1 — ещё не началось)
var esc_nodes: Array = []          # 0.20: люки (квады в стене)
var vent := {}                     # 0.21: герой ползёт по вентиляции {from, to, t, dur}; пусто — нет
var vent_release := false          # после входа/выхода — отпусти кнопку, иначе сразу полезет обратно
var vent_cam: Node3D = null        # точка, за которой камера едет вдоль трубы
var vent_snd := 0.0
var hatch_hold := 0.0              # 0.20: сколько держим «ЗАКРЫТЬ» у люка
var hatch_noise := 0.0
var battle_phase := ""        # 0.18: поле битвы — "calm" (ещё не встретились) / "fight" / "after" (победители)
var battle_won: Array = []     # 0.18: победители, ещё не пошедшие за трофеем (дерутся — подождут)
var battle_seek_t := 0.0       # 0.18.1: в бою раз в 8 с отставшие идут к ближайшему врагу (без ничьих)
var floor_kind := "normal"
var key_taken := false         # 0.16: ключ-карта логова подобрана — лифт открыт
var key_holder: Human = null   # у кого ключ-карта (пока не упала)
var disguise_blown := false    # 0.16: бандиты раскусили маскировку (до конца этажа)
var fire_fx: Array = []        # 0.16: пламя в бочках логова (анимация)
const START_KIT := {"bottle": 2}  # 0.13: стартовый набор (слоты: бутылки и кирпич в одном слоте)
var swap_pk: Dictionary = {}    # 0.13: лежащий рядом предмет, который можно взять ЗАМЕНОЙ (кнопка «Заменить»)
const DEEP_FLOOR := 10        # 0.11.1: с этого этажа отряды зачистки больше (6 и 4)
const NOISE_STEP := 18.0       # порог на каждого следующего щелкуна: 18, 36
const NOISE_DECAY := 0.03       # шум медленно стихает (~2 в минуту)
var noise_on := false
var noise_pending := -1.0       # через сколько секунд придёт щелкун на шум (-1 — не ждём)
var noise_from_player := false  # emit_noise: текущий шум поднял герой (source == null) — для «приманки» щелкуна
var squad_first_t := -1.0       # когда на этаж приехал первый отряд (для first_contact)
var human_wary := false         # …а на прошлом заметили — теперь отряды осторожнее (чаще вместе)
var fx: Fx
var sfx: Sfx
var hud: Hud
var stats := {"kills": 0, "knockouts": 0, "hacked": 0, "floors": 0}
var run_from := 1       # 0.20.3: с какого этажа (и типа) начат забег — «ЕЩЁ РАЗ» после смерти начинает оттуда же
var run_kind := ""
var password: Array = []
var hacked := 0
var quote := ""
var death_line := ""
var cam_yaw := 0.0
var cam_target: Node3D = null   # 0.19.1: для раскадровок — камера следит не за героем
var cam_pos := Vector3.ZERO
var cam_dist := CAM_DIST
var shake_t := 0.0
var hack_noise_t := 0.0
var type_t := 0.0
var elev_hold := 0.0
var ctx := {}            # что сейчас можно сделать кнопкой-контекстом
var ctx_held := false
var autotest := false
var autotest_log_t := 0.0
var rng := RandomNumberGenerator.new()
var alert_count := 0

var world_vp: SubViewport
var world_rect: TextureRect
var level_root: Node3D
var camera: Camera3D
var env: Environment


func _ready() -> void:
	rng.randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	_load_save()
	sfx = Sfx.new()
	add_child(sfx)
	_build_world()
	hud = Hud.new()
	add_child(hud)
	hud.game = self
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	# 0.20.3: в тестах-сценах (не бот) «только приехал» выключено — сцены ставят врагов сразу после загрузки этажа
	for a in ["--itemtest", "--perftest", "--npcwatch", "--aitest", "--balancetest", "--posetest"]:
		if a in OS.get_cmdline_user_args():
			grace_off = true
	if "--itemtest" in OS.get_cmdline_user_args():
		start_run()
		var t: Node = load("res://scripts/tests/item_test.gd").new()
		add_child(t)
		t.run(self)
	elif "--perftest" in OS.get_cmdline_user_args():
		start_run()
		var pa := OS.get_cmdline_user_args()
		var ptn: Node = load("res://scripts/tests/perf_test.gd").new()
		add_child(ptn)
		ptn.run(self, int(pa[pa.find("--perftest") + 1]))
	elif "--npcwatch" in OS.get_cmdline_user_args():
		# наблюдение за NPC без игрока (scripts/tests/npc_watch.gd): «-- --npcwatch <этаж> <секунд>»
		start_run()
		var na := OS.get_cmdline_user_args()
		var ni := na.find("--npcwatch")
		var nw: Node = load("res://scripts/tests/npc_watch.gd").new()
		add_child(nw)
		nw.run(self, int(na[ni + 1]) if ni + 1 < na.size() else 5, float(na[ni + 2]) if ni + 2 < na.size() else 240.0)
	elif "--aitest" in OS.get_cmdline_user_args():
		start_run()
		var at: Node = load("res://scripts/tests/ai_test.gd").new()
		add_child(at)
		at.run(self)
	elif "--balancetest" in OS.get_cmdline_user_args():
		_load_floor(3, false)
		var bt: Node = load("res://scripts/tests/balance_test.gd").new()
		add_child(bt)
		bt.run(self)
	elif "--posetest" in OS.get_cmdline_user_args():
		start_run()
		var args := OS.get_cmdline_user_args()
		var pt: Node = load("res://scripts/tests/pose_test.gd").new()
		add_child(pt)
		if "--humans" in args:
			pt.run_humans(self, args[args.find("--posetest") + 1])
		elif "--v08" in args:
			pt.run_08(self, args[args.find("--posetest") + 1])
		elif "--readme" in args:
			pt.run_readme(self, args[args.find("--posetest") + 1])
		elif "--vent" in args:
			pt.run_vent(self, args[args.find("--posetest") + 1])
		elif "--escape" in args:
			pt.run_escape(self, args[args.find("--posetest") + 1])
		elif "--witness" in args:
			pt.run_witness(self, args[args.find("--posetest") + 1])
		elif "--roof" in args:
			pt.run_roof(self, args[args.find("--posetest") + 1])
		elif "--battle" in args:
			pt.run_battle(self, args[args.find("--posetest") + 1])
		elif "--fort" in args:
			pt.run_fort(self, args[args.find("--posetest") + 1])
		elif "--lair" in args:
			pt.run_lair(self, args[args.find("--posetest") + 1])
		elif "--officewar" in args:
			pt.run_office_war(self, args[args.find("--posetest") + 1])
		elif "--office" in args:
			pt.run_office(self, args[args.find("--posetest") + 1])
		elif "--vaulthud" in args:
			pt.run_vault_hud(self, args[args.find("--posetest") + 1])
		elif "--v14" in args:
			pt.run_v014(self, args[args.find("--posetest") + 1])
		elif "--glimpse" in args:
			pt.run_glimpse(self, args[args.find("--posetest") + 1])
		elif "--cover" in args:
			pt.run_cover(self, args[args.find("--posetest") + 1])
		elif "--slots" in args:
			pt.run_slots(self, args[args.find("--posetest") + 1])
		elif "--v12" in args:
			pt.run_v012(self, args[args.find("--posetest") + 1])
		elif "--clicker" in args:
			pt.run_clicker(self, args[args.find("--posetest") + 1])
		elif "--anim" in args:
			pt.run_anim(self, args[args.find("--posetest") + 1])
		elif "--v07" in args:
			pt.run_07(self, args[args.find("--posetest") + 1])
		elif "--menu" in args:
			pt.run_menu(self, args[args.find("--posetest") + 1], int(args[args.find("--menu") + 1]))
		elif "--silhouette" in args:
			pt.run_silhouette(self, args[args.find("--posetest") + 1])
		else:
			pt.run(self, args[args.find("--posetest") + 1])
	elif autotest:
		print("[autotest] старт")
		# «--seed N» — повторяемый прогон (этажи и случайности ИИ): найти удачный без графики, потом записать видео
		var args := OS.get_cmdline_user_args()
		var sd := args.find("--seed")
		if sd >= 0 and sd + 1 < args.size():
			rng.seed = int(args[sd + 1])
			seed(int(args[sd + 1]))
			print("[autotest] зерно ", args[sd + 1])
		start_run()
		# «--start-floor 3» — сразу на нужный этаж, «--squad-now» — отряд людей приезжает сразу
		var sf := args.find("--start-floor")
		if sf >= 0 and sf + 1 < args.size():
			floor_num = int(args[sf + 1])
			_load_floor(floor_num, false)
		# «--kit» — снаряжение, с которым игрок обычно доходит до глубоких этажей (для финала)
		if "--kit" in args:
			for id in {"pistol": 6, "uzi": 15, "knife": 5, "medkit": 1, "grenade": 2}:
				player.add_item(id, {"pistol": 6, "uzi": 15, "knife": 5, "medkit": 1, "grenade": 2}[id])
		# «--arena» — бот с арсеналом охотится на отряды людей, меняя оружие (scripts/tests/smart_bot.gd)
		if "--smart" in args or "--arena" in args:
			_bot_smart = load("res://scripts/tests/smart_bot.gd").new()
			_bot_smart.arena = "--arena" in args
		if "--squad-now" in args:
			for w in waves:
				w.time = 0.0
	else:
		_go_title()


func _build_world() -> void:
	world_vp = SubViewport.new()
	world_vp.size = Vector2i(426, LOW_RES_H)
	world_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_vp.msaa_3d = Viewport.MSAA_DISABLED
	world_vp.audio_listener_enable_3d = false
	add_child(world_vp)
	world_rect = TextureRect.new()
	world_rect.texture = world_vp.get_texture()
	world_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_rect.stretch_mode = TextureRect.STRETCH_SCALE
	world_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_rect)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.035, 0.045)
	env.fog_density = 0.045
	var we := WorldEnvironment.new()
	we.environment = env
	world_vp.add_child(we)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 60.0
	world_vp.add_child(camera)
	camera.current = true
	level_root = Node3D.new()
	world_vp.add_child(level_root)
	world_vp.add_child(PS1PostFX.new())


func _on_resize() -> void:
	var s := get_viewport().get_visible_rect().size
	var aspect := s.x / maxf(1.0, s.y)
	world_vp.size = Vector2i(roundi(LOW_RES_H * aspect), LOW_RES_H)


# ================================================================ сохранение
func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://save.cfg") == OK:
		best_floor = cf.get_value("game", "best_floor", 0)
		max_reached = cf.get_value("game", "max_reached", best_floor + 1)
		beaten = cf.get_value("game", "beaten", 0)
		sfx_muted_saved = cf.get_value("game", "muted", false)
	# тестовая сборка для автора (export-пресет «Android Cheat», фича cheat): начинать можно до 30-го этажа
	if OS.has_feature("cheat"):
		max_reached = maxi(max_reached, CHEAT_FLOOR)


var sfx_muted_saved := false
var max_reached := 1   # самый дальний этаж, на который приезжал (для «Играть с этажа N»)
const CHEAT_FLOOR := 30   # в чит-сборке «Играть с этажа» открыто до него
var cheat_kind := ""   # 0.18.2: чит-сборка — тип первого этажа из «Играть с этажа» ("" — как повезёт)
const CHEAT_KINDS := [["", "КАК ПОВЕЗЁТ"], ["normal", "ОБЫЧНЫЙ"], ["lair", "ЛОГОВО"], ["fort", "УКР. ОФИС"], ["battle", "ПОЛЕ БИТВЫ"]]


## Чит-сборка (или --cheatmenu для скриншота): на экране «Играть с этажа» можно выбрать тип этажа.
func cheat_menu() -> bool:
	return OS.has_feature("cheat") or "--cheatmenu" in OS.get_cmdline_user_args()


## Этажи, с которых можно начать: 5, 10, 15… — до самого дальнего, куда доезжал.
func start_floors() -> Array:
	var out: Array = []
	var n := 5
	while n <= max_reached:
		out.append(n)
		n += 5
	return out


func _save() -> void:
	if autotest or "--itemtest" in OS.get_cmdline_user_args() or "--posetest" in OS.get_cmdline_user_args():
		return
	var cf := ConfigFile.new()
	cf.set_value("game", "best_floor", best_floor)
	cf.set_value("game", "max_reached", max_reached)
	cf.set_value("game", "beaten", beaten)
	cf.set_value("game", "muted", sfx.muted)
	cf.save("user://save.cfg")


# ================================================================ этажи
func _go_title() -> void:
	state = "title"
	state_t = 0.0
	sfx.set_muted(sfx_muted_saved)
	_load_floor(1, true)


## Новый забег с этажа from (1 — обычный старт; 5, 10… — из меню «Играть с…»).
## Набор всегда стартовый (2 бутылки + кирпич, 100 hp) — с дальнего этажа сознательно тяжело.
func start_run(from: int = 1, kind: String = "") -> void:
	if from >= FINAL_FLOOR:
		kind = ""   # 30-й — всегда крыша
	floor_num = from
	run_from = from
	run_kind = kind
	stats = {"kills": 0, "knockouts": 0, "hacked": 0, "floors": 0, "time": 0.0, "alerts": 0, "from": from}
	player = null
	spotted_by_humans = false
	_load_floor(from, false, kind)
	player.hp = 100.0
	player.inv = {}
	# 0.13: бутылки и кирпич — один слот «метаемое», поэтому старт — только 2 бутылки (было 2 бутылки + кирпич)
	for id in START_KIT:
		player.add_item(id, START_KIT[id])
	player.selected = "bottle"
	sfx.start_ambience()


## kind — тип этажа ("normal" / "lair"); пусто — решает _floor_kind_for (спецэтаж каждый 5-й с шансом 50%).
func _load_floor(n: int, demo: bool, kind: String = "") -> void:
	var keep_hp := 100.0
	var keep_inv := {}
	var keep_sel := ""
	if player != null and is_instance_valid(player):
		keep_hp = player.hp
		keep_inv = player.inv.duplicate()
		keep_sel = player.selected
	for c in level_root.get_children():
		level_root.remove_child(c)
		c.queue_free()
	enemies.clear()
	projectiles.clear()
	bullets.clear()
	pickups.clear()
	squads.clear()
	floor_t = 0.0
	arrive_t = -1.0
	human_kills = 0
	click_waves.clear()
	_reset_npc_stats()
	noise_on = not demo and n >= 3
	noise_pending = -1.0
	squad_first_t = -1.0
	office_hostile = false   # 0.15: агро офисников спадает на следующем этаже
	faction_war_on = false
	key_taken = false
	key_holder = null
	disguise_blown = false
	fire_fx.clear()
	battle_phase = ""
	battle_won.clear()
	heli_phase = ""
	heli_node = null
	heli_rotor = null
	elites.clear()
	esc_t = -1.0
	esc_nodes.clear()
	hatch_hold = 0.0
	if vent_cam != null and cam_target == vent_cam:
		cam_target = null
	vent = {}
	vent_cam = null
	if env != null:
		env.background_color = Color(0.03, 0.035, 0.045)   # крыша меняет небо — обычным этажам вернуть
		env.fog_light_color = Color(0.03, 0.035, 0.045)
	floor_kind = kind if kind != "" else ("normal" if demo else _floor_kind_for(n))
	if floor_kind in ["lair", "fort", "battle", "roof"]:
		noise_on = false   # логово: без зомби — и щелкунов на шум нет
	if not demo:
		human_wary = spotted_by_humans
		spotted_by_humans = false
	waves = _plan_waves(n) if not demo and floor_kind == "normal" else []
	L = OfficeLevel.generate(n, rng.randi(), floor_kind)
	view = LevelView.new()
	level_root.add_child(view)
	view.build(L)
	fx = Fx.new()
	level_root.add_child(fx)
	var st: Dictionary = L.start_elev
	player = Player.new()
	level_root.add_child(player)
	player.setup(self, L, st.stand, st.angle)
	player.hp = keep_hp
	player.inv = keep_inv
	player.selected = keep_sel
	player.invuln = 1.5
	if demo:
		player.frozen = true
		player.visible = false
	if floor_kind == "lair":
		_spawn_lair(n)
	elif floor_kind == "roof":
		_spawn_roof(n)
	elif floor_kind == "battle":
		_spawn_battle(n)
	elif floor_kind == "fort":
		_spawn_fort(n)
	else:
		_spawn_enemies(n)
	_build_fires()
	_build_escapes()
	_build_vents()
	password.clear()
	for i in 5:
		password.append(rng.randi_range(0, 9))
	hacked = 0
	for i in L.pcs.size():
		view.set_pc_screen(i, 0)
	view.set_exit_unlocked(floor_kind in ["fort", "battle"])
	view.set_door_open(0.0)
	cam_yaw = st.angle if not demo else 0.0
	cam_yaw = _nice_yaw(cam_yaw)
	cam_pos = player.position
	quote = QUOTES[rng.randi_range(0, QUOTES.size() - 1)]
	hud.set_level(L)
	alert_count = 0
	if not demo:
		state = "intro"
		state_t = 0.0
		arrive_grace = 0.0 if grace_off else ARRIVE_GRACE   # идёт только в игре: вступление + 3 с
	var deep := minf(1.0, (n - 1) / 12.0)
	env.fog_density = 0.04 + deep * 0.03
	if floor_kind == "roof":
		env.fog_density = 0.022   # 0.19: на открытой крыше видно дальше


## Камера смотрит «за спину» — но округляем до 90°, чтобы стены шли ровно.
func _nice_yaw(a: float) -> float:
	return roundf(a / (PI / 2)) * (PI / 2)


func _spawn_enemies(n: int) -> void:
	var count := mini(24, 5 + int(n * 1.6))
	var w: Dictionary
	if n == 1: w = {"zombie": 80, "woman": 20}
	elif n == 2: w = {"zombie": 65, "woman": 30, "fat": 5}
	elif n < 6: w = {"zombie": 50, "woman": 30, "fat": 20}
	else: w = {"zombie": 40, "woman": 30, "fat": 30}
	var sp: Vector3 = L.start_elev.stand
	var dist := L.bfs_dist(floori(sp.x), floori(sp.z))
	# 0.20.3: в стартовой комнате героя (и в 14 шагах) врагов нет — зайти могут потом
	var used: Array = []
	var hack_cells := {}
	for pc in L.pcs:
		hack_cells[pc.sz * L.W + pc.sx] = true
	# часть зомби «работает» за компьютерами
	var spots := L.work_spots.duplicate()
	_shuffle(spots)
	var workers := int(count * 0.35)
	for s in spots:
		if workers <= 0: break
		var ci := floori(s.z) * L.W + floori(s.x)
		if hack_cells.has(ci) or dist[ci] < 10 or L.in_start_zone(ci, dist): continue
		var kind := "zombie" if rng.randf() < 0.65 else "woman"
		_add_enemy(kind, Vector3(s.x, 0, s.z), s.ang, true)
		used.append(Vector2(s.x, s.z))
		workers -= 1
		count -= 1
	var tries := 0
	while count > 0 and tries < 2000:
		tries += 1
		var x := rng.randi_range(1, L.W - 2)
		var z := rng.randi_range(1, L.H - 2)
		var ci := z * L.W + x
		if not L.walkable(x, z) or dist[ci] < 12 or L.in_start_zone(ci, dist): continue
		var pos := Vector2(x + 0.5, z + 0.5)
		var close := false
		for u in used:
			if pos.distance_to(u) < 3.0: close = true
		if close: continue
		var kind := _weighted(w)
		_add_enemy(kind, Vector3(pos.x, 0, pos.y), rng.randf() * TAU, false)
		used.append(pos)
		count -= 1
	_spawn_clickers(n, dist)


## Щелкуны (0.9): с 3-го этажа, немного (3–4: 1; 5–7: 1–2; 8+: 2–3). Не ближе 15 м к старту героя и друг к другу,
## не ближе 5 м к компьютерам и к лифту-выходу (иначе вынужденный укус при взломе/у лифта).
func _spawn_clickers(n: int, dist: PackedInt32Array) -> void:
	if n < 3:
		return
	var want := 1 if n < 5 else (rng.randi_range(1, 2) if n < 8 else rng.randi_range(2, 3))
	var placed: Array = []
	var sp: Vector3 = L.start_elev.stand
	var ex: Vector3 = L.exit_elev.stand
	for _try in 3000:
		if placed.size() >= want:
			break
		var x := rng.randi_range(1, L.W - 2)
		var z := rng.randi_range(1, L.H - 2)
		if not L.walkable(x, z) or dist[z * L.W + x] < 15 or L.in_start_zone(z * L.W + x, dist):
			continue
		var p := Vector2(x + 0.5, z + 0.5)
		if p.distance_to(Vector2(sp.x, sp.z)) < 15.0 or p.distance_to(Vector2(ex.x, ex.z)) < 5.0:
			continue
		var bad := false
		for pc in L.pcs:
			if p.distance_to(Vector2(pc.sx + 0.5, pc.sz + 0.5)) < 5.0: bad = true
		for q in placed:
			if p.distance_to(q) < 15.0: bad = true
		if bad:
			continue
		var c := Clicker.new()
		level_root.add_child(c)
		c.setup_clicker(self, L, Vector3(p.x, 0, p.y), rng.randf() * TAU)
		enemies.append(c)
		placed.append(p)


## Громкое событие — в шум этажа (0.10).
func add_noise(v: float) -> void:
	if npc_stats.is_empty():
		return
	npc_stats.noise += v
	npc_stats.noise_total += v


## Шум этажа стихает; превысил порог — через 10–20 с приходит щелкун (этажи 3–5: +1, с 6-го: до +2).
func _update_noise(dt: float) -> void:
	if not noise_on or npc_stats.is_empty():
		return
	npc_stats.noise = maxf(0.0, npc_stats.noise - NOISE_DECAY * dt)
	var cap := 1 if floor_num < 6 else 2
	var came: int = npc_stats.noise_clickers
	if noise_pending < 0.0:
		if came < cap and npc_stats.noise >= NOISE_STEP * (came + 1):
			noise_pending = rng.randf_range(10.0, 20.0)
		return
	noise_pending -= dt
	if noise_pending <= 0.0:
		noise_pending = -1.0
		if _spawn_noise_clicker():
			npc_stats.noise_clickers += 1
			hud.toast("Где-то в вентиляции защёлкало…", Color(0.8, 0.6, 1.0), 3.5)
			if autotest:
				print("[autotest] щелкун пришёл на шум (шум %.1f)" % npc_stats.noise)


## Щелкун на шум: подальше от героя (≥ 22 шагов пути), не на голове у бандитов, не у ПК и лифтов.
func _spawn_noise_clicker() -> bool:
	var from := player.position
	if not L.walkable(floori(from.x), floori(from.z)):
		from = L.start_elev.stand   # героя нет на этаже (--aitest)
	var dist := L.bfs_dist(floori(from.x), floori(from.z))
	var ex: Vector3 = L.exit_elev.stand
	for _try in 2000:
		var x := rng.randi_range(1, L.W - 2)
		var z := rng.randi_range(1, L.H - 2)
		if not L.walkable(x, z) or dist[z * L.W + x] < 22:
			continue
		var p := Vector2(x + 0.5, z + 0.5)
		if p.distance_to(Vector2(ex.x, ex.z)) < 5.0:
			continue
		var bad := false
		for e: Enemy in enemies:
			if e is Human and not e.is_dead() and p.distance_to(Vector2(e.px(), e.pz())) < 8.0:
				bad = true
				break
		for pc in L.pcs:
			if p.distance_to(Vector2(pc.sx + 0.5, pc.sz + 0.5)) < 4.0: bad = true
		if bad:
			continue
		var c := Clicker.new()
		level_root.add_child(c)
		c.setup_clicker(self, L, Vector3(p.x, 0, p.y), rng.randf() * TAU)
		enemies.append(c)
		return true
	return false


## Щелчок щелкуна: бандиты рядом затихают, на экране — волна (радар + над щелкуном).
func clicker_click(c: Clicker) -> void:
	sfx.play_at("click_c", c.position, player.position, 1.0, 14.0)
	click_waves.append({"pos": c.position, "t": 0.0})
	for e: Enemy in enemies:
		if e is Human:
			(e as Human).hear_click(c.position)


func _add_enemy(kind: String, pos: Vector3, ang: float, working: bool) -> void:
	var e := Enemy.new()
	level_root.add_child(e)
	e.setup(self, L, kind, pos, ang, working)
	enemies.append(e)


func _weighted(w: Dictionary) -> String:
	var total := 0.0
	for k in w: total += w[k]
	var r := rng.randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0: return k
	return w.keys()[0]


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ================================================================ цикл
func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	state_t += dt
	match state:
		"title":
			_update_world(dt, false)
			var a := state_t * 0.06
			var c := Vector3(L.W * 0.5, 0, L.H * 0.5)
			_place_camera(c + Vector3(sin(a) * 8.0, 0, cos(a) * 8.0), a + PI, 14.0, dt, true)
		"intro":
			_update_world(dt, false)
			_follow_camera(dt)
			if state_t > 3.0 or (autotest and state_t > 0.5):
				state = "play"
				state_t = 0.0
		"play":
			_update_play(dt)
		"victory":
			_update_victory(dt)
		"elevator":
			_update_elevator(dt)
		"dead":
			_update_world(dt, true)
			_follow_camera(dt)
			if state_t > 2.5:
				state = "gameover"
				state_t = 0.0
				if autotest:
					print("[autotest] игрок погиб на этаже ", floor_num)
					get_tree().quit()
		"gameover", "pause", "howto":
			pass
		"floors":
			_update_world(dt, false)
			var a2 := state_t * 0.06
			var c2 := Vector3(L.W * 0.5, 0, L.H * 0.5)
			_place_camera(c2 + Vector3(sin(a2) * 8.0, 0, cos(a2) * 8.0), a2 + PI, 14.0, dt, true)
	hud.update_hud(dt)


func _update_world(dt: float, with_player: bool) -> void:
	if with_player:
		player.update(dt, Vector2.ZERO)
	else:
		player.update_light(dt)
	for e: Enemy in enemies:
		e.update(dt)
	_update_fires(dt)   # 0.16: пламя в бочках логова
	_update_battle(dt)   # 0.18: поле битвы — кто победил
	_update_roof(dt)   # 0.19: крыша — вертолёт и элита
	_update_escapes(dt)   # 0.20: волны бандитов с пожарных лестниц
	_separate()
	var i := projectiles.size() - 1
	while i >= 0:
		var p: Projectile = projectiles[i]
		p.update(dt)
		if p.done:
			p.queue_free()
			projectiles.remove_at(i)
		i -= 1
	i = bullets.size() - 1
	while i >= 0:
		var b: Bullet = bullets[i]
		b.update(dt)
		if b.done:
			b.queue_free()
			bullets.remove_at(i)
		i -= 1
	_update_squads(dt)
	_update_noise(dt)
	_update_pickups(dt)
	var w := click_waves.size() - 1
	while w >= 0:
		click_waves[w].t += dt
		if click_waves[w].t > 1.2:
			click_waves.remove_at(w)
		w -= 1
	fx.update(dt)


func _update_play(dt: float) -> void:
	stats.time = float(stats.get("time", 0.0)) + dt
	arrive_grace = maxf(0.0, arrive_grace - dt)
	_update_vent(dt)
	var mv := _read_move()
	if autotest:
		mv = _autopilot(dt)
	player.update(dt, mv)
	_update_world(dt, false)
	_update_silhouettes()
	_update_waves(dt)
	_update_context(dt)
	_follow_camera(dt)
	_blink_pcs()


## Движение из стика (экранные координаты) -> мир с учётом поворота камеры.
func _read_move() -> Vector2:
	var s: Vector2 = hud.move_vec
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): k.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): k.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): k.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): k.x += 1
	if k != Vector2.ZERO:
		s = k.normalized() * (0.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	# вперёд по экрану = от камеры
	var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
	return right * s.x + fwd * (-s.y)


func _separate() -> void:
	var all: Array = enemies.duplicate()
	all.append(player)
	for i in all.size():
		var a: Actor = all[i]
		if a is Enemy and a.is_down(): continue
		for j in range(i + 1, all.size()):
			var b: Actor = all[j]
			if b is Enemy and b.is_down(): continue
			var d := Vector2(b.position.x - a.position.x, b.position.z - a.position.z)
			var min_d := a.radius + b.radius
			var l := d.length()
			if l < min_d and l > 0.0001:
				var push := d / l * (min_d - l) * 0.5
				if a is Player:
					b.move(push.x * 2.0, push.y * 2.0)
				elif b is Player:
					a.move(-push.x * 2.0, -push.y * 2.0)
				else:
					a.move(-push.x, -push.y)
					b.move(push.x, push.y)


# ---------------------------------------------------------------- камера
func _follow_camera(dt: float) -> void:
	_place_camera(cam_target.position if is_instance_valid(cam_target) else player.position, cam_yaw, cam_dist, dt, false)


func _place_camera(target: Vector3, yaw: float, dist: float, dt: float, instant: bool) -> void:
	cam_pos = target if instant else cam_pos.lerp(target, minf(1.0, dt * 8.0))
	# если стена заслоняет героя — камера плавно поднимается почти вертикально
	var want := CAM_PITCH
	if player != null and player.visible and _occluded(cam_pos, yaw, CAM_PITCH, dist):
		want = deg_to_rad(76.0)
	cam_pitch = want if instant else lerpf(cam_pitch, want, minf(1.0, dt * 4.0))
	var off := Vector3(sin(yaw) * cos(cam_pitch), sin(cam_pitch), cos(yaw) * cos(cam_pitch)) * dist
	var shake := Vector3.ZERO
	if shake_t > 0.0:
		shake_t = maxf(0.0, shake_t - dt)
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake_t * 0.4
	var look := cam_pos + Vector3(0, 0.8, 0)
	camera.position = look + off + shake
	camera.look_at(look + shake, Vector3.UP)


var cam_pitch := CAM_PITCH


## Луч от камеры к груди героя проходит через стену/шкаф ниже их верха?
func _occluded(target: Vector3, yaw: float, pitch: float, dist: float) -> bool:
	var head := target + Vector3(0, 1.1, 0)
	var eye := target + Vector3(0, 0.8, 0) + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	for i in range(1, 24):
		var p := head.lerp(eye, i / 24.0)
		if p.y > OfficeLevel.WALL_H: break
		var c := L.cell(floori(p.x), floori(p.z))
		if c == OfficeLevel.WALL or (c == OfficeLevel.TALL and p.y < 1.9):
			return true
	return false


## Силуэт врага за стеной: только если стена закрывает его от камеры И (он ближе 7 м к герою ИЛИ охотится
## на героя). Красный — охотится, тускло-оранжевый — просто рядом. Не волхак: дальних спокойных не видно.
## Проверка по сетке, каждый враг раз в 6 кадров.
var _sil_frame := 0


func _update_silhouettes() -> void:
	_sil_frame += 1
	var cam := camera.global_position
	for i in enemies.size():
		var e: Enemy = enemies[i]
		if e.is_dead():
			e.model.set_silhouette(0)
			continue
		if (i + _sil_frame) % 6 != 0:
			continue
		var hunting := e.hunts_player()
		var mode := 0
		if (hunting or e.dist_to(player) < 7.0) and _wall_between(e.position + Vector3(0, 1.0, 0), cam):
			mode = 2 if hunting else 1
		e.model.set_silhouette(mode)


## Стена/шкаф на луче от точки к камере (ниже их верха)?
func _wall_between(from: Vector3, to: Vector3) -> bool:
	for k in range(1, 20):
		var p := from.lerp(to, k / 20.0)
		if p.y > OfficeLevel.WALL_H: break
		var c := L.cell(floori(p.x), floori(p.z))
		if c == OfficeLevel.WALL or (c == OfficeLevel.TALL and p.y < 1.9):
			return true
	return false


func rotate_camera(d: float) -> void:
	cam_yaw = wrapf(cam_yaw + d, -PI, PI)


func shake(amount: float) -> void:
	shake_t = maxf(shake_t, amount)


# ---------------------------------------------------------------- шум
## Шум слышат враги в радиусе r (за стенами — хуже). ring — показать кольцо на полу.
func emit_noise(pos: Vector3, r: float, kind: String, ring: bool = false, extra: Vector3 = Vector3.ZERO, source: Node = null) -> void:
	noise_from_player = source == null   # без источника шумят только герой и его броски
	for e: Enemy in enemies:
		if e != source and not (noise_from_player and hero_hidden()):
			e.hear(pos, r, kind, extra)
	noise_from_player = false
	match kind:
		"gun": add_noise(1.0)
		"boom": add_noise(4.0)
		"shout": add_noise(2.0)
	if source == null and (kind == "gun" or kind == "boom"):
		bandits_locate(pos)
	if ring and fx != null:
		var col := Color(0.8, 0.8, 0.8, 0.5)
		match kind:
			"distract": col = Color(0.4, 0.8, 1.0, 0.8)
			"gun", "boom": col = Color(1.0, 0.35, 0.25, 0.9)
		fx.noise_ring(pos, r, col)


## 0.12: ГРОМКОЕ от героя (выстрел, взрыв, драка кулаками) в ~8 м от бандита — его отряд знает, где герой.
## Одна пара идёт в лоб, другая обходит с фланга, стрелок разворачивается и стреляет. Герой присел за мебелью
## (от этого бандита) — знают район, но не точку: идут и ищут рядом.
const LOCATE_R := 8.0
func bandits_locate(pos: Vector3) -> void:
	if player == null or player.dead or player.frozen:
		return
	for sq in squads:
		if not sq.members.is_empty() and (sq.members[0] as Human).is_loyal():
			continue   # 0.15/0.16: лояльные (офисники; бандиты при маскировке) на шум героя не ополчаются
		var near := false
		for h: Human in sq.members:
			if not h.is_dead() and not h.is_down() and Vector2(h.px() - pos.x, h.pz() - pos.z).length() <= LOCATE_R:
				near = true
				break
		if not near:
			continue
		npc_stats.bandit_locates += 1
		var i := 0
		for h: Human in sq.members:
			if h.is_dead() or h.is_down() or h.grabbed_by != null or h.state == Enemy.S.CHOKED:
				continue
			var hidden := Enemy.crouched(player) and L.line_blocked(h.px(), h.pz(), player.px(), player.pz(), 1)
			if hidden:
				if not h.is_hostile():
					h._investigate(player.position + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)), true)
			else:
				var flank: bool = (h.pair_i % 2 == 1) if h.pair_i >= 0 else (i % 2 == 1)
				h.locate_player(flank and not h.is_gunner())
			i += 1


# ---------------------------------------------------------------- взлом / лифт
func _update_context(dt: float) -> void:
	ctx = {}
	if player.dead: return
	var pp := Vector2(player.px(), player.pz())
	for pc in L.pcs:
		if pc.hacked: continue
		if pp.distance_to(Vector2(pc.sx + 0.5, pc.sz + 0.5)) < 1.0:
			ctx = {"kind": "hack", "pc": pc}
			break
	# 0.20: у пожарного люка — «ЗАКРЫТЬ» (держать 3 с)
	if ctx.is_empty():
		for es in L.escapes:
			if not es.locked and pp.distance_to(Vector2(es.stand.x, es.stand.z)) < 1.3:
				ctx = {"kind": "hatch", "esc": es}
	# 0.21: у решётки вентиляции — «ВЕНТ.» (нажать): залез — вылез у другой решётки. Один раз за этаж и только
	# в тревогу (за героем гонятся); без тревоги — «ВЕНТ. ✕» и подсказка.
	if ctx.is_empty() and vent.is_empty():
		for v in L.vents:
			if v.used:
				continue
			for k in ["a", "b"]:
				var e: Dictionary = v[k]
				if pp.distance_to(Vector2(e.stand.x, e.stand.z)) < 1.0:
					ctx = {"kind": "vent", "v": v, "from": e, "to": v["b" if k == "a" else "a"], "ok": any_hostile()}
	var st: Vector3 = L.exit_elev.stand
	if ctx.is_empty() and pp.distance_to(Vector2(st.x, st.z)) < 1.4:
		ctx = {"kind": "elevator"}
	var vpress := ctx_held or Input.is_key_pressed(KEY_E)   # бот вентиляцией не пользуется
	if not vpress:
		vent_release = false
	if ctx.get("kind", "") == "vent" and vpress and not vent_release and not player.frozen:
		vent_release = true
		if ctx.ok:
			ctx.v.used = true
			_enter_vent(ctx.from, ctx.to, ctx.v.len)
			return
		sfx.play("deny")
		hud.toast("Вентиляция — на крайний случай: залезть можно, только когда за тобой гонятся (один раз).", Color(0.45, 0.85, 1.0), 3.0)
	var held := ctx_held or Input.is_key_pressed(KEY_E) or (autotest and bot_hold and not ctx.is_empty())
	if ctx.get("kind", "") == "hack" and held and not player.dead:
		var pc: Dictionary = ctx.pc
		player.hacking = true
		player.crouch = false
		player.turn_to(player.angle_to_point(pc.x + 0.5, pc.z + 0.5), 10.0 * dt)
		pc.progress += dt / (HACK_TIME + hacked * 0.3)
		type_t -= dt
		if type_t <= 0.0:
			type_t = randf_range(0.05, 0.12)
			sfx.play("type", 0.5, 0.3)
		hack_noise_t -= dt
		if hack_noise_t <= 0.0:
			hack_noise_t = 0.6
			emit_noise(player.position, 2.5, "step", false)
		if pc.progress >= 1.0:
			_hack_done(pc)
	else:
		player.hacking = false
	# 0.20: держишь «ЗАКРЫТЬ» у люка 3 с — заблокирован (лязг слышно в 4 м)
	if ctx.get("kind", "") == "hatch" and held:
		hatch_hold += dt
		hatch_noise -= dt
		player.turn_to(player.angle_to_point(ctx.esc.plane.x, ctx.esc.plane.z), 10.0 * dt)
		if hatch_noise <= 0.0:
			hatch_noise = 0.6
			emit_noise(player.position, 4.0, "step", true)
			sfx.play("hit", 0.3)
		if hatch_hold >= HATCH_TIME:
			_lock_hatch(ctx.esc)
	else:
		hatch_hold = 0.0
	if ctx.get("kind", "") == "elevator" and held:
		if not exit_open():
			if elev_hold <= 0.0:
				sfx.play("deny")
				if floor_kind == "roof":
					hud.toast("Вертолёта ещё нет — подойди к площадке." if heli_phase == "wait" else "Сначала разберись с охраной вертолёта.", Color(1, 0.5, 0.4))
				elif floor_kind == "lair":
					hud.toast("Лифт: нужна ключ-карта — она на спине у одного из бандитов (зелёная).", Color(1, 0.5, 0.4))
				else:
					hud.toast("Лифт: нужен пароль (%d/5 цифр). Взломай компьютеры!" % hacked, Color(1, 0.5, 0.4))
			elev_hold = 1.0
		else:
			elev_hold += dt
			if int(elev_hold * 5.0) != int((elev_hold - dt) * 5.0):
				sfx.play("beep", 0.6, 0.0)
			if elev_hold >= 1.2:
				_start_elevator()
	elif not exit_open():
		elev_hold = maxf(0.0, elev_hold - dt)
	else:
		elev_hold = 0.0


func _hack_done(pc: Dictionary) -> void:
	pc.hacked = true
	player.hacking = false
	hacked += 1
	stats.hacked += 1
	view.set_pc_screen(pc.i, 2)
	sfx.play("hack_ok")
	emit_noise(player.position, 4.0, "distract", false)
	var digit: int = password[hacked - 1]
	var rw := Items.roll_reward(rng, player.hp / player.max_hp, player.inv)
	give_reward(rw.id, rw.amount)
	var df := Items.def(rw.id)
	sfx.play("pickup", 0.8)
	hud.reward_popup(hacked, digit, rw)
	if autotest:
		print("[autotest] ПК взломан %d/5, цифра %d, награда %s x%d (%s)" % [hacked, digit, df.name, rw.amount, Items.CAT_NAMES[df.cat]])
	if hacked == 5:
		view.set_exit_unlocked(true)
		sfx.play("ding", 0.6)
		hud.toast("Пароль собран! Беги к лифту!", Color(1, 0.9, 0.3))


## Выдать награду: сверх потолка — лишнее падает на пол рядом с героем (награда не пропадает).
func give_reward(id: String, amount: int) -> void:
	var blocker := player.slot_blocker(id)
	var got := player.add_item(id, amount)
	if got < amount:
		var df := Items.def(id)
		var a := rng.randf() * TAU
		_add_pickup(id, amount - got, player.position + Vector3(cos(a), 0, sin(a)) * 0.7, blocker == "")
		if blocker != "":
			hud.toast("%s: слот занят (%s) — лежит рядом, можно заменить" % [df.name, Items.def(blocker).name], Items.CAT_COLORS[df.cat], 2.4)
		else:
			hud.toast("%s: больше не унести — лишнее на полу" % df.name, Items.CAT_COLORS[df.cat], 2.0)


## 0.13: замена — взять лежащий предмет pk вместо того, что в его слоте. Старое падает на пол со всем запасом.
## Берём сколько влезает до потолка, остаток лежит.
func do_swap(pk: Dictionary = {}) -> bool:
	if pk.is_empty():
		pk = swap_pk
	if pk.is_empty() or not pickups.has(pk) or player.dead:
		return false
	var id: String = pk.id
	var old := player.slot_blocker(id)
	if old == "":
		return false
	var n_old: int = player.inv.get(old, 0)
	player.inv.erase(old)
	var node: Node3D = pk.node
	_add_pickup(old, n_old, Vector3(node.position.x, 0, node.position.z) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)), true)
	var got := player.add_item(id, pk.n)
	player.selected = id
	pk.n -= got
	if pk.n <= 0:
		node.queue_free()
		pickups.erase(pk)
	else:
		pk.blocked = true
	swap_pk = {}
	sfx.play("pickup", 0.8)
	var df := Items.def(id)
	hud.toast("Заменил: %s ×%d → %s ×%d" % [Items.def(old).name, n_old, df.name, got], Items.CAT_COLORS[df.cat], 2.2)
	return true


func _blink_pcs() -> void:
	var ph := int(Time.get_ticks_msec() / 400) % 2
	for i in L.pcs.size():
		if not L.pcs[i].hacked:
			view.set_pc_screen(i, ph)


func _start_elevator() -> void:
	if floor_kind == "roof":
		_board_heli()   # 0.19: с крыши — в вертолёт, конец игры
		return
	state = "elevator"
	state_t = 0.0
	player.frozen = true
	player.hacking = false
	sfx.play("ding", 1.0)
	if autotest:
		print("[autotest] этаж %d пройден" % floor_num)


func _update_elevator(dt: float) -> void:
	var e: Dictionary = L.exit_elev
	view.set_door_open(state_t / 1.0 if state_t < 2.6 else 1.0 - (state_t - 2.6) / 0.8)
	if state_t > 1.0 and state_t < 2.5:
		var inside: Vector3 = e.plane - e.normal * 0.45
		var d := Vector2(inside.x - player.px(), inside.z - player.pz())
		if d.length() > 0.1:
			player.position.x += d.normalized().x * minf(d.length(), 2.2 * dt)
			player.position.z += d.normalized().y * minf(d.length(), 2.2 * dt)
			player.turn_to(atan2(d.x, d.y), 10.0 * dt)
			player.speed_now = 2.2
			player.walk_phase += 2.2 * dt * 4.0
		else:
			player.speed_now = 0.0
			player.turn_to(atan2(e.normal.x, e.normal.z), 8.0 * dt)
	player.update(dt, Vector2.ZERO)
	_update_world(dt, false)
	_follow_camera(dt)
	if state_t > 4.2:
		floor_num += 1
		stats.floors += 1
		if floor_num - 1 > best_floor:
			best_floor = floor_num - 1
		if floor_num > max_reached:
			max_reached = floor_num
		_save()
		player.hp = minf(player.max_hp, player.hp + FLOOR_HEAL)
		_load_floor(floor_num, false)
		if autotest and floor_num > _autotest_floors():
			print("[autotest] OK: дошли до этажа ", floor_num, ", статистика ", stats)
			get_tree().quit()


# ---------------------------------------------------------------- события
func damage_player(dmg: float, from: Enemy, nonlethal: bool = false) -> void:
	if autotest and not ("--mortal" in OS.get_cmdline_user_args()):
		return
	player.hurt(dmg, from.position, nonlethal)


func on_player_dead() -> void:
	state = "dead"
	state_t = 0.0
	death_line = DEATH_LINES[rng.randi_range(0, DEATH_LINES.size() - 1)]
	if floor_num - 1 > best_floor:
		best_floor = floor_num - 1
	_save()


## 0.18: замер боёв людей (npc_stats.blog): «фракция:оружие:что» — выстрел, попадание во врага, по своему, убийство.
func battle_log(h: Node, what: String) -> void:
	if npc_stats.is_empty() or not (h is Human):
		return
	var key := "%s:%s:%s" % [(h as Human).faction, (h as Human).weapon, what]
	npc_stats.blog[key] = int(npc_stats.blog.get(key, 0)) + 1


func on_enemy_killed(e: Enemy, from = null) -> void:
	if e is Human and from == player:
		hero_violence(e as Human)   # 0.19.1: кто из своих видел — реагирует
	if e is Human and from is Human:
		battle_log(from, "kill→" + e.faction)
	if from == player:
		stats.kills += 1
	# 0.10: кто кого убил (баланс фракций)
	if e is Human and e.faction == "office":
		# 0.15: кто убил офисника
		if from == player:
			npc_stats.office_by_hero += 1
		elif from is Human:
			npc_stats.office_by_bandits += 1
		elif from is Enemy:
			npc_stats.office_by_zombies += 1
	elif e is Human and from is Human and (from as Human).faction == "office":
		npc_stats.bandits_by_office += 1
	elif e is Human:
		if from == player:
			npc_stats.humans_by_hero += 1
		elif from is Clicker:
			if (from as Clicker).lure_t > 0.0:
				npc_stats.humans_by_clicker_lured += 1
			else:
				npc_stats.humans_by_clicker += 1
		elif from is Enemy and (from as Enemy).faction == "zombie":
			npc_stats.humans_by_zombies += 1
	elif e.faction == "zombie" and from is Human:
		if (from as Human).stabbing:
			npc_stats.zombies_quiet += 1
		else:
			npc_stats.zombies_open += 1
	fx.decal(e.position, "stain", Color(0.42, 0.02, 0.02, 0.95), 1.3)


func on_enemy_alert(e: Enemy) -> void:
	alert_count += 1
	if e.foe == player:
		stats.alerts = int(stats.get("alerts", 0)) + 1
	if e is Human and e.faction == "human" and not player_disguised():   # 0.15: «запомнили» — только бандиты; 0.16: не в куртке
		spotted_by_humans = true
		if npc_stats.first_contact < 0.0 and squad_first_t >= 0.0:
			npc_stats.first_contact = floor_t - squad_first_t


func spawn_projectile(id: String, from: Vector3, to: Vector3) -> void:
	var p := Projectile.new()
	level_root.add_child(p)
	p.setup(self, L, id, from, to)
	projectiles.append(p)


func any_hostile() -> bool:
	for e: Enemy in enemies:
		if e.hunts_player(): return true
	return false


func any_searching() -> bool:
	for e: Enemy in enemies:
		if e.hot and not e.is_down() and (e.foe == null or e.foe == player): return true
	return false


# ---------------------------------------------------------------- люди
## План приезда отрядов: со 2-го этажа. 2–3 этаж — трое; дальше размер случайный и растёт, с 6-го — второй отряд.
## 0.7: основной отряд — всегда 4 человека (две пары) со 2-го этажа; с 6-го — подкрепление из 3.
func _plan_waves(n: int) -> Array:
	if n < 2:
		return []
	# 0.11.1: с DEEP_FLOOR этажи кишат зомби — бандиты выходят на зачистку бо́льшими составами:
	# основной отряд 6 (три пары), подкрепление 4 (две пары, тоже зачистка)
	var deep := n >= DEEP_FLOOR
	var out := [{"hack": 2, "time": 70.0, "size": 6 if deep else 4, "done": false, "main": true}]
	# 0.15: офисники — на нечётных этажах (кроме 1-го) с шансом 50%, тогда же, что и бандиты (у стартового лифта);
	# 1–6 этажи — 1–3 человека, дальше — 2–5. На таких этажах подкрепления бандитов нет.
	var office := n >= 3 and n % 2 == 1 and rng.randf() < 0.5
	if office:
		out.append({"hack": 2, "time": 70.0, "size": rng.randi_range(1, 3) if n <= 6 else rng.randi_range(2, 5),
			"done": false, "office": true})
	elif n >= 6:
		out.append({"hack": 4, "time": 160.0, "size": 4 if deep else 3, "done": false, "main": false})
	return out


func _update_waves(dt: float) -> void:
	floor_t += dt
	for w in waves:
		if not w.done and (hacked >= w.hack or floor_t >= w.time):
			w.done = true
			if w.get("office", false):
				_spawn_office(w.size)
			else:
				_spawn_squad(w.size, w.get("main", true))
	if arrive_t >= 0.0:
		arrive_t += dt
		view.set_door_open(minf(1.0, arrive_t / 0.8) if arrive_t < 3.0 else maxf(0.0, 1.0 - (arrive_t - 3.0) / 0.8))
		if arrive_t > 3.8:
			arrive_t = -1.0


## Отряд выходит из лифта-выхода и ВМЕСТЕ идёт занимать комнату (фаза travel), там решает, как патрулировать.
## Не больше одного стрелка (узи или болтовка), остальные — нож, топор или кастет.
## Основной отряд из 4 = две пары: «ближняя» (два холодных) и «со стрелком» (холодное + стрелок).
## Подкрепление (main = false) настороже, если основной отряд потерял 2+ человек.
## esc — пожарная лестница (0.20): отряд появляется у неё, а не из лифта-выхода.
func _spawn_squad(size: int, main: bool = true, esc: Dictionary = {}) -> void:
	var e: Dictionary = L.exit_elev if esc.is_empty() else esc
	var nrm: Vector3 = e.normal
	var side := Vector3(nrm.z, 0, -nrm.x)
	var wary := human_wary
	if not main:
		for s in squads:
			if s.get("main", false) and s.members.filter(func(m): return m.is_dead()).size() >= 2:
				wary = true
	var sq := {"members": [], "leader": null, "phase": "travel", "plan": "", "t": 0.0, "wary": wary, "main": main, "pairs": []}
	_squad_new_dest(sq, e.stand)
	# пары (4 или 6 человек) — стрелок последний (последняя пара: холодное + стрелок), иначе случайно
	var paired := size >= 4 and size % 2 == 0
	var gunner := size - 1 if paired else rng.randi_range(0, size - 1)
	for i in size:
		var wid := ""
		if i == gunner:
			wid = "rifle" if rng.randf() < (0.35 if floor_num < 6 else 0.5) else "uzi"
		else:
			wid = _weighted({"knife": 40, "axe": 35, "knuckles": 25})
		var pos: Vector3 = e.plane + nrm * 0.45 + side * ((i % 3) - 1) * 0.55 + nrm * (i / 3) * 0.6
		var h := Human.new()
		level_root.add_child(h)
		sq.members.append(h)
		if i == 0:
			sq.leader = h
		h.setup_human(self, L, pos, atan2(nrm.x, nrm.z), wid, sq, "lead" if i == 0 else "follow")
		enemies.append(h)
	if paired:
		for pi in size / 2:
			sq.pairs.append([sq.members[pi * 2], sq.members[pi * 2 + 1]])
		if not wary:
			_start_sweep(sq)
	squads.append(sq)
	if squad_first_t < 0.0:
		squad_first_t = floor_t
	arrive_t = 0.0
	if not esc.is_empty():
		sfx.play_at("hit", e.plane, player.position, 0.8, 30.0)   # лязг люка
		if npc_stats.escape_waves == 0:
			hud.toast("С пожарной лестницы лезут бандиты! Люк можно закрыть.", Color(1, 0.6, 0.35), 3.5)
		npc_stats.escape_waves += 1
		npc_stats.escape_bandits += size
		if autotest:
			print("[autotest] с пожарной лестницы: ", sq.members.map(func(m): return m.weapon))
		return
	sfx.play_at("ding", e.plane, player.position, 1.0, 40.0)
	hud.toast("Где-то звякнул лифт… На этаж кто-то приехал.", Color(1, 0.7, 0.4), 3.5)
	if human_wary:
		hud.toast("Похоже, мародёры тебя запомнили — держатся вместе.", Color(1, 0.55, 0.3), 3.5)
	if autotest:
		print("[autotest] приехал отряд людей: ", sq.members.map(func(m): return m.weapon), " настороже=", human_wary)


## 0.15: офисники приезжают на СТАРТОВОМ лифте и зачищают этаж в сторону лифта-выхода (навстречу бандитам).
## Оружие: стрелок (с 2 человек; с 4 — двое) — револьвер / гвоздомёт / арбалет, остальные — труба / нож / топор.
## Пары по двое (лишний — третьим в последней паре), один — сам по себе.
func _spawn_office(size: int) -> void:
	var e: Dictionary = L.start_elev
	var nrm: Vector3 = e.normal
	var side := Vector3(nrm.z, 0, -nrm.x)
	var sq := {"members": [], "leader": null, "phase": "travel", "plan": "", "t": 0.0, "wary": false, "main": false,
		"pairs": [], "fac": "office"}
	_squad_new_dest(sq, e.stand)
	var gunners := 0 if size == 1 and rng.randf() < 0.5 else (2 if size >= 4 else 1)
	for i in size:
		var wid := ""
		if i >= size - gunners:
			wid = _weighted({"revolver": 45, "nailgun": 35, "crossbow": 20})
		else:
			wid = _weighted({"pipe": 45, "knife": 30, "axe": 25})
		var pos: Vector3 = e.plane + nrm * 0.45 + side * ((i % 3) - 1) * 0.55 + nrm * (i / 3) * 0.6
		var h := Human.new()
		level_root.add_child(h)
		sq.members.append(h)
		if i == 0:
			sq.leader = h
		h.setup_human(self, L, pos, atan2(nrm.x, nrm.z), wid, sq, "lead" if i == 0 else "follow", "office")
		enemies.append(h)
	var m: Array = sq.members
	var pi := 0
	while pi < m.size():
		var pair: Array = m.slice(pi, pi + 2)
		pi += 2
		if pi == m.size() - 1:
			pair.append(m[pi])   # лишний — третьим в эту пару
			pi += 1
		sq.pairs.append(pair)
	squads.append(sq)
	_start_sweep(sq)
	npc_stats.office_spawned += size
	arrive_t = 0.0
	sfx.play_at("ding", e.plane, player.position, 1.0, 40.0)
	hud.toast("Звякнул лифт у входа… Похоже, живые сотрудники — они не против тебя.", Color(0.5, 0.75, 1.0), 3.5)
	if autotest:
		print("[autotest] приехали офисники: ", sq.members.map(func(x): return x.weapon))


## 0.10 — отряд зачистки: сразу из лифта две пары расходятся и крадутся каждая своим списком комнат
## (этаж делится на две стороны по комнатам), в сторону стартового лифта героя. Там встреча — короткий отдых
## всех четверых (squad_meet), потом пары охотятся по этажу как раньше (_squad_settle).
func _start_sweep(sq: Dictionary) -> void:
	# 0.15: офисники идут от стартового лифта к лифту-выходу (обратный порядок комнат, встреча у выхода)
	var office: bool = sq.get("fac", "human") == "office"
	var routes := _build_sweep_routes(sq.pairs.size(), office)
	var meet_elev: Dictionary = L.exit_elev if office else L.start_elev
	sq.phase = "sweep"
	sq.routes = routes
	sq.meet = meet_elev.stand
	sq.meet_t = 0.0
	sq.room = L.rooms[meet_elev.room]
	sq.dest = sq.meet
	sq.plan = "sweep"
	for pi in sq.pairs.size():
		var pair: Array = sq.pairs[pi]
		var lead: Human = pair[0]
		lead.role = "hunt"
		lead.pair_lead = null
		lead.pair_i = pi
		lead.hunt_cd = randf_range(2.0, 5.0)
		for fi in range(1, pair.size()):
			var fol: Human = pair[fi]
			fol.role = "follow"
			fol.pair_lead = lead
			fol.pair_i = pi
	sq.leader = sq.pairs[0][0]
	_squad_resume(sq)
	if autotest:
		print("[autotest] отряд зачистки: пары расходятся сразу, комнат на пару ", routes.map(func(r): return r.size()))


## Списки комнат для двух пар: по комнатам, не по оси. Зерно A — комната дальше всех «в стороне» от пути
## лифт-выход → старт; зерно B — самая далёкая от A (по пути). Комнаты делятся поровну по близости к зёрнам,
## в каждой стороне — до 7 комнат с наименьшим крюком, по порядку от лифта-выхода к старту.
func _build_sweep_routes(k: int = 2, reverse: bool = false) -> Array:
	var ex: Vector3 = L.exit_elev.stand
	var st: Vector3 = L.start_elev.stand
	var de := L.bfs_dist(floori(ex.x), floori(ex.z))
	var ds := L.bfs_dist(floori(st.x), floori(st.z))
	var items: Array = []
	for r in L.rooms:
		if r.corridor or r.area < 9 or r.id == L.exit_elev.room:
			continue
		var c := L.nearest_walkable((r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2, 3)
		if c.x < 0:
			continue
		var a: int = de[c.y * L.W + c.x]
		var b: int = ds[c.y * L.W + c.x]
		if a < 0 or b < 0:
			continue
		items.append({"r": r, "c": c, "de": a, "detour": a + b, "k": 0})
	if items.size() < k:
		var few: Array = [items.map(func(it): return it.r)]
		while few.size() < k:
			few.append([])
		return few
	var seed_a: Dictionary = items[0]
	for it in items:
		if it.detour > seed_a.detour:
			seed_a = it
	var da := L.bfs_dist(seed_a.c.x, seed_a.c.y)
	var seed_b: Dictionary = items[1] if items[0] == seed_a else items[0]
	for it in items:
		if da[it.c.y * L.W + it.c.x] > da[seed_b.c.y * L.W + seed_b.c.x]:
			seed_b = it
	var db := L.bfs_dist(seed_b.c.x, seed_b.c.y)
	for it in items:
		it.k = da[it.c.y * L.W + it.c.x] - db[it.c.y * L.W + it.c.x]
	items.sort_custom(func(a, b): return a.k < b.k)
	# k сторон (0.11.1: на глубине три пары) — подряд идущие куски вдоль оси «ближе к A … ближе к B»
	var out: Array = []
	var per := 7 if k <= 2 else 5
	for s in k:
		var side: Array = items.slice(items.size() * s / k, items.size() * (s + 1) / k)
		side.sort_custom(func(a, b): return a.detour < b.detour)
		var keep: Array = side.slice(0, per)
		if reverse:
			keep.sort_custom(func(a, b): return a.de > b.de)   # офисники: от старта к выходу
		else:
			keep.sort_custom(func(a, b): return a.de < b.de)
		out.append(keep.map(func(it): return it.r))
	return out


## Пары сошлись у стартового лифта (или кто-то ждал 45 с) — короткий отдых всех, с убранным оружием.
func squad_meet(sq: Dictionary) -> void:
	var n := 0
	for h: Human in sq.members:
		if not h.is_dead() and h.state == Enemy.S.REST and h.goal_kind == "meet":
			n += 1
	npc_stats.meet_arrived += n
	sq.phase = "rest"
	sq.t = rng.randf_range(12.0, 20.0)
	for h: Human in sq.members:
		if h.is_dead():
			continue
		h.role = "rest"
		if h.state == Enemy.S.REST:
			h.rest_len = 0.0
			h.goal_kind = "rest"
		elif h.state in [Enemy.S.GUARD, Enemy.S.PATROL, Enemy.S.LOOK]:
			h._resume_role()
	if autotest:
		print("[autotest] пары сошлись у стартового лифта (%d чел.), отдых %d с" % [n, int(sq.t)])


## Новая комната, которую займёт отряд: не коридор, подальше от точки from (12–34 м).
func _squad_new_dest(sq: Dictionary, from: Vector3) -> void:
	var cands: Array = []
	for r in L.rooms:
		if r.corridor or r.area < 16:
			continue
		var c := Vector2((r.x0 + r.x1) * 0.5 + 0.5, (r.z0 + r.z1) * 0.5 + 0.5)
		var d := c.distance_to(Vector2(from.x, from.z))
		if d > 12.0 and d < 34.0:
			cands.append(r)
	if cands.is_empty():
		cands = L.rooms.filter(func(r): return not r.corridor)
	var room: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	var cell := L.nearest_walkable((room.x0 + room.x1) / 2, (room.z0 + room.z1) / 2, 4)
	if cell.x < 0:
		cell = L.random_reachable(from.x, from.z, 10, 30)
	sq.room = room
	sq.dest = Vector3(cell.x + 0.5, 0, cell.y + 0.5)


## 0.8: отряд пришёл в комнату — сначала отдыхает 15–30 с (сидят/стоят у стен, оружие убрано, фонари опущены,
## раненые перевязываются), потом расходится (_squad_settle).
func squad_arrived(sq: Dictionary) -> void:
	sq.phase = "rest"
	sq.t = rng.randf_range(15.0, 30.0)
	for h: Human in sq.members:
		if not h.is_dead():
			h.role = "rest"
	_squad_resume(sq)
	if autotest:
		print("[autotest] отряд занял комнату, отдыхает %d с" % int(sq.t))


## После отдыха — как патрулировать. Если на прошлом этаже люди тебя заметили (wary),
## чаще ходят парами и втроём, но иногда всё равно расходятся.
func _squad_settle(sq: Dictionary) -> void:
	var alive_m: Array = sq.members.filter(func(m): return not m.is_dead())
	if alive_m.is_empty():
		return
	sq.phase = "settled"
	sq.t = rng.randf_range(45.0, 80.0)
	# настороженный отряд (0.10): в первый раз держится вчетвером, на пары расходится позже
	var wary_first: bool = sq.wary and not sq.get("split_once", false) and not sq.get("pairs", []).is_empty()
	if wary_first:
		sq.split_once = true
	# отряд из пар: пары расходятся зачищать этаж каждая своим маршрутом; ведущий пары — с холодным (охотник)
	if not sq.get("pairs", []).is_empty() and not wary_first:
		var hunters := 0
		for pair in sq.pairs:
			var alive_p: Array = pair.filter(func(m): return not m.is_dead())
			if alive_p.is_empty():
				continue
			alive_p.sort_custom(func(a, b): return not a.is_gunner() and b.is_gunner())
			var lead: Human = alive_p[0]
			lead.role = "hunt"
			lead.pair_lead = null
			hunters += 1
			for fi in range(1, alive_p.size()):   # 0.15: в паре офисников может быть и трое
				alive_p[fi].role = "follow"
				alive_p[fi].pair_lead = lead
		if hunters > 0:
			sq.plan = "pairs"
			_squad_resume(sq)
			if autotest:
				print("[autotest] отряд занял комнату, пары расходятся на зачистку")
			return
	var w := {"guard_wide": 30, "room_wide": 25, "split": 20, "together": 10, "guard_pair": 15}
	if sq.wary:
		w = {"guard_wide": 15, "room_wide": 15, "split": 5, "together": 35, "guard_pair": 30}
	if alive_m.size() == 1:
		w = {"guard_wide": 1}
	elif wary_first:
		w = {"together": 1}
	sq.plan = _weighted(w)
	alive_m.shuffle()
	var roles: Array = []
	match sq.plan:
		"guard_wide": roles = ["guard", "wide", "wide", "room", "room"]
		"room_wide": roles = ["room", "room", "wide", "wide", "room"]
		"split": roles = ["wide", "wide", "wide", "wide", "wide"]
		"together": roles = ["lead", "follow", "follow", "follow", "follow"]
		"guard_pair": roles = ["guard", "lead", "follow", "follow", "room"]
	for i in alive_m.size():
		var h: Human = alive_m[i]
		h.role = roles[mini(i, roles.size() - 1)]
		if h.role == "lead":
			sq.leader = h
	if alive_m.size() == 1:
		alive_m[0].role = "wide"
	_squad_resume(sq)
	if autotest:
		print("[autotest] отряд занял комнату, план: ", sq.plan)


## Спокойные члены отряда переходят к своим ролям (дерущиеся — сами, когда закончат).
func _squad_resume(sq: Dictionary) -> void:
	for h: Human in sq.members:
		if not h.is_dead() and h.state in [Enemy.S.GUARD, Enemy.S.PATROL, Enemy.S.LOOK, Enemy.S.REST]:
			h._resume_role()


## Время от времени отряд собирается и вместе идёт занимать новую комнату.
# ================================================================ 0.16: спецэтажи, логово, маскировка
## Тип этажа: каждый 5-й (с 5-го) — 50% спецэтаж (один из SPECIALS поровну). В тестах (есть аргументы после «--»)
## спецэтажи только по флагу: --lair — всегда логово, --special — как в игре.
func _floor_kind_for(n: int, roll: bool = false) -> String:
	var args := OS.get_cmdline_user_args()
	if n >= FINAL_FLOOR or "--roof" in args:
		return "roof"   # 0.19: 30-й этаж — всегда крыша
	if "--battle" in args:
		return "battle"
	if "--fort" in args:
		return "fort"
	if "--lair" in args:
		return "lair"
	if not roll and not args.is_empty() and not "--special" in args:
		return "normal"
	if n >= 5 and n % 5 == 0 and rng.randf() < 0.5:
		return SPECIALS[rng.randi_range(0, SPECIALS.size() - 1)]
	return "normal"


## Выход открыт: обычный этаж — пароль собран; логово — ключ-карта подобрана.
func exit_open() -> bool:
	if floor_kind == "roof":
		return heli_phase == "landed" and elites.all(func(e): return not is_instance_valid(e) or e.is_dead() or e.is_down())   # 0.19
	if floor_kind in ["fort", "battle"]:
		return true   # 0.17: у выживальщиков проход открыт
	return key_taken if floor_kind == "lair" else hacked >= 5


func player_disguised() -> bool:
	return player != null and is_instance_valid(player) and player.disguised


## Логово: 6–10 бандитов без зомби. Охранник у комнаты с маскировкой, трое патрулируют этаж, остальные живут:
## греются у бочек, отливают у стен, бродят. У одного (не охранника) — ключ-карта на спине.
func _spawn_lair(n: int) -> void:
	var count := clampi(6 + rng.randi_range(0, 2) + (n - 5) / 5, 6, 10)
	var gunners := 3 if count >= 9 else 2
	var sp: Vector3 = L.start_elev.stand
	var dist := L.bfs_dist(floori(sp.x), floori(sp.z))
	var ctr := L.nearest_walkable(L.W / 2, L.H / 2, 8)
	var sq := {"members": [], "leader": null, "phase": "lair", "plan": "lair", "t": 0.0, "wary": false, "main": true,
		"pairs": [], "fac": "human", "dest": Vector3(ctr.x + 0.5, 0, ctr.y + 0.5), "room": {}}
	var used: Array = []
	for i in count:
		var wid := ""
		if i >= count - gunners:
			wid = "rifle" if rng.randf() < 0.35 else "uzi"
		else:
			wid = _weighted({"knife": 40, "axe": 30, "knuckles": 30})
		var role := "guard" if i == 0 else ("wide" if i <= 3 else "lair")
		var pos: Vector3 = L.loot.guard
		var ang: float = L.loot.guard_ang
		if role != "guard":
			for _try in 400:
				var x := rng.randi_range(1, L.W - 2)
				var z := rng.randi_range(1, L.H - 2)
				var ci := z * L.W + x
				if not L.walkable(x, z) or dist[ci] < 18 or L.door[ci] or L.in_start_zone(ci, dist):
					continue
				var p := Vector2(x + 0.5, z + 0.5)
				var close := false
				for u in used:
					if p.distance_to(u) < 4.0: close = true
				if close: continue
				pos = Vector3(p.x, 0, p.y)
				ang = rng.randf() * TAU
				break
		used.append(Vector2(pos.x, pos.z))
		var h := Human.new()
		level_root.add_child(h)
		if role == "guard":
			h.post = pos
			h.post_ang = ang
			h.has_post = true
		h.setup_human(self, L, pos, ang, wid, sq, role)
		sq.members.append(h)
		enemies.append(h)
	sq.leader = sq.members[1]
	squads.append(sq)
	# ключ-карта — у случайного бандита без поста (лучше у живущего в логове, чем у патрульного)
	var cands: Array = sq.members.filter(func(h): return h.role == "lair")
	if cands.is_empty():
		cands = sq.members.filter(func(h): return h.role != "guard")
	key_holder = cands[rng.randi_range(0, cands.size() - 1)]
	key_holder.has_key = true
	key_holder.model.add_keycard()
	_add_pickup("disguise", 1, L.loot.pos)
	npc_stats.lair_bandits = count
	if autotest:
		print("[autotest] логово: бандитов %d, ключ у %s (%s)" % [count, key_holder.weapon, key_holder.role])


## Ключ-карта упала с бандита (убит / вырублен / задушен) — лежит на полу, светится зелёным.
func drop_keycard(h: Human) -> void:
	if not h.has_key:
		return
	h.has_key = false
	h.model.remove_keycard()
	if h == key_holder:
		key_holder = null
	_add_pickup("keycard", 1, h.position + Vector3(0.3, 0, 0.3))
	npc_stats.key_dropped_t = floor_t
	hud.toast("Ключ-карта упала — подбери её!", Color(0.4, 1.0, 0.5), 2.5)


func _take_keycard() -> void:
	key_taken = true
	npc_stats.key_taken_t = floor_t
	view.set_exit_unlocked(true)
	sfx.play("ding", 0.6)
	hud.toast("Ключ-карта у тебя — лифт открыт! Беги к лифту!", Color(0.4, 1.0, 0.5), 3.0)
	if autotest:
		print("[autotest] ключ-карта подобрана")


## 0.17: укреплённый офис выживальщиков: 5–7 офисников, без зомби, лифт открыт. Охранник у комнаты с пакетами,
## двое болтают (кухня), один слушает радио, до двух патрулируют, остальные бродят по комнатам.
func _spawn_fort(n: int) -> void:
	var count := rng.randi_range(5, 7)
	var gunners := 2
	var ctr := L.nearest_walkable(L.W / 2, L.H / 2, 8)
	var sq := {"members": [], "leader": null, "phase": "fort", "plan": "fort", "t": 0.0, "wary": false, "main": true,
		"pairs": [], "fac": "office", "dest": Vector3(ctr.x + 0.5, 0, ctr.y + 0.5), "room": {}}
	var roles := ["guard", "talk", "talk", "radio", "wide", "wide", "fort"]
	var posts := [[L.loot.guard, L.loot.guard_ang], [L.talk.a, L.talk.ang_a], [L.talk.b, L.talk.ang_b], [L.radio.pos, L.radio.ang]]
	var sp: Vector3 = L.start_elev.stand
	var dist := L.bfs_dist(floori(sp.x), floori(sp.z))
	var used: Array = []
	for i in count:
		var wid := ""
		if i >= count - gunners:
			wid = _weighted({"revolver": 45, "nailgun": 35, "crossbow": 20})
		else:
			wid = _weighted({"pipe": 45, "knife": 30, "axe": 25})
		var role: String = roles[i]
		var pos := Vector3.ZERO
		var ang := 0.0
		if i < posts.size():
			pos = posts[i][0]
			ang = posts[i][1]
		else:
			for _try in 400:
				var x := rng.randi_range(1, L.W - 2)
				var z := rng.randi_range(1, L.H - 2)
				var ci := z * L.W + x
				if not L.walkable(x, z) or dist[ci] < 10 or L.door[ci] or L.in_start_zone(ci, dist):
					continue
				var pp := Vector2(x + 0.5, z + 0.5)
				var close := false
				for u in used:
					if pp.distance_to(u) < 4.0: close = true
				if close: continue
				pos = Vector3(pp.x, 0, pp.y)
				ang = rng.randf() * TAU
				break
		used.append(Vector2(pos.x, pos.z))
		var h := Human.new()
		level_root.add_child(h)
		if i < posts.size():
			h.post = pos
			h.post_ang = ang
			h.has_post = true
		h.setup_human(self, L, pos, ang, wid, sq, role, "office")
		sq.members.append(h)
		enemies.append(h)
	sq.leader = sq.members[0]
	squads.append(sq)
	_add_pickup("bags", 1, L.loot.pos)
	npc_stats.fort_office = count
	if autotest:
		print("[autotest] укреплённый офис: офисников %d" % count)


## 0.18: поле битвы — развороченный офис, без зомби, лифт открыт. Офисники (4–6) и бандиты (5–6) — у разных концов
## этажа; половина каждой стороны продвигается к середине, половина патрулирует свою часть. Бой — когда заметят друг
## друга (faction_war); победители подбирают стволы убитых, палят в воздух и разбредаются осматривать этаж.
const BATTLE_GUNS := ["uzi", "rifle", "revolver", "nailgun", "crossbow"]

func _spawn_battle(n: int) -> void:
	var sd := L.start_dist()
	var sides: Array = L.sides.duplicate()
	if rng.randf() < 0.5:
		sides.reverse()
	var plan := [["office", rng.randi_range(4, 6), {"revolver": 45, "nailgun": 35, "crossbow": 20}, {"pipe": 45, "knife": 30, "axe": 25}],
		["human", rng.randi_range(5, 6), {"uzi": 65, "rifle": 35}, {"knife": 40, "axe": 30, "knuckles": 30}]]
	for s in 2:
		var fac: String = plan[s][0]
		var count: int = plan[s][1]
		var base: Vector3 = sides[s].pos
		var sq := {"members": [], "leader": null, "phase": "battle", "plan": "battle", "t": 0.0, "wary": false, "main": true,
			"pairs": [], "fac": fac, "dest": base, "front": L.ammo_pos, "room": {}}
		var used: Array = []
		for i in count:
			var wid: String = _weighted(plan[s][2]) if i >= count - 2 else _weighted(plan[s][3])
			var pos := base
			for _try in 60:
				var c := L.nearest_walkable(floori(base.x) + rng.randi_range(-4, 4), floori(base.z) + rng.randi_range(-4, 4), 2)
				if c.x < 0 or L.in_start_zone(c.y * L.W + c.x, sd): continue
				var p := Vector3(c.x + 0.5, 0, c.y + 0.5)
				var close := false
				for u in used:
					if p.distance_to(u) < 1.4: close = true
				if not close:
					pos = p
					break
			used.append(pos)
			var h := Human.new()
			level_root.add_child(h)
			h.setup_human(self, L, pos, rng.randf() * TAU, wid, sq, "advance" if i % 2 == 0 else "wide", fac)
			sq.members.append(h)
			enemies.append(h)
		sq.leader = sq.members[0]
		squads.append(sq)
	_add_pickup("ammo", 1, L.ammo_pos)
	battle_phase = "calm"
	npc_stats.battle_office = plan[0][1]
	npc_stats.battle_bandits = plan[1][1]
	if autotest:
		print("[autotest] поле битвы: офисников %d, бандитов %d" % [npc_stats.battle_office, npc_stats.battle_bandits])


## Кто победил: пока обе стороны на ногах — бой; одна выбыла (убиты/лежат) — живые победители идут за стволами.
func _update_battle(dt: float) -> void:
	if battle_phase == "":
		return
	if battle_phase == "after":
		_battle_winners()
		return
	if battle_phase == "calm":
		if faction_war_on:
			battle_phase = "fight"
			npc_stats.battle_start_t = floor_t
		return
	var up := {"office": [], "human": []}
	for e: Enemy in enemies:
		if e is Human and not e.is_dead() and not e.is_down() and e.state != Enemy.S.CHOKED:
			up[e.faction].append(e)
	if not up.office.is_empty() and not up.human.is_empty():
		# обе стороны знают друг о друге: кто остался без противника — раз в 8 с идёт к ближайшему живому врагу
		battle_seek_t -= dt
		if battle_seek_t <= 0.0:
			battle_seek_t = 8.0
			for fac in ["office", "human"]:
				var other: Array = up.human if fac == "office" else up.office
				for h: Human in up[fac]:
					if h.is_hostile() or h.state in [Enemy.S.INVESTIGATE, Enemy.S.STARTLED]:
						continue
					var best: Human = null
					var bd := 1e9
					for o: Human in other:
						if h.dist_to(o) < bd:
							bd = h.dist_to(o)
							best = o
					if best != null:
						h._investigate(best.position, true)
		return
	battle_phase = "after"
	var win := "office" if not up.office.is_empty() else ("human" if not up.human.is_empty() else "none")
	npc_stats.battle_winner = win
	npc_stats.battle_end_t = floor_t
	if win == "none":
		return
	hud.toast("Стрельба стихла — %s взяли верх." % ("офисники" if win == "office" else "бандиты"), Color(1.0, 0.75, 0.4), 3.0)
	battle_won = up[win].duplicate()
	_battle_winners()


## Победители, кто уже успокоился (не дерётся), идут за ближайшим стволом убитого (до 20 м) или сразу салютуют.
func _battle_winners() -> void:
	var claimed := {}
	for e: Enemy in enemies:
		if e is Human and not (e as Human).loot_pk.is_empty():
			claimed[(e as Human).loot_pk] = true
	var i := battle_won.size() - 1
	while i >= 0:
		var h: Human = battle_won[i]
		if not is_instance_valid(h) or h.is_dead():
			battle_won.remove_at(i)
		elif not h.is_hostile() and not h.is_down() and h.state != Enemy.S.CHOKED:
			battle_won.remove_at(i)
			var best: Dictionary = {}
			var bd := 20.0
			for pk in pickups:
				if pk.id in BATTLE_GUNS and not claimed.has(pk):
					var d := h.position.distance_to((pk.node as Node3D).position)
					if d < bd:
						bd = d
						best = pk
			if best.is_empty():
				battle_cheer(h)
			else:
				claimed[best] = true
				h.loot_pk = best
				h.role = "loot"
				h._resume_role()
		i -= 1


## Победитель дошёл до ствола: берёт (если он ещё лежит) — теперь воюет им; потом салют.
func battle_take(h: Human) -> void:
	var pk: Dictionary = h.loot_pk
	h.loot_pk = {}
	if not pk.is_empty() and pickups.has(pk):
		var id: String = pk.id
		(pk.node as Node3D).queue_free()
		pickups.erase(pk)
		h.weapon = id
		h.W = Human.WEAPONS[id]
		h.ammo = h.W.get("mag", 0)
		npc_stats.battle_guns_taken += 1
	battle_cheer(h)


## Салют победы: стоит 2–3 с, стрелок палит вверх; потом бродит по этажу (роль "fort").
func battle_cheer(h: Human) -> void:
	h.role = "fort"
	h.state = Enemy.S.LOOK
	h.t = randf_range(2.0, 3.0)
	h.look_base = h.angle
	h.path = PackedInt32Array()
	h.cheer_t = h.t - 0.2
	h.cheer_shot = randf_range(0.0, 0.3)


## Ящик с патронами: всё огнестрельное у героя — до потолка. Нечего пополнить — false (ящик остаётся).
func _take_ammo() -> bool:
	var got := false
	for id in player.inv.keys():
		var df := Items.def(id)
		if df.cat == Items.Cat.WEAPON and player.inv[id] < Items.cap(id):
			player.inv[id] = Items.cap(id)
			got = true
	if got:
		sfx.play("pickup", 0.8)
		hud.toast("Ящик с патронами: всё огнестрельное заряжено до упора.", Items.CAT_COLORS[Items.Cat.WEAPON], 2.5)
	else:
		hud.toast("Ящик с патронами — заряжать нечего.", C_DIM_TOAST, 1.8)
	return got


## 0.20: пожарные лестницы (этажи 20–29, обычные этажи). После 3-го взлома (через 5–10 с), потом раз в 3 мин (0.20.1) —
## с незаблокированной лестницы спускаются 2–3 бандита (не больше 3 за раз), пока живых бандитов меньше потолка
## (10 на 20-м → 14 на 29-м). Отряд прочёсывает весь этаж (обычные планы и переходы отряда). Заблокированный люк — всё.
const HATCH_TIME := 3.0
const ESCAPE_GAP := 180.0   # 0.20.1: между волнами с лестниц

func escape_cap() -> int:
	return 10 + int(round((L.floor_num - 20) * 4.0 / 9.0))


func _update_escapes(dt: float) -> void:
	if L == null or L.escapes.is_empty() or floor_kind != "normal":
		return
	if esc_t < 0.0:
		if hacked >= 3:
			esc_t = rng.randf_range(5.0, 10.0)
		return
	esc_t -= dt
	if esc_t > 0.0:
		return
	esc_t = ESCAPE_GAP   # 0.20.1: раз в 3 минуты (было 60–90 с — «слишком много»)
	var open: Array = L.escapes.filter(func(e): return not e.locked)
	if open.is_empty():
		return
	var live := enemies.filter(func(e): return e is Human and e.faction == "human" and not e.is_dead()).size()
	var n := mini(mini(rng.randi_range(2, 3), escape_cap() - live), 3)
	if n <= 0:
		esc_t = 15.0   # потолок — проверим снова скоро
		return
	_spawn_squad(n, false, open[rng.randi_range(0, open.size() - 1)])


func _lock_hatch(es: Dictionary) -> void:
	es.locked = true
	hatch_hold = 0.0
	npc_stats.hatches_locked += 1
	sfx.play("hit", 0.9)
	for nd in esc_nodes:
		if nd.get_meta("esc") == es:
			(nd.get_child(0) as MeshInstance3D).material_override.albedo_texture = OfficeTex.get_tex("hatch_locked")
	var left: int = L.escapes.filter(func(e): return not e.locked).size()
	hud.toast("Люк заколочен." + (" Есть ещё одна лестница." if left > 0 else " Лестниц больше нет."), Color(0.6, 1.0, 0.6), 3.0)
	if autotest:
		print("[autotest] люк заблокирован")


## 0.21: герой не виден и не слышен врагам — только приехал на этаж или ползёт по вентиляции.
func hero_hidden() -> bool:
	return arrive_grace > 0.0 or not vent.is_empty()


## Залез в решётку: герой пропал (не виден, не слышен, урона нет), камера едет вдоль трубы к другой решётке.
## Гнавшиеся теряют его у входа и обыскивают там. Лязг решётки слышно в 2 м.
func _enter_vent(from: Dictionary, to: Dictionary, ln: float) -> void:
	emit_noise(player.position, 2.0, "step", true)
	sfx.play("hit", 0.25)
	if any_hostile():
		npc_stats.vent_escapes += 1
	npc_stats.vents_used += 1
	vent = {"from": from, "to": to, "t": 0.0, "dur": clampf(ln / 3.0, 2.0, 6.0)}
	vent_release = true
	vent_snd = 0.0
	player.frozen = true
	player.visible = false
	player.lock = null
	player.hacking = false
	vent_cam = Node3D.new()
	level_root.add_child(vent_cam)
	vent_cam.position = player.position
	cam_target = vent_cam
	if autotest:
		print("[autotest] залез в вентиляцию")


func _update_vent(dt: float) -> void:
	if vent.is_empty():
		return
	vent.t += dt
	var k := smoothstep(0.0, 1.0, minf(1.0, vent.t / vent.dur))
	var a: Vector3 = vent.from.stand
	var b: Vector3 = vent.to.stand
	vent_cam.position = a.lerp(b, k)
	vent_snd -= dt
	if vent_snd <= 0.0:
		vent_snd = 0.45
		sfx.play("step", 0.12, 0.2)   # глухое шуршание в трубе — врагам не слышно
	if vent.t >= vent.dur:
		_exit_vent()


func _exit_vent() -> void:
	var to: Dictionary = vent.to
	vent = {}
	player.position = Vector3(to.stand.x, 0, to.stand.z)
	player.angle = atan2(to.normal.x, to.normal.z)
	player.rotation.y = player.angle
	player.crouch = true
	player.visible = true
	player.frozen = false
	vent_release = true
	if cam_target == vent_cam:
		cam_target = null
	vent_cam.queue_free()
	vent_cam = null
	emit_noise(player.position, 2.0, "step", true)
	sfx.play("hit", 0.25)


## Решётки вентиляции — у пола в стене (без освещения, чтобы было видно и в тёмной комнате).
func _build_vents() -> void:
	for v in L.vents:
		for e in [v.a, v.b]:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.8, 0.5)
			q.mesh = qm
			level_root.add_child(q)
			q.position = e.plane + e.normal * 0.02 + Vector3(0, 0.32, 0)
			q.rotation.y = atan2(e.normal.x, e.normal.z)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_texture = OfficeTex.get_tex("vent")
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.albedo_color = Color(0.8, 0.8, 0.8)
			q.material_override = m


## Люки — квады в проёме внешней стены (без освещения, чтобы было видно и в тёмной комнате).
func _build_escapes() -> void:
	esc_nodes.clear()
	for es in L.escapes:
		var node := Node3D.new()
		level_root.add_child(node)
		node.position = es.plane + es.normal * 0.02
		node.rotation.y = atan2(es.normal.x, es.normal.z)
		node.set_meta("esc", es)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.95, 1.9)
		q.mesh = qm
		q.position = Vector3(0, 0.95, 0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = OfficeTex.get_tex("hatch_locked" if es.locked else "hatch")
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.albedo_color = Color(0.85, 0.85, 0.85)
		q.material_override = m
		node.add_child(q)
		esc_nodes.append(node)


## 0.19: крыша (30-й этаж, финал). 10–12 бандитов без зомби, расставлены как в логове: двое на постах (у площадки и
## у бака/антенны), трое патрулируют, остальные курят у парапета и бродят. Герой подошёл к площадке (12 м) — садится
## вертолёт, выходят трое элитных (hp ×1.5, M4A1-S, маскировку не принимают) и ищут его рядом. Все трое лежат —
## «В ВЕРТОЛЁТ» → конец игры.
const HELI_TRIGGER := 12.0

func _spawn_roof(n: int) -> void:
	var count := rng.randi_range(10, 12)
	var gunners := 4
	var ctr := L.nearest_walkable(L.W / 2, L.H / 2, 8)
	var sq := {"members": [], "leader": null, "phase": "roof", "plan": "roof", "t": 0.0, "wary": false, "main": true,
		"pairs": [], "fac": "human", "dest": Vector3(ctr.x + 0.5, 0, ctr.y + 0.5), "room": {}}
	var sp: Vector3 = L.start_elev.stand
	var dist := L.bfs_dist(floori(sp.x), floori(sp.z))
	# посты: у площадки (спиной к ней) и у самой дальней от старта «точки обзора»
	var posts: Array = []
	var pc := L.nearest_walkable(floori(L.helipad.x) - 5, floori(L.helipad.z) + 3, 3)
	if pc.x >= 0:
		posts.append([Vector3(pc.x + 0.5, 0, pc.y + 0.5), PI * 1.5])
	var used: Array = []
	for i in count:
		var wid := ""
		if i >= count - gunners:
			wid = "rifle" if rng.randf() < 0.35 else "uzi"
		else:
			wid = _weighted({"knife": 40, "axe": 30, "knuckles": 30})
		var role := "guard" if i < posts.size() else ("wide" if i < posts.size() + 3 else "lair")
		var pos := Vector3.ZERO
		var ang := rng.randf() * TAU
		if role == "guard":
			pos = posts[i][0]
			ang = posts[i][1]
		else:
			for _try in 400:
				var x := rng.randi_range(1, L.W - 2)
				var z := rng.randi_range(1, L.H - 2)
				var ci := z * L.W + x
				if not L.walkable(x, z) or dist[ci] < 14:
					continue
				var p := Vector2(x + 0.5, z + 0.5)
				var close := false
				for u in used:
					if p.distance_to(u) < 3.5: close = true
				if close: continue
				pos = Vector3(p.x, 0, p.y)
				break
		used.append(Vector2(pos.x, pos.z))
		var h := Human.new()
		level_root.add_child(h)
		if role == "guard":
			h.post = pos
			h.post_ang = ang
			h.has_post = true
		h.setup_human(self, L, pos, ang, wid, sq, role)
		sq.members.append(h)
		enemies.append(h)
	sq.leader = sq.members[0]
	squads.append(sq)
	heli_phase = "wait"
	elites.clear()
	env.background_color = Color(0.02, 0.03, 0.07)   # ночное небо
	env.fog_light_color = Color(0.03, 0.04, 0.08)
	if autotest:
		print("[autotest] крыша: бандитов %d" % count)


## Вертолёт: ждёт героя у площадки → садится 5 с (шум лопастей) → высадка элиты → ждёт, пока все трое лягут.
func _update_roof(dt: float) -> void:
	if heli_phase == "" or heli_phase == "leaving":
		return
	if heli_rotor != null:
		heli_rotor.rotation.y += dt * (22.0 if heli_phase != "landed" else 9.0)
	match heli_phase:
		"wait":
			if player != null and not player.dead and player.visible \
					and Vector2(player.px() - L.helipad.x, player.pz() - L.helipad.z).length() < HELI_TRIGGER:
				heli_phase = "landing"
				heli_t = 0.0
				_build_heli()
				hud.toast("Слышишь? Над крышей — вертолёт!", Color(1.0, 0.85, 0.4), 3.0)
		"landing":
			heli_t += dt
			heli_node.position.y = lerpf(14.0, 0.0, clampf(heli_t / 5.0, 0.0, 1.0))
			_heli_sound(dt, 0.3)
			if heli_t >= 5.0:
				heli_phase = "landed"
				_spawn_elites()
		"landed":
			_heli_sound(dt, 0.6)


func _heli_sound(dt: float, gap: float) -> void:
	heli_snd_t -= dt
	if heli_snd_t <= 0.0:
		heli_snd_t = gap
		sfx.play_at("heli", heli_node.position, player.position, 1.0, 40.0)


## Трое элитных выходят у двери (западный край площадки) и идут искать героя рядом с тем местом, где он сейчас.
func _spawn_elites() -> void:
	var sq: Dictionary = squads[0] if not squads.is_empty() else {"members": [], "dest": L.helipad}
	for k in 3:
		var pos: Vector3 = L.helipad + Vector3(-2.2, 0, (k - 1) * 1.1)
		var c := L.nearest_walkable(floori(pos.x), floori(pos.z), 2)
		var h := Human.new()
		level_root.add_child(h)
		h.elite = true
		h.setup_human(self, L, Vector3(c.x + 0.5, 0, c.y + 0.5), PI * 1.5, "m4", sq, "elite")
		h.max_hp = 150.0
		h.hp = 150.0
		h.model.add_armor()
		h.attn = 1.2
		sq.members.append(h)
		enemies.append(h)
		elites.append(h)
		var guess := player.position + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		h._investigate(guess, true)
	hud.toast("Из вертолёта вышли трое в бронежилетах. Убери их — и улетай.", Color(1.0, 0.5, 0.35), 3.5)
	if autotest:
		print("[autotest] вертолёт сел, элита вышла")


## Вертолёт из коробок: корпус, кабина, хвост, полозья, несущий и хвостовой винты (heli_rotor крутится).
func _build_heli() -> void:
	heli_node = Node3D.new()
	level_root.add_child(heli_node)
	heli_node.position = L.helipad + Vector3(0, 14.0, 0)
	var mk := func(size: Vector3, pos: Vector3, col: Color, parent: Node3D) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		mi.material_override = m
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := Color(0.18, 0.22, 0.18)
	mk.call(Vector3(1.5, 1.3, 3.0), Vector3(0, 1.15, 0), body, heli_node)
	mk.call(Vector3(1.3, 0.9, 0.9), Vector3(0, 1.3, 1.7), Color(0.35, 0.5, 0.6), heli_node)    # кабина (стекло)
	mk.call(Vector3(0.35, 0.35, 3.2), Vector3(0, 1.5, -3.0), body, heli_node)                 # хвостовая балка
	mk.call(Vector3(0.12, 0.9, 0.6), Vector3(0, 1.9, -4.4), body, heli_node)                  # киль
	for sx in [-0.75, 0.75]:
		mk.call(Vector3(0.08, 0.08, 3.0), Vector3(sx, 0.08, 0.2), Color(0.12, 0.12, 0.12), heli_node)   # полозья
		mk.call(Vector3(0.06, 0.45, 0.06), Vector3(sx, 0.3, 0.9), Color(0.12, 0.12, 0.12), heli_node)
		mk.call(Vector3(0.06, 0.45, 0.06), Vector3(sx, 0.3, -0.6), Color(0.12, 0.12, 0.12), heli_node)
	mk.call(Vector3(0.6, 0.9, 0.05), Vector3(0.76, 1.1, 0.3), Color(0.05, 0.06, 0.05), heli_node)   # открытая дверь
	heli_rotor = Node3D.new()
	heli_node.add_child(heli_rotor)
	heli_rotor.position = Vector3(0, 2.0, 0)
	mk.call(Vector3(7.0, 0.04, 0.22), Vector3.ZERO, Color(0.1, 0.1, 0.1), heli_rotor)
	mk.call(Vector3(0.22, 0.04, 7.0), Vector3.ZERO, Color(0.1, 0.1, 0.1), heli_rotor)
	mk.call(Vector3(0.05, 1.1, 0.12), Vector3(0.12, 1.9, -4.5), Color(0.1, 0.1, 0.1), heli_node)   # хвостовой винт
	heli_node.rotation.y = PI * 0.5   # носом к югу, дверь — к западу (к «выходу»)


## Герой садится в вертолёт: прячем героя, вертолёт взлетает, через пару секунд — финальный экран.
func _board_heli() -> void:
	state = "victory"
	state_t = 0.0
	heli_phase = "leaving"
	player.frozen = true
	player.visible = false
	player.hacking = false
	stats.floors += 1
	beaten += 1
	best_floor = maxi(best_floor, FINAL_FLOOR)
	max_reached = maxi(max_reached, FINAL_FLOOR)
	_save()
	sfx.play("ding", 1.0)
	if autotest:
		print("[autotest] ИГРА ПРОЙДЕНА: ", stats)


func _update_victory(dt: float) -> void:
	_update_world(dt, false)
	if heli_node != null:
		heli_rotor.rotation.y += dt * 24.0
		if state_t > 1.0:
			heli_node.position.y += dt * (1.5 + state_t)
			heli_node.position.x += dt * 2.0
		_heli_sound(dt, 0.25)
		_place_camera(Vector3(heli_node.position.x, 0, heli_node.position.z), cam_yaw, 9.0 + state_t * 1.5, dt, false)


## Надеть пакеты на ноги — до конца этажа шаги и бег бесшумны.
func wear_bags() -> void:
	player.bags = true
	player.model.add_bags()
	npc_stats.bags_worn += 1
	sfx.play("pickup", 0.6)
	hud.toast("Пакеты на ногах: шаги и бег бесшумны до конца этажа.", Items.CAT_COLORS[Items.Cat.SPECIAL], 3.0)


## Взял пакеты: кто из лояльных офисников видит героя — гонит взашей (кулаком, не насмерть, ~10 с).
## Ответишь ударом — враги все (обычная логика 0.15).
func _bags_theft() -> void:
	var n := 0
	for e: Enemy in enemies:
		if not (e is Human) or e.faction != "office" or e.is_down() or e.state == Enemy.S.CHOKED or not (e as Human).is_loyal():
			continue
		var d := e.dist_to(player)
		if d > 12.0 or L.line_blocked(e.px(), e.pz(), player.px(), player.pz(), 0):
			continue
		if d >= 2.0 and absf(wrapf(e.angle_to_point(player.px(), player.pz()) - e.angle, -PI, PI)) >= deg_to_rad(60.0):
			continue
		var h := e as Human
		h.angry_t = 10.0
		h.foe = player
		h.last_seen = player.position
		h.state = Enemy.S.CHASE
		h.path = PackedInt32Array()
		h._shout()
		n += 1
	if n > 0:
		npc_stats.bags_theft_seen += 1
		hud.toast("Заметили с пакетами — гонят взашей! Не бей в ответ.", Color(1.0, 0.6, 0.35), 3.0)


## Надеть куртку бандита. Нельзя, пока за героем гонится бандит (переодеваться некогда, и он видел тебя).
func wear_disguise() -> bool:
	for e: Enemy in enemies:
		if e is Human and e.faction == "human" and not e.is_dead() and e.is_hostile() and e.foe == player:
			hud.toast("Сейчас не до переодевания — бандиты тебя видят", Color(1, 0.5, 0.4), 2.0)
			return false
	player.disguised = true
	disguise_blown = false
	player.set_look("human")
	npc_stats.disguise_worn += 1
	sfx.play("pickup", 0.7)
	hud.toast("Ты в куртке бандита: бандиты примут за своего до конца этажа. Офисники — нет.", Items.CAT_COLORS[Items.Cat.SPECIAL], 3.5)
	return true


## Кто-то из своих жертвы (той же стороны, лояльной к герою) видит нападение героя на неё (или героя рядом с ней):
## в 12 м, без стен, жертва или герой — в переднем секторе 120° (не только узкий луч фонаря).
func loyal_witnessed(victim: Human) -> bool:
	for e: Enemy in enemies:
		if not (e is Human) or e == victim or e.faction != victim.faction or e.is_down() or e.state == Enemy.S.CHOKED:
			continue
		for a: Actor in [victim, player]:
			var d := e.dist_to(a)
			if d > 12.0 or L.line_blocked(e.px(), e.pz(), a.px(), a.pz(), 0):
				continue
			if d < 2.0 or absf(wrapf(e.angle_to_point(a.px(), a.pz()) - e.angle, -PI, PI)) < deg_to_rad(60.0):
				return true
	return false


## Герой напал на лояльного, и это стало известно: офисники — враги до конца этажа; бандиты — маскировка раскрыта.
## 0.19.1: герой душит / режет со спины / убивает человека. Свои жертвы, кто это видит (≤ 12 м, без стен; герой или
## жертва в секторе 120°, ≤ 2 м — всегда), реагируют: стрелок кричит и стреляет; ближник рядом со своими (≤ 5 м) —
## нападают вместе; ближник один — бежит к своим с криком и приводит 2–3 обыскать место (не точку, а поиск);
## своих на этаже нет — дерётся сам. Лояльные (ещё не знают) не реагируют.
func hero_violence(victim: Human) -> void:
	if player == null or player.dead:
		return
	for e: Enemy in enemies:
		if not (e is Human) or e == victim or e.faction != victim.faction:
			continue
		var w := e as Human
		if w.is_dead() or w.is_down() or w.state == Enemy.S.CHOKED or w.is_hostile() or w.report_t > 0.0 \
				or w.is_loyal() or w.grabbed_by != null or not _sees_violence(w, victim):
			continue
		npc_stats.witnesses += 1
		w.foe = player
		w.last_seen = player.position
		var allies: Array = _allies_of(w, victim)
		var near: Array = allies.filter(func(o): return w.dist_to(o) <= 5.0)
		if w.is_gunner() or allies.is_empty() or not near.is_empty():
			if w.is_gunner():
				w._shout()
			w._instant_alert = true
			w.alert()
			w._instant_alert = false
			for o: Human in near:
				if not o.is_hostile():
					o.locate_player(false)   # рядом — нападают вместе
			continue
		w.report_t = 25.0
		w.report_pos = player.position
		w.report_ally = nearest_ally(w)
		w.report_shout = 0.0
		w.path = PackedInt32Array()
		npc_stats.witness_runs += 1


func _sees_violence(w: Human, victim: Human) -> bool:
	var d := w.dist_to(player)
	if d > 12.0 or L.line_blocked(w.px(), w.pz(), player.px(), player.pz(), 0):
		return false
	if d < 2.0:
		return true
	for a: Actor in [player, victim]:
		if absf(wrapf(w.angle_to_point(a.px(), a.pz()) - w.angle, -PI, PI)) < deg_to_rad(60.0):
			return true
	return false


## Живые свои (кроме самого и жертвы), на ногах.
func _allies_of(w: Human, exclude: Node = null) -> Array:
	return enemies.filter(func(o): return o is Human and o != w and o != exclude and o.faction == w.faction \
		and not o.is_dead() and not o.is_down() and o.state != Enemy.S.CHOKED)


func nearest_ally(w: Human) -> Human:
	var best: Human = null
	var bd := 1e9
	for o: Human in _allies_of(w):
		var d := w.dist_to(o)
		if d < bd:
			bd = d
			best = o
	return best


## Свидетель привёл своих (или его услышали): он и 2–3 ближних (не дерущихся) обыскивают место — по 3 точки вокруг.
func raise_search(w: Human, pos: Vector3) -> void:
	var team: Array = _allies_of(w).filter(func(o): return not o.is_hostile())
	team.sort_custom(func(a, b): return w.dist_to(a) < w.dist_to(b))
	team = team.slice(0, rng.randi_range(2, 3))
	team.append(w)
	for h: Human in team:
		h.search_pts.clear()
		for _k in 3:
			var c := L.nearest_walkable(floori(pos.x) + rng.randi_range(-4, 4), floori(pos.z) + rng.randi_range(-4, 4), 2)
			if c.x >= 0:
				h.search_pts.append(Vector3(c.x + 0.5, 0, c.y + 0.5))
		h._investigate(pos + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)), true)
	npc_stats.witness_searches += 1
	if autotest:
		print("[autotest] свидетель привёл %d искать героя" % (team.size() - 1))


## locate — видевшие/рядом сразу знают, где герой (жертва в сознании, очнулся и доложил); false — реагируют только
## свидетели (0.19.1, hero_violence: бегут за своими / кричат и стреляют).
func loyal_betrayed(reporter: Human, locate: bool = true) -> void:
	if reporter.faction == "office":
		set_office_hostile(reporter, locate)
		return
	if disguise_blown:
		return
	disguise_blown = true
	npc_stats.disguise_blown += 1
	player.set_look("player")
	hud.toast("Бандиты раскусили маскировку — они против тебя!", Color(1.0, 0.45, 0.35), 3.0)
	for e: Enemy in enemies:
		if locate and e is Human and e.faction == "human" and not e.is_down() and e.state != Enemy.S.CHOKED and e.dist_to(reporter) < 14.0:
			(e as Human).locate_player(false)
	if autotest:
		print("[autotest] маскировка раскрыта")


## Пламя в бочках логова: два скрещённых языка огня, без освещения, подрагивают (_update_fires).
func _build_fires() -> void:
	fire_fx.clear()
	for f in L.fires:
		var node := Node3D.new()
		level_root.add_child(node)
		node.position = Vector3(f.x + 0.5, 0.82, f.z + 0.5)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = OfficeTex.get_tex("flame")
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		for k in 2:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.5, 0.75)
			q.mesh = qm
			q.material_override = m
			q.position = Vector3(0, 0.3, 0)
			q.rotation.y = k * PI * 0.5 + 0.4
			node.add_child(q)
		fire_fx.append(node)


func _update_fires(_dt: float) -> void:
	var tm := Time.get_ticks_msec() * 0.001
	for i in fire_fx.size():
		var node: Node3D = fire_fx[i]
		node.scale = Vector3(1.0 + sin(tm * 9.0 + i) * 0.08, 1.0 + sin(tm * 13.0 + i * 2.0) * 0.18 + sin(tm * 5.3) * 0.08, 1.0)
		node.rotation.y = sin(tm * 2.0 + i) * 0.25


func _update_squads(dt: float) -> void:
	for sq in squads:
		var alive_m: Array = sq.members.filter(func(m): return not m.is_dead())
		if alive_m.is_empty():
			continue
		if not Enemy.alive(sq.leader):
			sq.leader = alive_m[0]
			if not sq.phase in ["sweep", "lair", "fort", "battle"]:
				sq.leader.role = "lead" if sq.phase == "travel" else ("rest" if sq.phase == "rest" else "wide")
		if sq.phase == "rest":
			sq.t -= dt
			if sq.t <= 0.0:
				_squad_settle(sq)
			continue
		if sq.phase == "sweep":
			# все живые (кроме схваченных) ждут у стартового лифта — встреча; кто-то ещё в пути/дерётся — ждём до 45 с
			var waiting := 0
			var busy := 0
			for h: Human in alive_m:
				if h.state == Enemy.S.REST and h.goal_kind == "meet":
					waiting += 1
				elif h.grabbed_by == null:
					busy += 1
			if waiting > 0:
				sq.meet_t += dt
			if waiting > 0 and (busy == 0 or sq.meet_t > 45.0):
				squad_meet(sq)
			continue
		if sq.phase != "settled":
			continue
		sq.t -= dt
		if sq.t <= 0.0:
			sq.phase = "travel"
			_squad_new_dest(sq, sq.dest)
			sq.leader = alive_m[rng.randi_range(0, alive_m.size() - 1)]
			for h: Human in alive_m:
				h.role = "lead" if h == sq.leader else "follow"
			_squad_resume(sq)



## 0.15: офисники против героя до конца этажа. Видевшие/доложивший сразу знают, где он.
func set_office_hostile(reporter: Human, locate: bool = true) -> void:
	if office_hostile:
		return
	office_hostile = true
	npc_stats.office_hostile += 1
	hud.toast("Офисники видели, как ты напал на своего, — теперь они против тебя", Color(0.5, 0.75, 1.0), 3.0)
	for e: Enemy in enemies:
		if locate and e is Human and e.faction == "office" and not e.is_down() and e.state != Enemy.S.CHOKED and e.dist_to(reporter) < 14.0:
			(e as Human).locate_player(false)
	if autotest:
		print("[autotest] офисники враждебны герою")


## 0.15: бандиты и офисники заметили друг друга — обе стороны знают друг о друге: каждый получает ближайшего врага
## другой стороны (ближник — по возможности не стрелка), знает, где он, 4 с; нечётная пара обходит с фланга.
func faction_war(spotter: Human, target: Human) -> void:
	if not faction_war_on:
		faction_war_on = true
		npc_stats.faction_war_t = floor_t
		hud.toast("Где-то бандиты и офисники заметили друг друга — перестрелка!", Color(1.0, 0.75, 0.4), 3.0)
		if autotest:
			print("[autotest] война фракций: ", spotter.faction, " заметил ", target.faction)
	for e: Enemy in enemies:
		if not (e is Human) or e.is_down() or e.state == Enemy.S.CHOKED or (e as Human).grabbed_by != null:
			continue
		var h := e as Human
		if h.is_hostile() and Enemy.alive(h.foe) and h.foe is Human:
			continue   # уже дерётся с людьми
		var best: Human = null
		var bd := 1e9
		for o: Enemy in enemies:
			if not (o is Human) or o.faction == h.faction or o.is_dead():
				continue
			var d := h.dist_to(o)
			if not h.is_gunner() and (o as Human).is_gunner():
				d += 6.0   # ближник на стрелка — в последнюю очередь
			if d < bd:
				bd = d
				best = o as Human
		if best == null or h.dist_to(best) > 40.0:
			continue
		h.foe = best
		h.last_seen = best.position
		h.lost_t = 0.0
		h.know_t = 4.0
		if not h.is_gunner() and h.pair_i % 2 == 1:
			var dir := Vector2(best.px() - h.px(), best.pz() - h.pz()).normalized()
			var side := Vector2(-dir.y, dir.x) * (1.0 if randf() < 0.5 else -1.0)
			var c := L.nearest_walkable(floori(best.px() + side.x * 4.0), floori(best.pz() + side.y * 4.0), 2)
			if c.x >= 0:
				h.flank_pos = Vector3(c.x + 0.5, 0, c.y + 0.5)
				h.flank_t = 7.0
		if not h.is_hostile():
			h._instant_alert = true
			h.alert()
			h._instant_alert = false


## Человек закричал: слышат зомби (идут на крик), а на помощь бегут не больше двух людей (своей стороны).
func human_shout(h: Human) -> void:
	var fp: Vector3 = h.foe.position if Enemy.alive(h.foe) else h.position
	emit_noise(h.position, Human.SHOUT_R, "shout", true, fp, h)
	var helpers: Array = []
	for e: Enemy in enemies:
		if e is Human and e != h and e.faction == h.faction and not e.is_down() and not e.is_hostile() and e.dist_to(h) < Human.SHOUT_R + 3.0:
			helpers.append(e)
	helpers.sort_custom(func(a, b): return a.dist_to(h) < b.dist_to(h))
	for i in mini(2, helpers.size()):
		helpers[i].respond(h)


## Мгновенный выстрел (болтовка людей): первая цель на линии (игрок или враг другой фракции) или стена.
func trace_shot(from: Vector2, dir: Vector2, max_t: float, shooter: Enemy) -> Dictionary:
	var wall_t := max_t
	var s := 0.3
	while s < max_t:
		var c := L.cell(floori(from.x + dir.x * s), floori(from.y + dir.y * s))
		if c == OfficeLevel.WALL or c == OfficeLevel.TALL:
			wall_t = s
			break
		s += 0.1
	var best_t := wall_t
	var best: Actor = null
	var cands: Array = enemies.duplicate()
	cands.append(player)
	for a: Actor in cands:
		if a == shooter or not Enemy.alive(a):
			continue
		if a is Enemy and (a as Enemy).is_down():
			continue   # 0.12.1: свои на линии огня тоже ловят пулю (раньше болтовка проходила сквозь них)
		var f := from - Vector2(a.px(), a.pz())
		var b := f.dot(dir)
		var cc := f.dot(f) - a.radius * a.radius * 1.3
		var disc := b * b - cc
		if disc < 0.0:
			continue
		var tt := -b - sqrt(disc)
		if tt > 0.0 and tt < best_t:
			best_t = tt
			best = a
	return {"t": best_t, "actor": best}


func spawn_bullet(from: Vector3, dir: Vector2, speed: float, dp: float, dz: float, who: Enemy) -> void:
	var b := Bullet.new()
	level_root.add_child(b)
	b.setup(self, L, from, dir, speed, dp, dz, who)
	bullets.append(b)


## Точка в луче чьего-то фонарика?
func in_flashlight(p: Vector3) -> bool:
	for e: Enemy in enemies:
		if e is Human and not (e as Human).is_loyal() and (e as Human).lights(p):
			return true
	return false


## С убитого человека падает его оружие (с остатком патронов) и иногда что-то ещё.
func drop_loot(h: Human) -> void:
	var amounts := {"uzi": rng.randi_range(5, 15), "rifle": rng.randi_range(1, 2), "knife": Items.def("knife").amount, "axe": Items.def("axe").amount,
		"knuckles": rng.randi_range(1, 3),
		# 0.15: уникальное оружие офисников
		"pipe": Items.def("pipe").amount, "revolver": rng.randi_range(2, 6), "nailgun": rng.randi_range(4, 12), "crossbow": rng.randi_range(1, 3),
		"m4": rng.randi_range(8, 15)}   # 0.19: M4A1-S элиты
	_add_pickup(h.weapon, amounts[h.weapon], h.position)
	# 0.7: всегда что-то полезное сверху — бросок или лечение (потолки запаса соблюдаются при подборе)
	var extra: String = _weighted({"bottle": 25, "brick": 20, "shuriken": 18, "grenade": 10, "coffee": 17, "medkit": 5, "energy": 5})
	_add_pickup(extra, 1, h.position + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))


## blocked — герой стоит рядом, но унести не может: подсказку «больше не унести» покажем, только когда
## он отойдёт и подойдёт снова (без спама каждый кадр).
func _add_pickup(id: String, n: int, pos: Vector3, blocked: bool = false) -> void:
	var node := Node3D.new()
	level_root.add_child(node)
	node.position = Vector3(pos.x, 0.12, pos.z)
	var mi := MeshInstance3D.new()
	mi.mesh = HeldItems.build_mesh(id) if HeldItems.has(id) else null
	node.add_child(mi)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.orientation = PlaneMesh.FACE_Y
	glow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = OfficeTex.get_tex("p_dot")
	m.albedo_color = Color(0.3, 1.0, 0.45, 0.95) if id == "keycard" else Color(Items.CAT_COLORS[Items.def(id).cat], 0.5)   # 0.16: ключ-карта — ярко-зелёная
	glow.material_override = m
	glow.position = Vector3(0, -0.09, 0)
	node.add_child(glow)
	pickups.append({"id": id, "n": n, "node": node, "mesh": mi, "blocked": blocked})


func _update_pickups(dt: float) -> void:
	var i := pickups.size() - 1
	var swap_best := 9.0
	swap_pk = {}
	while i >= 0:
		var pk: Dictionary = pickups[i]
		var mi: MeshInstance3D = pk.mesh
		mi.rotation.y += dt * 1.5
		var node: Node3D = pk.node
		var dist := Vector2(node.position.x - player.px(), node.position.z - player.pz()).length()
		var near := player.visible and not player.dead and dist < 0.9
		# 0.13: другой предмет в занятом слоте — сам не берётся, рядом появляется кнопка «Заменить»
		if near and player.slot_blocker(pk.id) != "":
			if dist < swap_best:
				swap_best = dist
				swap_pk = pk
			if not pk.blocked:
				pk.blocked = true
				var bl := player.slot_blocker(pk.id)
				hud.toast("%s — слот занят (%s). «Заменить»?" % [Items.def(pk.id).name, Items.def(bl).name], C_DIM_TOAST, 1.8)
			i -= 1
			continue
		if not near:
			pk.blocked = false
		elif pk.id == "ammo" and not pk.blocked:
			# 0.18: ящик с патронами — пополняет всё огнестрельное до потолка (нечего — остаётся лежать)
			if _take_ammo():
				node.queue_free()
				pickups.remove_at(i)
			else:
				pk.blocked = true
		elif pk.id == "keycard":
			# 0.16: ключ-карта логова — не в инвентарь, сразу открывает лифт
			_take_keycard()
			node.queue_free()
			pickups.remove_at(i)
		elif not pk.blocked:
			# берём сколько влезает до потолка, остаток остаётся лежать
			var id: String = pk.id
			var df := Items.def(id)
			var got := player.add_item(id, pk.n)
			if got <= 0:
				pk.blocked = true
				hud.toast("%s: больше не унести (%d/%d)" % [df.name, player.inv.get(id, 0), Items.cap(id)], C_DIM_TOAST, 1.5)
			else:
				sfx.play("pickup", 0.8)
				hud.toast("Подобрано: %s ×%d" % [df.name, got], Items.CAT_COLORS[df.cat], 2.0)
				pk.n -= got
				if id == "bags" and floor_kind == "fort":
					_bags_theft()
				if pk.n <= 0:
					node.queue_free()
					pickups.remove_at(i)
				else:
					pk.blocked = true
		i -= 1


# ---------------------------------------------------------------- кнопки (из HUD и клавиатуры)
func on_button(btn: String, pressed: bool) -> void:
	if btn == "ctx":
		ctx_held = pressed
		return
	if btn == "melee" and player != null:
		player.melee_hold = pressed   # 0.12: держишь УДАР при удушении — насмерть
	if not pressed: return
	match btn:
		"use":
			if state == "play": player.use_item()
		"melee":
			if state == "play": player.melee()
		"crouch":
			if state == "play": player.crouch = not player.crouch
		"swap":
			if state == "play": do_swap()
		"unlock":
			if state == "play": player.lock = null   # 0.16.1: снять захват цели
		"vault":
			if state == "play": player.start_vault()
		"pause": toggle_pause()
		"start":
			start_run()
		"howto":
			state = "howto"
		"floors":
			state = "floors"   # меню «Играть с этажа…»
		"title":
			_go_title()
		"retry":
			start_run(run_from, run_kind)   # 0.20.3: после смерти — с того же этажа, что выбрал в начале
		"sound":
			sfx.set_muted(not sfx.muted)
			sfx_muted_saved = sfx.muted
			_save()
		"quit":
			get_tree().quit()
		_:
			if btn.begins_with("kind_") and state == "floors" and cheat_menu():
				cheat_kind = btn.substr(5)
			elif btn.begins_with("from_") and state == "floors":
				start_run(int(btn.substr(5)), cheat_kind if cheat_menu() else "")


## Тап по экрану во время игры: по врагу — захват цели, по захваченному — снять захват.
func tap_world(p: Vector2) -> void:
	if state != "play" or player.dead: return
	var e := hud.pick_enemy(p)
	if e == null: return
	player.toggle_lock(e)
	sfx.play("beep", 0.5 if player.lock != null else 0.3, 0.0)


func toggle_pause() -> void:
	if state == "play":
		state = "pause"
	elif state == "pause":
		state = "play"


func select_item(id: String) -> void:
	if player.inv.get(id, 0) > 0:
		player.selected = id
		var df := Items.def(id)
		hud.toast("%s — %s" % [df.name, df.desc], Items.CAT_COLORS[df.cat], 1.6)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_F: on_button("use", true)
			KEY_Q, KEY_J: on_button("melee", true)
			KEY_C, KEY_CTRL: on_button("crouch", true)
			KEY_R: on_button("swap", true)
			KEY_V: on_button("vault", true)
			KEY_T: on_button("unlock", true)   # 0.16.1: снять цель
			KEY_ESCAPE, KEY_P: on_button("pause", true)
			KEY_TAB:
				var o: Array = player.owned() if player else []
				if o.size() > 0:
					var i := (o.find(player.selected) + 1) % o.size()
					select_item(o[i])
			KEY_ENTER:
				if state in ["title", "gameover"]: start_run()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match state:
			"play": toggle_pause()
			"pause": toggle_pause()
			"howto", "gameover", "floors", "victory": _go_title()
			"title": get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# в автотесте не ставим на паузу — иначе встаёт запись видео, если окно свернули
		if state == "play" and not autotest:
			state = "pause"


# ---------------------------------------------------------------- автотест
## Бот: идёт к ближайшему невзломанному ПК, взламывает, потом к лифту. Игрок бессмертен.
var _bot_path := PackedInt32Array()
var _bot_i := 0
var _bot_goal := Vector2i(-1, -1)
var _bot_task := Vector2i(-1, -1)
var _bot_smart: RefCounted = null
var bot_hold := true   # бот «держит кнопку» взлома/лифта, когда стоит рядом


## Сколько этажей проходит бот: по умолчанию 2, «-- --autotest --floors 4» — больше.
func _autotest_floors() -> int:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--floors")
	return int(args[i + 1]) if i >= 0 and i + 1 < args.size() else 2


func _autopilot(dt: float) -> Vector2:
	autotest_log_t -= dt
	if autotest_log_t <= 0.0:
		autotest_log_t = 5.0
		var hostile := 0
		var humans := 0
		var zdead := 0
		for e: Enemy in enemies:
			if e.is_hostile(): hostile += 1
			if e is Human and not e.is_dead(): humans += 1
			if not e is Human and e.is_dead(): zdead += 1
		print("[autotest] этаж %d, взломано %d, позиция (%.1f, %.1f), в погоне %d, людей живо %d, зомби мертво %d, hp %d" % [floor_num, hacked, player.px(), player.pz(), hostile, humans, zdead, player.hp])
	var goal := _bot_task_goal(_bot_smart != null)
	# «--smart» — бот сам решает: крадётся, прячется, убегает, отбивается (scripts/tests/smart_bot.gd)
	if _bot_smart != null:
		return _bot_smart.think(self, dt, goal)
	bot_hold = true
	# «--sneak» — бот всё время крадётся вприсядку
	if "--sneak" in OS.get_cmdline_user_args() and not player.hacking:
		player.crouch = true
	# стоим только у ПК или у лифта с полным паролем; путь к ПК может идти мимо лифта-выхода
	var k: String = ctx.get("kind", "")
	if k == "hack" or (k == "elevator" and exit_open()):
		return Vector2.ZERO
	return _bot_walk(goal, 0.6)


## Цель бота: невзломанный ПК или лифт. ПК держим, пока не взломан: иначе между двумя почти
## равноудалёнными ПК бот дёргается на месте. careful — обходить ПК, возле которых толпятся враги.
func _bot_task_goal(careful: bool) -> Vector2i:
	if exit_open():
		var st: Vector3 = L.exit_elev.stand
		return Vector2i(floori(st.x), floori(st.z))
	# 0.16 логово: компьютеров нет — цель ключ-карта (лежит на полу или у хозяина)
	if floor_kind == "lair":
		for pk in pickups:
			if pk.id == "keycard":
				var kn: Node3D = pk.node
				return Vector2i(floori(kn.position.x), floori(kn.position.z))
		if key_holder != null and is_instance_valid(key_holder):
			return Vector2i(floori(key_holder.px()), floori(key_holder.pz()))
		var st2: Vector3 = L.exit_elev.stand
		return Vector2i(floori(st2.x), floori(st2.z))
	# 0.19 крыша: к вертолётной площадке; сел — к ближайшему живому элитному (бой решает smart_bot)
	if floor_kind == "roof":
		# умный бот сначала сидит в засаде и снимает одиночек (к площадке не подходит, пока не готов)
		if heli_phase == "wait" and _bot_smart != null:
			var rg: Vector2i = _bot_smart.roof_goal(self)
			if rg.x >= 0:
				return rg
		var hp3: Vector3 = L.helipad
		var tgt := Vector2(hp3.x, hp3.z)
		if heli_phase == "landed":
			var bd := 1e9
			for el in elites:
				if is_instance_valid(el) and not el.is_dead() and not el.is_down() and el.dist_to(player) < bd:
					bd = el.dist_to(player)
					tgt = Vector2(el.px(), el.pz())
		return L.nearest_walkable(floori(tgt.x), floori(tgt.y), 3)
	# 0.20: перед 3-м взломом (после него с лестниц лезут бандиты) умный бот заколачивает люки — ближний первым
	if careful and hacked >= 2 and floor_kind == "normal":
		var bd2 := 1e9
		var hatch := Vector2i(-1, -1)
		for es in L.escapes:
			if es.locked: continue
			var sv: Vector3 = es.stand
			var dd := Vector2(sv.x - player.px(), sv.z - player.pz()).length()
			if dd < bd2:
				bd2 = dd
				hatch = Vector2i(floori(sv.x), floori(sv.z))
		if hatch.x >= 0:
			return hatch
	var goal := Vector2i(-1, -1)
	var best := 1e9
	for pc in L.pcs:
		if pc.hacked: continue
		if Vector2i(pc.sx, pc.sz) == _bot_task:
			return _bot_task
		var d := Vector2(pc.sx - player.px(), pc.sz - player.pz()).length()
		if careful:
			for e: Enemy in enemies:
				var near_pc := Vector2(e.px() - pc.sx, e.pz() - pc.sz).length()
				if not e.is_dead() and near_pc < (8.0 if e is Human else (5.5 if e is Clicker else 4.0)):
					d += 20.0 if e is Human else (25.0 if e is Clicker else 12.0)
			# ПК, от которого бот отступил (у него щелкун), — временно в конец очереди
			if float(_bot_smart.avoid_pc.get(Vector2i(pc.sx, pc.sz), -1.0)) > float(_bot_smart.now):
				d += 40.0
		if d < best:
			best = d
			goal = Vector2i(pc.sx, pc.sz)
	_bot_task = goal
	return goal


## Идти к клетке goal по A* со скоростью spd (длина стика: 0.6 — шаг, 1 — бег).
func _bot_walk(goal: Vector2i, spd: float) -> Vector2:
	var c := -1
	if _bot_i < _bot_path.size():
		c = _bot_path[_bot_i]
	# новая цель или бота оттолкнули от пути (зомби, _separate) — строим путь заново
	if goal != _bot_goal or (c >= 0 and Vector2(c % L.W + 0.5 - player.px(), c / L.W + 0.5 - player.pz()).length() > 2.5):
		_bot_goal = goal
		_bot_path = L.find_path(floori(player.px()), floori(player.pz()), goal.x, goal.y, 20000)
		_bot_i = 0
	if _bot_i >= _bot_path.size():
		var dd := Vector2(goal.x + 0.5 - player.px(), goal.y + 0.5 - player.pz())
		return dd.normalized() * spd if dd.length() > 0.1 else Vector2.ZERO
	c = _bot_path[_bot_i]
	var to := Vector2(c % L.W + 0.5 - player.px(), c / L.W + 0.5 - player.pz())
	if to.length() < 0.3:
		_bot_i += 1
	return to.normalized() * spd
