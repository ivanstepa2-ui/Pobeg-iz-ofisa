class_name OfficeLevel
extends RefCounted
## Процедурный этаж бесконечного офиса: сетка 1 клетка = 1 метр.
## BSP-разбиение на комнаты и коридоры, мебель, 5 компьютеров для взлома,
## лифт прибытия и лифт выхода, запечённый свет. Плюс запросы для ИИ: A*, линия видимости.

const FLOOR := 0
const WALL := 1
const LOW := 2   # стол/перегородка: не пройти, но видно поверх (если не присел)
const TALL := 3  # шкаф/стойка: не пройти и не видно
const PROP := 4  # 0.13: фикус, кулер — не пройти, но видно и простреливается насквозь (за ним не спрятаться)
const SEE_THROUGH := ["plant", "cooler"]
const WALL_H := 2.6
const DX := [0, 1, 0, -1]
const DZ := [-1, 0, 1, 0]
const MINR := 4

const STYLES := {
	"corridor": {"floor": ["carpet_gray", "lino", "carpet_blue"], "wall": ["wall_gray", "wall_beige"], "windows": true},
	"openspace": {"floor": ["carpet_blue", "carpet_green", "carpet_brown", "carpet_gray"], "wall": ["wall_beige", "wall_green", "wall_gray"], "windows": true},
	"meeting": {"floor": ["carpet_brown", "carpet_blue"], "wall": ["wall_wood", "wall_beige"], "windows": true},
	"kitchen": {"floor": ["lino"], "wall": ["wall_tile", "wall_beige"], "windows": true},
	"director": {"floor": ["carpet_red"], "wall": ["wall_wood"], "windows": true},
	"server": {"floor": ["server_floor"], "wall": ["wall_metal"], "windows": false},
	"storage": {"floor": ["concrete"], "wall": ["wall_concrete"], "windows": false},
	"toilet": {"floor": ["floor_tiles"], "wall": ["wall_tile"], "windows": false},
	"roof": {"floor": ["roof_tar"], "wall": ["parapet"], "windows": false},   # 0.19: крыша
}
const ROOM_NAMES := {
	"corridor": "Коридор", "openspace": "Опенспейс", "meeting": "Переговорная", "kitchen": "Кухня",
	"director": "Кабинет директора", "server": "Серверная", "storage": "Склад", "toilet": "Туалет", "roof": "Крыша",
}
const LIGHT_MODES := {
	"bright": {"amb": Color(0.30, 0.31, 0.29), "c": Color(1.0, 1.0, 0.92), "i": 0.72},
	"dim": {"amb": Color(0.18, 0.19, 0.18), "c": Color(0.95, 0.95, 0.85), "i": 0.5},
	"flicker": {"amb": Color(0.16, 0.17, 0.16), "c": Color(0.9, 1.0, 0.85), "i": 0.65},
	"dark": {"amb": Color(0.07, 0.075, 0.09), "c": Color(0.85, 0.9, 1.0), "i": 0.45},
	"server": {"amb": Color(0.07, 0.09, 0.15), "c": Color(0.45, 0.65, 1.0), "i": 0.5},
	"warm": {"amb": Color(0.24, 0.20, 0.16), "c": Color(1.0, 0.82, 0.58), "i": 0.62},
	"red": {"amb": Color(0.13, 0.04, 0.04), "c": Color(1.0, 0.25, 0.2), "i": 0.55},
	"night": {"amb": Color(0.15, 0.16, 0.23), "c": Color(0.85, 0.9, 1.0), "i": 0.6},   # 0.19: ночная крыша
}

var W := 0
var H := 0
var floor_num := 1
var spacious := false
var rng := RandomNumberGenerator.new()
var cells := PackedByteArray()
var room := PackedInt32Array()
var door := PackedByteArray()
var reserved := PackedByteArray()
var elev := PackedByteArray()
var rooms: Array = []
var props: Array = []
var decals: Array = []
var wall_decor: Array = []
var pc_cand: Array = []
var work_spots: Array = []
var pcs: Array = []
var lair := false          # 0.16: логово бандитов — разграбленный офис без компьютеров, костры в бочках
var fort := false          # 0.17: укреплённый офис выживальщиков — без зомби и взлома, баррикады, радио
var battle := false        # 0.18: поле битвы — развороченный офис, без зомби и взлома; офисники против бандитов
var roof := false          # 0.19: крыша (30-й этаж, финал) — открытая площадка за парапетом, вертолётная площадка
var helipad := Vector3.ZERO   # 0.19: центр вертолётной площадки
var escapes: Array = []    # 0.20: пожарные лестницы (этажи 20–29) {x, z, d, normal, plane, stand, room}
var sides := []            # 0.18: где стоят стороны [{pos: Vector3}, {pos}] — у разных концов этажа
var ammo_pos := Vector3.ZERO   # 0.18: ящик с патронами — между сторонами
var talk := {}             # 0.17: место разговора двоих {room, a, b (Vector3), ang_a, ang_b}
var radio := {}            # 0.17: радио и слушатель {pos (где сидит), ang, room}
var fires: Array = []      # 0.16: бочки с огнём {x, z, room}
var loot := {}             # 0.16: охраняемая комната с маскировкой {room, pos, guard, guard_ang}
var start_elev := {}
var exit_elev := {}
var lum := PackedFloat32Array()
var light_rgb := PackedColorArray()

# служебное для BFS/A*
var _q := PackedInt32Array()
var _seen := PackedInt32Array()
var _stamp := 0


static func generate(n: int, seed_v: int, kind: String = "normal") -> OfficeLevel:
	for a in 25:
		var L := OfficeLevel.new()
		L.lair = kind == "lair"
		L.fort = kind == "fort"
		L.battle = kind == "battle"
		L.roof = kind == "roof"
		if L._try(n, seed_v + a * 7919):
			return L
	push_error("OfficeLevel: не удалось сгенерировать этаж")
	return null


func idx(x: int, z: int) -> int:
	return z * W + x


