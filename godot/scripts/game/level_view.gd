class_name LevelView
extends Node3D
## 3D-представление этажа: статическая геометрия с запечённым светом,
## плюс динамика — мониторы взламываемых ПК и двери лифта выхода.

const DX := OfficeLevel.DX
const DZ := OfficeLevel.DZ
const WH := OfficeLevel.WALL_H
const PARAPET_H := 1.1   # 0.19: парапет крыши

var L: OfficeLevel
var kit: MeshKit
var pc_nodes: Array = []        # [{node, screen: MeshInstance3D}]
var exit_doors: Array = []      # [MeshInstance3D, MeshInstance3D]
var exit_display: MeshInstance3D
var door_open := 0.0
var _lit_cache := {}


func build(level: OfficeLevel) -> void:
	L = level
	kit = MeshKit.new()
	_floors_and_walls()
	for p in L.props:
		_prop(p)
	_decals()
	_wall_decor()
	_elevator(L.start_elev, false)
	if not L.roof:
		_elevator(L.exit_elev, true)   # 0.19: на крыше выход — вертолёт (game), не лифт
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for pc in L.pcs:
		_build_pc(pc)


## Свет из комнаты rid; в альфе — «зерно» мерцания (если лампы в комнате мигают).
func _lit(rid: int, p: Vector3, n: Vector3) -> Color:
	var c := L.light_at(rid, p, n)
	if rid >= 0 and L.rooms[rid].flick:
		c.a = L.rooms[rid].seed / 255.0
	return c


func _lf(rid: int) -> Callable:
	if not _lit_cache.has(rid):
		_lit_cache[rid] = func(p: Vector3, n: Vector3) -> Color: return _lit(rid, p, n)
	return _lit_cache[rid]


func _floors_and_walls() -> void:
	var W := L.W
	for z in L.H:
		for x in W:
			var i := z * W + x
			var c := L.cells[i]
			if c != OfficeLevel.WALL:
				var rid := L.room[i]
				var tex: String = "floor_door" if L.door[i] else (L.rooms[rid].floor_tex if rid >= 0 else "concrete")
				var a := Vector3(x, 0, z + 1)
				var b := Vector3(x + 1, 0, z + 1)
				var cc := Vector3(x + 1, 0, z)
				var d := Vector3(x, 0, z)
				kit.quad(tex, a, b, cc, d, _lit(rid, a, Vector3.UP), _lit(rid, b, Vector3.UP), _lit(rid, cc, Vector3.UP), _lit(rid, d, Vector3.UP))
				if L.door[i]:
					_lintel(x, z, rid)
				continue
			# стена: грани к непустым соседям + тёмная «крышка» (её видно сверху, как в MGS)
			for dd in 4:
				var nx: int = x + DX[dd]
				var nz: int = z + DZ[dd]
				if not L.inb(nx, nz): continue
				var j := nz * W + nx
				if L.cells[j] == OfficeLevel.WALL: continue
				if L.elev[i] != 0 and _is_elev_front(i, dd): continue
				var rid2 := L.room[j]
				var room: Dictionary = L.rooms[rid2] if rid2 >= 0 else {}
				var tex2: String = room.get("wall_tex", "wall_gray")
				var border := x == 0 or z == 0 or x == W - 1 or z == L.H - 1
				if border and room.get("windows", false) and (x * 7 + z * 13) % 3 != 0:
					tex2 = "wall_window"
				if L.roof:
					# 0.19: край крыши — низкий парапет; будки — бетон в полный рост
					tex2 = "parapet" if border else "wall_concrete"
				_wall_face(x, z, dd, tex2, rid2, 0.0, PARAPET_H if L.roof and border else WH)
			var col := Color(0.55, 0.55, 0.6)
			var th := PARAPET_H if L.roof and (x == 0 or z == 0 or x == W - 1 or z == L.H - 1) else WH
			kit.quad_flat("wall_top", Vector3(x, th, z + 1), Vector3(x + 1, th, z + 1), Vector3(x + 1, th, z), Vector3(x, th, z), col)


func _is_elev_front(i: int, d: int) -> bool:
	for e in [L.start_elev, L.exit_elev]:
		var ii := [e.e1.y * L.W + e.e1.x, e.e2.y * L.W + e.e2.x]
		if i in ii and e.d == d:
			return true
	return false


