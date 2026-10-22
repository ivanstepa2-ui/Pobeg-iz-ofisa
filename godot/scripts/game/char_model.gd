class_name CharModel
extends Node3D
## Low-poly персонаж из коробок (как на PS1) с процедурной анимацией.
## Локально смотрит в +Z; правая рука — со стороны -X.

const SPECS := {
	"player": {"pre": "p", "hip": 0.92, "torso": Vector3(0.42, 0.56, 0.24), "head": Vector3(0.27, 0.29, 0.27), "arm": Vector3(0.12, 0.62, 0.12), "leg": Vector3(0.15, 0.92, 0.15)},
	"zombie": {"pre": "z", "hip": 0.92, "torso": Vector3(0.44, 0.58, 0.25), "head": Vector3(0.27, 0.3, 0.27), "arm": Vector3(0.12, 0.64, 0.12), "leg": Vector3(0.15, 0.92, 0.15)},
	"woman": {"pre": "w", "hip": 0.9, "torso": Vector3(0.36, 0.52, 0.22), "head": Vector3(0.25, 0.28, 0.25), "arm": Vector3(0.1, 0.6, 0.1), "leg": Vector3(0.12, 0.9, 0.12), "skirt": true, "hair": true},
	"clicker": {"pre": "c", "hip": 0.9, "torso": Vector3(0.42, 0.56, 0.24), "head": Vector3(0.3, 0.32, 0.3), "arm": Vector3(0.12, 0.66, 0.12), "leg": Vector3(0.15, 0.9, 0.15)},
	"human": {"pre": "h", "hip": 0.92, "torso": Vector3(0.44, 0.56, 0.26), "head": Vector3(0.27, 0.29, 0.27), "arm": Vector3(0.13, 0.62, 0.13), "leg": Vector3(0.16, 0.92, 0.16), "lamp": true},
	# 0.15: офисник — живой сотрудник (третья сторона), без фонаря-налобника, оружие в руках как у людей
	"office": {"pre": "o", "hip": 0.92, "torso": Vector3(0.41, 0.55, 0.23), "head": Vector3(0.26, 0.29, 0.26), "arm": Vector3(0.12, 0.62, 0.12), "leg": Vector3(0.15, 0.92, 0.15)},
	"fat": {"pre": "f", "hip": 0.95, "torso": Vector3(0.66, 0.62, 0.48), "head": Vector3(0.32, 0.3, 0.32), "arm": Vector3(0.16, 0.62, 0.16), "leg": Vector3(0.2, 0.95, 0.2)},
}

static var _mesh_cache: Dictionary = {}
static var _shadow_mat: StandardMaterial3D

var kind := "zombie"
var spec: Dictionary
var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var hand_r: Node3D          # точка хвата в правой ладони (только у героя)
var back_slot: Node3D       # крепление за спиной (дробовик)
var hip_slot: Node3D        # на поясе (нож/кастет/труба убраны)
var held: MeshInstance3D    # предмет в руках, см. HeldItems
var held_id := ""
var shadow: MeshInstance3D
var _mats: Dictionary = {}
var _last_tint := Color(-1, 0, 0)