func inb(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < W and z < H


func cell(x: int, z: int) -> int:
	if not inb(x, z):
		return WALL
	return cells[z * W + x]


## 0.20.3: стартовая зона героя — тут при появлении нет врагов (зайти потом могут): его комната (не коридор и не вся
## крыша) и всё ближе 14 шагов по пути. ds — bfs_dist от start_elev.stand (start_dist()).
func in_start_zone(i: int, ds: PackedInt32Array) -> bool:
	if ds[i] >= 0 and ds[i] < 14:
		return true
	var st: Vector3 = start_elev.stand
	var rm: int = room[floori(st.z) * W + floori(st.x)]
	return not roof and rm >= 0 and room[i] == rm and not rooms[rm].corridor


func start_dist() -> PackedInt32Array:
	var st: Vector3 = start_elev.stand
	return bfs_dist(floori(st.x), floori(st.z))


func walkable(x: int, z: int) -> bool:
	return inb(x, z) and cells[z * W + x] == FLOOR


func room_at(x: float, z: float) -> Dictionary:
	var cx := floori(x)
	var cz := floori(z)
	if not inb(cx, cz):
		return {}
	var r := room[cz * W + cx]
	return rooms[r] if r >= 0 else {}


# ================================================================ генерация
func _try(n: int, seed_v: int) -> bool:
	floor_num = n
	rng.seed = seed_v
	if roof:
		return _roof_try()
	# со 2-го этажа (где появляются люди) — этажи крупнее и с более просторными комнатами
	spacious = n >= 2
	var size := mini(46, 28 + int(n * 1.6)) if not spacious else mini(58, 34 + int(n * 1.8))
	W = size + rng.randi_range(0, 6)
	H = size - rng.randi_range(0, 4)
	var N := W * H
	cells.resize(N); cells.fill(WALL)
	room.resize(N); room.fill(-1)
	door.resize(N); door.fill(0)
	reserved.resize(N); reserved.fill(0)
	elev.resize(N); elev.fill(0)
	_q.resize(N); _seen.resize(N); _seen.fill(0)
	for z in range(1, H - 1):
		for x in range(1, W - 1):
			cells[z * W + x] = FLOOR
	var leaves: Array = []
	_split({"x0": 1, "z0": 1, "x1": W - 2, "z1": H - 2}, 0, leaves)
	if not connected():
		return false
	_make_rooms(leaves)
	if rooms.size() < 6:
		return false
	if not _place_elevators():
		return false
	if n >= 20 and n < 30 and not (lair or fort or battle):
		_place_escapes(rng.randi_range(1, 2))   # 0.20: до мебели — проход перед люком свободен
	for r in rooms:
		_furnish(r)
	if lair:
		# 0.16: компьютеров нет (выход по ключ-карте), зато костры и охраняемая комната с маскировкой
		_place_fires()
		if fires.is_empty() or not _choose_loot_room():
			return false
	elif battle:
		# 0.18: компьютеров нет (разбиты), завалы, пара очагов огня; стороны — у разных концов, ящик патронов — между
		_place_rubble()
		_place_fires(1, 2)
		if not _choose_sides():
			return false
	elif fort:
		# 0.17: компьютеры есть, но не взламываются (лифт открыт); баррикады, комната с пакетами, разговор, радио
		_fortify()
		if not _choose_loot_room() or not _choose_talk() or not _place_radio():
			return false
	elif not _choose_pcs():
		return false
	_add_decals()
	_setup_lights()
	_compute_light_grid()
	return true


func _split(n: Dictionary, depth: int, leaves: Array) -> void:
	var w: int = n.x1 - n.x0 + 1
	var h: int = n.z1 - n.z0 + 1
	var can_v := w >= MINR * 2 + 1
	var can_h := h >= MINR * 2 + 1
	var area := w * h
	var stop := not can_v and not can_h
	if not stop and depth >= 2:
		var k := 1.6 if spacious else 1.0
		if area < 60 * k: stop = rng.randf() < 0.7
		elif area < 110 * k: stop = rng.randf() < 0.35
		elif area < 160 * k: stop = rng.randf() < 0.12
	if stop:
		leaves.append({"x0": n.x0, "z0": n.z0, "x1": n.x1, "z1": n.z1, "corridor": false})
		return
	var vert: bool
	if can_v and can_h:
		vert = rng.randf() < (0.85 if w > h else (0.15 if w < h else 0.5))
	else:
		vert = can_v
	var span: int = w if vert else h
	var a0: int = n.x0 if vert else n.z0
	var a1: int = n.x1 if vert else n.z1
	if depth <= 1 and span >= MINR * 2 + 5 and rng.randf() < (0.9 if depth == 0 else 0.6):
		var cw := 2 if rng.randf() < 0.55 else 3
		var s := _pick_split(n, vert, a0 + MINR, a1 - MINR - cw - 1, cw + 1)
		if s >= 0:
			_wall_line(n, vert, s)
			_wall_line(n, vert, s + cw + 1)
			var corr := {"x0": s + 1, "x1": s + cw, "z0": n.z0, "z1": n.z1, "corridor": true} if vert \
				else {"x0": n.x0, "x1": n.x1, "z0": s + 1, "z1": s + cw, "corridor": true}
			leaves.append(corr)
			_add_doors(n, vert, s, true)
			_add_doors(n, vert, s + cw + 1, true)
			_split(_sub(n, vert, a0, s - 1), depth + 1, leaves)
			_split(_sub(n, vert, s + cw + 2, a1), depth + 1, leaves)
			return
	var s2 := _pick_split(n, vert, a0 + MINR, a1 - MINR, 0)
	if s2 < 0:
		leaves.append({"x0": n.x0, "z0": n.z0, "x1": n.x1, "z1": n.z1, "corridor": false})
		return
	_wall_line(n, vert, s2)
	_add_doors(n, vert, s2, false)
	_split(_sub(n, vert, a0, s2 - 1), depth + 1, leaves)
	_split(_sub(n, vert, s2 + 1, a1), depth + 1, leaves)


func _sub(n: Dictionary, vert: bool, a: int, b: int) -> Dictionary:
	if vert:
		return {"x0": a, "x1": b, "z0": n.z0, "z1": n.z1}
	return {"x0": n.x0, "x1": n.x1, "z0": a, "z1": b}


func _pick_split(n: Dictionary, vert: bool, lo: int, hi: int, extra: int) -> int:
	if hi < lo:
		return -1
	for _t in 12:
		var s := rng.randi_range(lo, hi)
		var ok := true
		var lines := [s, s + extra] if extra > 0 else [s]
		for q in lines:
			if vert:
				if door[(n.z0 - 1) * W + q] or door[(n.z1 + 1) * W + q]: ok = false
			else:
				if door[q * W + n.x0 - 1] or door[q * W + n.x1 + 1]: ok = false
		if ok:
			return s
	return -1


func _wall_line(n: Dictionary, vert: bool, s: int) -> void:
	if vert:
		for z in range(n.z0, n.z1 + 1): cells[z * W + s] = WALL
	else:
		for x in range(n.x0, n.x1 + 1): cells[s * W + x] = WALL


func _add_doors(n: Dictionary, vert: bool, s: int, many: bool) -> void:
	var a: int = n.z0 if vert else n.x0
	var b: int = n.z1 if vert else n.x1
	var ln := b - a + 1
	var count := maxi(1, roundi(ln / float(rng.randi_range(6, 9)))) if many else (2 if ln > 10 and rng.randf() < 0.5 else 1)
	var used: Array = []
	for _i in count * 4:
		if used.size() >= count: break
		var p := rng.randi_range(a + 1, b - 1)
		var close := false
		for u in used:
			if absi(u - p) < 3: close = true
		if not close: used.append(p)
	if used.is_empty(): used.append((a + b) / 2)
	for p in used:
		_set_door(s if vert else p, p if vert else s)
		if not many and rng.randf() < 0.25 and p + 1 <= b - 1 and not used.has(p + 1):
			_set_door(s if vert else p + 1, p + 1 if vert else s)


func _set_door(x: int, z: int) -> void:
	cells[z * W + x] = FLOOR
	door[z * W + x] = 1


## Все проходимые клетки связаны (4-связность)?
func connected() -> bool:
	var total := 0
	var start := -1
	for i in W * H:
		if cells[i] == FLOOR:
			total += 1
			if start < 0: start = i
	if start < 0:
		return false
	return _flood(start) == total


func _flood(start: int) -> int:
	_stamp += 1
	var h := 0
	var t := 0
	_q[t] = start; t += 1
	_seen[start] = _stamp
	while h < t:
		var c := _q[h]; h += 1
		var x := c % W
		var z := c / W
		for d in 4:
			var nx: int = x + DX[d]
			var nz: int = z + DZ[d]
			if nx < 0 or nz < 0 or nx >= W or nz >= H: continue
			var j := nz * W + nx
			if _seen[j] == _stamp or cells[j] != FLOOR: continue
			_seen[j] = _stamp
			_q[t] = j; t += 1
	return t


## BFS-расстояния (в шагах) от клетки по проходимым клеткам; -1 = недостижимо.
func bfs_dist(sx: int, sz: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(W * H); dist.fill(-1)
	if not walkable(sx, sz):
		return dist
	var q := PackedInt32Array(); q.resize(W * H)
	var h := 0
	var t := 0
	var s := sz * W + sx
	q[t] = s; t += 1; dist[s] = 0
	while h < t:
		var c := q[h]; h += 1
		var x := c % W
		var z := c / W
		for d in 4:
			var nx: int = x + DX[d]
			var nz: int = z + DZ[d]
			if not inb(nx, nz): continue
			var j := nz * W + nx
			if dist[j] >= 0 or cells[j] != FLOOR: continue
			dist[j] = dist[c] + 1
			q[t] = j; t += 1
	return dist


func _make_rooms(leaves: Array) -> void:
	for i in leaves.size():
		var lf: Dictionary = leaves[i]
		var r := {"id": i, "x0": lf.x0, "z0": lf.z0, "x1": lf.x1, "z1": lf.z1, "corridor": lf.corridor}
		r.w = r.x1 - r.x0 + 1
		r.h = r.z1 - r.z0 + 1
		r.area = r.w * r.h
		for z in range(r.z0, r.z1 + 1):
			for x in range(r.x0, r.x1 + 1):
				room[z * W + x] = i
		var t := "corridor"
		if not r.corridor:
			var w: Dictionary
			if r.area >= 80: w = {"openspace": 70, "meeting": 10, "storage": 8, "server": 6, "kitchen": 6}
			elif r.area >= 40: w = {"openspace": 34, "meeting": 16, "kitchen": 14, "director": 12, "server": 12, "storage": 12}
			else: w = {"toilet": 22, "storage": 22, "server": 18, "director": 16, "kitchen": 12, "openspace": 10}
			if mini(r.w, r.h) < 5: w.erase("meeting")
			t = _weighted(w)
		r.type = t
		var st: Dictionary = STYLES[t]
		r.floor_tex = st.floor[rng.randi_range(0, st.floor.size() - 1)]
		r.wall_tex = st.wall[rng.randi_range(0, st.wall.size() - 1)]
		r.windows = st.windows
		rooms.append(r)
	# двери принадлежат одной из соседних комнат
	for z in H:
		for x in W:
			var i := z * W + x
			if door[i]:
				for d in 4:
					var nx: int = x + DX[d]
					var nz: int = z + DZ[d]
					if inb(nx, nz) and room[nz * W + nx] >= 0 and not door[nz * W + nx]:
						room[i] = room[nz * W + nx]
						break


func _weighted(w: Dictionary) -> String:
	var total := 0.0
	for k in w: total += w[k]
	var r := rng.randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0: return k
	return w.keys()[0]


# ---------------------------------------------------------------- лифты
func _elevator_candidates() -> Array:
	var res: Array = []
	for z in range(0, H):
		for x in range(0, W):
			if cells[z * W + x] != WALL or door[z * W + x]: continue
			for d in 4:
				var p := 1 if (d == 0 or d == 2) else 2
				var e2x: int = x + DX[p]
				var e2z: int = z + DZ[p]
				if cell(e2x, e2z) != WALL or (inb(e2x, e2z) and door[e2z * W + e2x]): continue
				if cell(x - DX[p], z - DZ[p]) != WALL or cell(e2x + DX[p], e2z + DZ[p]) != WALL: continue
				var f1x: int = x + DX[d]
				var f1z: int = z + DZ[d]
				var f2x: int = e2x + DX[d]
				var f2z: int = e2z + DZ[d]
				if not walkable(f1x, f1z) or not walkable(f2x, f2z): continue
				if door[f1z * W + f1x] or door[f2z * W + f2x]: continue
				if not walkable(f1x + DX[d], f1z + DZ[d]) or not walkable(f2x + DX[d], f2z + DZ[d]): continue
				var rid := room[f1z * W + f1x]
				if rid < 0 or rid != room[f2z * W + f2x]: continue
				if rooms[rid].type in ["toilet", "server", "storage"]: continue
				res.append({"e1": Vector2i(x, z), "e2": Vector2i(e2x, e2z), "d": d, "f1": Vector2i(f1x, f1z), "f2": Vector2i(f2x, f2z), "room": rid})
	return res


func _place_elevators() -> bool:
	var cands := _elevator_candidates()
	if cands.size() < 2:
		return false
	var pref: Array = cands.filter(func(c): return rooms[c.room].type in ["corridor", "openspace"])
	var st: Dictionary = pref[rng.randi_range(0, pref.size() - 1)] if pref.size() > 0 else cands[rng.randi_range(0, cands.size() - 1)]
	var dist := bfs_dist(st.f1.x, st.f1.y)
	var scored: Array = []
	for c in cands:
		var dd := dist[c.f1.y * W + c.f1.x]
		if dd < 0: continue
		if c.e1 == st.e1 or c.e1 == st.e2 or c.e2 == st.e1 or c.e2 == st.e2: continue
		scored.append([dd, c])
	if scored.is_empty():
		return false
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var top := maxi(1, scored.size() * 15 / 100)
	var ex: Dictionary = scored[rng.randi_range(0, top - 1)][1]
	if scored[0][0] < 14:
		return false
	start_elev = _elev_info(st, 1)
	exit_elev = _elev_info(ex, 2)
	return true


func _elev_info(c: Dictionary, kind: int) -> Dictionary:
	var d: int = c.d
	for e in [c.e1, c.e2]:
		elev[e.y * W + e.x] = kind
	for f in [c.f1, c.f2]:
		reserved[f.y * W + f.x] = 1
		reserved[(f.y + DZ[d]) * W + f.x + DX[d]] = 1
	var ecx: float = (c.e1.x + c.e2.x) / 2.0 + 0.5
	var ecz: float = (c.e1.y + c.e2.y) / 2.0 + 0.5
	var nrm := Vector3(DX[d], 0, DZ[d])
	return {
		"kind": kind, "d": d, "room": c.room, "e1": c.e1, "e2": c.e2,
		"normal": nrm,
		"plane": Vector3(ecx, 0, ecz) + nrm * 0.5,              # центр фасада на полу
		"stand": Vector3(ecx, 0, ecz) + nrm * 1.5,              # где стоять игроку
		"angle": atan2(DX[d], DZ[d]),                           # взгляд «от лифта»
	}


# ---------------------------------------------------------------- мебель
func _cell_free(x: int, z: int) -> bool:
	if x < 1 or z < 1 or x >= W - 1 or z >= H - 1:
		return false
	var i := z * W + x
	if cells[i] != FLOOR or door[i] or reserved[i]:
		return false
	for d in 4:
		if door[(z + DZ[d]) * W + x + DX[d]]:
			return false
	return true


func _try_block(list: Array, type: int) -> bool:
	for c in list:
		if not _cell_free(c.x, c.y): return false
	for c in list: cells[c.y * W + c.x] = type
	if not connected():
		for c in list: cells[c.y * W + c.x] = FLOOR
		return false
	return true


func _edge(r: Dictionary, side: int) -> Array:
	var out: Array = []
	match side:
		0:
			for x in range(r.x0, r.x1 + 1): out.append(Vector2i(x, r.z0))
		2:
			for x in range(r.x0, r.x1 + 1): out.append(Vector2i(x, r.z1))
		1:
			for z in range(r.z0, r.z1 + 1): out.append(Vector2i(r.x1, z))
		3:
			for z in range(r.z0, r.z1 + 1): out.append(Vector2i(r.x0, z))
	return out


func _against_wall(c: Vector2i, side: int) -> bool:
	return cell(c.x + DX[side], c.y + DZ[side]) == WALL and elev[(c.y + DZ[side]) * W + c.x + DX[side]] == 0


func _place_on_walls(r: Dictionary, kinds: Dictionary, count: int) -> void:
	var tries := count * 5
	while count > 0 and tries > 0:
		tries -= 1
		var side := rng.randi_range(0, 3)
		var e := _edge(r, side)
		var c: Vector2i = e[rng.randi_range(0, e.size() - 1)]
		if not _against_wall(c, side): continue
		var k := _weighted(kinds)
		var t := LOW if k in ["copier", "counter", "boxes_low"] else (PROP if k in SEE_THROUGH else TALL)
		if _try_block([c], t):
			props.append({"k": k, "x": c.x, "z": c.y, "face": (side + 2) % 4, "room": r.id})
			count -= 1


func _chair(x: float, z: float, ang: float, rid: int) -> void:
	if (lair or battle) and rng.randf() < 0.5:
		return   # 0.16: в логове половину стульев растащили на костры
	props.append({"k": "chair", "fx": x, "fz": z, "ang": ang, "room": rid})


func _desk(r: Dictionary, c: Vector2i, face: int, parts: Array, with_pc: bool) -> void:
	var screens := ["scr_excel", "scr_desktop", "scr_off", "scr_bsod", "scr_excel", "scr_desktop"]
	if lair or battle:
		with_pc = false   # 0.16: в логове столы разбиты, компьютеры вынесены
	var d := {"k": "desk", "x": c.x, "z": c.y, "face": face, "parts": parts, "pc": with_pc,
		"screen": screens[rng.randi_range(0, screens.size() - 1)], "room": r.id, "hack": -1}
	if lair or battle:
		d.broken = true
	props.append(d)
	var sx: int = c.x + DX[face]
	var sz: int = c.y + DZ[face]
	if walkable(sx, sz) and not door[sz * W + sx]:
		var to_desk := atan2(-DX[face], -DZ[face])
		_chair(sx + 0.5 + rng.randf_range(-0.12, 0.12), sz + 0.5 + rng.randf_range(-0.12, 0.12), to_desk + rng.randf_range(-0.5, 0.5), r.id)
		if with_pc:
			pc_cand.append({"prop": d, "x": c.x, "z": c.y, "face": face, "room": r.id, "sx": sx, "sz": sz})
			work_spots.append({"x": sx + 0.5, "z": sz + 0.5, "ang": to_desk, "prop": d})


func _furnish(r: Dictionary) -> void:
	match r.type:
		"openspace": _furnish_openspace(r)
		"meeting": _furnish_meeting(r)
		"kitchen": _furnish_kitchen(r)
		"director": _furnish_director(r)
		"server": _furnish_rows(r, "rack", true)
		"storage": _furnish_rows(r, "shelf", false)
		"toilet": _furnish_toilet(r)
		"corridor":
			_place_on_walls(r, {"plant": 40, "cooler": 25, "copier": 15, "cabinet": 20}, maxi(r.w, r.h) / 7)
	_wall_decor(r)


func _furnish_openspace(r: Dictionary) -> void:
	var along_x: bool = r.w >= r.h
	var U0: int = r.x0 if along_x else r.z0
	var U1: int = r.x1 if along_x else r.z1
	var V0: int = r.z0 if along_x else r.x0
	var V1: int = r.z1 if along_x else r.x1
	var face_neg := 0 if along_x else 3
	var face_pos := 2 if along_x else 1
	var side_neg := 3 if along_x else 0
	var side_pos := 1 if along_x else 2
	var a := V0 + 1
	while a + 2 <= V1:
		var u := U0 + 1
		while u <= U1 - 1:
			var run_end := mini(U1 - 1, u + rng.randi_range(1, 3))
			var placed: Array = []
			for uu in range(u, run_end + 1):
				var p1 := Vector2i(uu, a) if along_x else Vector2i(a, uu)
				var p2 := Vector2i(uu, a + 1) if along_x else Vector2i(a + 1, uu)
				if _try_block([p1, p2], LOW): placed.append(uu)
				else: break
			for k in placed.size():
				var uu: int = placed[k]
				var ends: Array = []
				if k == 0: ends.append(side_neg)
				if k == placed.size() - 1: ends.append(side_pos)
				var parts1: Array = ends.duplicate(); parts1.append(face_pos)
				_desk(r, Vector2i(uu, a) if along_x else Vector2i(a, uu), face_neg, parts1, rng.randf() < 0.85)
				_desk(r, Vector2i(uu, a + 1) if along_x else Vector2i(a + 1, uu), face_pos, ends, rng.randf() < 0.85)
			u = run_end + 1 + rng.randi_range(1, 2)
		a += 4
	_place_on_walls(r, {"plant": 40, "cabinet": 30, "cooler": 15, "copier": 15}, 2 + r.area / 60)


func _furnish_meeting(r: Dictionary) -> void:
	if r.w >= 5 and r.h >= 5:
		var x0: int = r.x0 + 2
		var x1: int = r.x1 - 2
		var z0: int = r.z0 + 2
		var z1: int = r.z1 - 2
		var list: Array = []
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1): list.append(Vector2i(x, z))
		if _try_block(list, LOW):
			props.append({"k": "table", "x0": x0, "z0": z0, "x1": x1, "z1": z1, "room": r.id})
			for x in range(x0, x1 + 1):
				if rng.randf() < 0.8: _chair(x + 0.5, z0 - 0.45, 0.0, r.id)
				if rng.randf() < 0.8: _chair(x + 0.5, z1 + 1.45, PI, r.id)
			for z in range(z0, z1 + 1):
				if rng.randf() < 0.7: _chair(x1 + 1.45, z + 0.5, -PI / 2, r.id)
			var mz := (z0 + z1) / 2
			var lp := {"k": "laptop", "x": x0, "z": mz, "face": 3, "room": r.id, "hack": -1}
			props.append(lp)
			pc_cand.append({"prop": lp, "x": x0, "z": mz, "face": 3, "room": r.id, "sx": x0 - 1, "sz": mz})
	_place_on_walls(r, {"plant": 60, "cabinet": 40}, 2)


func _furnish_kitchen(r: Dictionary) -> void:
	var side := rng.randi_range(0, 3)
	var e := _edge(r, side)
	var face := (side + 2) % 4
	var n := mini(e.size() - 1, rng.randi_range(3, 6))
	var start := rng.randi_range(0, maxi(0, e.size() - n))
	var placed := 0
	for k in range(start, start + n):
		var c: Vector2i = e[k]
		if not _against_wall(c, side): continue
		var variant := "sink" if placed == 1 else ("coffee" if placed == 2 else ("micro" if rng.randf() < 0.3 else "plain"))
		if _try_block([c], LOW):
			props.append({"k": "counter", "x": c.x, "z": c.y, "face": face, "variant": variant, "room": r.id})
			placed += 1
	if start + n < e.size() and _against_wall(e[start + n], side) and _try_block([e[start + n]], TALL):
		props.append({"k": "fridge", "x": e[start + n].x, "z": e[start + n].y, "face": face, "room": r.id})
	_place_on_walls(r, {"vending": 50, "cooler": 30, "plant": 20}, 2)
	var cx: int = (r.x0 + r.x1) / 2
	var cz: int = (r.z0 + r.z1) / 2
	if r.w >= 5 and r.h >= 5 and _try_block([Vector2i(cx, cz)], LOW):
		props.append({"k": "smalltable", "x": cx, "z": cz, "room": r.id})
		_chair(cx - 0.45, cz + 0.5, PI / 2, r.id)
		_chair(cx + 1.45, cz + 0.5, -PI / 2, r.id)


func _furnish_director(r: Dictionary) -> void:
	var side := rng.randi_range(0, 3)
	var e := _edge(r, side)
	var inward := (side + 2) % 4
	if e.size() >= 4:
		var mid := e.size() / 2 - 1
		var d1 := Vector2i(e[mid].x + DX[inward], e[mid].y + DZ[inward])
		var d2 := Vector2i(e[mid + 1].x + DX[inward], e[mid + 1].y + DZ[inward])
		if _against_wall(e[mid], side) and _try_block([d1, d2], LOW):
			props.append({"k": "bigdesk", "a": d1, "b": d2, "room": r.id})
			var mon := {"k": "monitor", "x": d1.x, "z": d1.y, "face": side, "room": r.id, "hack": -1, "screen": "scr_desktop"}
			props.append(mon)
			pc_cand.append({"prop": mon, "x": d1.x, "z": d1.y, "face": side, "room": r.id, "sx": e[mid].x, "sz": e[mid].y})
			_chair(e[mid].x + 0.5, e[mid].y + 0.5, atan2(DX[inward], DZ[inward]), r.id)
	_place_on_walls(r, {"cabinet": 50, "shelf": 30, "plant": 20}, 3)
	var opp := _edge(r, inward)
	if opp.size() >= 4:
		var m2 := opp.size() / 2 - 1
		if _against_wall(opp[m2], inward) and _against_wall(opp[m2 + 1], inward) and _try_block([opp[m2], opp[m2 + 1]], LOW):
			props.append({"k": "sofa", "a": opp[m2], "b": opp[m2 + 1], "face": side, "room": r.id})


func _furnish_rows(r: Dictionary, kind: String, console: bool) -> void:
	var along_x: bool = r.w >= r.h
	var U0: int = r.x0 if along_x else r.z0
	var U1: int = r.x1 if along_x else r.z1
	var V0: int = r.z0 if along_x else r.x0
	var V1: int = r.z1 if along_x else r.x1
	var v := V0 + 1
	while v <= V1 - 1:
		for u in range(U0 + 1, U1):
			if rng.randf() < 0.14: continue
			var c := Vector2i(u, v) if along_x else Vector2i(v, u)
			if _try_block([c], TALL):
				props.append({"k": kind, "x": c.x, "z": c.y, "face": 2 if along_x else 1, "room": r.id})
		v += 2
	if console:
		_wall_desk(r)
	else:
		_place_on_walls(r, {"boxes": 70, "boxes_low": 30}, 3)
		if rng.randf() < 0.4: _wall_desk(r)


func _wall_desk(r: Dictionary) -> void:
	for _t in 30:
		var side := rng.randi_range(0, 3)
		var e := _edge(r, side)
		var c: Vector2i = e[rng.randi_range(0, e.size() - 1)]
		if not _against_wall(c, side): continue
		var face := (side + 2) % 4
		var s := Vector2i(c.x + DX[face], c.y + DZ[face])
		if not _cell_free(s.x, s.y): continue
		if _try_block([c], LOW):
			_desk(r, c, face, [side], true)
			return


func _furnish_toilet(r: Dictionary) -> void:
	var side := 0 if r.w >= r.h else 3
	if rng.randf() < 0.5: side = (side + 2) % 4
	for c in _edge(r, side):
		if _against_wall(c, side) and rng.randf() < 0.8 and _try_block([c], TALL):
			props.append({"k": "stall", "x": c.x, "z": c.y, "face": (side + 2) % 4, "room": r.id})
	var opp := (side + 2) % 4
	var cnt := 0
	for c in _edge(r, opp):
		if cnt < 3 and _against_wall(c, opp) and rng.randf() < 0.6 and _try_block([c], LOW):
			props.append({"k": "counter", "x": c.x, "z": c.y, "face": side, "variant": "sink", "room": r.id})
			cnt += 1


func _wall_decor(r: Dictionary) -> void:
	var kinds := {
		"corridor": ["poster1", "poster2", "clock", "i_extinguisher"], "openspace": ["poster1", "poster2", "whiteboard", "clock"],
		"meeting": ["whiteboard", "whiteboard", "clock"], "kitchen": ["clock", "poster2"], "director": ["poster1", "clock"],
		"server": ["i_extinguisher"], "storage": ["i_extinguisher"], "toilet": [],
	}
	var list: Array = kinds[r.type]
	if lair:
		list = ["graffiti1", "graffiti2", "graffiti3", "graffiti1", "poster2"]   # 0.16: стены в граффити
	if list.is_empty(): return
	var count: int = 1 + (r.w + r.h) / 8
	for _t in count * 4:
		if count <= 0: break
		var side := rng.randi_range(0, 3)
		var e := _edge(r, side)
		var c: Vector2i = e[rng.randi_range(0, e.size() - 1)]
		if not walkable(c.x, c.y) or door[c.y * W + c.x] or not _against_wall(c, side): continue
		var tex: String = list[rng.randi_range(0, list.size() - 1)]
		var spec: Array = {"poster1": [0.5, 1.2, 1.9], "poster2": [0.5, 1.2, 1.9], "clock": [0.4, 1.95, 2.35],
			"whiteboard": [0.92, 0.9, 1.8], "i_extinguisher": [0.3, 0.35, 0.85],
			"graffiti1": [0.96, 0.45, 1.75], "graffiti2": [0.96, 0.3, 1.5], "graffiti3": [0.9, 0.6, 1.9]}[tex]
		wall_decor.append({"x": c.x, "z": c.y, "dir": side, "tex": tex, "w": spec[0], "y0": spec[1], "y1": spec[2], "room": r.id})
		count -= 1


# ---------------------------------------------------------------- компьютеры
func _choose_pcs() -> bool:
	var sf: Vector3 = start_elev.stand
	var dist := bfs_dist(floori(sf.x), floori(sf.z))
	var start_room: int = start_elev.room
	var cands: Array = []
	for c in pc_cand:
		var dd := dist[c.sz * W + c.sx]
		if c.room != start_room and dd > 6 and walkable(c.sx, c.sz):
			cands.append(c)
	if cands.size() < 5:
		return false
	var chosen: Array = []
	var used_rooms := {}
	while chosen.size() < 5:
		var best = null
		var best_s := -1e9
		for c in cands:
			if chosen.has(c): continue
			var md := 30.0
			for o in chosen:
				md = minf(md, Vector2(c.x - o.x, c.z - o.z).length())
			var s := md + (-8.0 if used_rooms.has(c.room) else 0.0) + rng.randf() * 3.0
			if chosen.is_empty(): s = dist[c.sz * W + c.sx] * 0.3 + rng.randf() * 10.0
			if s > best_s:
				best_s = s
				best = c
		chosen.append(best)
		used_rooms[best.room] = true
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		c.prop.hack = i
		c.prop.pc = true
		pcs.append({"i": i, "x": c.x, "z": c.z, "face": c.face, "sx": c.sx, "sz": c.sz, "room": c.room,
			"prop": c.prop, "laptop": c.prop.k == "laptop", "hacked": false, "progress": 0.0})
	return true


# ---------------------------------------------------------------- 0.16: логово бандитов
## Бочки с огнём: 2–4 комнаты (не коридор/туалет/серверная, не у лифтов), бочка ближе к середине, вокруг свободно.
func _place_fires(lo: int = 2, hi: int = 4) -> void:
	var want := rng.randi_range(lo, hi)
	var cands: Array = rooms.filter(func(r): return not r.corridor and not r.type in ["toilet", "server"] and r.area >= 16 \
		and r.id != start_elev.room and r.id != exit_elev.room)
	cands.shuffle()
	for r in cands:
		if fires.size() >= want:
			break
		var cx: int = (r.x0 + r.x1) / 2
		var cz: int = (r.z0 + r.z1) / 2
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for z in range(r.z0 + 1, r.z1):
			for x in range(r.x0 + 1, r.x1):
				var free := true
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if not _cell_free(x + dx, z + dz):
							free = false
				if not free:
					continue
				var d := Vector2(x - cx, z - cz).length() + rng.randf() * 1.5
				if d < bd:
					bd = d
					best = Vector2i(x, z)
		if best.x < 0 or not _try_block([best], PROP):
			continue
		props.append({"k": "barrel", "x": best.x, "z": best.y, "room": r.id})
		fires.append({"x": best.x, "z": best.y, "room": r.id})


## Охраняемая комната: небольшая (склад/кабинет/серверная/кухня/туалет), лучше с одной дверью, не у лифтов.
## Маскировка — в дальнем от двери углу; охранник стоит снаружи у двери, лицом от неё.
func _choose_loot_room() -> bool:
	var sd := start_dist()
	var best := {}
	var best_s := -1e9
	for r in rooms:
		if r.corridor or r.id == start_elev.room or r.id == exit_elev.room or r.area < 9 or r.area > 70:
			continue
		var doors: Array = []
		for z in range(r.z0 - 1, r.z1 + 2):
			for x in range(r.x0 - 1, r.x1 + 2):
				if inb(x, z) and door[z * W + x]:
					for d in 4:
						var nx: int = x + DX[d]
						var nz: int = z + DZ[d]
						if inb(nx, nz) and room[nz * W + nx] == r.id and not door[nz * W + nx] and nx >= r.x0 and nx <= r.x1 and nz >= r.z0 and nz <= r.z1:
							doors.append({"door": Vector2i(x, z), "in": Vector2i(nx, nz), "d": d})
							break
		if doors.is_empty():
			continue
		var dr: Dictionary = doors[0]
		# снаружи: клетка за дверью с другой стороны
		var out := Vector2i(dr.door.x - DX[dr.d], dr.door.y - DZ[dr.d])
		if not walkable(out.x, out.y) or in_start_zone(out.y * W + out.x, sd):
			continue
		var dist := bfs_dist(dr.in.x, dr.in.y)
		var far := Vector2i(-1, -1)
		var fd := -1
		for z in range(r.z0, r.z1 + 1):
			for x in range(r.x0, r.x1 + 1):
				var dd := dist[z * W + x]
				if walkable(x, z) and not door[z * W + x] and dd > fd and dd < 40:
					fd = dd
					far = Vector2i(x, z)
		if far.x < 0 or fd < 2:
			continue
		var s := (30.0 if doors.size() == 1 else 0.0) + (12.0 if r.type in ["storage", "director", "server"] else 0.0) \
			+ fd + rng.randf() * 6.0
		if s > best_s:
			best_s = s
			best = {"room": r.id, "pos": Vector3(far.x + 0.5, 0, far.y + 0.5), "guard": Vector3(out.x + 0.5, 0, out.y + 0.5),
				"guard_ang": atan2(-DX[dr.d], -DZ[dr.d]), "door": dr.door}
	if best.is_empty():
		return false
	loot = best
	return true


# ---------------------------------------------------------------- 0.17: укреплённый офис выживальщиков
## Баррикады: коридоры заставлены коробками и шкафами вдоль стен (проходы остаются — _try_block держит связность).
func _fortify() -> void:
	for r in rooms:
		if r.corridor:
			_place_on_walls(r, {"boxes": 35, "boxes_low": 45, "cabinet": 20}, maxi(2, maxi(r.w, r.h) / 4))


## Место разговора двоих: кухня (иначе переговорная/опенспейс/кабинет), две соседние свободные клетки ближе к середине.
func _choose_talk() -> bool:
	var order := ["kitchen", "meeting", "openspace", "director", "storage"]
	var sd := start_dist()
	var cands: Array = rooms.filter(func(r): return not r.corridor and r.id != loot.get("room", -1) and r.area >= 9)
	var prio := func(r: Dictionary) -> int: return order.find(r.type) if order.has(r.type) else 99
	cands.sort_custom(func(x, y): return prio.call(x) < prio.call(y))
	for r in cands:
		var cx: float = (r.x0 + r.x1) * 0.5
		var cz: float = (r.z0 + r.z1) * 0.5
		var best := {}
		var bd := 1e9
		for z in range(r.z0, r.z1 + 1):
			for x in range(r.x0, r.x1 + 1):
				if not walkable(x, z) or door[z * W + x] or in_start_zone(z * W + x, sd): continue
				for k in [1, 2]:
					var x2: int = x + DX[k]
					var z2: int = z + DZ[k]
					if not walkable(x2, z2) or door[z2 * W + x2] or room[z2 * W + x2] != r.id or in_start_zone(z2 * W + x2, sd): continue
					var d := Vector2(x + 0.5 - cx, z + 0.5 - cz).length() + rng.randf()
					if d < bd:
						bd = d
						best = {"a": Vector2i(x, z), "b": Vector2i(x2, z2), "k": k}
		if best.is_empty():
			continue
		var a := Vector3(best.a.x + 0.5, 0, best.a.y + 0.5)
		var b := Vector3(best.b.x + 0.5, 0, best.b.y + 0.5)
		talk = {"room": r.id, "a": a, "b": b, "ang_a": atan2(b.x - a.x, b.z - a.z), "ang_b": atan2(a.x - b.x, a.z - b.z)}
		return true
	return false


## Радио: в комнате (не охраняемой и не той, где болтают) у стены сидит слушатель, радио — перед ним на полу.
func _place_radio() -> bool:
	var cands: Array = rooms.filter(func(r): return not r.corridor and r.id != loot.get("room", -1) and r.id != talk.get("room", -1))
	cands.shuffle()
	var sd := start_dist()
	for r in cands:
		for _try in 30:
			var side := rng.randi_range(0, 3)
			var e := _edge(r, side)
			var c: Vector2i = e[rng.randi_range(0, e.size() - 1)]
			if not walkable(c.x, c.y) or door[c.y * W + c.x] or not _against_wall(c, side) or in_start_zone(c.y * W + c.x, sd):
				continue
			var inx: int = c.x - DX[side]
			var inz: int = c.y - DZ[side]
			if not walkable(inx, inz):
				continue
			var ang := atan2(-DX[side], -DZ[side])   # лицом в комнату, к радио
			var p := Vector3(c.x + 0.5, 0, c.y + 0.5)
			var rp := p + Vector3(-DX[side], 0, -DZ[side]) * 0.7
			radio = {"pos": p, "ang": ang, "room": r.id}
			props.append({"k": "radio", "fx": rp.x, "fz": rp.z, "ang": ang + PI, "room": r.id})
			return true
	return false


# ---------------------------------------------------------------- 0.18: поле битвы
## Завалы: в комнатах по 1–3 кучи бетона/мусора (низкие — за ними прячутся и через них перелезают), в коридорах редко.
func _place_rubble() -> void:
	for r in rooms:
		var n := rng.randi_range(0, 1) if r.corridor else rng.randi_range(1, 3)
		for _try in n * 8:
			if n <= 0:
				break
			var x := rng.randi_range(r.x0 + 1, maxi(r.x0 + 1, r.x1 - 1))
			var z := rng.randi_range(r.z0 + 1, maxi(r.z0 + 1, r.z1 - 1))
			var free := true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if not _cell_free(x + dx, z + dz):
						free = false
			if not free or not _try_block([Vector2i(x, z)], LOW):
				continue
			props.append({"k": "rubble", "x": x, "z": z, "room": r.id})
			n -= 1


## Стороны — у разных концов этажа, обе не ближе 14 шагов к старту героя; ящик с патронами — посередине между ними.
func _choose_sides() -> bool:
	var st: Vector3 = start_elev.stand
	var ds := bfs_dist(floori(st.x), floori(st.z))
	var a := -1
	for i in W * H:
		if ds[i] >= 0 and cells[i] == FLOOR and not door[i] and (a < 0 or ds[i] > ds[a]):
			a = i
	if a < 0:
		return false
	var da := bfs_dist(a % W, a / W)
	var b := -1
	for i in W * H:
		if ds[i] >= 14 and not in_start_zone(i, ds) and da[i] >= 0 and cells[i] == FLOOR and not door[i] and (b < 0 or da[i] > da[b]):
			b = i
	if b < 0 or da[b] < 18:
		return false
	var db := bfs_dist(b % W, b / W)
	var m := -1
	var ms := 1e9
	for i in W * H:
		if ds[i] < 8 or da[i] < 0 or db[i] < 0 or cells[i] != FLOOR or door[i]:
			continue
		var s := absf(da[i] - db[i]) + (0.0 if room[i] >= 0 and not rooms[room[i]].corridor else 3.0) + rng.randf() * 2.0
		if s < ms:
			ms = s
			m = i
	if m < 0:
		return false
	sides = [{"pos": Vector3(a % W + 0.5, 0, a / W + 0.5)}, {"pos": Vector3(b % W + 0.5, 0, b / W + 0.5)}]
	ammo_pos = Vector3(m % W + 0.5, 0, m / W + 0.5)
	return true


# ---------------------------------------------------------------- 0.19: крыша (финал)
## Крыша: одна открытая площадка за парапетом (граница — низкая стена), у одного края — будка лестницы с лифтом
## (старт), у другого — вертолётная площадка (выход — вертолёт). Кондиционеры и вентиляция — LOW (прятаться/перелезать),
## баки и будки — TALL/WALL, антенны — PROP. Ночь: тёмный синий свет, фонари.
func _roof_try() -> bool:
	W = 40 + rng.randi_range(0, 4)
	H = 30 + rng.randi_range(0, 4)
	var N := W * H
	cells.resize(N); cells.fill(WALL)
	room.resize(N); room.fill(-1)
	door.resize(N); door.fill(0)
	reserved.resize(N); reserved.fill(0)
	elev.resize(N); elev.fill(0)
	_q.resize(N); _seen.resize(N); _seen.fill(0)
	for z in range(1, H - 1):
		for x in range(1, W - 1):
			cells[z * W + x] = FLOOR
			room[z * W + x] = 0
	var r := {"id": 0, "x0": 1, "z0": 1, "x1": W - 2, "z1": H - 2, "corridor": false, "type": "roof",
		"floor_tex": "roof_tar", "wall_tex": "parapet", "windows": false}
	r.w = r.x1 - r.x0 + 1
	r.h = r.z1 - r.z0 + 1
	r.area = r.w * r.h
	rooms.append(r)
	# будка лестницы с лифтом у левого края (4×4 стены), лифт на восточной грани
	var zc := H / 2 - 1
	for z in range(zc - 1, zc + 3):
		for x in range(3, 7):
			cells[z * W + x] = WALL
			room[z * W + x] = -1
	start_elev = _elev_info({"e1": Vector2i(6, zc), "e2": Vector2i(6, zc + 1), "d": 1,
		"f1": Vector2i(7, zc), "f2": Vector2i(7, zc + 1), "room": 0}, 1)
	# вертолётная площадка у правого края (радиус 3 клетки свободен)
	var hx := W - 9
	var hz := H / 2
	helipad = Vector3(hx + 0.5, 0, hz + 0.5)
	for z in range(hz - 4, hz + 5):
		for x in range(hx - 4, hx + 5):
			if inb(x, z):
				reserved[z * W + x] = 1
	decals.append({"x": helipad.x, "z": helipad.z, "kind": "helipad", "rot": 0.0, "size": 3.4, "room": 0})
	# «выход» — дверь вертолёта: стоять у западного края площадки (лифта нет — рисовать нечего)
	exit_elev = {"kind": 2, "d": 3, "room": 0, "e1": Vector2i(-99, -99), "e2": Vector2i(-99, -99), "normal": Vector3(-1, 0, 0),
		"plane": helipad + Vector3(-1.2, 0, 0), "stand": helipad + Vector3(-2.2, 0, 0), "angle": PI * 0.5}
	# мебель крыши
	var kinds := [["tank", 2, TALL, rng.randi_range(2, 3)], ["booth", 3, WALL, rng.randi_range(1, 2)],
		["ac", 2, LOW, rng.randi_range(8, 12)], ["vent", 1, LOW, rng.randi_range(6, 10)], ["antenna", 1, PROP, rng.randi_range(3, 4)]]
	for k in kinds:
		var placed := 0
		for _try in 300:
			if placed >= k[3]:
				break
			var sz: int = k[1]
			var x := rng.randi_range(2, W - 2 - sz)
			var z := rng.randi_range(2, H - 2 - sz)
			var long_x := rng.randf() < 0.5
			var list: Array = []
			for dz in range(sz if k[0] != "ac" or not long_x else 1):
				for dx in range(sz if k[0] != "ac" or long_x else 1):
					list.append(Vector2i(x + dx, z + dz))
			var near_start := Vector2(x - start_elev.stand.x, z - start_elev.stand.z).length() < 4.0
			if near_start or not _try_block(list, k[2]):
				continue
			var x1: int = list[-1].x
			var z1: int = list[-1].y
			props.append({"k": k[0], "x": x, "z": z, "x1": x1, "z1": z1, "room": 0})
			placed += 1
	# свет: ночь + фонари сеткой и огни площадки
	r.light = "night"
	r.amb = LIGHT_MODES.night.amb
	r.flick = false
	r.seed = 7
	r.lamps = []
	for z in range(4, H - 2, 9):
		for x in range(5, W - 2, 10):
			r.lamps.append({"p": Vector3(x + 0.5, 3.2, z + 0.5), "c": Color(1.0, 0.85, 0.6), "i": 0.65, "r": 8.0})
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		r.lamps.append({"p": helipad + Vector3(cos(a) * 3.2, 0.4, sin(a) * 3.2), "c": Color(0.3, 1.0, 0.4) if k % 2 == 0 else Color(1.0, 0.3, 0.25), "i": 0.7, "r": 3.0})
	r.lamps.append({"p": start_elev.plane + start_elev.normal * 0.6 + Vector3(0, 2.2, 0), "c": Color(1.0, 0.95, 0.8), "i": 0.6, "r": 4.0})
	_compute_light_grid()
	return true


# ---------------------------------------------------------------- 0.20: пожарные лестницы
## Люк пожарной лестницы — во внешней стене (прямой участок), перед ним проход в этаж. Не ближе 14 шагов к старту
## героя и 6 — к лифту-выходу; два люка — не ближе 15 м друг к другу. Две клетки перед люком — без мебели.
func _place_escapes(count: int) -> void:
	var st: Vector3 = start_elev.stand
	var ex: Vector3 = exit_elev.stand
	var ds := bfs_dist(floori(st.x), floori(st.z))
	var de := bfs_dist(floori(ex.x), floori(ex.z))
	var cands: Array = []
	for z in H:
		for x in W:
			if not (x == 0 or z == 0 or x == W - 1 or z == H - 1) or cells[z * W + x] != WALL or elev[z * W + x] != 0:
				continue
			for d in 4:
				var fx: int = x + DX[d]
				var fz: int = z + DZ[d]
				if not walkable(fx, fz) or door[fz * W + fx] or reserved[fz * W + fx] or not walkable(fx + DX[d], fz + DZ[d]):
					continue
				# прямой участок стены: соседи вдоль стены — тоже стена
				var sx: int = DX[(d + 1) % 4]
				var sz: int = DZ[(d + 1) % 4]
				if cell(x + sx, z + sz) != WALL or cell(x - sx, z - sz) != WALL:
					continue
				var fi := fz * W + fx
				if ds[fi] < 14 or de[fi] < 6:
					continue
				cands.append({"x": x, "z": z, "d": d, "score": ds[fi] + rng.randf() * 10.0})
	cands.sort_custom(func(a, b): return a.score > b.score)
	for c in cands:
		if escapes.size() >= count:
			break
		var far := true
		for e in escapes:
			if Vector2(c.x - e.x, c.z - e.z).length() < 15.0:
				far = false
		if not far:
			continue
		var nrm := Vector3(DX[c.d], 0, DZ[c.d])
		var plane := Vector3(c.x + 0.5, 0, c.z + 0.5) + nrm * 0.5
		var fx: int = c.x + DX[c.d]
		var fz: int = c.z + DZ[c.d]
		reserved[fz * W + fx] = 1
		reserved[(fz + DZ[c.d]) * W + fx + DX[c.d]] = 1
		escapes.append({"x": c.x, "z": c.z, "d": c.d, "normal": nrm, "plane": plane, "stand": plane + nrm * 0.9,
			"room": room[fz * W + fx], "locked": false})


func _add_decals() -> void:
	var n := 8 + floor_num * 3 + W * H / 120
	if lair or battle:
		n *= 2   # 0.16: разгром — мусор и кровь везде
	for _i in n:
		var x := rng.randi_range(1, W - 2)
		var z := rng.randi_range(1, H - 2)
		if cells[z * W + x] == WALL: continue
		var rid := room[z * W + x]
		if rid < 0: continue
		var t: String = rooms[rid].type
		var kind := "blood"
		var roll := rng.randf()
		if (lair or t in ["openspace", "meeting", "director"]) and roll < 0.5: kind = "papers"
		if battle and roll > 0.6: kind = "scorch"   # 0.18: следы взрывов и пожара
		elif t == "kitchen" and roll < 0.5: kind = "coffee"
		decals.append({"x": x + rng.randf_range(0.2, 0.8), "z": z + rng.randf_range(0.2, 0.8), "kind": kind,
			"rot": rng.randf() * TAU, "size": rng.randf_range(0.35, 0.7), "room": rid})


# ---------------------------------------------------------------- свет
func _setup_lights() -> void:
	var deep := minf(1.0, (floor_num - 1) / 10.0)
	for r in rooms:
		var w: Dictionary
		match r.type:
			"server": w = {"server": 100}
			"director": w = {"warm": 70, "dim": 20, "flicker": 10}
			"storage": w = {"dim": 35, "dark": 45, "flicker": 20}
			"toilet": w = {"bright": 30, "flicker": 50, "dark": 20}
			_: w = {"bright": 55, "dim": 25, "flicker": 14, "dark": 6}
		if w.has("bright"): w.bright *= (1.0 - 0.5 * deep)
		if not w.has("server"):
			w.dark = w.get("dark", 0) + 20 * deep
			w.flicker = w.get("flicker", 0) + 10 * deep
			if floor_num >= 4: w.red = 4 + 6 * deep
		if fort and not w.has("server"):
			w = {"bright": 50, "warm": 40, "dim": 10}   # 0.17: у выживальщиков есть свет (генератор)
		if (lair or battle) and not w.has("server"):
			w = {"dark": 25, "dim": 45, "flicker": 30}   # 0.16: свет в логове почти везде разбит
			for f in fires:
				if f.room == r.id:
					w = {"dim": 100}   # светит в основном бочка
		var mode := _weighted(w)
		var m: Dictionary = LIGHT_MODES[mode]
		r.light = mode
		r.amb = m.amb
		r.flick = mode == "flicker" or (mode == "dark" and rng.randf() < 0.5)
		r.seed = 1 + (r.id * 37) % 250
		r.lamps = []
		var nx := maxi(1, roundi(r.w / 4.0))
		var nz := maxi(1, roundi(r.h / 4.0))
		for j in nz:
			for i in nx:
				if mode == "dark" and r.lamps.size() > 0: break
				r.lamps.append({"p": Vector3(r.x0 + (i + 0.5) * r.w / float(nx), 2.9, r.z0 + (j + 0.5) * r.h / float(nz)),
					"c": m.c, "i": m.i * rng.randf_range(0.85, 1.1), "r": 7.0})
	# 0.16: огонь в бочках — тёплый мерцающий свет вокруг
	for f in fires:
		var fr: Dictionary = rooms[f.room]
		fr.flick = true
		fr.lamps.append({"p": Vector3(f.x + 0.5, 1.3, f.z + 0.5), "c": Color(1.0, 0.55, 0.2), "i": 0.95, "r": 6.5})
	# свечение компьютеров для взлома и лифтов
	for pc in pcs:
		rooms[pc.room].lamps.append({"p": Vector3(pc.x + 0.5, 1.0, pc.z + 0.5), "c": Color(0.3, 1.0, 0.45), "i": 0.55, "r": 2.6})
	for e in [start_elev, exit_elev]:
		var p: Vector3 = e.plane + e.normal * 0.6
		rooms[e.room].lamps.append({"p": Vector3(p.x, 2.2, p.z), "c": Color(1.0, 0.95, 0.8), "i": 0.6, "r": 4.0})


func light_at(rid: int, p: Vector3, n: Vector3) -> Color:
	if rid < 0 or rid >= rooms.size():
		return Color(0.15, 0.15, 0.15)
	var r: Dictionary = rooms[rid]
	var amb: Color = r.amb
	var k := 0.85 + 0.15 * n.y
	var col := Color(amb.r * k, amb.g * k, amb.b * k)
	for lp in r.lamps:
		var d: Vector3 = lp.p - p
		var dl := d.length()
		if dl > lp.r: continue
		dl = maxf(dl, 0.001)
		var ndl := d.dot(n) / dl * 0.75 + 0.25
		if ndl <= 0.0: continue
		var att: float = 1.0 - dl / lp.r
		var f: float = att * att * ndl * lp.i
		col += lp.c * f
	return Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0), 1.0)