func _wall_face(x: int, z: int, d: int, tex: String, rid: int, y0: float = 0.0, y1: float = WH) -> void:
	var a: Vector3
	var b: Vector3
	match d:
		2:
			a = Vector3(x, 0, z + 1); b = Vector3(x + 1, 0, z + 1)
		0:
			a = Vector3(x + 1, 0, z); b = Vector3(x, 0, z)
		1:
			a = Vector3(x + 1, 0, z + 1); b = Vector3(x + 1, 0, z)
		_:
			a = Vector3(x, 0, z); b = Vector3(x, 0, z + 1)
	var n := Vector3(DX[d], 0, DZ[d])
	var p0 := a + Vector3(0, y0, 0)
	var p1 := b + Vector3(0, y0, 0)
	var p2 := b + Vector3(0, y1, 0)
	var p3 := a + Vector3(0, y1, 0)
	kit.quad(tex, p0, p1, p2, p3, _lit(rid, p0, n), _lit(rid, p1, n), _lit(rid, p2, n), _lit(rid, p3, n),
		false, Vector2(0, 1.0 - y1 / WH), Vector2(1, 1.0 - y0 / WH))


func _lintel(x: int, z: int, rid: int) -> void:
	var room: Dictionary = L.rooms[rid] if rid >= 0 else {}
	var tex: String = room.get("wall_tex", "wall_gray")
	kit.aabb(Vector3(x, 2.15, z), Vector3(x + 1, WH, z + 1), {"f": tex, "b": tex, "r": tex, "l": tex, "d": "wall_top", "t": "wall_top"}, _lf(rid))


func _cell_xf(x: int, z: int, face: int, y: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(DX[face], DZ[face])), Vector3(x + 0.5, y, z + 0.5))


## Монитор ЭЛТ + клавиатура на столе. Если screen == "" — без экрана (экран будет динамическим).
func monitor(k: MeshKit, xf: Transform3D, screen: String, light) -> void:
	k.box(xf, Vector3(0, 0.18, -0.2), Vector3(0.21, 0.18, 0.17), {"f": "monitor_body", "b": "monitor_body", "r": "monitor_body", "l": "monitor_body", "t": "monitor_body"}, light)
	if screen != "":
		k.box(xf, Vector3(0, 0.19, -0.026), Vector3(0.16, 0.13, 0.004), {"f": screen}, light)
	k.box(xf, Vector3(0, 0.012, 0.15), Vector3(0.2, 0.012, 0.07), {"t": "keyboard", "f": "monitor_body", "l": "monitor_body", "r": "monitor_body"}, light)


func laptop(k: MeshKit, xf: Transform3D, screen: String, light) -> void:
	k.box(xf, Vector3(0, 0.012, 0.05), Vector3(0.17, 0.012, 0.12), {"t": "keyboard", "f": "metal", "l": "metal", "r": "metal", "b": "metal"}, light)
	var hinge := xf * Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0, 0.02, -0.07))
	k.box(hinge, Vector3(0, 0.12, 0), Vector3(0.17, 0.12, 0.008), {"b": "metal", "t": "metal", "l": "metal", "r": "metal"}, light)
	if screen != "":
		k.box(hinge, Vector3(0, 0.12, 0.009), Vector3(0.15, 0.1, 0.002), {"f": screen}, light)