func setup(k: String) -> void:
	kind = k
	spec = SPECS[k]
	var pre: String = spec.pre
	var T: Vector3 = spec.torso
	var Hd: Vector3 = spec.head
	var A: Vector3 = spec.arm
	var Lg: Vector3 = spec.leg
	body = _node(self, Vector3.ZERO)
	hips = _node(body, Vector3(0, spec.hip, 0))
	var leg_tex := pre + "_legs"
	var leg_x: float = T.x * 0.25 if k != "fat" else T.x * 0.28
	leg_l = _node(hips, Vector3(leg_x, 0, 0))
	leg_r = _node(hips, Vector3(-leg_x, 0, 0))
	# нога из двух частей (бедро + голень) с коленом — для приседа на корточки
	var lf := {"f": leg_tex, "b": leg_tex, "l": leg_tex, "r": leg_tex, "d": leg_tex}
	var seg: float = Lg.y / 2
	knee_l = _node(leg_l, Vector3(0, -seg, 0))
	knee_r = _node(leg_r, Vector3(0, -seg, 0))
	for lg in [leg_l, leg_r]:
		_part(lg, "thigh", Vector3(0, -seg / 2, 0), Vector3(Lg.x / 2, seg / 2, Lg.z / 2), lf, Vector2(0, 0.5))
	for kn in [knee_l, knee_r]:
		_part(kn, "shin", Vector3(0, -seg / 2, 0), Vector3(Lg.x / 2 * 0.95, seg / 2, Lg.z / 2 * 0.95), lf, Vector2(0.5, 1.0))
	torso = _node(hips, Vector3.ZERO)
	_part(torso, "torso", Vector3(0, T.y / 2, 0), T / 2, {"f": pre + "_shirt_f", "b": pre + "_shirt", "l": pre + "_shirt", "r": pre + "_shirt", "t": pre + "_shirt", "d": leg_tex})
	if spec.get("skirt", false):
		_part(hips, "skirt", Vector3(0, -0.14, 0), Vector3(T.x * 0.56, 0.17, T.z * 0.62), {"f": "w_skirt", "b": "w_skirt", "l": "w_skirt", "r": "w_skirt", "d": "w_skirt"})
	head = _node(torso, Vector3(0, T.y + 0.02, 0))
	_part(head, "head", Vector3(0, Hd.y / 2, 0), Hd / 2, {"f": pre + "_face", "b": pre + "_hair", "l": pre + "_side", "r": pre + "_side", "t": pre + "_hair", "d": pre + "_skin"})
	if spec.get("hair", false):
		_part(head, "hairback", Vector3(0, Hd.y * 0.3, -Hd.z / 2 - 0.03), Vector3(Hd.x / 2 + 0.01, Hd.y * 0.55, 0.035), {"f": "w_hair", "b": "w_hair", "l": "w_hair", "r": "w_hair", "t": "w_hair", "d": "w_hair"})
	var ax: float = T.x / 2 + A.x / 2 + 0.01
	arm_l = _node(torso, Vector3(ax, T.y - 0.06, 0))
	arm_r = _node(torso, Vector3(-ax, T.y - 0.06, 0))
	var sl := pre + "_sleeve"
	for am in [arm_l, arm_r]:
		_part(am, "arm", Vector3(0, -A.y / 2, 0), A / 2, {"f": sl, "b": sl, "l": sl, "r": sl, "t": sl, "d": pre + "_skin"})
	if k == "player" or k == "human" or k == "office":
		hand_r = _node(arm_r, Vector3(0, -A.y + 0.02, 0.02))
		back_slot = _node(torso, Vector3(0, T.y * 0.55, -T.z / 2 - 0.05))
		hip_slot = _node(hips, Vector3(-T.x * 0.5 - 0.03, -0.04, 0.04))
	if spec.get("lamp", false):
		# фонарик на груди
		_part(torso, "lamp", Vector3(T.x * 0.22, T.y * 0.72, T.z / 2 + 0.04), Vector3(0.05, 0.04, 0.04), MeshKit.all_faces("lamp", "", true))
	shadow = MeshInstance3D.new()
	var qm := QuadMesh.new()
	var sz := 1.3 if k == "fat" else 0.9
	qm.size = Vector2(sz, sz)
	qm.orientation = PlaneMesh.FACE_Y
	shadow.mesh = qm
	shadow.position = Vector3(0, 0.025, 0)
	shadow.material_override = _get_shadow_mat()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)


static func _get_shadow_mat() -> StandardMaterial3D:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.albedo_texture = OfficeTex.get_tex("shadow")
		_shadow_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_shadow_mat.albedo_color = Color(1, 1, 1, 0.8)
	return _shadow_mat


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, part: String, center: Vector3, half: Vector3, faces: Dictionary, v_range: Vector2 = Vector2(0, 1)) -> void:
	var key := kind + ":" + part
	if not _mesh_cache.has(key):
		var k := MeshKit.new()
		k.box(Transform3D.IDENTITY, center, half, faces, null, Color(0.62, 0.62, 0.62), v_range)
		_mesh_cache[key] = k.commit()
	parent.add_child(_instance(_mesh_cache[key]))


