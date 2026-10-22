class_name Hud
extends CanvasLayer
## HUD и тач-управление: плавающий стик слева, кнопки справа, инвентарь снизу,
## радар (как Soliton Radar в MGS), иконки «!»/«?» над врагами, меню.

const C_TEXT := Color(0.92, 0.95, 0.88)
const C_DIM := Color(0.6, 0.65, 0.6)
const C_GREEN := Color(0.35, 1.0, 0.5)
const C_RED := Color(1.0, 0.3, 0.25)
const C_YEL := Color(1.0, 0.85, 0.3)
const C_PANEL := Color(0.02, 0.05, 0.03, 0.78)
const C_CLICK := Color(0.78, 0.45, 1.0)   # щелкун и его щелчки

var game: Node
var move_vec := Vector2.ZERO
var canvas: HudCanvas
var radar: RadarView
var font: Font
var size := Vector2(854, 480)

var touches: Dictionary = {}
var joy_active := false
var joy_base := Vector2.ZERO
var joy_knob := Vector2.ZERO
const JOY_R := 58.0

var buttons: Dictionary = {}       # id -> {pos, r}
var menu_buttons: Array = []       # [{rect, id, label}]
var inv_slots: Array = []          # [{rect, id}]
var toasts: Array = []
var popup := {}
var popup_t := 0.0
var dmg_t := 0.0
var map_tex: ImageTexture


func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	canvas = HudCanvas.new()
	canvas.hud = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	radar = RadarView.new()
	radar.hud = self
	radar.clip_contents = true
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(radar)


func set_level(L: OfficeLevel) -> void:
	var img := Image.create(L.W, L.H, false, Image.FORMAT_RGBA8)
	for z in L.H:
		for x in L.W:
			var c := L.cells[z * L.W + x]
			var col := Color(0.02, 0.12, 0.05, 0.9)
			match c:
				OfficeLevel.WALL: col = Color(0.25, 0.75, 0.35, 1.0)
				OfficeLevel.TALL: col = Color(0.12, 0.42, 0.2, 1.0)
				OfficeLevel.LOW, OfficeLevel.PROP: col = Color(0.07, 0.28, 0.12, 1.0)
			img.set_pixel(x, z, col)
	map_tex = ImageTexture.create_from_image(img)


func toast(text: String, col: Color = C_TEXT, dur: float = 2.5) -> void:
	for t in toasts:
		if t.text == text:
			t.t = dur
			return
	toasts.append({"text": text, "col": col, "t": dur})
	if toasts.size() > 4:
		toasts.remove_at(0)


func reward_popup(n: int, digit: int, rw: Dictionary) -> void:
	popup = {"n": n, "digit": digit, "rw": rw}
	popup_t = 3.2


func damage_flash() -> void:
	dmg_t = 0.45


# ================================================================ обновление и раскладка
func update_hud(dt: float) -> void:
	size = get_viewport().get_visible_rect().size
	dmg_t = maxf(0.0, dmg_t - dt)
	popup_t = maxf(0.0, popup_t - dt)
	var i := toasts.size() - 1
	while i >= 0:
		toasts[i].t -= dt
		if toasts[i].t <= 0.0:
			toasts.remove_at(i)
		i -= 1
	_layout()
	radar.visible = game.state in ["play", "pause", "intro", "elevator"]
	canvas.queue_redraw()
	radar.queue_redraw()


func _layout() -> void:
	var W := size.x
	var H := size.y
	buttons = {
		"use": {"pos": Vector2(W - 84, H - 88), "r": 48.0},
		"melee": {"pos": Vector2(W - 196, H - 58), "r": 36.0},
		"crouch": {"pos": Vector2(W - 62, H - 204), "r": 32.0},
		"ctx": {"pos": Vector2(W - 198, H - 168), "r": 42.0},
		"swap": {"pos": Vector2(W - 62, H - 290), "r": 32.0},   # 0.13: «Заменить» — над «ПРИСЕД», не на «ВЗЛОМ»
		"vault": {"pos": Vector2(W - 146, H - 264), "r": 36.0},  # 0.14: «Перелезть» — между «ВЗЛОМ» и «ЗАМЕНИТЬ» (0.14.2: r 30 → 36)
		"pause": {"pos": Vector2(W - 172, 34), "r": 22.0},
		"unlock": {"pos": Vector2(64, H - 236), "r": 30.0},   # 0.16.1: «Снять цель» — слева сверху от стика, только при захвате
	}
	radar.position = Vector2(W - 140, 10)
	radar.size = Vector2(130, 130)
	inv_slots.clear()
	if game.player == null: return
	var o: Array = game.player.owned()
	var slot := 46.0
	var x0 := W * 0.5 - o.size() * slot * 0.5
	for k in o.size():
		inv_slots.append({"rect": Rect2(x0 + k * slot + 3, H - 56, slot - 6, slot - 6), "id": o[k]})


# ================================================================ ввод
func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_down(ev.index, ev.position)
		else:
			_up(ev.index, ev.position)
	elif ev is InputEventScreenDrag:
		_drag(ev.index, ev.position, ev.relative)


func _playing() -> bool:
	return game.state == "play"


func _down(id: int, p: Vector2) -> void:
	if game.state in ["play"]:
		for b in ["pause", "use", "melee", "crouch", "ctx", "swap", "vault", "unlock"]:
			if b == "ctx" and game.ctx.is_empty(): continue
			if b == "swap" and game.swap_pk.is_empty(): continue
			if b == "vault" and game.player.vault_target().is_empty(): continue
			if b == "unlock" and game.player.valid_lock() == null: continue
			var B: Dictionary = buttons[b]
			if p.distance_to(B.pos) <= B.r + 8.0:
				touches[id] = {"role": "btn", "btn": b}
				game.on_button(b, true)
				return
		for s in inv_slots:
			if s.rect.grow(3).has_point(p):
				game.select_item(s.id)
				touches[id] = {"role": "none"}
				return
		if Rect2(radar.position, radar.size).has_point(p):
			game.cam_yaw = game._nice_yaw(game.cam_yaw + PI / 2)
			touches[id] = {"role": "none"}
			return
		# короткий тап (без сдвига) по врагу — захват цели; поэтому запоминаем старт касания
		var tap := {"start": p, "t0": Time.get_ticks_msec(), "moved": 0.0}
		if p.x < size.x * 0.45 and not joy_active:
			joy_active = true
			joy_base = p
			joy_knob = Vector2.ZERO
			tap.role = "joy"
			touches[id] = tap
			return
		tap.role = "cam"
		touches[id] = tap
		return
	touches[id] = {"role": "menu", "start": p}