func _prop(p: Dictionary) -> void:
	var rid: int = p.room
	var lf := _lf(rid)
	match p.k:
		"desk":
			var x: int = p.x
			var z: int = p.z
			if p.get("broken", false):
				_broken_desk(p, lf)
				return
			kit.aabb(Vector3(x + 0.03, 0.72, z + 0.03), Vector3(x + 0.97, 0.78, z + 0.97), {"t": "desk_top", "f": "desk_side", "b": "desk_side", "r": "desk_side", "l": "desk_side"}, lf)
			var f: int = p.face
			if f == 0 or f == 2:
				kit.aabb(Vector3(x + 0.06, 0, z + 0.1), Vector3(x + 0.1, 0.72, z + 0.9), MeshKit.all_faces("desk_side"), lf)
				kit.aabb(Vector3(x + 0.9, 0, z + 0.1), Vector3(x + 0.94, 0.72, z + 0.9), MeshKit.all_faces("desk_side"), lf)
			else:
				kit.aabb(Vector3(x + 0.1, 0, z + 0.06), Vector3(x + 0.9, 0.72, z + 0.1), MeshKit.all_faces("desk_side"), lf)
				kit.aabb(Vector3(x + 0.1, 0, z + 0.9), Vector3(x + 0.9, 0.72, z + 0.94), MeshKit.all_faces("desk_side"), lf)
			for d in p.parts:
				var a: Vector3
				var b: Vector3
				match d:
					0: a = Vector3(x, 0, z); b = Vector3(x + 1, 1.3, z + 0.05)
					2: a = Vector3(x, 0, z + 0.95); b = Vector3(x + 1, 1.3, z + 1)
					1: a = Vector3(x + 0.95, 0, z); b = Vector3(x + 1, 1.3, z + 1)
					_: a = Vector3(x, 0, z); b = Vector3(x + 0.05, 1.3, z + 1)
				kit.aabb(a, b, MeshKit.all_faces("partition", "desk_side"), lf)
			if p.pc and p.hack < 0:
				monitor(kit, _cell_xf(x, z, f, 0.78), p.screen, lf)
		"monitor":
			if p.hack < 0 and not L.lair:
				monitor(kit, _cell_xf(p.x, p.z, p.face, 0.8), p.screen, lf)
		"laptop":
			if p.hack < 0 and not L.lair:
				var xf := _cell_xf(p.x, p.z, p.face, 0.8)
				xf.origin += xf.basis.z * 0.22
				laptop(kit, xf, "scr_desktop", lf)
		"barrel":
			# 0.16: железная бочка с огнём (пламя — живое, game._build_fires)
			var bx := Transform3D(Basis(Vector3.UP, 0.3), Vector3(p.x + 0.5, 0, p.z + 0.5))
			kit.box(bx, Vector3(0, 0.42, 0), Vector3(0.27, 0.42, 0.27), {"f": "barrel", "b": "barrel", "l": "barrel", "r": "barrel", "t": "ash"}, lf)
			kit.box(bx, Vector3(0, 0.6, 0), Vector3(0.29, 0.03, 0.29), MeshKit.all_faces("metal"), lf)
			kit.box(bx, Vector3(0, 0.2, 0), Vector3(0.29, 0.03, 0.29), MeshKit.all_faces("metal"), lf)
		"ac":
			# 0.19: кондиционер на крыше (низкий блок с решёткой и вентилятором сверху)
			kit.aabb(Vector3(p.x + 0.06, 0, p.z + 0.06), Vector3(p.x1 + 0.94, 0.85, p.z1 + 0.94), {"f": "ac_unit", "b": "ac_unit", "l": "ac_unit", "r": "ac_unit", "t": "metal"}, lf)
			kit.box(Transform3D(Basis(), Vector3((p.x + p.x1) * 0.5 + 0.5, 0.85, (p.z + p.z1) * 0.5 + 0.5)), Vector3(0, 0.03, 0), Vector3(0.32, 0.03, 0.32), {"t": "ac_fan", "f": "metal", "b": "metal", "l": "metal", "r": "metal"}, lf)
		"vent":
			# 0.19: вентиляционный короб с «грибком»
			kit.aabb(Vector3(p.x + 0.2, 0, p.z + 0.2), Vector3(p.x + 0.8, 0.6, p.z + 0.8), MeshKit.all_faces("metal"), lf)
			kit.aabb(Vector3(p.x + 0.08, 0.6, p.z + 0.08), Vector3(p.x + 0.92, 0.78, p.z + 0.92), MeshKit.all_faces("gun_dark"), lf)
		"tank":
			# 0.19: водяной бак на опорах
			kit.aabb(Vector3(p.x + 0.15, 0.5, p.z + 0.15), Vector3(p.x1 + 0.85, 2.6, p.z1 + 0.85), {"f": "tank", "b": "tank", "l": "tank", "r": "tank", "t": "metal", "d": "metal"}, lf)
			for c in [[p.x + 0.2, p.z + 0.2], [p.x1 + 0.7, p.z + 0.2], [p.x + 0.2, p.z1 + 0.7], [p.x1 + 0.7, p.z1 + 0.7]]:
				kit.aabb(Vector3(c[0], 0, c[1]), Vector3(c[0] + 0.1, 0.5, c[1] + 0.1), MeshKit.all_faces("gun_dark"), lf)
		"antenna":
			# 0.19: антенна — мачта с перекладинами (видно и стреляется насквозь)
			kit.aabb(Vector3(p.x + 0.45, 0, p.z + 0.45), Vector3(p.x + 0.55, 3.4, p.z + 0.55), MeshKit.all_faces("metal"), lf)
			for y in [1.6, 2.4, 3.1]:
				kit.aabb(Vector3(p.x + 0.1, y, p.z + 0.47), Vector3(p.x + 0.9, y + 0.05, p.z + 0.53), MeshKit.all_faces("metal"), lf)
		"booth":
			pass   # 0.19: будка — клетки-стены (рисуются как стены)
		"rubble":
			# 0.18: куча бетона и обломков (низкая — видно поверх, можно перелезть)
			var rr := L.rng
			for k in 4:
				var s := rr.randf_range(0.14, 0.26)
				var bx := Transform3D(Basis(Vector3(rr.randf_range(-1, 1), 1, rr.randf_range(-1, 1)).normalized(), rr.randf_range(0, TAU)), Vector3(p.x + rr.randf_range(0.25, 0.75), 0, p.z + rr.randf_range(0.25, 0.75)))
				kit.box(bx, Vector3(0, s * 0.9, 0), Vector3(s * 1.3, s, s), MeshKit.all_faces("concrete"), lf)
			kit.box(Transform3D(Basis(), Vector3(p.x + 0.5, 0, p.z + 0.5)), Vector3(0, 0.1, 0), Vector3(0.45, 0.1, 0.42), MeshKit.all_faces("concrete"), lf)
		"radio":
			# 0.17: радиоприёмник на полу у выживальщика (корпус, шкала, антенна)
			var rx := Transform3D(Basis(Vector3.UP, p.ang), Vector3(p.fx, 0, p.fz))
			kit.box(rx, Vector3(0, 0.13, 0), Vector3(0.2, 0.13, 0.08), {"f": "radio", "b": "gun_dark", "l": "gun_dark", "r": "gun_dark", "t": "gun_dark"}, lf)
			kit.box(rx, Vector3(0.14, 0.42, -0.02), Vector3(0.008, 0.17, 0.008), MeshKit.all_faces("metal"), lf)
		"chair":
			_chair(Transform3D(Basis(Vector3.UP, p.ang), Vector3(p.fx, 0, p.fz)), lf)
		"table":
			var a2 := Vector3(p.x0 + 0.1, 0.72, p.z0 + 0.1)
			var b2 := Vector3(p.x1 + 0.9, 0.8, p.z1 + 0.9)
			kit.aabb(a2, b2, MeshKit.all_faces("wood_dark"), lf)
			for c in [Vector2(a2.x, a2.z), Vector2(b2.x - 0.08, a2.z), Vector2(a2.x, b2.z - 0.08), Vector2(b2.x - 0.08, b2.z - 0.08)]:
				kit.aabb(Vector3(c.x, 0, c.y), Vector3(c.x + 0.08, 0.72, c.y + 0.08), MeshKit.all_faces("metal"), lf)
		"bigdesk":
			var a3: Vector2i = p.a
			var b3: Vector2i = p.b
			var lo := Vector3(mini(a3.x, b3.x) + 0.05, 0, mini(a3.y, b3.y) + 0.05)
			var hi := Vector3(maxi(a3.x, b3.x) + 0.95, 0.8, maxi(a3.y, b3.y) + 0.95)
			kit.aabb(lo, hi, MeshKit.all_faces("wood_dark"), lf)
		"smalltable":
			kit.aabb(Vector3(p.x + 0.15, 0.68, p.z + 0.15), Vector3(p.x + 0.85, 0.74, p.z + 0.85), MeshKit.all_faces("desk_top"), lf)
			kit.aabb(Vector3(p.x + 0.45, 0, p.z + 0.45), Vector3(p.x + 0.55, 0.68, p.z + 0.55), MeshKit.all_faces("metal"), lf)
		"cabinet":
			kit.aabb(Vector3(p.x + 0.08, 0, p.z + 0.08), Vector3(p.x + 0.92, 1.45, p.z + 0.92), MeshKit.all_faces("cabinet", "metal"), lf)
		"shelf":
			kit.aabb(Vector3(p.x + 0.05, 0, p.z + 0.05), Vector3(p.x + 0.95, 2.0, p.z + 0.95), MeshKit.all_faces("shelf", "wood_dark"), lf)
		"rack":
			var f2 := {"f": "rack", "b": "rack", "r": "metal", "l": "metal", "t": "metal"}
			if p.face == 1:
				f2 = {"r": "rack", "l": "rack", "f": "metal", "b": "metal", "t": "metal"}
			kit.aabb(Vector3(p.x + 0.06, 0, p.z + 0.06), Vector3(p.x + 0.94, 2.1, p.z + 0.94), f2, lf)
		"plant":
			kit.aabb(Vector3(p.x + 0.3, 0, p.z + 0.3), Vector3(p.x + 0.7, 0.4, p.z + 0.7), MeshKit.all_faces("pot"), lf)
			var cx: float = p.x + 0.5
			var cz: float = p.z + 0.5
			var col := _lit(rid, Vector3(cx, 1.0, cz), Vector3.UP)
			kit.quad_flat("leaves", Vector3(cx - 0.55, 0.3, cz), Vector3(cx + 0.55, 0.3, cz), Vector3(cx + 0.55, 1.6, cz), Vector3(cx - 0.55, 1.6, cz), col)
			kit.quad_flat("leaves", Vector3(cx, 0.3, cz - 0.55), Vector3(cx, 0.3, cz + 0.55), Vector3(cx, 1.6, cz + 0.55), Vector3(cx, 1.6, cz - 0.55), col)
		"cooler":
			kit.aabb(Vector3(p.x + 0.3, 0, p.z + 0.3), Vector3(p.x + 0.7, 1.3, p.z + 0.7), MeshKit.all_faces("cooler"), lf)
		"vending", "fridge":
			var t: String = p.k
			var side := "red_metal" if t == "vending" else "white"
			var faces := {"f": side, "b": side, "r": side, "l": side, "t": "metal"}
			faces[MeshKit.FACE_KEY[p.face]] = t
			kit.aabb(Vector3(p.x + 0.07, 0, p.z + 0.07), Vector3(p.x + 0.93, 1.95, p.z + 0.93), faces, lf)
		"copier":
			kit.aabb(Vector3(p.x + 0.1, 0, p.z + 0.12), Vector3(p.x + 0.9, 1.0, p.z + 0.88), MeshKit.all_faces("copier"), lf)
		"counter":
			var fc: int = p.face
			var lo2 := Vector3(p.x, 0, p.z)
			var hi2 := Vector3(p.x + 1, 0.9, p.z + 1)
			match fc:
				0: lo2.z += 0.3
				2: hi2.z -= 0.3
				1: hi2.x -= 0.3
				_: lo2.x += 0.3
			var faces2 := {"f": "counter_side", "b": "counter_side", "r": "counter_side", "l": "counter_side", "t": "counter_top"}
			kit.aabb(lo2, hi2, faces2, lf)
			var xf2 := _cell_xf(p.x, p.z, fc, 0.9)
			xf2.origin -= xf2.basis.z * 0.15
			match p.get("variant", "plain"):
				"sink":
					kit.box(xf2, Vector3(0, 0.002, 0), Vector3(0.25, 0.002, 0.18), {"t": "metal"}, null, Color(0.3, 0.3, 0.32))
					kit.box(xf2, Vector3(0, 0.15, -0.2), Vector3(0.02, 0.15, 0.02), MeshKit.all_faces("metal"), lf)
				"coffee":
					kit.box(xf2, Vector3(0, 0.22, -0.05), Vector3(0.15, 0.22, 0.15), {"f": "coffee_machine", "b": "metal", "l": "metal", "r": "metal", "t": "metal"}, lf)
				"micro":
					kit.box(xf2, Vector3(0, 0.14, -0.05), Vector3(0.22, 0.14, 0.16), {"f": "scr_off", "b": "metal", "l": "metal", "r": "metal", "t": "metal"}, lf)
		"boxes", "boxes_low":
			var n := 3 if p.k == "boxes" else 1
			var y := 0.0
			for i in n:
				var s := L.rng.randf_range(0.32, 0.42)
				var xf3 := Transform3D(Basis(Vector3.UP, L.rng.randf_range(-0.4, 0.4)), Vector3(p.x + 0.5 + L.rng.randf_range(-0.06, 0.06), y, p.z + 0.5 + L.rng.randf_range(-0.06, 0.06)))
				kit.box(xf3, Vector3(0, s, 0), Vector3(s, s, s), MeshKit.all_faces("box"), lf)
				y += s * 2
		"stall":
			var faces3 := {"f": "stall", "b": "stall", "r": "stall", "l": "stall", "t": "wall_top"}
			kit.aabb(Vector3(p.x + 0.03, 0, p.z + 0.03), Vector3(p.x + 0.97, 1.95, p.z + 0.97), faces3, lf)
		"sofa":
			var a4: Vector2i = p.a
			var b4: Vector2i = p.b
			var lo3 := Vector3(mini(a4.x, b4.x) + 0.05, 0, mini(a4.y, b4.y) + 0.05)
			var hi3 := Vector3(maxi(a4.x, b4.x) + 0.95, 0.45, maxi(a4.y, b4.y) + 0.95)
			kit.aabb(lo3, hi3, MeshKit.all_faces("sofa"), lf)
			# спинка у стены (противоположно p.face)
			var back := (int(p.face) + 2) % 4
			var lo4 := lo3
			var hi4 := Vector3(hi3.x, 0.9, hi3.z)
			match back:
				0: hi4.z = lo3.z + 0.25
				2: lo4.z = hi3.z - 0.25
				1: lo4.x = hi3.x - 0.25
				_: hi4.x = lo3.x + 0.25
			kit.aabb(lo4, hi4, MeshKit.all_faces("sofa"), lf)