## MeshInstance с материалами этой модели (они тонируются светом в set_light).
func _instance(mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var texs: Array = mesh.get_meta("texs")
	for i in texs.size():
		var tex: String = texs[i]
		if not _mats.has(tex):
			_mats[tex] = PS1Material.create_unique(OfficeTex.get_tex(tex), Color.WHITE, Vector2.ONE, false, true)
			_last_tint = Color(-1, 0, 0)
			if silhouette > 0:
				_mats[tex].next_pass = _sil_mats[silhouette - 1]
		mi.set_surface_override_material(i, _mats[tex])
	return mi


## Силуэт сквозь стены: 0 — нет, 1 — тускло-оранжевый (просто рядом), 2 — красный (охотится на героя).
## Второй проход материалов: без освещения и без теста глубины — рисуется поверх стен.
static var _sil_mats: Array = []
var silhouette := 0


func set_silhouette(mode: int) -> void:
	if mode == silhouette:
		return
	silhouette = mode
	if _sil_mats.is_empty():
		for c in [Color(1.0, 0.55, 0.15, 0.35), Color(1.0, 0.12, 0.08, 0.5)]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.no_depth_test = true
			m.albedo_color = c
			m.render_priority = 10
			_sil_mats.append(m)
	var np: Material = null if mode == 0 else _sil_mats[mode - 1]
	for m in _mats.values():
		m.next_pass = np


## Сменить предмет в руках ("" — пустые руки).
func set_held(id: String) -> void:
	if id == held_id or hand_r == null:
		return
	held_id = id
	if held != null:
		held.queue_free()
		held = null
	if not HeldItems.has(id):
		return
	var key := "held:" + id
	if not _mesh_cache.has(key):
		_mesh_cache[key] = HeldItems.build_mesh(id)
	held = _instance(_mesh_cache[key])
	hand_r.add_child(held)


## Стойка под предмет id в правой руке. aim — 0 опущено … 1 на изготовке; recoil — отдача 0..1;
## act — прогресс действия 0..1 (бросок, удар ножом/топором, питьё), < 0 — нет действия.
## Позы рук пишутся в словарь p поверх походки. Грипы — см. HeldItems.
static func pose_held(p: Dictionary, id: String, aim: float, recoil: float, act: float) -> void:
	var sw: float = p.get("arm_r", 0.0)
	var sl: float = p.get("arm_l", 0.0)
	var mix := func(key: String, low: float, hi: float) -> void:
		p[key] = lerpf(low, hi, aim)
	# корпус наклонён (присед, бег) — руки с оружием доворачиваем, чтобы ствол смотрел горизонтально
	var ln: float = p.get("lean", 0.0)
	match HeldItems.grip(id):
		"pistol":
			mix.call("arm_r", -0.3 + sw * 0.3, -1.55 - recoil * 0.5 - ln)
			mix.call("arm_l", sl, -1.45 - recoil * 0.4 - ln)
			mix.call("out_r", 0.1, -0.32)
			mix.call("out_l", 0.08, -0.4)
		"rifle":
			mix.call("arm_r", sw, -1.3 - recoil * 0.3 - ln)
			mix.call("arm_l", sl, -1.5 - recoil * 0.3 - ln)
			mix.call("out_r", 0.08, -0.12)
			mix.call("out_l", 0.08, -0.55)
			p["lean"] = p.get("lean", 0.0) - recoil * 0.15
		"throw":
			mix.call("arm_r", -0.25 + sw * 0.3, -3.4)
			mix.call("arm_l", sl, -1.2)
			mix.call("out_r", 0.1, 0.3)
			if act >= 0.0:
				p["arm_r"] = lerpf(-3.4, -0.8, act)
				p["arm_l"] = lerpf(-1.2, -0.3, act)
				p["lean"] = p.get("lean", 0.0) + 0.2 * sin(act * PI)
		"heavy":
			mix.call("arm_r", -0.35, -2.9)
			mix.call("arm_l", -0.35, -2.9)
			mix.call("out_r", 0.05, -0.15)
			mix.call("out_l", 0.05, -0.15)
			if act >= 0.0:
				p["arm_r"] = lerpf(-2.9, -1.1, act)
				p["arm_l"] = p["arm_r"]
		"knife":
			# опущен у бедра; на изготовке — нож вперёд, левая прикрывает; удар — выпад
			mix.call("arm_r", -0.3 + sw * 0.3, -0.85)
			mix.call("arm_l", sl, -0.65)
			mix.call("out_r", 0.1, -0.05)
			mix.call("out_l", 0.08, -0.12)
			p["lean"] = p.get("lean", 0.0) + 0.08 * aim
			if act >= 0.0:
				var k := sin(act * PI)
				p["arm_r"] = lerpf(p["arm_r"], -1.7, k)
				p["out_r"] = lerpf(p["out_r"], -0.32, k)
				p["lean"] = p["lean"] + 0.2 * k
		"axe":
			# опущен в руке; на изготовке — двумя руками над правым плечом; удар — сверху вниз
			mix.call("arm_r", -0.2 + sw * 0.2, -2.7)
			mix.call("arm_l", sl, -2.5)
			mix.call("out_r", 0.1, 0.05)
			mix.call("out_l", 0.08, -0.42)
			if act >= 0.0:
				p["arm_r"] = lerpf(-2.8, -0.5, act)
				p["arm_l"] = p["arm_r"]
				p["out_l"] = -0.35
				p["lean"] = p.get("lean", 0.0) + 0.35 * sin(act * PI)
		"club":
			mix.call("arm_r", -0.2 + sw * 0.25, -2.6)
			mix.call("arm_l", sl, -0.6)
			mix.call("out_r", 0.1, 0.2)
			mix.call("out_l", 0.08, -0.1)
			if act >= 0.0:
				p["arm_r"] = lerpf(-2.7, -0.6, act)
				p["out_r"] = lerpf(0.25, -0.3, act)
				p["lean"] = p.get("lean", 0.0) + 0.25 * sin(act * PI)
		"fist":
			mix.call("arm_r", sw, -1.15)
			mix.call("arm_l", sl, -1.25)
			mix.call("out_r", 0.08, -0.28)
			mix.call("out_l", 0.08, -0.32)
			if act >= 0.0:
				var kp := sin(act * PI)
				p["arm_r"] = lerpf(p["arm_r"], -1.65, kp)
				p["out_r"] = lerpf(p["out_r"], -0.12, kp)
				p["lean"] = p.get("lean", 0.0) + 0.18 * kp
		"consume":
			p["arm_r"] = -0.35 + sw * 0.3
			if act >= 0.0:
				var k3 := sin(act * PI)
				p["arm_r"] = lerpf(p["arm_r"], -2.5, k3)
				p["out_r"] = lerpf(0.1, -0.55, k3)
				p["head_pitch"] = -0.25 * k3


## Положение модели предмета: в руке (опущен / вдоль взгляда при прицеле) или за спиной.
## stowed — оружие убрано (люди на отдыхе): узи/болтовка/топор/дробовик — за спину, остальное — на пояс.
func place_held(id: String, aim: float, recoil: float, hidden: bool, stowed: bool = false) -> void:
	set_held(id)
	if held == null:
		return
	var g := HeldItems.grip(id)
	if stowed and hip_slot != null:
		held.visible = true
		if g in ["rifle", "pistol", "axe"]:
			attach_held(back_slot)
			held.position = Vector3(0.06, 0, 0) if g == "pistol" else Vector3.ZERO
			held.transform.basis = Basis(Vector3.BACK, 0.6 if g != "axe" else -0.5) * Basis(Vector3.RIGHT, -PI / 2)
		else:
			attach_held(hip_slot)
			held.position = Vector3.ZERO
			held.transform.basis = Basis(Vector3.RIGHT, PI / 2)   # клинком/трубой вниз
		return
	held.visible = not hidden or HeldItems.stow(id) == "back"
	if HeldItems.stow(id) == "back" and (aim < 0.5 or hidden):
		attach_held(back_slot)
		held.position = Vector3.ZERO
		held.transform.basis = Basis(Vector3.BACK, 0.6) * Basis(Vector3.RIGHT, -PI / 2)
		return
	attach_held(hand_r)
	held.position = Vector3.ZERO
	var low := (hand_r.global_basis * Basis(Vector3.RIGHT, 0.7)).get_rotation_quaternion()
	if g == "pistol" or g == "rifle":
		# на изготовке ствол смотрит точно по корпусу (на цель), с отдачей
		var yaw := global_rotation.y + torso.rotation.y
		var hi := (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -recoil * 0.5)).get_rotation_quaternion()
		held.global_basis = Basis(low.slerp(hi, aim))
	elif g == "knife" or g == "axe" or g == "club":
		var hi2 := hand_r.global_basis.get_rotation_quaternion()
		held.global_basis = Basis(low.slerp(hi2, aim))
	else:
		held.transform.basis = Basis.IDENTITY