func _drag(id: int, p: Vector2, rel: Vector2) -> void:
	if not touches.has(id): return
	var t: Dictionary = touches[id]
	if t.has("moved"):
		t.moved += rel.length()
	match t.role:
		"joy":
			joy_knob = (p - joy_base).limit_length(JOY_R)
			move_vec = joy_knob / JOY_R
		"cam":
			game.rotate_camera(-rel.x * 0.008)


func _up(id: int, p: Vector2) -> void:
	if not touches.has(id): return
	var t: Dictionary = touches[id]
	touches.erase(id)
	if t.has("moved") and t.moved < 16.0 and Time.get_ticks_msec() - t.t0 < 400 and _playing():
		game.tap_world(t.start)
	match t.role:
		"joy":
			joy_active = false
			move_vec = Vector2.ZERO
			joy_knob = Vector2.ZERO
		"btn":
			game.on_button(t.btn, false)
		"menu":
			for b in menu_buttons:
				if b.rect.has_point(p) and b.rect.has_point(t.start):
					game.sfx.play("beep", 0.5, 0.0)
					game.on_button(b.id, true)
					return


# ================================================================ рисование
func text(ci: CanvasItem, pos: Vector2, s: String, fs: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var w := width
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0.0:
		w = 2000.0
		x = pos.x - 1000.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT and width < 0.0:
		w = 2000.0
		x = pos.x - 2000.0
	ci.draw_string_outline(font, Vector2(x, pos.y), s, align, w, fs, 4, Color(0, 0, 0, col.a))
	ci.draw_string(font, Vector2(x, pos.y), s, align, w, fs, col)


func draw_all(ci: CanvasItem) -> void:
	menu_buttons.clear()
	var st: String = game.state
	if st in ["play", "pause", "intro", "elevator", "dead"]:
		_draw_world_marks(ci)
		_draw_hud(ci)
	if dmg_t > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.0, 0.0, dmg_t * 0.6))
	match st:
		"title": _draw_title(ci)
		"howto": _draw_howto(ci)
		"floors": _draw_floors(ci)
		"intro": _draw_intro(ci)
		"pause": _draw_pause(ci)
		"elevator": _draw_elevator(ci)
		"dead", "gameover": _draw_gameover(ci)
		"victory": _draw_victory(ci)


func _project(p: Vector3) -> Variant:
	var cam: Camera3D = game.camera
	if cam.is_position_behind(p): return null
	var v: Vector2 = cam.unproject_position(p)
	var vs := Vector2(game.world_vp.size)
	return v * (size / vs)


func _draw_world_marks(ci: CanvasItem) -> void:
	var tsec := Time.get_ticks_msec() * 0.001
	# компьютеры для взлома
	for pc in game.L.pcs:
		if pc.hacked: continue
		var sp = _project(Vector3(pc.x + 0.5, 1.6 + sin(tsec * 3.0) * 0.08, pc.z + 0.5))
		# за краем экрана не рисуем: там координаты в десятки тысяч px — триангуляция сбоит
		if sp == null or not Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(sp): continue
		var pts := PackedVector2Array([sp + Vector2(0, -9), sp + Vector2(7, 0), sp + Vector2(0, 9), sp + Vector2(-7, 0)])
		_poly(ci, pts, Color(0.3, 1.0, 0.45, 0.85))
		text(ci, sp + Vector2(0, -14), "ПК", 13, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	if game.exit_open():
		var e: Dictionary = game.L.exit_elev
		var ep = _project(e.plane + Vector3(0, 2.9, 0))
		if ep != null:
			text(ci, ep, "ВЕРТОЛЁТ ▼" if game.floor_kind == "roof" else "ЛИФТ ▼", 16, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	# 0.16: упавшая ключ-карта
	for pk in game.pickups:
		if pk.id == "bags":
			var bp = _project(pk.node.position + Vector3(0, 0.9 + sin(tsec * 3.0) * 0.08, 0))
			if bp != null and Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(bp):
				text(ci, bp, "ПАКЕТЫ", 13, Items.CAT_COLORS[Items.Cat.SPECIAL], HORIZONTAL_ALIGNMENT_CENTER)   # 0.19.1
			continue
		if pk.id != "keycard": continue
		var kp = _project(pk.node.position + Vector3(0, 0.9 + sin(tsec * 3.0) * 0.08, 0))
		if kp != null and Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(kp):
			text(ci, kp, "КЛЮЧ-КАРТА", 13, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	# щелчки щелкунов — фиолетовые волны над ними (на телефоне без звука тоже видно)
	for wv in game.click_waves:
		if Vector2(wv.pos.x - game.player.px(), wv.pos.z - game.player.pz()).length() > 16.0: continue
		var wp = _project(wv.pos + Vector3(0, 2.0, 0))
		if wp == null or not Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(wp): continue
		var k: float = wv.t / 1.2
		for ring in 2:
			var rr := 6.0 + (k + ring * 0.3) * 22.0
			ci.draw_arc(wp, rr, -2.4, -0.7, 10, Color(C_CLICK, (1.0 - k) * 0.9), 2.0)
		if wv.t < 0.5:
			text(ci, wp + Vector2(0, -8), "щёлк", 12, Color(C_CLICK, 1.0 - k), HORIZONTAL_ALIGNMENT_CENTER)
	# значки над врагами
	for en: Enemy in game.enemies:
		if en.icon == "" or en.is_dead(): continue
		if en.dist_to(game.player) > 22.0: continue
		var h := 2.25 if en.state != Enemy.S.KNOCKED else 0.7
		var ip = _project(en.position + Vector3(0, h, 0))
		if ip == null: continue
		var col := C_YEL
		var s := en.icon
		if s == "!" or s == "!!": col = C_RED
		elif s == "z":
			col = Color(0.7, 0.85, 1.0)
			s = "z z"
		text(ci, ip, s, 24 if s.begins_with("!") else 18, col, HORIZONTAL_ALIGNMENT_CENTER)
	# прицел: захваченная тапом цель (жёлтая рамка, видна и за стеной) или автоприцел
	var pl: Player = game.player
	if game.state == "play" and not pl.dead:
		var lk := pl.valid_lock()
		if lk != null:
			_lock_mark(ci, lk, tsec)
		if pl.selected != "" and pl.can_aim():
			var df := Items.def(pl.selected)
			var t := pl.aim_target(pl.selected)
			if t != null and t != lk:
				_bracket(ci, t, C_RED if df.cat == Items.Cat.WEAPON else C_YEL)
			elif t == null and df.cat != Items.Cat.WEAPON:
				var tg := pl.throw_target(pl.selected)
				var gp = _project(tg.pos)
				if gp != null:
					ci.draw_arc(gp, 9.0, 0, TAU, 16, Color(0.5, 0.85, 1.0, 0.8), 2.0)
	# прогресс взлома
	if pl.hacking and game.ctx.has("pc"):
		var pc2: Dictionary = game.ctx.pc
		var r := Rect2(size.x * 0.5 - 130, size.y * 0.62, 260, 18)
		ci.draw_rect(r.grow(4), C_PANEL)
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(pc2.progress, 0, 1), r.size.y)), C_GREEN)
		var lines := ["> brute_force.exe --floor=%d" % game.floor_num, "> подбор пароля...", "> обход антивируса...", "> sudo give_me_password"]
		text(ci, Vector2(size.x * 0.5, r.position.y - 8), lines[int(pc2.progress * 4) % 4], 15, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, r.position.y + 15), "ВЗЛОМ %d%%" % int(pc2.progress * 100), 14, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)