func _chair(xf: Transform3D, lf) -> void:
	kit.box(xf, Vector3(0, 0.45, 0), Vector3(0.22, 0.04, 0.22), MeshKit.all_faces("chair"), lf)
	kit.box(xf, Vector3(0, 0.75, -0.2), Vector3(0.22, 0.25, 0.03), MeshKit.all_faces("chair"), lf)
	kit.box(xf, Vector3(0, 0.22, 0), Vector3(0.03, 0.22, 0.03), MeshKit.all_faces("metal"), lf)
	kit.box(xf, Vector3(0, 0.03, 0), Vector3(0.24, 0.02, 0.03), MeshKit.all_faces("metal"), lf)
	kit.box(xf, Vector3(0, 0.03, 0), Vector3(0.03, 0.02, 0.24), MeshKit.all_faces("metal"), lf)


func _decals() -> void:
	for d in L.decals:
		var tex := "stain"
		var col := _lit(d.room, Vector3(d.x, 0, d.z), Vector3.UP)
		match d.kind:
			"blood": col = Color(col.r * 0.75, col.g * 0.06, col.b * 0.06, col.a)
			"coffee": col = Color(col.r * 0.45, col.g * 0.28, col.b * 0.16, col.a)
			"papers": tex = "papers"
			"scorch": col = Color(col.r * 0.12, col.g * 0.11, col.b * 0.1, col.a)   # 0.18: копоть
			"helipad":
				tex = "helipad"   # 0.19: круг с буквой H
				col = Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, col.a)
		var s: float = d.size
		var c := cos(d.rot) * s
		var sn := sin(d.rot) * s
		var y := 0.012 + fmod(d.x * 7.31 + d.z * 3.7, 1.0) * 0.006
		kit.quad_flat(tex, Vector3(d.x - c - sn, y, d.z + sn - c), Vector3(d.x + c - sn, y, d.z - sn - c),
			Vector3(d.x + c + sn, y, d.z - sn + c), Vector3(d.x - c + sn, y, d.z + sn + c), col)