func _compute_light_grid() -> void:
	lum.resize(W * H)
	light_rgb.resize(W * H)
	for z in H:
		for x in W:
			var i := z * W + x
			if cells[i] == WALL:
				lum[i] = 0.0
				light_rgb[i] = Color(0.2, 0.2, 0.2)
				continue
			var c := light_at(room[i], Vector3(x + 0.5, 0.9, z + 0.5), Vector3.UP)
			light_rgb[i] = c
			lum[i] = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b


## Насколько игрок виден в этой точке (0.15 — темнота, 1 — яркий свет).
func visibility_at(x: float, z: float) -> float:
	var cx := floori(x)
	var cz := floori(z)
	if not inb(cx, cz): return 0.5
	return clampf((lum[cz * W + cx] - 0.12) / 0.45, 0.15, 1.0)


func light_color_at(x: float, z: float) -> Color:
	var cx := floori(x)
	var cz := floori(z)
	if not inb(cx, cz): return Color(0.4, 0.4, 0.4)
	return light_rgb[cz * W + cx]


# ================================================================ запросы ИИ
## Линия заблокирована? mode 0 — пули/взгляд на стоящего (стены, шкафы),
## 1 — взгляд на присевшего (ещё и столы дальше 1.3 м от смотрящего), 2 — ходьба (всё непроходимое).
func line_blocked(x0: float, z0: float, x1: float, z1: float, mode: int = 0) -> bool:
	var cx := floori(x0)
	var cz := floori(z0)
	var ex := floori(x1)
	var ez := floori(z1)
	var dx := x1 - x0
	var dz := z1 - z0
	var sx := 1 if dx > 0 else -1
	var sz := 1 if dz > 0 else -1
	var tdx := absf(1.0 / dx) if dx != 0.0 else 1e9
	var tdz := absf(1.0 / dz) if dz != 0.0 else 1e9
	var tmx := ((cx + 1 - x0) if sx > 0 else (x0 - cx)) * tdx if dx != 0.0 else 1e9
	var tmz := ((cz + 1 - z0) if sz > 0 else (z0 - cz)) * tdz if dz != 0.0 else 1e9
	for _g in 300:
		if cx == ex and cz == ez:
			return false
		if absf(tmx - tmz) < 1e-9:
			if _blk(cx + sx, cz, mode, x0, z0) and _blk(cx, cz + sz, mode, x0, z0):
				return true
			cx += sx; cz += sz; tmx += tdx; tmz += tdz
		elif tmx < tmz:
			cx += sx; tmx += tdx
		else:
			cz += sz; tmz += tdz
		if cx == ex and cz == ez:
			return false
		if _blk(cx, cz, mode, x0, z0):
			return true
		if minf(tmx, tmz) > 1.0001:
			return false
	return false