## Перевесить предмет в руку или за спину.
func attach_held(slot: Node3D) -> void:
	if held != null and held.get_parent() != slot:
		held.reparent(slot, false)


func _exit_tree() -> void:
	for m in _mats.values():
		PS1Material.release(m)


## Тинт освещения (цвет клетки) + вспышка при ударе.
func set_light(c: Color, flash: float = 0.0) -> void:
	var t := Color(c.r / 0.62, c.g / 0.62, c.b / 0.62) * 0.95
	if flash > 0.0:
		t = t.lerp(Color(2.5, 2.2, 2.2), flash)
	if absf(t.r - _last_tint.r) + absf(t.g - _last_tint.g) + absf(t.b - _last_tint.b) < 0.02:
		return
	_last_tint = t
	for m in _mats.values():
		m.set_shader_parameter("albedo_color", t)


## Поза: ключи (радианы) leg_l, leg_r, knee_l, knee_r (> 0 — голень назад), arm_l, arm_r, arm_out, out_l, out_r, lean, roll, twist,
## head_yaw, head_pitch, head_roll, drop, fall.
## arm_* < 0 — рука вперёд/вверх; out_* > 0 — в сторону, < 0 — к центру (сводит руки); twist — поворот корпуса.
func apply_pose(p: Dictionary) -> void:
	leg_l.rotation = Vector3(p.get("leg_l", 0.0), 0, 0)
	leg_r.rotation = Vector3(p.get("leg_r", 0.0), 0, 0)
	knee_l.rotation = Vector3(p.get("knee_l", 0.0), 0, 0)
	knee_r.rotation = Vector3(p.get("knee_r", 0.0), 0, 0)
	var out: float = p.get("arm_out", 0.08)
	arm_l.rotation = Vector3(p.get("arm_l", 0.0), 0, p.get("out_l", out))
	arm_r.rotation = Vector3(p.get("arm_r", 0.0), 0, -p.get("out_r", out))
	torso.rotation = Vector3(p.get("lean", 0.0), p.get("twist", 0.0), p.get("roll", 0.0))
	head.rotation = Vector3(p.get("head_pitch", 0.0), p.get("head_yaw", 0.0), p.get("head_roll", 0.0))
	hips.position.y = spec.hip - p.get("drop", 0.0)
	body.rotation = Vector3(p.get("fall", 0.0), 0, 0)
	shadow.visible = absf(p.get("fall", 0.0)) < 0.5


