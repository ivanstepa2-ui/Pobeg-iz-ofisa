class_name OfficeTex
extends RefCounted
## Процедурные пиксельные текстуры офиса, персонажей и иконок (32x32 / 32x64 / 16x16).
## Рисуются попиксельно при старте — никаких внешних ассетов, ограниченные палитры как на PS1.

static var _tex: Dictionary = {}
static var _img: Dictionary = {}
static var _rng := RandomNumberGenerator.new()


static func get_tex(tex_name: String) -> ImageTexture:
	if _tex.is_empty():
		build()
	if not _tex.has(tex_name):
		push_error("OfficeTex: нет текстуры " + tex_name)
		return _tex["p_solid"]
	return _tex[tex_name]


static func get_image(tex_name: String) -> Image:
	if _tex.is_empty():
		build()
	return _img[tex_name]


# ---------------------------------------------------------------- рисование
static func _new(n: String, w: int, h: int) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	_img[n] = im
	return im

static func _c(c: Array, a: int = 255) -> Color:
	return Color8(clampi(int(c[0]), 0, 255), clampi(int(c[1]), 0, 255), clampi(int(c[2]), 0, 255), a)

static func P(im: Image, x: int, y: int, c: Array, a: int = 255) -> void:
	if x < 0 or y < 0 or x >= im.get_width() or y >= im.get_height():
		return
	im.set_pixel(x, y, _c(c, a))

static func R(im: Image, x: int, y: int, w: int, h: int, c: Array, a: int = 255) -> void:
	for j in range(y, y + h):
		for i in range(x, x + w):
			P(im, i, j, c, a)

static func N(im: Image, c: Array, n: float, x: int = 0, y: int = 0, w: int = -1, h: int = -1) -> void:
	if w < 0: w = im.get_width()
	if h < 0: h = im.get_height()
	for j in range(y, y + h):
		for i in range(x, x + w):
			var k := _rng.randf_range(-n, n)
			P(im, i, j, [c[0] + k, c[1] + k, c[2] + k])

static func M(im: Image, x: int, y: int, k: float) -> void:
	if x < 0 or y < 0 or x >= im.get_width() or y >= im.get_height():
		return
	var p := im.get_pixel(x, y)
	im.set_pixel(x, y, Color(p.r * k, p.g * k, p.b * k, p.a))

static func circ(im: Image, ox: float, oy: float, r: float, c: Array, a: int = 255) -> void:
	for j in range(floori(oy - r), ceili(oy + r) + 1):
		for i in range(floori(ox - r), ceili(ox + r) + 1):
			var dx := i + 0.5 - ox
			var dy := j + 0.5 - oy
			if dx * dx + dy * dy <= r * r:
				P(im, i, j, c, a)