func _wall_decor() -> void:
	for w in L.wall_decor:
		var d: int = w.dir
		var nx: int = DX[d]
		var nz: int = DZ[d]
		var face_n := Vector3(-nx, 0, -nz)
		var center := Vector3(w.x + 0.5 + nx * 0.48, 0, w.z + 0.5 + nz * 0.48)
		var right := Vector3(face_n.z, 0, -face_n.x) * -1.0
		var hw: float = w.w * 0.5
		var a: Vector3 = center - right * hw + Vector3(0, w.y0, 0)
		var b: Vector3 = center + right * hw + Vector3(0, w.y0, 0)
		var col := _lit(w.room, center + Vector3(0, 1.5, 0), face_n)
		kit.quad_flat(w.tex, a, b, b + Vector3(0, w.y1 - w.y0, 0), a + Vector3(0, w.y1 - w.y0, 0), col)


# ---------------------------------------------------------------- лифты
func _elevator(e: Dictionary, is_exit: bool) -> void:
	var N: Vector3 = e.normal
	var C: Vector3 = e.plane
	var R := Vector3(N.z, 0, -N.x)
	var lit := Color(0.62, 0.6, 0.55)
	var pt := func(s: float, y: float, off: float) -> Vector3: return C + R * (s - 1.0) + Vector3(0, y, 0) + N * off
	var fq := func(tex: String, s0: float, s1: float, y0: float, y1: float, off: float, col: Color) -> void:
		kit.quad_flat(tex, pt.call(s0, y0, off), pt.call(s1, y0, off), pt.call(s1, y1, off), pt.call(s0, y1, off), col)
	fq.call("elev_frame", 0.0, 0.2, 0.0, 2.1, 0.0, lit)
	fq.call("elev_frame", 1.8, 2.0, 0.0, 2.1, 0.0, lit)
	fq.call("elev_frame", 0.0, 2.0, 2.1, WH, 0.0, lit)
	fq.call("elev_panel", 2.08, 2.32, 0.95, 1.45, 0.03, Color(0.8, 0.8, 0.8))
	# кабина внутри стенных клеток (видна, когда двери открыты)
	var cab := Color(1.0, 0.95, 0.8)
	kit.quad_flat("elev_inside", pt.call(0.2, 0.01, 0.0), pt.call(1.8, 0.01, 0.0), pt.call(1.8, 0.01, -0.95), pt.call(0.2, 0.01, -0.95), cab)
	kit.quad_flat("elev_inside", pt.call(0.2, 0.0, -0.95), pt.call(1.8, 0.0, -0.95), pt.call(1.8, 2.1, -0.95), pt.call(0.2, 2.1, -0.95), cab)
	kit.quad_flat("elev_inside", pt.call(0.2, 0.0, 0.0), pt.call(0.2, 0.0, -0.95), pt.call(0.2, 2.1, -0.95), pt.call(0.2, 2.1, 0.0), cab)
	kit.quad_flat("elev_inside", pt.call(1.8, 0.0, -0.95), pt.call(1.8, 0.0, 0.0), pt.call(1.8, 2.1, 0.0), pt.call(1.8, 2.1, -0.95), cab)
	kit.quad_flat("elev_inside", pt.call(0.2, 2.1, 0.0), pt.call(1.8, 2.1, 0.0), pt.call(1.8, 2.1, -0.95), pt.call(0.2, 2.1, -0.95), cab)
	if not is_exit:
		fq.call("elev_door", 0.2, 1.0, 0.0, 2.1, 0.01, lit)
		fq.call("elev_door", 1.0, 1.8, 0.0, 2.1, 0.01, lit)
		fq.call("elev_display0", 0.75, 1.25, 2.2, 2.45, 0.02, Color(0.8, 0.8, 0.8))
		return
	# двери выхода — отдельные узлы, их будем раздвигать
	for side in 2:
		var k := MeshKit.new()
		k.quad_flat("elev_door", Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0), Vector3(0.4, 2.1, 0), Vector3(-0.4, 2.1, 0), lit)
		var mi := MeshInstance3D.new()
		mi.mesh = k.commit()
		add_child(mi)
		mi.basis = Basis(Vector3.UP, atan2(N.x, N.z))
		mi.position = pt.call(0.6 if side == 0 else 1.4, 0.0, 0.012)
		mi.set_meta("base", mi.position)
		mi.set_meta("dir", -R if side == 0 else R)
		exit_doors.append(mi)
	var kd := MeshKit.new()
	kd.quad_flat("elev_display0", Vector3(-0.25, 0, 0), Vector3(0.25, 0, 0), Vector3(0.25, 0.25, 0), Vector3(-0.25, 0.25, 0), Color(0.8, 0.8, 0.8))
	exit_display = MeshInstance3D.new()
	exit_display.mesh = kd.commit()
	add_child(exit_display)
	exit_display.basis = Basis(Vector3.UP, atan2(N.x, N.z))
	exit_display.position = pt.call(1.0, 2.2, 0.02)