## Безопасная заливка многоугольника: пропускаем вырожденные (совпавшие/NaN-точки, нулевая площадь) —
## иначе движок пишет «Invalid polygon data, triangulation failed» (было у лифта и на краю радара).
func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var area := 0.0
	for i in pts.size():
		var a := pts[i]
		if not (is_finite(a.x) and is_finite(a.y)) or absf(a.x) > 1e4 or absf(a.y) > 1e4:
			return
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	if absf(area) < 2.0:
		return
	# та же триангуляция, что в движке: не вышла — не рисуем (иначе ошибка в лог каждый кадр)
	if Geometry2D.triangulate_polygon(pts).is_empty():
		if game.autotest and _poly_fail < 5:
			_poly_fail += 1
			print("[hud] пропущен вырожденный многоугольник: ", pts)
		return
	ci.draw_colored_polygon(pts, col)


var _poly_fail := 0


## Прямоугольник врага на экране (или null, если он за камерой).
func _enemy_rect(e: Enemy) -> Variant:
	var a = _project(e.position + Vector3(0, 2.0, 0))
	var b = _project(e.position)
	if a == null or b == null: return null
	var hgt: float = maxf(16.0, b.y - a.y)
	return Rect2(a.x - hgt * 0.35, a.y, hgt * 0.7, hgt)


## Враг под пальцем (с запасом — палец толстый, враги на экране мелкие). Стены не мешают.
func pick_enemy(p: Vector2) -> Enemy:
	var best: Enemy = null
	var best_d := 1e9
	for e: Enemy in game.enemies:
		if e.is_dead() or e.dist_to(game.player) > Player.LOCK_RANGE: continue
		var r = _enemy_rect(e)
		if r == null: continue
		if not r.grow(maxf(16.0, r.size.x * 0.5)).has_point(p): continue
		var d := p.distance_to(r.get_center())
		if d < best_d:
			best_d = d
			best = e
	return best


## Захваченная цель: жёлтая рамка с уголками и подписью.
func _lock_mark(ci: CanvasItem, e: Enemy, tsec: float) -> void:
	var r = _enemy_rect(e)
	if r == null: return
	r = r.grow(3.0)
	var a := 0.75 + 0.25 * sin(tsec * 6.0)
	var col := Color(C_YEL, a)
	ci.draw_rect(r, Color(C_YEL, 0.12))
	ci.draw_rect(r, col, false, 2.0)
	_corners(ci, r.grow(3.0), col, 9.0, 3.0)
	text(ci, Vector2(r.get_center().x, r.position.y - 6), "ЦЕЛЬ", 12, col, HORIZONTAL_ALIGNMENT_CENTER)


func _bracket(ci: CanvasItem, e: Enemy, col: Color) -> void:
	var r = _enemy_rect(e)
	if r == null: return
	_corners(ci, r, col, 6.0, 2.0)


func _corners(ci: CanvasItem, r: Rect2, col: Color, k: float, w: float) -> void:
	for c in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
		var sx := 1.0 if c.x < r.get_center().x else -1.0
		var sy := 1.0 if c.y < r.get_center().y else -1.0
		ci.draw_line(c, c + Vector2(k * sx, 0), col, w)
		ci.draw_line(c, c + Vector2(0, k * sy), col, w)