func _blk(x: int, z: int, mode: int, vx: float, vz: float) -> bool:
	if not inb(x, z): return true
	var c := cells[z * W + x]
	if c == WALL or c == TALL: return true
	if mode == 2: return c != FLOOR
	if mode == 1 and c == LOW:
		var ddx := x + 0.5 - vx
		var ddz := z + 0.5 - vz
		return ddx * ddx + ddz * ddz > 1.69
	return false


func nearest_walkable(x: int, z: int, max_r: int = 4) -> Vector2i:
	if walkable(x, z): return Vector2i(x, z)
	for r in range(1, max_r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r: continue
				if walkable(x + dx, z + dz): return Vector2i(x + dx, z + dz)
	return Vector2i(-1, -1)


const NX8 := [1, -1, 0, 0, 1, 1, -1, -1]
const NZ8 := [0, 0, 1, -1, 1, -1, 1, -1]
var _g := PackedFloat32Array()
var _came := PackedInt32Array()
var _open_st := PackedInt32Array()
var _closed := PackedInt32Array()
var _pf := 0
var _hk := PackedInt32Array()
var _hp := PackedFloat32Array()
var _hn := 0


## A* по сетке (8 направлений, без срезания углов). Возвращает список индексов клеток (без стартовой).
## low_cost ≥ 0 (0.14, бандиты): можно через LOW-клетки (стол, перегородка…) — только прямо, с доплатой low_cost.
func find_path(sx: int, sz: int, tx: int, tz: int, max_iter: int = 4000, low_cost: float = -1.0) -> PackedInt32Array:
	var res := PackedInt32Array()
	var N := W * H
	if _g.size() != N:
		_g.resize(N); _came.resize(N); _open_st.resize(N); _open_st.fill(0); _closed.resize(N); _closed.fill(0)
		_hk.resize(N * 8); _hp.resize(N * 8)
	var t := nearest_walkable(tx, tz, 4)
	if t.x < 0: return res
	var s := nearest_walkable(sx, sz, 2)
	if s.x < 0: return res
	var start := s.y * W + s.x
	var goal := t.y * W + t.x
	if start == goal:
		res.append(goal)
		return res
	_pf += 1
	_hn = 0
	_g[start] = 0.0
	_came[start] = -1
	_open_st[start] = _pf
	_hpush(start, _heur(s.x, s.y, t.x, t.y))
	var it := 0
	var found := false
	while _hn > 0 and it < max_iter:
		it += 1
		var c := _hpop()
		if _closed[c] == _pf: continue
		_closed[c] = _pf
		if c == goal:
			found = true
			break
		var cx := c % W
		var cz := c / W
		for k in 8:
			var ddx: int = NX8[k]
			var ddz: int = NZ8[k]
			var nx := cx + ddx
			var nz := cz + ddz
			if nx < 0 or nz < 0 or nx >= W or nz >= H: continue
			var n := nz * W + nx
			if _closed[n] == _pf: continue
			var extra := 0.0
			if cells[n] != FLOOR:
				# бандит перелезает: только LOW, только прямо (не по диагонали), и не из/в LOW по диагонали
				if low_cost < 0.0 or cells[n] != LOW or (ddx != 0 and ddz != 0): continue
				extra = low_cost
			if ddx != 0 and ddz != 0 and (cells[c] != FLOOR or cells[cz * W + nx] != FLOOR or cells[nz * W + cx] != FLOOR): continue
			var ng := _g[c] + (1.4142 if (ddx != 0 and ddz != 0) else 1.0) + extra
			if _open_st[n] != _pf or ng < _g[n]:
				_open_st[n] = _pf
				_g[n] = ng
				_came[n] = c
				_hpush(n, ng + _heur(nx, nz, t.x, t.y))
	if not found: return res
	var p := goal
	while p != start and p >= 0:
		res.append(p)
		p = _came[p]
	res.reverse()
	return res


func _heur(x: int, z: int, tx: int, tz: int) -> float:
	var dx := absi(x - tx)
	var dz := absi(z - tz)
	return dx + dz - 0.5858 * mini(dx, dz)


func _hpush(key: int, pri: float) -> void:
	if _hn >= _hk.size(): return
	var i := _hn
	_hn += 1
	while i > 0:
		var par := (i - 1) >> 1
		if _hp[par] <= pri: break
		_hk[i] = _hk[par]; _hp[i] = _hp[par]
		i = par
	_hk[i] = key; _hp[i] = pri


func _hpop() -> int:
	var top := _hk[0]
	_hn -= 1
	var n := _hn
	if n > 0:
		var lk := _hk[n]
		var lp := _hp[n]
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			var mp := lp
			if l < n and _hp[l] < mp:
				m = l; mp = _hp[l]
			if r < n and _hp[r] < mp:
				m = r; mp = _hp[r]
			if m == i: break
			_hk[i] = _hk[m]; _hp[i] = _hp[m]
			i = m
		_hk[i] = lk; _hp[i] = lp
	return top


## Случайная достижимая клетка в радиусе шагов (для блужданий зомби).
func random_reachable(x: float, z: float, min_steps: int, max_steps: int) -> Vector2i:
	var s := nearest_walkable(floori(x), floori(z), 2)
	if s.x < 0: return Vector2i(-1, -1)
	var q := PackedInt32Array()
	var d := {}
	var si := s.y * W + s.x
	q.append(si); d[si] = 0
	var h := 0
	var good: Array = []
	while h < q.size():
		var c := q[h]; h += 1
		var dc: int = d[c]
		if dc >= min_steps: good.append(c)
		if dc >= max_steps: continue
		var cx := c % W
		var cz := c / W
		for k in 4:
			var nx: int = cx + DX[k]
			var nz: int = cz + DZ[k]
			if not walkable(nx, nz): continue
			var j := nz * W + nx
			if d.has(j): continue
			d[j] = dc + 1
			q.append(j)
	if good.is_empty(): return s
	var g: int = good[rng.randi_range(0, good.size() - 1)]
	return Vector2i(g % W, g / W)