func set_exit_unlocked(on: bool) -> void:
	if exit_display:
		exit_display.material_override = PS1Material.create(OfficeTex.get_tex("elev_display1" if on else "elev_display0"), Color.WHITE, Vector2.ONE, false, true)


func set_door_open(t: float) -> void:
	door_open = clampf(t, 0.0, 1.0)
	for d in exit_doors:
		d.position = d.get_meta("base") + d.get_meta("dir") * (0.78 * door_open)


# ---------------------------------------------------------------- ПК для взлома
func _build_pc(pc: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)
	var p: Dictionary = pc.prop
	var y := 0.8 if pc.laptop or p.k == "monitor" else 0.78
	var xf := _cell_xf(pc.x, pc.z, pc.face, y)
	if pc.laptop:
		xf.origin += xf.basis.z * 0.22
	node.transform = xf
	var k := MeshKit.new()
	var col := L.light_at(pc.room, xf.origin + Vector3(0, 0.3, 0), Vector3.UP)
	if pc.laptop:
		laptop(k, Transform3D.IDENTITY, "", null)
	else:
		monitor(k, Transform3D.IDENTITY, "", null)
	var body := MeshInstance3D.new()
	body.mesh = k.commit()
	body.material_override = null
	node.add_child(body)
	# подкрасим корпус под свет комнаты
	for i in body.mesh.get_surface_count():
		var tex: String = body.mesh.get_meta("texs")[i]
		body.set_surface_override_material(i, PS1Material.create(OfficeTex.get_tex(tex), Color(col.r / 0.62, col.g / 0.62, col.b / 0.62), Vector2.ONE, false, true))
	var ks := MeshKit.new()
	var white := Color(0.75, 0.75, 0.75)
	if pc.laptop:
		var hinge := Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0, 0.02, -0.07))
		ks.box(hinge, Vector3(0, 0.12, 0.009), Vector3(0.15, 0.1, 0.002), {"f": "scr_hack0"}, null, white)
	else:
		ks.box(Transform3D.IDENTITY, Vector3(0, 0.19, -0.026), Vector3(0.16, 0.13, 0.004), {"f": "scr_hack0"}, null, white)
	var scr := MeshInstance3D.new()
	scr.mesh = ks.commit()
	node.add_child(scr)
	pc_nodes.append({"node": node, "screen": scr})