## 0.16: зелёная ключ-карта на спине (у хозяина пароля логова) — светится и в темноте: без освещения,
## с ореолом. remove_keycard() — упала на пол.
var keycard: Node3D = null

func add_keycard() -> void:
	if keycard != null:
		return
	var T: Vector3 = spec.torso
	keycard = Node3D.new()
	torso.add_child(keycard)
	keycard.position = Vector3(T.x * 0.22, T.y * 0.3, -T.z / 2 - 0.015)   # ниже и сбоку — не под ремнём ствола
	var card := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.13, 0.17, 0.012)
	card.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.35, 1.0, 0.5)
	card.material_override = m
	keycard.add_child(card)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	glow.mesh = q
	glow.rotation.y = PI   # лицом назад
	glow.position = Vector3(0, 0, -0.02)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_texture = OfficeTex.get_tex("p_dot")
	gm.albedo_color = Color(0.3, 1.0, 0.45, 0.55)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = gm
	keycard.add_child(glow)


func remove_keycard() -> void:
	if keycard != null:
		keycard.queue_free()
		keycard = null


## 0.17: пакеты на ногах (белые, поверх ботинок) — у героя, надевшего «пакеты».
func add_bags() -> void:
	var Lg: Vector3 = spec.leg
	var seg: float = Lg.y / 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.82, 0.83, 0.86)
	for kn in [knee_l, knee_r]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(Lg.x * 1.35, 0.16, Lg.z * 1.9)
		b.mesh = bm
		b.material_override = m
		b.position = Vector3(0, -seg + 0.07, 0.03)
		(kn as Node3D).add_child(b)


## 0.19: бронежилет элиты — тёмный короб поверх торса с «плитами» спереди и сзади.
func add_armor() -> void:
	var T: Vector3 = spec.torso
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.17, 0.15)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for z_off in [T.z / 2 + 0.02, -T.z / 2 - 0.02]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(T.x * 0.9, T.y * 0.62, 0.05)
		b.mesh = bm
		b.material_override = m
		b.position = Vector3(0, T.y * 0.55, z_off)
		torso.add_child(b)