static func line(im: Image, x0: int, y0: int, x1: int, y1: int, c: Array) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	for _g in 400:
		P(im, x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

static func speck(im: Image, n: int, k: float, x: int = 0, y: int = 0, w: int = -1, h: int = -1) -> void:
	if w < 0: w = im.get_width()
	if h < 0: h = im.get_height()
	for _i in n:
		M(im, x + _rng.randi_range(0, w - 1), y + _rng.randi_range(0, h - 1), k)

static func blood(im: Image, n: int, x: int, y: int, w: int, h: int) -> void:
	for _i in n:
		var px := x + _rng.randi_range(0, w - 1)
		var py := y + _rng.randi_range(0, h - 1)
		var c: Array = [120, 12, 12] if _rng.randf() < 0.5 else [86, 6, 8]
		P(im, px, py, c)
		if _rng.randf() < 0.6: P(im, px + 1, py, c)
		if _rng.randf() < 0.5: P(im, px, py + 1, c)

static func text_lines(im: Image, x: int, y: int, w: int, h: int, c: Array, gap: int, min_l: int, rng: RandomNumberGenerator) -> void:
	var j := y
	while j < y + h:
		var ln := rng.randi_range(min_l, w)
		for i in ln:
			if rng.randf() < 0.85:
				P(im, x + i, j, c)
		j += gap

static func pick(arr: Array):
	return arr[_rng.randi_range(0, arr.size() - 1)]


# ---------------------------------------------------------------- генерация
static func build() -> void:
	_rng.seed = 20251
	_walls()
	_floors()
	_furniture()
	_effects()
	_characters()
	_icons()
	_lair()
	_fort()
	_battle()
	_roof()
	_escape()
	for k in _img.keys():
		_tex[k] = ImageTexture.create_from_image(_img[k])


static func _wall(n: String, base: Array, nz: float, stripes: int = 0, bb: Array = [62, 54, 46]) -> Image:
	var t := _new(n, 32, 64)
	N(t, base, nz)
	if stripes > 0:
		for x in range(0, 32, stripes):
			for y in 57:
				M(t, x, y, 0.92)
	speck(t, 30, 0.85, 0, 44, 32, 13)
	R(t, 0, 57, 32, 7, bb)
	R(t, 0, 57, 32, 1, [bb[0] * 1.5, bb[1] * 1.5, bb[2] * 1.5])
	speck(t, 10, 0.8, 0, 58, 32, 6)
	return t


static func _walls() -> void:
	_wall("wall_beige", [182, 170, 138], 5, 8)
	_wall("wall_gray", [146, 152, 162], 5)
	_wall("wall_green", [132, 150, 124], 5, 16)
	var t := _new("wall_wood", 32, 64)
	for p in 4:
		var b := [104 + _rng.randi_range(-8, 8), 66 + _rng.randi_range(-6, 6), 40]
		N(t, b, 6, p * 8, 0, 8, 64)
		for _k in 4:
			var gx := p * 8 + _rng.randi_range(1, 6)
			for y in 64:
				if _rng.randf() < 0.7: M(t, gx, y, 0.85)
		for y in 64: M(t, p * 8, y, 0.7)
	R(t, 0, 57, 32, 7, [48, 30, 20])
	t = _new("wall_tile", 32, 64)
	for y in 64:
		for x in 32:
			var g := x % 8 == 0 or y % 8 == 0
			var k := _rng.randi_range(-6, 6)
			var c: Array = [150, 152, 150] if g else [214 + k, 218 + k, 216 + k]
			if not g and y >= 32 and y < 40: c = [90, 130, 170]
			P(t, x, y, c)
	t = _new("wall_metal", 32, 64)
	N(t, [92, 98, 108], 5)
	for y in 64:
		M(t, 0, y, 0.6); M(t, 16, y, 0.6)
		P(t, 1, y, [130, 136, 146]); P(t, 17, y, [130, 136, 146])
	R(t, 0, 58, 32, 6, [40, 42, 48])
	t = _new("wall_concrete", 32, 64)
	N(t, [118, 118, 114], 9)
	for _k in 3:
		var x := _rng.randi_range(2, 29)
		var y := _rng.randi_range(2, 40)
		for _s in 14:
			M(t, x, y, 0.6); x += _rng.randi_range(-1, 1); y += 1
	speck(t, 60, 0.8, 0, 40, 32, 24)
	t = _new("wall_window", 32, 64)
	N(t, [182, 170, 138], 5)
	R(t, 2, 6, 28, 38, [64, 66, 72])
	for y in range(8, 42):
		for x in range(4, 28):
			var k := (y - 8) / 34.0
			P(t, x, y, [8 + k * 10, 12 + k * 14, 28 + k * 24])
	for _i in 26:
		var c: Array = [230, 200, 110] if _rng.randf() < 0.7 else [150, 200, 230]
		P(t, _rng.randi_range(4, 26), _rng.randi_range(20, 40), c)
	R(t, 15, 8, 2, 34, [64, 66, 72]); R(t, 4, 24, 24, 1, [64, 66, 72])
	line(t, 6, 38, 13, 10, [40, 52, 70])
	R(t, 1, 43, 30, 3, [200, 200, 196]); R(t, 0, 57, 32, 7, [62, 54, 46])
	t = _new("wall_top", 16, 16)
	N(t, [30, 30, 34], 3)
	t = _new("elev_door", 32, 64)
	for x in 32:
		var k := _rng.randi_range(-8, 8)
		for y in 64:
			P(t, x, y, [150 + k, 156 + k, 164 + k])
	R(t, 0, 0, 1, 64, [80, 84, 90]); R(t, 31, 0, 1, 64, [190, 194, 200])
	t = _new("elev_frame", 16, 16)
	N(t, [72, 76, 84], 4)
	t = _new("elev_inside", 32, 32)
	N(t, [196, 186, 150], 5)
	for x in range(0, 32, 8):
		for y in 32: M(t, x, y, 0.8)
	t = _new("elev_panel", 16, 32)
	N(t, [160, 164, 172], 3)
	R(t, 2, 2, 12, 6, [10, 10, 10]); R(t, 4, 3, 3, 4, [220, 40, 20]); R(t, 9, 3, 3, 4, [220, 40, 20])
	for r in 4:
		for c in 3:
			R(t, 3 + c * 4, 12 + r * 4, 2, 2, [220, 222, 228])
	for i in 2:
		t = _new("elev_display" + str(i), 32, 16)
		N(t, [16, 8, 8], 2)
		var col: Array = [255, 60, 40] if i == 1 else [110, 26, 20]
		# стрелка «вверх»
		for k in 5:
			R(t, 16 - k, 3 + k, 1 + k * 2, 1, col)
		R(t, 14, 8, 5, 5, col)


static func _carpet(n: String, base: Array) -> Image:
	var t := _new(n, 32, 32)
	N(t, base, 7)
	speck(t, 60, 0.75)
	speck(t, 30, 1.25)
	for i in 32:
		M(t, i, 0, 0.88); M(t, 0, i, 0.88)
	return t


static func _floors() -> void:
	_carpet("carpet_blue", [62, 70, 90])
	_carpet("carpet_brown", [92, 68, 54])
	_carpet("carpet_green", [60, 78, 66])
	_carpet("carpet_gray", [86, 86, 90])
	var t := _carpet("carpet_red", [118, 28, 32])
	for i in 32:
		P(t, i, 2, [180, 150, 60]); P(t, i, 29, [180, 150, 60])
	t = _new("lino", 32, 32)
	for y in 32:
		for x in 32:
			var on := ((x >> 4) + (y >> 4)) & 1
			var k := _rng.randi_range(-5, 5)
			P(t, x, y, [198 + k, 194 + k, 178 + k] if on else [128 + k, 134 + k, 140 + k])
	t = _new("floor_tiles", 32, 32)
	for y in 32:
		for x in 32:
			var k := _rng.randi_range(-5, 5)
			P(t, x, y, [150, 152, 150] if (x % 8 == 0 or y % 8 == 0) else [212 + k, 214 + k, 216 + k])
	t = _new("concrete", 32, 32)
	N(t, [112, 110, 106], 10)
	speck(t, 50, 0.8)
	t = _new("server_floor", 32, 32)
	N(t, [146, 150, 158], 4)
	for i in 32:
		P(t, i, 0, [70, 72, 78]); P(t, 0, i, [70, 72, 78]); P(t, i, 16, [70, 72, 78]); P(t, 16, i, [70, 72, 78])
	t = _new("floor_door", 32, 32)
	N(t, [96, 92, 88], 5)
	for i in range(0, 32, 4):
		for j in 32: M(t, i, j, 0.85)


static func _furniture() -> void:
	var t := _new("desk_top", 32, 32)
	N(t, [176, 134, 88], 5)
	for _k in 9:
		var y := _rng.randi_range(0, 31)
		for x in 32:
			if _rng.randf() < 0.8: M(t, x, y, 0.88)
	for i in 32:
		M(t, i, 0, 0.7); M(t, i, 31, 0.7); M(t, 0, i, 0.7); M(t, 31, i, 0.7)
	t = _new("desk_side", 16, 16)
	N(t, [128, 130, 138], 4)
	t = _new("partition", 32, 32)
	for y in 32:
		for x in 32:
			var k := 6 if (x + y) & 1 else -6
			P(t, x, y, [92 + k, 102 + k, 126 + k])
	R(t, 0, 0, 32, 3, [182, 182, 188])
	t = _new("monitor_body", 16, 16)
	N(t, [204, 198, 178], 4)
	t = _new("scr_off", 16, 16)
	N(t, [18, 22, 20], 3)
	line(t, 2, 13, 8, 2, [44, 52, 48])
	t = _new("scr_desktop", 16, 16)
	N(t, [0, 118, 120], 4)
	for i in 3: R(t, 1, 1 + i * 4, 2, 2, [240, 240, 240])
	R(t, 6, 3, 8, 7, [190, 190, 190]); R(t, 6, 3, 8, 1, [0, 0, 130]); R(t, 0, 14, 16, 2, [190, 190, 190])
	t = _new("scr_excel", 16, 16)
	N(t, [228, 230, 228], 2)
	R(t, 0, 0, 16, 2, [40, 140, 70])
	for y in range(2, 16, 3):
		for x in 16: P(t, x, y, [170, 170, 170])
	for _k in 16: P(t, _rng.randi_range(1, 14), _rng.randi_range(3, 15), [40, 40, 40])
	t = _new("scr_bsod", 16, 16)
	N(t, [12, 12, 168], 3)
	var rr := RandomNumberGenerator.new(); rr.seed = 5
	text_lines(t, 2, 4, 12, 10, [240, 240, 255], 2, 4, rr)
	for ph in 2:
		t = _new("scr_hack" + str(ph), 16, 16)
		N(t, [4, 14, 6], 2)
		for i in 16:
			P(t, i, 0, [40, 200, 80]); P(t, i, 15, [40, 200, 80]); P(t, 0, i, [40, 200, 80]); P(t, 15, i, [40, 200, 80])
		rr.seed = 77 + ph
		text_lines(t, 2, 2, 12, 10, [70, 255, 110], 2, 3, rr)
		if ph == 1: R(t, 2, 12, 2, 2, [140, 255, 160])
	t = _new("scr_ok", 16, 16)
	N(t, [10, 60, 22], 3)
	line(t, 3, 8, 6, 11, [120, 255, 140]); line(t, 6, 11, 12, 4, [120, 255, 140])
	line(t, 3, 9, 6, 12, [120, 255, 140]); line(t, 6, 12, 12, 5, [120, 255, 140])
	t = _new("keyboard", 16, 16)
	N(t, [196, 192, 176], 3)
	for y in range(1, 15, 3):
		for x in range(1, 15, 2): P(t, x, y, [150, 146, 130])
	t = _new("chair", 16, 16)
	N(t, [38, 42, 58], 5)
	t = _new("metal", 16, 16)
	N(t, [120, 124, 132], 5)
	t = _new("gun_dark", 8, 8)
	N(t, [44, 46, 52], 4); R(t, 0, 0, 8, 1, [86, 90, 98])
	t = _new("lamp", 4, 4)
	R(t, 0, 0, 4, 4, [255, 248, 200])
	t = _new("gun_grip", 8, 8)
	N(t, [30, 26, 24], 4)
	for y in range(1, 8, 2): R(t, 1, y, 6, 1, [50, 44, 40])
	t = _new("wood_dark", 32, 32)
	N(t, [82, 52, 34], 5)
	for _k in 8:
		var y2 := _rng.randi_range(0, 31)
		for x in 32:
			if _rng.randf() < 0.8: M(t, x, y2, 0.85)
	t = _new("cabinet", 32, 32)
	N(t, [138, 142, 150], 3)
	for d in 3:
		R(t, 0, d * 11, 32, 1, [80, 82, 90]); R(t, 12, d * 11 + 4, 8, 2, [190, 192, 200])
	t = _new("shelf", 32, 64)
	N(t, [74, 50, 34], 4)
	var cols := [[170, 30, 30], [30, 60, 150], [220, 190, 40], [40, 120, 60], [30, 30, 34], [200, 200, 200]]
	for s in 4:
		var y0 := 2 + s * 15
		var x := 2
		while x < 28:
			var w := _rng.randi_range(2, 4)
			var h := _rng.randi_range(9, 12)
			R(t, x, y0 + 12 - h, w, h, pick(cols)); R(t, x, y0 + 12 - h + 3, w, 2, [230, 230, 220])
			x += w
		R(t, 0, y0 + 12, 32, 2, [96, 66, 44])
	t = _new("rack", 32, 64)
	N(t, [26, 26, 30], 3)
	R(t, 0, 0, 2, 64, [70, 72, 80]); R(t, 30, 0, 2, 64, [70, 72, 80])
	for y in range(3, 62, 6):
		R(t, 3, y, 26, 1, [52, 54, 60])
		for l in _rng.randi_range(1, 4):
			P(t, 22 + l * 2, y + 2, pick([[40, 255, 90], [255, 170, 30], [60, 160, 255]]))
	t = _new("vending", 32, 64)
	N(t, [168, 28, 30], 6)
	R(t, 3, 4, 20, 38, [24, 32, 40])
	for r in 5:
		for c in 4:
			R(t, 5 + c * 4, 7 + r * 7, 3, 4, pick([[230, 60, 40], [60, 160, 230], [240, 210, 60], [80, 200, 90], [240, 240, 240]]))
	R(t, 25, 8, 4, 6, [30, 30, 30]); R(t, 6, 47, 16, 7, [12, 12, 12])
	t = _new("red_metal", 16, 16)
	N(t, [168, 28, 30], 6)
	t = _new("fridge", 32, 64)
	N(t, [218, 220, 224], 3)
	R(t, 0, 22, 32, 1, [150, 152, 156]); R(t, 26, 8, 2, 10, [160, 162, 168]); R(t, 26, 28, 2, 14, [160, 162, 168])
	R(t, 6, 30, 5, 5, [250, 230, 90])
	t = _new("white", 16, 16)
	N(t, [216, 218, 222], 3)
	# 0.15 (оружие офисников): корпус строительного гвоздомёта, оперение болта арбалета
	t = _new("tool_yellow", 16, 16)
	N(t, [230, 182, 30], 6); R(t, 0, 12, 16, 4, [30, 30, 32]); R(t, 2, 4, 5, 3, [30, 30, 32])
	t = _new("bolt_red", 8, 8)
	N(t, [190, 40, 36], 4)
	t = _new("counter_top", 32, 32)
	N(t, [176, 176, 172], 10)
	t = _new("counter_side", 32, 32)
	N(t, [212, 212, 206], 3)
	R(t, 15, 2, 2, 28, [160, 160, 156]); R(t, 11, 8, 2, 6, [90, 90, 90]); R(t, 19, 8, 2, 6, [90, 90, 90]); R(t, 0, 29, 32, 3, [40, 40, 40])
	t = _new("coffee_machine", 16, 16)
	N(t, [32, 32, 36], 3)
	R(t, 2, 1, 12, 4, [170, 170, 176]); R(t, 3, 2, 3, 2, [60, 220, 120]); R(t, 5, 8, 6, 7, [12, 12, 12])
	t = _new("whiteboard", 32, 32)
	N(t, [236, 236, 234], 2)
	for i in 32:
		P(t, i, 0, [150, 150, 150]); P(t, i, 31, [150, 150, 150]); P(t, 0, i, [150, 150, 150]); P(t, 31, i, [150, 150, 150])
	var lx := 3
	var ly := 6
	for _s in 6:
		var ny := ly + _rng.randi_range(1, 5)
		line(t, lx, ly, lx + 4, ny, [200, 30, 30]); lx += 4; ly = ny
	R(t, 4, 22, 8, 5, [40, 60, 200])
	t = _new("copier", 32, 32)
	N(t, [190, 190, 186], 3)
	R(t, 2, 2, 28, 9, [60, 62, 66]); R(t, 4, 4, 8, 4, [80, 200, 120]); R(t, 2, 16, 28, 1, [130, 130, 128])
	t = _new("box", 32, 32)
	N(t, [158, 116, 72], 7)
	R(t, 0, 13, 32, 6, [196, 176, 126])
	t = _new("sofa", 32, 32)
	N(t, [96, 54, 32], 6)
	for x in range(0, 32, 8):
		for y in 32: M(t, x, y, 0.75)
	t = _new("leaves", 32, 32)
	for _i in 26:
		circ(t, _rng.randi_range(4, 27), _rng.randi_range(2, 26), _rng.randf_range(2, 4), pick([[40, 116, 50], [60, 146, 60], [30, 92, 40], [80, 160, 70]]))
	for _s in 4: line(t, 16, 31, _rng.randi_range(6, 26), 18, [70, 90, 40])
	t = _new("pot", 16, 16)
	N(t, [156, 84, 52], 6)
	R(t, 0, 0, 16, 3, [176, 100, 64])
	t = _new("cooler", 16, 32)
	N(t, [222, 222, 226], 3)
	R(t, 0, 0, 16, 12, [86, 146, 222])
	P(t, 6, 18, [220, 40, 40]); P(t, 9, 18, [40, 80, 220])
	t = _new("stall", 32, 64)
	N(t, [196, 168, 158], 4)
	R(t, 0, 56, 32, 8, [30, 30, 32]); R(t, 24, 26, 4, 2, [200, 40, 40])
	blood(t, 6, 4, 40, 20, 14)
	t = _new("poster1", 16, 16)
	N(t, [30, 46, 96], 4)
	for i in 6: line(t, 8 - i, 3 + i, 8 + i, 3 + i, [210, 210, 220])
	R(t, 3, 12, 10, 1, [240, 240, 240])
	t = _new("poster2", 16, 16)
	N(t, [170, 36, 36], 4)
	circ(t, 8, 5, 3, [20, 20, 20]); R(t, 5, 8, 6, 5, [20, 20, 20]); R(t, 2, 14, 12, 1, [250, 250, 250])
	t = _new("clock", 16, 16)
	circ(t, 8, 8, 7.5, [30, 30, 30]); circ(t, 8, 8, 6.3, [236, 236, 230])
	line(t, 8, 8, 8, 3, [20, 20, 20]); line(t, 8, 8, 11, 9, [20, 20, 20])
	t = _new("trash", 16, 16)
	N(t, [60, 64, 70], 4)
	R(t, 0, 0, 16, 2, [90, 94, 100])


static func _effects() -> void:
	var t := _new("stain", 32, 32)
	circ(t, 16, 16, 8, [200, 200, 200])
	for _i in 14:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(6, 13)
		circ(t, 16 + cos(a) * d, 16 + sin(a) * d, _rng.randf_range(1, 3.5), [200, 200, 200])
	t = _new("papers", 32, 32)
	for _p in 3:
		var x0 := _rng.randi_range(1, 16)
		var y0 := _rng.randi_range(1, 14)
		R(t, x0, y0, 12, 15, [232, 232, 226])
		for y in range(y0 + 2, y0 + 14, 2):
			for x in range(x0 + 1, x0 + _rng.randi_range(6, 11)): P(t, x, y, [120, 120, 130])
	t = _new("shadow", 32, 32)
	for y in 32:
		for x in 32:
			var d := sqrt((x - 15.5) * (x - 15.5) + (y - 15.5) * (y - 15.5)) / 15.5
			P(t, x, y, [0, 0, 0], 0 if d >= 1.0 else int(200 * pow(1.0 - d, 0.7)))
	t = _new("ring", 32, 32)
	for y in 32:
		for x in 32:
			var d := sqrt((x - 15.5) * (x - 15.5) + (y - 15.5) * (y - 15.5))
			if d > 13.0 and d < 15.6: P(t, x, y, [255, 255, 255])
	t = _new("blast", 32, 32)
	for y in 32:
		for x in 32:
			var d := sqrt((x - 15.5) * (x - 15.5) + (y - 15.5) * (y - 15.5)) / 15.5 + _rng.randf_range(-0.12, 0.12)
			if d < 1.0:
				var c: Array = [255, 250, 210] if d < 0.3 else ([255, 190, 60] if d < 0.6 else [230, 90, 20])
				P(t, x, y, c, int(255 * (1.0 - d * d)))
	t = _new("smoke", 32, 32)
	for y in 32:
		for x in 32:
			var d := sqrt((x - 15.5) * (x - 15.5) + (y - 15.5) * (y - 15.5)) / 15.5 + _rng.randf_range(-0.15, 0.15)
			var g := 200 + _rng.randi_range(-25, 25)
			if d < 1.0: P(t, x, y, [g, g, g], int(220 * (1.0 - d)))
	t = _new("p_flash", 16, 16)
	for i in 6:
		var a := i / 6.0 * TAU
		line(t, 8, 8, 8 + int(cos(a) * 7), 8 + int(sin(a) * 7), [255, 240, 160])
	circ(t, 8, 8, 3.5, [255, 255, 230])
	t = _new("p_solid", 4, 4)
	R(t, 0, 0, 4, 4, [255, 255, 255])
	t = _new("p_dot", 16, 16)
	circ(t, 8, 8, 6, [255, 255, 255])
	t = _new("p_glass", 16, 16)
	line(t, 3, 12, 8, 2, [190, 240, 210]); line(t, 8, 2, 12, 13, [150, 220, 180]); line(t, 4, 12, 12, 13, [210, 250, 220])


# ---------------------------------------------------------------- персонажи
const SKIN_P := [226, 178, 140]
const SKIN_Z := [128, 150, 116]
const SKIN_W := [176, 182, 160]
const SKIN_F := [176, 150, 152]


static func _plaid(t: Image, buttons: bool) -> void:
	for y in 16:
		for x in 16:
			var c: Array = [166, 38, 36]
			if x % 5 == 0 or y % 5 == 0: c = [66, 18, 20]
			elif x % 5 == 2 or y % 5 == 2: c = [196, 76, 66]
			var k := _rng.randi_range(-6, 6)
			P(t, x, y, [c[0] + k, c[1] + k, c[2] + k])
	if buttons:
		R(t, 7, 0, 2, 16, [140, 30, 30])
		for b in range(3, 16, 4): P(t, 8, b, [220, 220, 210])
		R(t, 6, 0, 4, 2, [60, 60, 64])


static func _characters() -> void:
	var HP := [86, 56, 36]
	var BEARD := [96, 64, 42]
	# --- Александр Вадимович: очки, борода, клетчатая рубашка, джинсы
	var t := _new("p_face", 16, 16)
	N(t, SKIN_P, 4); N(t, HP, 6, 0, 0, 16, 4); R(t, 0, 4, 1, 7, HP); R(t, 15, 4, 1, 7, HP)
	R(t, 3, 5, 4, 1, [70, 46, 30]); R(t, 9, 5, 4, 1, [70, 46, 30])
	R(t, 2, 6, 5, 3, [20, 20, 24]); R(t, 9, 6, 5, 3, [20, 20, 24]); R(t, 7, 7, 2, 1, [20, 20, 24])
	R(t, 3, 7, 3, 1, [190, 210, 220]); R(t, 10, 7, 3, 1, [190, 210, 220])
	P(t, 4, 7, [30, 30, 40]); P(t, 11, 7, [30, 30, 40]); R(t, 7, 9, 2, 2, [200, 150, 116])
	N(t, BEARD, 6, 1, 11, 14, 5); N(t, BEARD, 6, 1, 9, 2, 2); N(t, BEARD, 6, 13, 9, 2, 2)
	R(t, 6, 12, 4, 1, [130, 60, 60])
	t = _new("p_hair", 16, 16); N(t, HP, 9)
	t = _new("p_side", 16, 16)
	N(t, SKIN_P, 4); N(t, HP, 8, 0, 0, 16, 6); N(t, HP, 8, 8, 6, 8, 5); R(t, 6, 7, 2, 3, [196, 146, 110])
	N(t, BEARD, 6, 0, 10, 8, 6); R(t, 0, 7, 2, 1, [20, 20, 24])
	_plaid(_new("p_shirt_f", 16, 16), true)
	_plaid(_new("p_shirt", 16, 16), false)
	t = _new("p_sleeve", 16, 16); _plaid(t, false); N(t, SKIN_P, 4, 0, 12, 16, 4)
	t = _new("p_legs", 16, 16); N(t, [52, 74, 128], 8); N(t, [44, 34, 28], 5, 0, 13, 16, 3); R(t, 0, 15, 16, 1, [220, 220, 220])
	t = _new("p_skin", 16, 16); N(t, SKIN_P, 4)
	# --- Зомби-менеджер
	t = _new("z_face", 16, 16)
	N(t, SKIN_Z, 8); N(t, [34, 34, 30], 6, 0, 0, 16, 3)
	R(t, 2, 6, 4, 3, [40, 44, 34]); R(t, 10, 6, 4, 3, [40, 44, 34]); P(t, 4, 7, [230, 50, 40]); P(t, 11, 7, [230, 50, 40])
	R(t, 7, 9, 2, 2, [100, 120, 90]); R(t, 5, 11, 6, 3, [50, 12, 12])
	for x in range(5, 11, 2): P(t, x, 11, [210, 210, 180])
	P(t, 6, 14, [150, 20, 20]); P(t, 6, 15, [150, 20, 20]); P(t, 9, 14, [150, 20, 20])
	t = _new("z_hair", 16, 16); N(t, [38, 38, 34], 8)
	for _i in 8: P(t, _rng.randi_range(0, 15), _rng.randi_range(0, 15), SKIN_Z)
	t = _new("z_side", 16, 16); N(t, SKIN_Z, 8); N(t, [38, 38, 34], 8, 0, 0, 16, 5); N(t, [38, 38, 34], 8, 9, 5, 7, 4)
	t = _new("z_shirt_f", 16, 16)
	N(t, [198, 198, 186], 10); R(t, 7, 1, 2, 12, [130, 20, 30]); R(t, 6, 1, 4, 2, [150, 30, 40]); blood(t, 14, 1, 4, 14, 10)
	t = _new("z_shirt", 16, 16); N(t, [196, 196, 184], 10); blood(t, 8, 0, 0, 16, 16)
	t = _new("z_sleeve", 16, 16); N(t, [196, 196, 184], 10); N(t, SKIN_Z, 8, 0, 11, 16, 5)
	t = _new("z_legs", 16, 16); N(t, [52, 54, 62], 6); N(t, [18, 18, 20], 3, 0, 13, 16, 3)
	t = _new("z_skin", 16, 16); N(t, SKIN_Z, 8)
	# --- Зомби-бухгалтерша
	var HW := [178, 146, 84]
	t = _new("w_face", 16, 16)
	N(t, SKIN_W, 6); N(t, HW, 10, 0, 0, 16, 4); R(t, 0, 4, 2, 9, HW); R(t, 14, 4, 2, 9, HW)
	R(t, 3, 6, 4, 3, [36, 30, 44]); R(t, 9, 6, 4, 3, [36, 30, 44]); R(t, 4, 7, 2, 1, [226, 224, 200]); R(t, 10, 7, 2, 1, [226, 224, 200])
	P(t, 5, 7, [200, 30, 30]); P(t, 10, 7, [200, 30, 30]); R(t, 6, 12, 4, 1, [176, 20, 40]); P(t, 9, 13, [176, 20, 40])
	t = _new("w_hair", 16, 16); N(t, HW, 10)
	for x in range(0, 16, 3):
		for y in 16:
			if _rng.randf() < 0.6: M(t, x, y, 0.82)
	t = _new("w_side", 16, 16); N(t, HW, 10); N(t, SKIN_W, 6, 0, 5, 5, 8)
	t = _new("w_shirt_f", 16, 16)
	N(t, [208, 126, 146], 8); line(t, 4, 0, 8, 4, [240, 240, 236]); line(t, 12, 0, 8, 4, [240, 240, 236]); blood(t, 12, 2, 6, 12, 10)
	t = _new("w_shirt", 16, 16); N(t, [208, 126, 146], 8); blood(t, 5, 0, 0, 16, 16)
	t = _new("w_sleeve", 16, 16); N(t, [208, 126, 146], 8); N(t, SKIN_W, 6, 0, 10, 16, 6)
	t = _new("w_skirt", 16, 16); N(t, [44, 44, 72], 6)
	t = _new("w_legs", 16, 16); N(t, [150, 150, 140], 6); N(t, [20, 18, 22], 3, 0, 13, 16, 3)
	t = _new("w_skin", 16, 16); N(t, SKIN_W, 6)
	# --- Щелкун: голова в грибковых пластинах (глаз нет), рваная серая рубашка, бледная кожа
	var SKIN_C := [150, 140, 118]
	t = _new("c_face", 16, 16)
	N(t, [120, 96, 66], 14)
	for i in 7:
		var cx := _rng.randi_range(1, 14)
		var cy := _rng.randi_range(1, 11)
		circ(t, cx, cy, _rng.randf_range(1.5, 3.0), [176, 150, 96]); P(t, cx, cy, [90, 60, 40])
	R(t, 4, 12, 8, 3, [60, 16, 16])
	for x in range(5, 11, 2): P(t, x, 12, [220, 210, 170])
	t = _new("c_hair", 16, 16); N(t, [120, 96, 66], 14)
	for i in 6: circ(t, _rng.randi_range(1, 14), _rng.randi_range(1, 14), _rng.randf_range(1.5, 3.0), [176, 150, 96])
	t = _new("c_side", 16, 16); N(t, [120, 96, 66], 14); circ(t, 6, 6, 3.0, [176, 150, 96]); N(t, SKIN_C, 6, 0, 12, 16, 4)
	t = _new("c_shirt_f", 16, 16); N(t, [110, 108, 100], 10); blood(t, 10, 0, 0, 16, 16)
	for i in 5: R(t, _rng.randi_range(0, 13), _rng.randi_range(0, 13), 3, 2, SKIN_C)
	t = _new("c_shirt", 16, 16); N(t, [110, 108, 100], 10); blood(t, 6, 0, 0, 16, 16)
	t = _new("c_sleeve", 16, 16); N(t, [110, 108, 100], 10); N(t, SKIN_C, 6, 0, 9, 16, 7)
	t = _new("c_legs", 16, 16); N(t, [46, 44, 42], 8); N(t, [20, 18, 18], 3, 0, 13, 16, 3)
	t = _new("c_skin", 16, 16); N(t, SKIN_C, 6)
	# --- Мародёр: балаклава, чёрная кожанка, спортивные штаны с лампасами (бандит из 90-х)
	t = _new("h_face", 16, 16)
	N(t, [26, 26, 30], 5); R(t, 2, 5, 12, 4, SKIN_P); R(t, 3, 6, 3, 2, [240, 240, 236]); R(t, 10, 6, 3, 2, [240, 240, 236])
	P(t, 4, 6, [40, 30, 20]); P(t, 11, 6, [40, 30, 20]); R(t, 6, 11, 4, 2, [60, 50, 50])
	t = _new("h_hair", 16, 16); N(t, [26, 26, 30], 5)
	for y in range(0, 16, 2): R(t, 0, y, 16, 1, [34, 34, 40])
	t = _new("h_side", 16, 16); N(t, [26, 26, 30], 5); R(t, 0, 5, 3, 4, SKIN_P)
	t = _new("h_shirt_f", 16, 16)
	N(t, [34, 30, 30], 6); R(t, 7, 0, 2, 16, [70, 70, 74]); R(t, 3, 0, 3, 3, [60, 54, 52]); R(t, 10, 0, 3, 3, [60, 54, 52])
	for y in range(1, 16, 3): P(t, 8, y, [180, 180, 186])
	t = _new("h_shirt", 16, 16); N(t, [34, 30, 30], 6); R(t, 0, 3, 16, 1, [48, 42, 42])
	t = _new("h_sleeve", 16, 16); N(t, [34, 30, 30], 6); N(t, [40, 40, 44], 4, 0, 12, 16, 4)
	t = _new("h_legs", 16, 16); N(t, [36, 44, 96], 6); R(t, 0, 0, 2, 13, [230, 230, 230]); R(t, 14, 0, 2, 13, [230, 230, 230]); N(t, [230, 230, 232], 4, 0, 13, 16, 3)
	t = _new("h_skin", 16, 16); N(t, SKIN_P, 4)
	# --- Офисник (живой, третья сторона): аккуратная стрижка, усталые глаза, голубая рубашка с тёмным галстуком,
	# белый бейдж на шнурке, жёлтая повязка на рукаве (знак своих), серые брюки, чёрные туфли.
	var HO := [70, 52, 38]
	var SHIRT_O := [150, 186, 222]
	t = _new("o_face", 16, 16)
	N(t, SKIN_P, 4); N(t, HO, 6, 0, 0, 16, 4); R(t, 0, 4, 1, 4, HO); R(t, 15, 4, 1, 4, HO)
	R(t, 3, 6, 3, 1, [60, 44, 32]); R(t, 10, 6, 3, 1, [60, 44, 32])
	R(t, 3, 7, 3, 2, [240, 240, 236]); R(t, 10, 7, 3, 2, [240, 240, 236]); P(t, 4, 7, [50, 70, 90]); P(t, 11, 7, [50, 70, 90])
	R(t, 3, 9, 3, 1, [196, 150, 126]); R(t, 10, 9, 3, 1, [196, 150, 126])   # мешки под глазами
	R(t, 7, 9, 2, 2, [200, 150, 116]); R(t, 6, 12, 4, 1, [150, 90, 80])
	t = _new("o_hair", 16, 16); N(t, HO, 7)
	t = _new("o_side", 16, 16); N(t, SKIN_P, 4); N(t, HO, 7, 0, 0, 16, 5); N(t, HO, 7, 9, 5, 7, 3); R(t, 6, 7, 2, 3, [196, 146, 110])
	t = _new("o_shirt_f", 16, 16)
	N(t, SHIRT_O, 6); R(t, 5, 0, 2, 2, [236, 240, 246]); R(t, 9, 0, 2, 2, [236, 240, 246])   # воротник
	R(t, 7, 1, 2, 10, [30, 40, 78]); R(t, 6, 1, 4, 2, [40, 52, 96])   # галстук
	line(t, 5, 0, 4, 9, [200, 40, 40]); line(t, 10, 0, 11, 9, [200, 40, 40])   # шнурок
	R(t, 3, 9, 4, 5, [244, 244, 240]); R(t, 3, 9, 4, 1, [200, 40, 40]); R(t, 4, 11, 2, 2, [140, 150, 170])   # бейдж с фото
	t = _new("o_shirt", 16, 16); N(t, SHIRT_O, 6); R(t, 0, 0, 16, 1, [236, 240, 246]); R(t, 5, 0, 6, 2, [200, 40, 40])
	t = _new("o_sleeve", 16, 16); N(t, SHIRT_O, 6); R(t, 0, 3, 16, 3, [236, 200, 40]); N(t, SKIN_P, 4, 0, 12, 16, 4)
	t = _new("o_legs", 16, 16); N(t, [70, 72, 80], 5); R(t, 7, 0, 2, 13, [60, 62, 70]); N(t, [18, 18, 20], 3, 0, 13, 16, 3)
	t = _new("o_skin", 16, 16); N(t, SKIN_P, 4)
	# --- Толстяк из отдела продаж
	t = _new("f_face", 16, 16)
	N(t, SKIN_F, 6)
	R(t, 3, 6, 3, 2, [60, 40, 44]); R(t, 10, 6, 3, 2, [60, 40, 44]); P(t, 4, 6, [230, 50, 40]); P(t, 11, 6, [230, 50, 40])
	R(t, 6, 8, 4, 3, [196, 140, 140]); R(t, 3, 11, 10, 2, [56, 12, 16])
	for x in range(4, 12, 2): P(t, x, 11, [220, 210, 170])
	R(t, 2, 14, 12, 1, [146, 124, 126]); P(t, 2, 3, [180, 220, 255])
	t = _new("f_hair", 16, 16); N(t, SKIN_F, 5)
	for i in 6: line(t, 1, 3 + i * 2, 14, 2 + i * 2, [60, 46, 40])
	t = _new("f_side", 16, 16); N(t, SKIN_F, 6); R(t, 6, 5, 3, 4, [150, 124, 126])
	t = _new("f_shirt_f", 16, 16)
	N(t, [146, 174, 206], 7); circ(t, 8, 9, 4, [120, 150, 186]); R(t, 3, 0, 2, 16, [150, 30, 30]); R(t, 11, 0, 2, 16, [150, 30, 30])
	for b in range(2, 16, 3): P(t, 8, b, [240, 240, 240])
	t = _new("f_shirt", 16, 16); N(t, [146, 174, 206], 7); R(t, 3, 0, 2, 16, [150, 30, 30]); R(t, 11, 0, 2, 16, [150, 30, 30])
	t = _new("f_sleeve", 16, 16); N(t, [146, 174, 206], 7); N(t, SKIN_F, 6, 0, 7, 16, 9)
	t = _new("f_legs", 16, 16); N(t, [96, 74, 52], 6); R(t, 0, 0, 16, 2, [30, 26, 22]); N(t, [16, 14, 14], 3, 0, 13, 16, 3)
	t = _new("f_skin", 16, 16); N(t, SKIN_F, 6)


static func _icons() -> void:
	var t := _new("i_pistol", 16, 16)
	R(t, 2, 4, 12, 3, [70, 72, 78]); R(t, 2, 4, 12, 1, [130, 134, 140]); R(t, 9, 7, 4, 6, [50, 50, 54])
	# 0.15: оружие офисников
	t = _new("i_revolver", 16, 16)
	R(t, 0, 4, 9, 2, [150, 154, 162]); R(t, 0, 4, 9, 1, [200, 204, 212]); R(t, 8, 3, 4, 5, [70, 72, 78])
	R(t, 10, 7, 4, 6, [110, 70, 40]); R(t, 11, 7, 2, 1, [150, 100, 60])
	t = _new("i_nailgun", 16, 16)
	R(t, 2, 3, 11, 5, [230, 182, 30]); R(t, 0, 4, 3, 3, [40, 40, 44]); R(t, 9, 8, 4, 6, [40, 40, 44]); R(t, 3, 8, 6, 2, [150, 154, 162])
	t = _new("i_crossbow", 16, 16)
	line(t, 1, 3, 7, 7, [60, 62, 68]); line(t, 1, 11, 7, 7, [60, 62, 68]); line(t, 1, 3, 1, 11, [220, 220, 210])
	R(t, 5, 6, 10, 2, [120, 74, 40]); R(t, 2, 7, 12, 1, [190, 40, 36])
	t = _new("i_shotgun", 16, 16)
	R(t, 0, 5, 11, 2, [60, 62, 66]); R(t, 0, 7, 9, 1, [90, 94, 100]); R(t, 10, 5, 5, 3, [120, 74, 40]); R(t, 12, 8, 3, 4, [120, 74, 40])
	t = _new("i_silenced", 16, 16)
	R(t, 0, 4, 6, 3, [30, 30, 34]); R(t, 6, 4, 8, 3, [70, 72, 78]); R(t, 6, 4, 8, 1, [130, 134, 140]); R(t, 10, 7, 4, 6, [50, 50, 54])
	t = _new("i_rifle", 16, 16)
	R(t, 0, 6, 9, 1, [60, 62, 66]); R(t, 5, 4, 4, 1, [40, 40, 44]); R(t, 6, 7, 6, 2, [110, 70, 40]); R(t, 11, 7, 5, 3, [110, 70, 40]); R(t, 13, 10, 3, 2, [110, 70, 40]); P(t, 8, 9, [150, 150, 156])
	t = _new("i_uzi", 16, 16)
	R(t, 2, 4, 11, 4, [54, 56, 62]); R(t, 2, 4, 11, 1, [100, 104, 112]); R(t, 0, 5, 2, 2, [54, 56, 62]); R(t, 8, 8, 3, 7, [34, 32, 30]); R(t, 12, 5, 3, 1, [80, 80, 86])
	t = _new("i_knife", 16, 16)
	line(t, 2, 13, 9, 6, [190, 194, 204]); line(t, 3, 13, 10, 6, [150, 154, 164]); R(t, 10, 3, 3, 4, [40, 34, 30]); R(t, 9, 6, 2, 2, [120, 120, 126])
	t = _new("i_axe", 16, 16)
	line(t, 3, 14, 12, 3, [130, 84, 44]); line(t, 4, 14, 13, 3, [110, 70, 40]); R(t, 9, 1, 6, 5, [210, 30, 30]); R(t, 13, 1, 2, 5, [200, 200, 206])
	t = _new("i_pipe", 16, 16)
	line(t, 2, 13, 12, 3, [150, 154, 162]); line(t, 3, 13, 13, 3, [110, 114, 122]); line(t, 2, 12, 12, 2, [190, 194, 200])
	R(t, 11, 1, 4, 4, [70, 72, 78]); R(t, 1, 12, 3, 3, [70, 72, 78])
	t = _new("i_knuckles", 16, 16)
	for k in 4: circ(t, 3.5 + k * 3, 6, 1.8, [176, 180, 190]); circ(t, 3.5 + k * 3, 6, 0.8, [0, 0, 0], 0)
	R(t, 2, 8, 12, 2, [150, 154, 164]); R(t, 4, 10, 8, 3, [130, 134, 144])
	t = _new("i_coffee", 16, 16)
	R(t, 4, 5, 8, 10, [236, 236, 230]); R(t, 3, 4, 10, 2, [60, 40, 30]); R(t, 4, 8, 8, 3, [150, 40, 40]); line(t, 6, 1, 7, 3, [200, 200, 200])
	t = _new("i_medkit", 16, 16)
	R(t, 1, 4, 14, 10, [236, 236, 236]); R(t, 6, 2, 4, 2, [150, 150, 150]); R(t, 7, 6, 2, 6, [220, 30, 30]); R(t, 5, 8, 6, 2, [220, 30, 30])
	t = _new("i_energy", 16, 16)
	R(t, 4, 2, 8, 13, [40, 170, 60]); R(t, 4, 2, 8, 1, [200, 200, 200]); line(t, 9, 4, 6, 8, [250, 230, 40]); line(t, 6, 8, 10, 8, [250, 230, 40]); line(t, 10, 8, 7, 12, [250, 230, 40])
	t = _new("i_bottle", 16, 16)
	R(t, 7, 0, 2, 4, [40, 110, 50]); R(t, 6, 4, 4, 2, [50, 130, 60]); R(t, 5, 6, 6, 9, [50, 140, 66]); R(t, 5, 9, 6, 3, [230, 220, 180])
	t = _new("i_alarm", 16, 16)
	circ(t, 8, 9, 6, [200, 30, 30]); circ(t, 8, 9, 4, [240, 240, 230]); circ(t, 3, 3, 2, [220, 190, 40]); circ(t, 13, 3, 2, [220, 190, 40])
	line(t, 8, 9, 8, 6, [20, 20, 20]); line(t, 8, 9, 10, 10, [20, 20, 20])
	t = _new("i_brick", 16, 16)
	R(t, 1, 5, 14, 7, [170, 70, 46]); R(t, 1, 8, 14, 1, [200, 180, 160]); R(t, 7, 5, 1, 3, [200, 180, 160]); R(t, 4, 9, 1, 3, [200, 180, 160]); R(t, 11, 9, 1, 3, [200, 180, 160])
	t = _new("i_extinguisher", 16, 16)
	R(t, 5, 4, 6, 11, [210, 30, 30]); R(t, 5, 4, 2, 11, [240, 80, 70]); R(t, 6, 1, 4, 3, [40, 40, 40]); line(t, 10, 2, 14, 5, [30, 30, 30]); R(t, 5, 8, 6, 2, [240, 240, 240])
	t = _new("i_shuriken", 16, 16)
	for i in 4:
		var a := i * PI / 2 + 0.4
		for r in 7:
			circ(t, 8 + cos(a) * r, 8 + sin(a) * r, maxf(0.6, (7 - r) / 3.0 * 0.7), [176, 180, 190])
	circ(t, 8, 8, 2.2, [110, 114, 122]); circ(t, 8, 8, 1.0, [0, 0, 0], 0)
	t = _new("i_grenade", 16, 16)
	circ(t, 8, 10, 5, [70, 96, 50])
	for y in range(6, 15, 3):
		for x in range(3, 14): M(t, x, y, 0.75)
	R(t, 6, 2, 4, 3, [140, 140, 140]); line(t, 10, 3, 13, 7, [160, 160, 160]); circ(t, 4, 3, 1.6, [200, 190, 60])
	t = _new("i_fist", 16, 16)
	R(t, 3, 5, 10, 8, SKIN_P)
	for x in range(3, 13, 3): R(t, x, 5, 1, 4, [180, 130, 100])
	R(t, 1, 9, 3, 4, SKIN_P); R(t, 5, 13, 7, 3, [166, 38, 36])
	t = _new("i_hack", 16, 16)
	R(t, 1, 2, 14, 10, [200, 196, 176]); R(t, 2, 3, 12, 8, [4, 30, 10]); R(t, 3, 5, 7, 1, [70, 255, 110]); R(t, 3, 7, 5, 1, [70, 255, 110]); R(t, 5, 12, 6, 2, [200, 196, 176]); R(t, 2, 14, 12, 1, [150, 146, 130])
	t = _new("i_elevator", 16, 16)
	R(t, 1, 1, 14, 14, [72, 76, 84]); R(t, 3, 3, 4, 12, [170, 176, 184]); R(t, 9, 3, 4, 12, [170, 176, 184])
	for k in 3: R(t, 8 - k, 0 + k, 1 + k * 2, 1, [255, 200, 60])


## 0.16: логово бандитов — граффити, бочка с огнём, пламя; иконки маскировки и ключ-карты.
static func _lair() -> void:
	# граффити — на прозрачном фоне (MeshKit.CUTOUT), брызги и потёки краски
	var t := _new("graffiti1", 32, 32)
	for i in 5:
		var y0 := 6 + i * 4
		var c: Array = [[230, 40, 40], [240, 200, 30], [40, 200, 230]][i % 3]
		for x in range(2, 30):
			var y := y0 + int(sin(x * 0.55 + i) * 2.5)
			R(t, x, y, 1, 3, c)
			if _rng.randf() < 0.12:
				R(t, x, y + 3, 1, _rng.randi_range(2, 6), c)   # потёк
	t = _new("graffiti2", 32, 32)
	circ(t, 16, 13, 10, [220, 220, 220])
	circ(t, 12, 12, 3, [20, 20, 20], 0); circ(t, 20, 12, 3, [20, 20, 20], 0)
	R(t, 11, 19, 10, 6, [220, 220, 220])
	for x in [12, 15, 18]: R(t, x, 21, 1, 4, [20, 20, 20], 0)
	for x in range(6, 27, 3): R(t, x, 26, 2, _rng.randi_range(2, 5), [200, 30, 30])
	t = _new("graffiti3", 32, 32)
	line(t, 3, 26, 26, 6, [60, 220, 80]); line(t, 4, 26, 27, 6, [60, 220, 80]); line(t, 5, 26, 28, 6, [60, 220, 80])
	line(t, 27, 6, 18, 7, [60, 220, 80]); line(t, 27, 6, 25, 15, [60, 220, 80])
	for i in 3:
		R(t, 4 + i * 8, 2, 5, 3, [250, 210, 40]); line(t, 4 + i * 8, 2, 6 + i * 8, 0, [250, 210, 40])
	for x in range(5, 28, 4): R(t, x, 27, 1, _rng.randi_range(2, 4), [60, 220, 80])
	t = _new("barrel", 32, 32)
	N(t, [96, 46, 30], 14)
	for y in [3, 15, 28]: R(t, 0, y, 32, 2, [60, 40, 34])
	speck(t, 60, 0.6, 0, 0, 32, 32)
	R(t, 0, 0, 32, 2, [40, 30, 26])
	t = _new("ash", 16, 16)
	N(t, [36, 32, 30], 10)
	for _i in 10: P(t, _rng.randi_range(1, 14), _rng.randi_range(1, 14), [255, _rng.randi_range(90, 170), 30])
	t = _new("flame", 16, 32)
	for y in 32:
		for x in 16:
			var k := float(y) / 31.0                       # 0 — верх, 1 — низ
			var half := 1.5 + 6.0 * pow(k, 0.7)
			var dx := absf(x - 7.5) + _rng.randf_range(-1.0, 1.0)
			if dx > half: continue
			var e := dx / half
			var c: Array = [255, 245, 170] if e < 0.35 and k > 0.4 else ([255, 170, 40] if e < 0.7 else [230, 70, 20])
			P(t, x, y, c, int(255 * clampf(1.2 - e, 0.0, 1.0) * clampf(k * 2.0, 0.2, 1.0)))
	t = _new("i_disguise", 16, 16)
	R(t, 2, 3, 12, 11, [46, 40, 36]); R(t, 1, 4, 2, 9, [40, 34, 30]); R(t, 13, 4, 2, 9, [40, 34, 30])
	R(t, 6, 2, 4, 2, [70, 64, 58]); line(t, 8, 4, 8, 13, [150, 150, 150]); R(t, 3, 7, 3, 1, [120, 30, 30])
	t = _new("i_keycard", 16, 16)
	R(t, 2, 4, 12, 9, [40, 230, 90]); R(t, 2, 6, 12, 2, [20, 60, 30]); R(t, 9, 9, 3, 3, [230, 250, 230])
	R(t, 7, 1, 2, 4, [180, 180, 180])


## 0.17: укреплённый офис — передняя панель радио; иконка пакетов на ноги.
static func _fort() -> void:
	var t := _new("radio", 32, 32)
	N(t, [52, 46, 40], 6)
	R(t, 2, 4, 16, 24, [30, 28, 26])
	for y in range(6, 26, 3):
		R(t, 3, y, 14, 1, [70, 66, 60])          # решётка динамика
	R(t, 20, 6, 10, 8, [200, 170, 90])         # шкала
	R(t, 24, 6, 1, 8, [200, 40, 30])
	circ(t, 23, 21, 3, [150, 150, 150]); circ(t, 28, 21, 2, [150, 150, 150])
	t = _new("i_bags", 16, 16)
	R(t, 1, 6, 6, 8, [235, 235, 240]); R(t, 9, 6, 6, 8, [235, 235, 240])
	R(t, 2, 4, 4, 2, [210, 210, 220]); R(t, 10, 4, 4, 2, [210, 210, 220])
	R(t, 1, 12, 6, 2, [180, 30, 30]); R(t, 9, 12, 6, 2, [30, 80, 200])   # полоски-надписи на пакетах


## 0.18: ящик с патронами (зелёный армейский, жёлтая маркировка).
static func _battle() -> void:
	var t := _new("i_ammo", 16, 16)
	R(t, 1, 4, 14, 10, [70, 92, 52]); R(t, 1, 4, 14, 2, [96, 120, 72]); R(t, 1, 12, 14, 2, [50, 66, 38])
	R(t, 4, 7, 8, 3, [230, 200, 60]); R(t, 2, 6, 1, 6, [40, 50, 30]); R(t, 13, 6, 1, 6, [40, 50, 30])


## 0.19: крыша — гудрон с гравием, парапет, вертолётная площадка (круг и H, на прозрачном), кондиционер, бак; иконка M4.
static func _roof() -> void:
	var t := _new("roof_tar", 32, 32)
	N(t, [46, 46, 50], 9)
	for _i in 70:
		P(t, _rng.randi_range(0, 31), _rng.randi_range(0, 31), [80 + _rng.randi_range(0, 30), 78, 74])
	t = _wall("parapet", [120, 118, 112], 8)
	R(t, 0, 0, 32, 3, [150, 148, 140])
	t = _new("helipad", 64, 64)
	for y in 64:
		for x in 64:
			var d := sqrt((x - 31.5) * (x - 31.5) + (y - 31.5) * (y - 31.5))
			if d > 27.0 and d < 31.0: P(t, x, y, [230, 230, 220])
			elif d > 25.0 and d <= 27.0: P(t, x, y, [230, 200, 40])
	R(t, 20, 18, 5, 28, [235, 235, 230]); R(t, 39, 18, 5, 28, [235, 235, 230]); R(t, 25, 29, 14, 5, [235, 235, 230])
	t = _new("ac_unit", 32, 32)
	N(t, [150, 154, 156], 5)
	for y in range(4, 28, 3): R(t, 3, y, 26, 1, [90, 94, 98])
	R(t, 0, 0, 32, 2, [120, 124, 126])
	t = _new("ac_fan", 16, 16)
	N(t, [60, 62, 66], 4)
	circ(t, 8, 8, 7, [30, 32, 36]); line(t, 2, 8, 14, 8, [110, 112, 116]); line(t, 8, 2, 8, 14, [110, 112, 116])
	t = _new("tank", 32, 32)
	N(t, [170, 172, 168], 6)
	for x in range(0, 32, 8): R(t, x, 0, 1, 32, [130, 132, 128])
	R(t, 0, 10, 32, 1, [130, 132, 128]); R(t, 0, 22, 32, 1, [130, 132, 128])
	t = _new("i_m4", 16, 16)
	R(t, 1, 6, 11, 3, [40, 40, 44]); R(t, 11, 7, 4, 1, [30, 30, 32]); R(t, 4, 9, 2, 4, [40, 40, 44])
	R(t, 7, 9, 2, 3, [60, 56, 50]); R(t, 0, 7, 2, 3, [60, 56, 50]); R(t, 4, 4, 5, 2, [30, 30, 34])


## 0.20: люк пожарной лестницы во внешней стене — открытый (за ним ночь и перекладины лестницы) и заколоченный.
static func _escape() -> void:
	var t := _new("hatch", 32, 64)
	R(t, 0, 0, 32, 64, [150, 40, 30])                 # красная рама
	R(t, 3, 3, 26, 58, [14, 18, 32])                  # проём — ночь
	for _i in 12: P(t, _rng.randi_range(4, 27), _rng.randi_range(4, 30), [200, 200, 160])   # огни города
	R(t, 6, 3, 2, 58, [110, 110, 116]); R(t, 24, 3, 2, 58, [110, 110, 116])                  # стойки лестницы
	for y in range(8, 60, 7): R(t, 6, y, 20, 2, [130, 130, 136])                            # перекладины
	t = _new("hatch_locked", 32, 64)
	R(t, 0, 0, 32, 64, [150, 40, 30])
	R(t, 3, 3, 26, 58, [70, 72, 78])                  # стальной лист
	for y in [12, 30, 48]: R(t, 1, y, 30, 4, [120, 84, 50])                                 # доски поперёк
	R(t, 13, 26, 6, 10, [60, 60, 64]); R(t, 15, 29, 2, 4, [200, 180, 60])                  # засов