## Экран ПК: 0/1 — мигающий «взломай меня», 2 — взломан.
func set_pc_screen(i: int, state: int) -> void:
	var names := ["scr_hack0", "scr_hack1", "scr_ok"]
	var scr: MeshInstance3D = pc_nodes[i].screen
	scr.material_override = PS1Material.create(OfficeTex.get_tex(names[state]), Color.WHITE, Vector2.ONE, false, true)


## 0.16: разбитый стол логова — столешница съехала одним краем на пол, одна пара ножек цела; перегородки на месте.
func _broken_desk(p: Dictionary, lf) -> void:
	var x: int = p.x
	var z: int = p.z
	var f: int = p.face
	var tilt := 0.32 if (x + z) % 2 == 0 else -0.32
	var axis := Vector3(1, 0, 0) if f == 1 or f == 3 else Vector3(0, 0, 1)
	var xf := Transform3D(Basis(axis, tilt), Vector3(x + 0.5, 0.48, z + 0.5))
	kit.box(xf, Vector3.ZERO, Vector3(0.46, 0.03, 0.46), {"t": "desk_top", "f": "desk_side", "b": "desk_side", "r": "desk_side", "l": "desk_side", "d": "desk_side"}, lf)
	var side := 1.0 if tilt < 0.0 else -1.0
	if f == 0 or f == 2:
		var lx := x + 0.5 + side * 0.4
		kit.aabb(Vector3(lx - 0.02, 0, z + 0.1), Vector3(lx + 0.02, 0.62, z + 0.9), MeshKit.all_faces("desk_side"), lf)
	else:
		var lz := z + 0.5 + side * 0.4
		kit.aabb(Vector3(x + 0.1, 0, lz - 0.02), Vector3(x + 0.9, 0.62, lz + 0.02), MeshKit.all_faces("desk_side"), lf)
	for d in p.parts:
		var a: Vector3
		var b: Vector3
		match d:
			0: a = Vector3(x, 0, z); b = Vector3(x + 1, 1.3, z + 0.05)
			2: a = Vector3(x, 0, z + 0.95); b = Vector3(x + 1, 1.3, z + 1)
			1: a = Vector3(x + 0.95, 0, z); b = Vector3(x + 1, 1.3, z + 1)
			_: a = Vector3(x, 0, z); b = Vector3(x + 0.05, 1.3, z + 1)
		kit.aabb(a, b, MeshKit.all_faces("partition", "desk_side"), lf)