func _draw_hud(ci: CanvasItem) -> void:
	var W := size.x
	var H := size.y
	var pl: Player = game.player
	var tsec := Time.get_ticks_msec() * 0.001
	# тревога — красная рамка
	if game.any_hostile():
		var a := 0.35 + 0.25 * sin(tsec * 8.0)
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.1, 0.1, a), false, 6.0)
		text(ci, Vector2(W * 0.5, 92), "! ТРЕВОГА !", 20, Color(1, 0.3, 0.25, 0.6 + 0.4 * sin(tsec * 8.0)), HORIZONTAL_ALIGNMENT_CENTER)
	elif game.any_searching():
		text(ci, Vector2(W * 0.5, 92), "? ПОИСК ?", 18, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	# портрет + здоровье
	ci.draw_rect(Rect2(8, 8, 214, 62), C_PANEL)
	ci.draw_texture_rect(OfficeTex.get_tex("p_face"), Rect2(14, 14, 50, 50), false, Color(1, 0.6, 0.6) if dmg_t > 0 else Color.WHITE)
	text(ci, Vector2(72, 28), "А.В. ДЗВИНИК", 14, C_TEXT)
	var tag_y := 74.0   # 0.16–0.17: значки «особого» под портретом
	if pl.disguised and not game.disguise_blown:
		ci.draw_rect(Rect2(8, tag_y, 120, 20), C_PANEL)
		text(ci, Vector2(68, tag_y + 15), "В МАСКИРОВКЕ", 12, Items.CAT_COLORS[Items.Cat.SPECIAL], HORIZONTAL_ALIGNMENT_CENTER)   # 0.16
		tag_y += 22.0
	if pl.bags:
		ci.draw_rect(Rect2(8, tag_y, 120, 20), C_PANEL)
		text(ci, Vector2(68, tag_y + 15), "В ПАКЕТАХ", 12, Items.CAT_COLORS[Items.Cat.SPECIAL], HORIZONTAL_ALIGNMENT_CENTER)   # 0.17
	var hpk: float = pl.hp / pl.max_hp
	ci.draw_rect(Rect2(72, 35, 140, 12), Color(0.15, 0.02, 0.02))
	ci.draw_rect(Rect2(72, 35, 140 * hpk, 12), C_GREEN.lerp(C_RED, 1.0 - hpk))
	text(ci, Vector2(142, 46), str(int(pl.hp)), 12, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var vis: float = game.L.visibility_at(pl.px(), pl.pz()) * (0.6 if pl.crouch else 1.0)
	text(ci, Vector2(72, 64), "ВИДНО:", 12, C_DIM)
	for k in 5:
		var on := vis > k * 0.2 + 0.05
		ci.draw_rect(Rect2(122 + k * 18, 55, 14, 9), C_YEL if on else Color(0.2, 0.2, 0.15))
	# этаж и пароль
	ci.draw_rect(Rect2(W * 0.5 - 150, 8, 300, 62), C_PANEL)
	if game.floor_kind == "roof":
		# 0.19: крыша — финал
		var left: int = game.elites.filter(func(e): return is_instance_valid(e) and not e.is_dead() and not e.is_down()).size()
		var line2 := "ВЕРТОЛЁТ ЖДЁТ — В ВЕРТОЛЁТ!" if game.exit_open() else ("ДОБЕРИСЬ ДО ВЕРТОЛЁТНОЙ ПЛОЩАДКИ" if game.heli_phase == "wait" else ("ВЕРТОЛЁТ САДИТСЯ…" if game.heli_phase == "landing" else "ОХРАНА ВЕРТОЛЁТА: %d" % left))
		text(ci, Vector2(W * 0.5, 30), "КРЫША · ЭТАЖ %d" % game.floor_num, 16, Color(0.6, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(W * 0.5, 56), line2, 14, C_GREEN if game.exit_open() else C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	elif game.floor_kind == "battle":
		# 0.18: поле битвы — лифт открыт
		text(ci, Vector2(W * 0.5, 30), "ПОЛЕ БИТВЫ · ЭТАЖ %d" % game.floor_num, 16, Color(1.0, 0.45, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(W * 0.5, 56), "ЛИФТ ОТКРЫТ", 16, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	elif game.floor_kind == "fort":
		# 0.17: укреплённый офис — лифт открыт
		text(ci, Vector2(W * 0.5, 30), "УКРЕПЛЁННЫЙ ОФИС · ЭТАЖ %d" % game.floor_num, 16, Color(0.5, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(W * 0.5, 56), "ЛИФТ ОТКРЫТ", 16, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	elif game.floor_kind == "lair":
		# 0.16: логово — вместо пароля ключ-карта
		text(ci, Vector2(W * 0.5, 30), "ЛОГОВО БАНДИТОВ · ЭТАЖ %d" % game.floor_num, 16, Color(1.0, 0.6, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(W * 0.5, 56), "КЛЮЧ-КАРТА: " + ("ЕСТЬ — К ЛИФТУ" if game.key_taken else "у бандита (зелёная)"), 16, C_GREEN if game.key_taken else C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		text(ci, Vector2(W * 0.5, 30), "ЭТАЖ %d" % game.floor_num, 18, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		var pw := ""
		for i in 5:
			pw += (str(game.password[i]) if i < game.hacked else "_") + " "
		text(ci, Vector2(W * 0.5, 56), "ПАРОЛЬ ЛИФТА: " + pw.strip_edges(), 16, C_GREEN if game.exit_open() else C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	var room: Dictionary = game.L.room_at(pl.px(), pl.pz())
	if not room.is_empty():
		text(ci, Vector2(W * 0.5, 84 if not (game.any_hostile() or game.any_searching()) else 112), OfficeLevel.ROOM_NAMES.get(room.type, ""), 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	# тосты
	var y := 136.0
	for t in toasts:
		var c: Color = t.col
		c.a = minf(1.0, t.t * 2.0)
		text(ci, Vector2(W * 0.5, y), t.text, 16, c, HORIZONTAL_ALIGNMENT_CENTER)
		y += 22.0
	# награда за взлом
	if popup_t > 0.0 and not popup.is_empty():
		var a2 := minf(1.0, popup_t * 2.0)
		var r := Rect2(W * 0.5 - 190, 128, 380, 112)
		ci.draw_rect(r, Color(0, 0.08, 0.03, 0.85 * a2))
		ci.draw_rect(r, Color(C_GREEN, a2), false, 2.0)
		var df := Items.def(popup.rw.id)
		text(ci, Vector2(W * 0.5, r.position.y + 26), "КОМПЬЮТЕР ВЗЛОМАН (%d/5)" % popup.n, 18, Color(C_GREEN, a2), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(W * 0.5, r.position.y + 50), "Цифра пароля: %d" % popup.digit, 16, Color(C_TEXT, a2), HORIZONTAL_ALIGNMENT_CENTER)
		ci.draw_texture_rect(Items.icon(popup.rw.id), Rect2(r.position.x + 24, r.position.y + 62, 40, 40), false, Color(1, 1, 1, a2))
		text(ci, Vector2(r.position.x + 76, r.position.y + 80), "%s ×%d  [%s]" % [df.name, popup.rw.amount, Items.CAT_NAMES[df.cat]], 16, Color(Items.CAT_COLORS[df.cat], a2))
		text(ci, Vector2(r.position.x + 76, r.position.y + 100), "нашлось %s" % popup.rw.flavor, 13, Color(C_DIM, a2))
	if game.state != "play":
		return
	# стик
	var jb := joy_base if joy_active else Vector2(118, H - 118)
	ci.draw_circle(jb, JOY_R, Color(1, 1, 1, 0.1 if joy_active else 0.05))
	ci.draw_arc(jb, JOY_R, 0, TAU, 32, Color(1, 1, 1, 0.35 if joy_active else 0.15), 2.0)
	ci.draw_circle(jb + joy_knob, 24, Color(1, 1, 1, 0.45 if joy_active else 0.15))
	if not joy_active:
		text(ci, jb + Vector2(0, 6), "ХОДИТЬ", 13, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
	# кнопки
	var sel: String = pl.selected
	_round_button(ci, "use", "" if sel != "" else "—", Items.CAT_COLORS[Items.def(sel).cat] if sel != "" else C_DIM)
	if sel != "":
		var B: Dictionary = buttons.use
		ci.draw_texture_rect(Items.icon(sel), Rect2(B.pos - Vector2(26, 30), Vector2(52, 52)), false)
		text(ci, B.pos + Vector2(0, 34), "%s %d/%d" % [Items.def(sel).name, pl.inv.get(sel, 0), Items.cap(sel)], 12, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	# 0.12: сзади цели, которая не видит героя, — подсказка: ДУШИТЬ (держи — насмерть) / УБИТЬ (нож или топор в руке)
	if pl.is_choking():
		_round_button(ci, "melee", "ДЕРЖИ" if not pl.choke_long else "ДУШИТЬ", C_YEL, true)
		text(ci, buttons.melee.pos + Vector2(0, 50), "насмерть" if pl.choke_long else "держи — насмерть", 12, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	elif pl.sneak_target() != null:
		var blade: bool = pl.blade_ready()
		_round_button(ci, "melee", "УБИТЬ" if blade else "ДУШИТЬ", C_RED if blade else C_YEL, true)
		if not blade:
			text(ci, buttons.melee.pos + Vector2(0, 50), "держи — насмерть", 12, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_round_button(ci, "melee", "УДАР", Color(1, 0.6, 0.5))
	_round_button(ci, "crouch", "ПРИСЕД", C_YEL if pl.crouch else C_DIM, pl.crouch)
	# 0.16.1: цель захвачена тапом — «СНЯТЬ ЦЕЛЬ» слева сверху от стика
	if pl.valid_lock() != null:
		_round_button(ci, "unlock", "", C_YEL, true)
		text(ci, buttons.unlock.pos + Vector2(0, 0), "СНЯТЬ", 12, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, buttons.unlock.pos + Vector2(0, 14), "ЦЕЛЬ", 12, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	# 0.14: вплотную к столу/перегородке/ксероксу и смотрит на него — «ПЕРЕЛЕЗТЬ»
	if not pl.vault_target().is_empty():
		_round_button(ci, "vault", "", C_GREEN, true)
		text(ci, buttons.vault.pos + Vector2(0, 2), "ПЕРЕ-", 13, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, buttons.vault.pos + Vector2(0, 17), "ЛЕЗТЬ", 13, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	# 0.13: рядом лежит предмет в занятый слот — «Заменить» + иконка того, на что меняем, и сколько там
	if not game.swap_pk.is_empty():
		var sp: Dictionary = game.swap_pk
		var SB: Dictionary = buttons.swap
		var scol: Color = Items.CAT_COLORS[Items.def(sp.id).cat]
		_round_button(ci, "swap", "", scol, true)
		ci.draw_texture_rect(Items.icon(sp.id), Rect2(SB.pos - Vector2(18, 22), Vector2(36, 36)), false)
		text(ci, SB.pos + Vector2(0, 26), "×%d" % sp.n, 12, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, SB.pos + Vector2(0, -38), "ЗАМЕНИТЬ", 13, scol, HORIZONTAL_ALIGNMENT_CENTER)
	if not game.ctx.is_empty():
		var lbl := "ВЗЛОМ" if game.ctx.kind == "hack" else ("ЛИФТ" if game.exit_open() else "ЛИФТ ✕")
		if game.floor_kind == "roof" and game.ctx.kind == "elevator":
			lbl = "В ВЕРТ." if game.exit_open() else "ВЕРТ. ✕"   # 0.19
		var ccol: Color = C_GREEN if game.ctx.kind == "hack" or game.exit_open() else C_RED
		if game.ctx.kind == "hatch":
			lbl = "ЗАКРЫТЬ"   # 0.20: заблокировать люк пожарной лестницы
			ccol = C_YEL
		_round_button(ci, "ctx", lbl, ccol, game.ctx_held)
		if game.ctx.kind == "hatch" and game.hatch_hold > 0.0:
			text(ci, buttons.ctx.pos + Vector2(0, 58), "%d%%" % int(100.0 * game.hatch_hold / game.HATCH_TIME), 12, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			text(ci, buttons.ctx.pos + Vector2(0, 58), "держи 3 с" if game.ctx.kind == "hatch" else "держи", 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	var pb: Dictionary = buttons.pause
	ci.draw_circle(pb.pos, pb.r, C_PANEL)
	ci.draw_rect(Rect2(pb.pos + Vector2(-8, -9), Vector2(5, 18)), C_TEXT)
	ci.draw_rect(Rect2(pb.pos + Vector2(3, -9), Vector2(5, 18)), C_TEXT)
	# инвентарь
	for s in inv_slots:
		var r2: Rect2 = s.rect
		var is_sel: bool = s.id == sel
		ci.draw_rect(r2, Color(0.05, 0.08, 0.06, 0.8))
		ci.draw_rect(r2, C_YEL if is_sel else Color(Items.CAT_COLORS[Items.def(s.id).cat], 0.5), false, 3.0 if is_sel else 1.5)
		ci.draw_texture_rect(Items.icon(s.id), r2.grow(-5), false)
		var cnt: int = pl.inv.get(s.id, 0)
		text(ci, r2.end - Vector2(2, 3), "%d/%d" % [cnt, Items.cap(s.id)], 11, C_YEL if cnt >= Items.cap(s.id) else C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)


func _round_button(ci: CanvasItem, id: String, label: String, col: Color, active: bool = false) -> void:
	var B: Dictionary = buttons[id]
	ci.draw_circle(B.pos, B.r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.75 if active else 0.55))
	ci.draw_arc(B.pos, B.r, 0, TAU, 32, Color(col, 0.9), 3.0 if active else 2.0)
	if label != "":
		text(ci, B.pos + Vector2(0, 6), label, 14, col, HORIZONTAL_ALIGNMENT_CENTER)


# ---------------------------------------------------------------- меню
func _menu_button(ci: CanvasItem, r: Rect2, id: String, label: String, col: Color = C_TEXT) -> void:
	ci.draw_rect(r, Color(0.03, 0.1, 0.05, 0.85))
	ci.draw_rect(r, Color(col, 0.8), false, 2.0)
	text(ci, Vector2(r.get_center().x, r.get_center().y + 7), label, 20, col, HORIZONTAL_ALIGNMENT_CENTER)
	menu_buttons.append({"rect": r, "id": id})


func _shade(ci: CanvasItem, a: float) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, a))


func _draw_title(ci: CanvasItem) -> void:
	var W := size.x
	var H := size.y
	_shade(ci, 0.45)
	var tsec := Time.get_ticks_msec() * 0.001
	var wob := sin(tsec * 2.0) * 2.0
	text(ci, Vector2(W * 0.5, 96 + wob), "ПОБЕГ ИЗ ОФИСА", 54, Color(0.4, 1.0, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 132), "Александр Вадимович Дзвиник против бесконечного офиса", 18, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var bw := 260.0
	var x := W * 0.5 - bw * 0.5
	var ids := [["start", "НАЧАТЬ СМЕНУ", C_GREEN]]
	# «Играть с этажа…» — появляется, когда хоть раз доехал до 5-го
	if not game.start_floors().is_empty():
		ids.append(["floors", "ИГРАТЬ С ЭТАЖА…", C_YEL])
	ids.append(["howto", "КАК ИГРАТЬ", C_TEXT])
	ids.append(["sound", "ЗВУК: " + ("ВЫКЛ" if game.sfx.muted else "ВКЛ"), C_TEXT])
	ids.append(["quit", "УВОЛИТЬСЯ (ВЫХОД)", C_DIM])
	var step := 60.0 if ids.size() <= 4 else 54.0
	for i in ids.size():
		_menu_button(ci, Rect2(x, 165 + i * step, bw, step - 8), ids[i][0], ids[i][1], ids[i][2])
	if game.best_floor > 0:
		text(ci, Vector2(W * 0.5, H - 24), "Рекорд: пройдено этажей — %d" % game.best_floor, 16, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)


## «Играть с этажа…»: 5, 10, 15… — те, до которых хоть раз доезжал. Набор — стартовый.
func _draw_floors(ci: CanvasItem) -> void:
	var W := size.x
	var H := size.y
	_shade(ci, 0.6)
	text(ci, Vector2(W * 0.5, 80), "ИГРАТЬ С ЭТАЖА", 34, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 112), "С собой только стартовый набор: 2 бутылки. Будет тяжело.", 15, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	var fl: Array = game.start_floors()
	var bw := 120.0
	var cols := mini(5, fl.size())
	var x0 := W * 0.5 - cols * (bw + 12) * 0.5 + 6
	for i in fl.size():
		var r := Rect2(x0 + (i % 5) * (bw + 12), 140 + int(i / 5) * 62, bw, 50)
		_menu_button(ci, r, "from_%d" % fl[i], "ЭТАЖ %d" % fl[i], C_GREEN)
	# 0.18.2: чит-сборка — какой будет первый этаж (только для 5, 10, 15…; дальше — как в игре)
	if game.cheat_menu():
		var ky := 140.0 + ceilf(fl.size() / 5.0) * 62.0 + 14.0
		text(ci, Vector2(W * 0.5, ky), "ЧИТ: тип этажа", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		var kw := 148.0
		var kx: float = W * 0.5 - game.CHEAT_KINDS.size() * (kw + 8) * 0.5 + 4
		for k in game.CHEAT_KINDS.size():
			var ck: Array = game.CHEAT_KINDS[k]
			var on: bool = game.cheat_kind == ck[0]
			_menu_button(ci, Rect2(kx + k * (kw + 8), ky + 10, kw, 42), "kind_" + ck[0], ck[1], C_YEL if on else C_DIM)
	_menu_button(ci, Rect2(W * 0.5 - 110, H - 70, 220, 46), "title", "НАЗАД", C_DIM)
	text(ci, Vector2(W * 0.5, H - 84), "Дальше всего доезжал: этаж %d" % game.max_reached, 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_howto(ci: CanvasItem) -> void:
	var W := size.x
	var H := size.y
	_shade(ci, 0.85)
	var lines := [
		["ЦЕЛЬ", C_GREEN],
		["Взломай 5 компьютеров с зелёным экраном — каждый даёт цифру пароля и случайную награду.", C_TEXT],
		["Собрал пароль — беги к лифту. Лифт везёт... на следующий этаж офиса.", C_TEXT],
		["УПРАВЛЕНИЕ", C_GREEN],
		["Стик слева: чуть-чуть — крадёшься тихо, до упора — бежишь (громко). Свайп справа — камера.", C_TEXT],
		["ПРИСЕД — тише и прячешься за столами. Сзади к тому, кто не видит: ДУШИТЬ (держи — насмерть), с ножом — УБИТЬ.", C_TEXT],
		["Тап по врагу (даже за стеной) — захват цели, жёлтая рамка. Тап ещё раз — снять захват.", C_YEL],
		["ПРЕДМЕТЫ", C_GREEN],
		["Оружие (пистолет, дробовик, ПБ) — убивает, но шумит. Лечение — кофе, энергетик, аптечка.", Items.CAT_COLORS[Items.Cat.WEAPON]],
		["Бутылка, будильник — только отвлекают. Кирпич, огнетушитель — отвлекают или нокаутируют.", Items.CAT_COLORS[Items.Cat.KNOCK]],
		["Сюрикен, граната — отвлекают или убивают (без нокдауна).", Items.CAT_COLORS[Items.Cat.LETHAL]],
		["ВРАГИ", C_GREEN],
		["Зомби-менеджер — медленный, но долго чует, куда ты убежал.", C_TEXT],
		["Зомби-бухгалтерша — быстрая, бьёт слабо, но часто.   Толстяк из продаж — рывки, бьёт больно.", C_TEXT],
		["Мародёры (со 2-го этажа) видят только фонариком, кричат и зовут своих. С них падает оружие.", Color(1.0, 0.65, 0.15)],
		["Темнота и присед прячут. «?» — что-то заподозрил, «!» — заметил. Выстрел в спину — насмерть.", C_YEL],
	]
	var y := 38.0
	for l in lines:
		var head: bool = l[1] == C_GREEN
		text(ci, Vector2(W * 0.5, y), l[0], 17 if head else 14, l[1], HORIZONTAL_ALIGNMENT_CENTER)
		y += 24.0 if head else 21.0
	_menu_button(ci, Rect2(W * 0.5 - 110, H - 64, 220, 46), "title", "ПОНЯТНО")


func _draw_intro(ci: CanvasItem) -> void:
	var a := clampf(3.0 - game.state_t, 0.0, 1.0)
	_shade(ci, a * 0.8)
	if game.floor_kind == "roof":
		# 0.19: финал
		text(ci, Vector2(size.x * 0.5, size.y * 0.42), "КРЫША", 52, Color(0.6, 0.75, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 44), "Этаж %d. Выше некуда. Ночь, ветер, бандиты." % game.floor_num, 18, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 74), "Доберись до вертолётной площадки — это твой выход.", 15, Color(C_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
		return
	if game.floor_kind == "battle":
		# 0.18: поле битвы
		text(ci, Vector2(size.x * 0.5, size.y * 0.42), "ПОЛЕ БИТВЫ", 46, Color(1.0, 0.45, 0.35, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 44), "Этаж %d. Офисники и бандиты делят этаж. Зомби нет." % game.floor_num, 18, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 74), "Лифт открыт — лишь бы не попасть под пулю. Где-то посередине ящик с патронами.", 15, Color(C_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
		return
	if game.floor_kind == "fort":
		# 0.17: укреплённый офис выживальщиков
		text(ci, Vector2(size.x * 0.5, size.y * 0.42), "УКРЕПЛЁННЫЙ ОФИС", 46, Color(0.5, 0.75, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 44), "Этаж %d. Здесь живут выжившие сотрудники. Зомби нет." % game.floor_num, 18, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 74), "Лифт открыт. У них есть пакеты на ноги — охраняют.", 15, Color(C_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
		return
	if game.floor_kind == "lair":
		# 0.16: логово бандитов
		text(ci, Vector2(size.x * 0.5, size.y * 0.42), "ЛОГОВО БАНДИТОВ", 46, Color(1.0, 0.55, 0.3, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 44), "Этаж %d. Компьютеров нет, зомби тоже." % game.floor_num, 18, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
		text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 74), "Пароль — на зелёной ключ-карте за спиной у одного из бандитов", 15, Color(C_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
		return
	text(ci, Vector2(size.x * 0.5, size.y * 0.42), "ЭТАЖ %d" % game.floor_num, 52, Color(0.4, 1.0, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 44), game.quote, 18, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(size.x * 0.5, size.y * 0.42 + 74), "Взломай 5 ПК и уходи на лифте", 15, Color(C_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_pause(ci: CanvasItem) -> void:
	var W := size.x
	_shade(ci, 0.6)
	text(ci, Vector2(W * 0.5, 120), "ПЕРЕРЫВ НА КОФЕ", 40, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	var x := W * 0.5 - 130
	_menu_button(ci, Rect2(x, 170, 260, 48), "pause", "ПРОДОЛЖИТЬ", C_GREEN)
	_menu_button(ci, Rect2(x, 230, 260, 48), "sound", "ЗВУК: " + ("ВЫКЛ" if game.sfx.muted else "ВКЛ"))
	_menu_button(ci, Rect2(x, 290, 260, 48), "title", "В ГЛАВНОЕ МЕНЮ", C_DIM)


func _draw_elevator(ci: CanvasItem) -> void:
	var t: float = game.state_t
	if t < 3.0: return
	var a := clampf((t - 3.0) / 0.8, 0.0, 1.0)
	_shade(ci, a)
	text(ci, Vector2(size.x * 0.5, size.y * 0.45), "ЛИФТ ЕДЕТ...", 30, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(size.x * 0.5, size.y * 0.45 + 40), "ЭТАЖ %d → %d" % [game.floor_num, game.floor_num + 1], 22, Color(C_YEL, a), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_gameover(ci: CanvasItem) -> void:
	var W := size.x
	var a := 1.0 if game.state == "gameover" else clampf(game.state_t / 2.5, 0.0, 0.7)
	_shade(ci, a * 0.75)
	if game.state != "gameover": return
	text(ci, Vector2(W * 0.5, 110), "ВЫ УВОЛЕНЫ", 52, C_RED, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 150), game.death_line, 18, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var s: Dictionary = game.stats
	text(ci, Vector2(W * 0.5, 192), "Этаж: %d   Взломано ПК: %d   Устранено: %d   Нокаутов: %d" % [game.floor_num, s.hacked, s.kills, s.knockouts], 16, C_YEL, HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 218), "Рекорд: %d эт." % game.best_floor, 15, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_button(ci, Rect2(W * 0.5 - 130, 250, 260, 48), "retry", "ЕЩЁ РАЗ", C_GREEN)
	_menu_button(ci, Rect2(W * 0.5 - 130, 310, 260, 48), "title", "В МЕНЮ", C_DIM)


# ================================================================ радар
func draw_radar(ci: Control) -> void:
	var L: OfficeLevel = game.L
	var pl: Player = game.player
	if L == null or pl == null or map_tex == null: return
	var sz := ci.size
	var c := sz * 0.5
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.06, 0.02, 0.85))
	var sc := 4.2
	var yaw: float = game.cam_yaw
	ci.draw_set_transform(c, yaw, Vector2(sc, sc))
	var p := Vector2(pl.px(), pl.pz())
	ci.draw_texture_rect(map_tex, Rect2(-p, Vector2(L.W, L.H)), false)
	var tsec := Time.get_ticks_msec() * 0.001
	for pc in L.pcs:
		if pc.hacked: continue
		var q := Vector2(pc.x + 0.5, pc.z + 0.5) - p
		ci.draw_rect(Rect2(q - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(0.4, 1, 0.5, 0.6 + 0.4 * sin(tsec * 6.0)))
	var e: Dictionary = L.exit_elev
	var eq := Vector2(e.plane.x, e.plane.z) - p
	ci.draw_rect(Rect2(eq - Vector2(1, 1), Vector2(2, 2)), C_YEL if game.exit_open() else Color(0.6, 0.6, 0.4))
	for en: Enemy in game.enemies:
		if en.is_dead(): continue
		var q2 := Vector2(en.px(), en.pz()) - p
		if q2.length() > 22.0: continue
		var col := C_RED if en.is_hostile() else (C_YEL if en.icon == "?" else Color(1, 0.5, 0.4))
		if en is Human and not en.is_hostile():
			col = Color(1.0, 0.65, 0.15) if en.icon != "?" else C_YEL
		if en is Human and (en as Human).is_loyal():
			col = Color(0.45, 0.75, 1.0)   # 0.15: офисники, пока свои, — голубые
		if en is Clicker:
			col = C_CLICK if not en.is_hostile() else Color(1.0, 0.3, 0.9)
		if not en.is_down() and not en is Clicker:
			var va := en._view_angle()
			var fov := deg_to_rad((en as Human).beam_fov() if en is Human else en.T.fov) * 0.5
			var rr := 4.0
			var cc := Color(col, 0.22)
			var cols := PackedColorArray([cc, cc, cc])
			var pl_ := q2 + Vector2(sin(va - fov), cos(va - fov)) * rr
			var pm := q2 + Vector2(sin(va), cos(va)) * rr * 1.1
			var pr := q2 + Vector2(sin(va + fov), cos(va + fov)) * rr
			ci.draw_primitive(PackedVector2Array([q2, pl_, pm]), cols, PackedVector2Array())
			ci.draw_primitive(PackedVector2Array([q2, pm, pr]), cols, PackedVector2Array())
		ci.draw_circle(q2, 0.55, col if not en.is_down() else Color(0.5, 0.6, 0.8))
	# 0.20: люки пожарных лестниц — красные (открыт) / серые (заблокирован) полоски у стены
	for es in L.escapes:
		var qe := Vector2(es.plane.x, es.plane.z) - p
		if qe.length() < 22.0:
			ci.draw_rect(Rect2(qe - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), Color(0.55, 0.55, 0.55) if es.locked else Color(1.0, 0.25, 0.2, 0.6 + 0.4 * sin(tsec * 4.0)))
	# 0.19.1: пакеты на ноги (укреплённый офис), пока не подобраны — розовый квадрат
	for pk in game.pickups:
		if pk.id == "bags":
			var qb := Vector2(pk.node.position.x, pk.node.position.z) - p
			ci.draw_rect(Rect2(qb - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), Color(Items.CAT_COLORS[Items.Cat.SPECIAL], 0.6 + 0.4 * sin(tsec * 5.0)))
	# волны щелчков на радаре
	for wv in game.click_waves:
		var qw := Vector2(wv.pos.x, wv.pos.z) - p
		if qw.length() > 22.0: continue
		var kw: float = wv.t / 1.2
		ci.draw_arc(qw, 0.8 + kw * 4.0, 0, TAU, 16, Color(C_CLICK, 1.0 - kw), 0.35)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# игрок — стрелка
	var fa: float = pl.angle - yaw
	var f := Vector2(sin(fa), cos(fa))
	var r := Vector2(f.y, -f.x)
	_poly(ci, PackedVector2Array([c + f * 7.0, c - f * 4.0 + r * 4.0, c - f * 4.0 - r * 4.0]), Color.WHITE)
	# стрелка к ближайшему невзломанному ПК или к лифту, если он за краем
	var goal := Vector2.INF
	var best := 1e9
	if game.floor_kind == "roof" and not game.exit_open():
		goal = Vector2(L.helipad.x, L.helipad.z)   # 0.19: к вертолётной площадке
	elif game.floor_kind == "lair" and not game.exit_open():
		# 0.16: логово — стрелка к упавшей ключ-карте (пока её не подняли)
		for pk in game.pickups:
			if pk.id == "keycard":
				goal = Vector2(pk.node.position.x, pk.node.position.z)
	elif not game.exit_open():
		for pc in L.pcs:
			if pc.hacked: continue
			var d := Vector2(pc.x + 0.5, pc.z + 0.5).distance_to(p)
			if d < best:
				best = d
				goal = Vector2(pc.x + 0.5, pc.z + 0.5)
	else:
		goal = Vector2(e.plane.x, e.plane.z)
	if goal != Vector2.INF:
		var rel := (goal - p).rotated(yaw) * sc
		if rel.length() > sz.x * 0.45:
			var dirv := rel.normalized()
			var tip := c + dirv * (sz.x * 0.45)
			var side := Vector2(dirv.y, -dirv.x)
			_poly(ci, PackedVector2Array([tip, tip - dirv * 9.0 + side * 5.0, tip - dirv * 9.0 - side * 5.0]), C_GREEN if not game.exit_open() else C_YEL)
	# 0.19.1: стрелка к пакетам у края радара, если они дальше видимого
	for pk in game.pickups:
		if pk.id != "bags": continue
		var relb := (Vector2(pk.node.position.x, pk.node.position.z) - p).rotated(yaw) * sc
		if relb.length() > sz.x * 0.45:
			var dvb := relb.normalized()
			var tb := c + dvb * (sz.x * 0.45)
			var sdb := Vector2(dvb.y, -dvb.x)
			_poly(ci, PackedVector2Array([tb, tb - dvb * 9.0 + sdb * 5.0, tb - dvb * 9.0 - sdb * 5.0]), Items.CAT_COLORS[Items.Cat.SPECIAL])
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.3, 1.0, 0.45, 0.7), false, 2.0)
	text(ci, Vector2(sz.x * 0.5, sz.y + 14), "РАДАР", 11, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)


class HudCanvas:
	extends Control
	var hud: Hud
	func _draw() -> void:
		hud.draw_all(self)


class RadarView:
	extends Control
	var hud: Hud
	func _draw() -> void:
		hud.draw_radar(self)


## 0.19: финал — вертолёт улетает, через 3,5 с экран «ТЫ СБЕЖАЛ!» со статистикой забега.
func _draw_victory(ci: CanvasItem) -> void:
	if game.state_t < 3.5:
		return
	var W := size.x
	var a := clampf((game.state_t - 3.5) / 1.5, 0.0, 1.0)
	_shade(ci, a * 0.8)
	var s: Dictionary = game.stats
	var tm := int(s.get("time", 0.0))
	text(ci, Vector2(W * 0.5, 96), "ТЫ СБЕЖАЛ!", 56, Color(C_GREEN, a), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 134), "Александр Вадимович Дзвиник улетает из бесконечного офиса.", 18, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 176), "Забег с %d-го этажа: %d:%02d   Этажей: %d   Взломано ПК: %d" % [int(s.get("from", 1)), tm / 60, tm % 60, s.floors, s.hacked], 16, Color(C_YEL, a), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 202), "Устранено: %d   Нокаутов: %d   Раз тебя замечали: %d" % [s.kills, s.knockouts, int(s.get("alerts", 0))], 16, Color(C_YEL, a), HORIZONTAL_ALIGNMENT_CENTER)
	text(ci, Vector2(W * 0.5, 228), "Игра пройдена: %d раз" % game.beaten, 15, Color(C_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
	if a >= 1.0:
		_menu_button(ci, Rect2(W * 0.5 - 130, 260, 260, 48), "retry", "НОВАЯ ИГРА", C_GREEN)
		_menu_button(ci, Rect2(W * 0.5 - 130, 320, 260, 48), "title", "В МЕНЮ", C_DIM)
