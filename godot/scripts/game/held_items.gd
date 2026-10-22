class_name HeldItems
extends RefCounted
## Как предмет выглядит в руках героя и какой стойкой его держат.
## Новое оружие/предмет = запись в Items.DEFS + запись здесь (grip, stow, parts, muzzle).
##
## Координаты модели: начало — точка хвата (в ладони), +Z — вперёд (ствол), +Y — вверх.
## parts: [центр, полуразмер, текстура].
##
## grip — стойка (позы описаны в Player._pose_item):
##   pistol  — пистолет: опущен в руке; прицел — двумя руками перед собой;
##   rifle   — двуручное (дробовик): без цели — за спиной; прицел — приклад к плечу;
##   throw   — бросаемое одной рукой: в опущенной руке; прицел — рука занесена для броска;
##   heavy   — тяжёлое бросаемое двумя руками (огнетушитель): прицел — над головой;
##   knife   — нож: у бедра; прицел — выставлен вперёд; удар — выпад;
##   axe     — топор: в опущенной руке; прицел — двумя руками над плечом; удар — сверху вниз;
##   club    — труба: в опущенной руке; прицел — одной рукой занесена над плечом; удар — наискосок вниз;
##   fist    — кастет: на кулаке; прицел — боксёрская стойка; удар — прямой;
##   consume — лечение: в руке; при использовании — подносит ко рту.
## Позы — CharModel.pose_held(), положение модели — CharModel.place_held() (общие для героя и людей).
## stow — где предмет, когда не целимся: hand (в руке) / back (за спиной).

const DEFS := {
	"pistol": {"grip": "pistol", "stow": "hand", "muzzle": Vector3(0, 0.04, 0.18), "parts": [
		[Vector3(0, 0.035, 0.07), Vector3(0.022, 0.028, 0.1), "gun_dark"],
		[Vector3(0, -0.03, 0.0), Vector3(0.02, 0.05, 0.03), "gun_grip"]]},
	"silenced": {"grip": "pistol", "stow": "hand", "muzzle": Vector3(0, 0.035, 0.33), "parts": [
		[Vector3(0, 0.035, 0.07), Vector3(0.022, 0.028, 0.1), "metal"],
		[Vector3(0, 0.035, 0.24), Vector3(0.02, 0.02, 0.08), "gun_dark"],
		[Vector3(0, -0.03, 0.0), Vector3(0.02, 0.05, 0.03), "gun_grip"]]},
	"shotgun": {"grip": "rifle", "stow": "back", "muzzle": Vector3(0, 0.04, 0.62), "parts": [
		[Vector3(0, 0.04, 0.3), Vector3(0.024, 0.024, 0.32), "gun_dark"],
		[Vector3(0, 0.0, 0.32), Vector3(0.03, 0.024, 0.09), "wood_dark"],
		[Vector3(0, 0.03, 0.0), Vector3(0.03, 0.045, 0.08), "gun_dark"],
		[Vector3(0, -0.01, -0.22), Vector3(0.028, 0.05, 0.15), "wood_dark"]]},
	"rifle": {"grip": "rifle", "stow": "back", "muzzle": Vector3(0, 0.04, 0.74), "parts": [
		[Vector3(0, 0.04, 0.46), Vector3(0.014, 0.014, 0.28), "gun_dark"],
		[Vector3(0, 0.0, 0.12), Vector3(0.03, 0.035, 0.3), "wood_dark"],
		[Vector3(0, 0.1, 0.1), Vector3(0.02, 0.02, 0.09), "gun_dark"],
		[Vector3(0.04, 0.05, -0.02), Vector3(0.03, 0.01, 0.01), "metal"],
		[Vector3(0, -0.02, -0.28), Vector3(0.03, 0.055, 0.12), "wood_dark"]]},
	"uzi": {"grip": "pistol", "stow": "hand", "muzzle": Vector3(0, 0.04, 0.25), "parts": [
		[Vector3(0, 0.03, 0.06), Vector3(0.026, 0.04, 0.11), "gun_dark"],
		[Vector3(0, 0.04, 0.2), Vector3(0.01, 0.01, 0.04), "gun_dark"],
		[Vector3(0, -0.06, 0.02), Vector3(0.018, 0.08, 0.02), "gun_grip"]]},
	# 0.19: M4A1-S элиты (крыша) — автомат с длинным глушителем, магазин, приклад
	"m4": {"grip": "rifle", "stow": "back", "muzzle": Vector3(0, 0.05, 0.78), "parts": [
		[Vector3(0, 0.05, 0.22), Vector3(0.025, 0.035, 0.2), "gun_dark"],
		[Vector3(0, 0.05, 0.6), Vector3(0.022, 0.022, 0.17), "metal"],
		[Vector3(0, 0.0, -0.1), Vector3(0.022, 0.04, 0.09), "gun_dark"],
		[Vector3(0, -0.04, 0.18), Vector3(0.015, 0.06, 0.025), "gun_grip"],
		[Vector3(0, 0.1, 0.18), Vector3(0.012, 0.012, 0.06), "gun_dark"]]},
	# 0.15 — оружие офисников (уникальные награды):
	# револьвер — длинный ствол, барабан, деревянная рукоять; бьёт сильнее пистолета
	"revolver": {"grip": "pistol", "stow": "hand", "muzzle": Vector3(0, 0.045, 0.25), "parts": [
		[Vector3(0, 0.045, 0.14), Vector3(0.014, 0.014, 0.1), "metal"],
		[Vector3(0, 0.038, 0.03), Vector3(0.03, 0.03, 0.035), "gun_dark"],
		[Vector3(0, 0.035, -0.015), Vector3(0.02, 0.03, 0.03), "metal"],
		[Vector3(0, -0.035, -0.035), Vector3(0.019, 0.055, 0.028), "wood_dark"]]},
	# гвоздомёт — жёлтый строительный инструмент: корпус, нос, лента гвоздей снизу; 12 гвоздей, медленнее узи
	"nailgun": {"grip": "pistol", "stow": "hand", "muzzle": Vector3(0, 0.03, 0.31), "parts": [
		[Vector3(0, 0.07, 0.07), Vector3(0.035, 0.055, 0.13), "tool_yellow"],
		[Vector3(0, 0.03, 0.24), Vector3(0.02, 0.03, 0.05), "gun_dark"],
		[Vector3(0, 0.0, 0.13), Vector3(0.012, 0.022, 0.09), "metal"],
		[Vector3(0, -0.035, -0.02), Vector3(0.024, 0.06, 0.03), "gun_dark"]]},
	# арбалет — приклад, плечи, тетива, болт с красным оперением; бесшумный и сильный, свой слот
	"crossbow": {"grip": "rifle", "stow": "back", "muzzle": Vector3(0, 0.06, 0.38), "parts": [
		[Vector3(0, 0.0, -0.06), Vector3(0.026, 0.035, 0.24), "wood_dark"],
		[Vector3(0, 0.04, 0.16), Vector3(0.013, 0.012, 0.16), "metal"],
		[Vector3(0, 0.045, 0.3), Vector3(0.27, 0.016, 0.02), "gun_dark"],
		[Vector3(0, 0.05, 0.18), Vector3(0.25, 0.004, 0.004), "white"],
		[Vector3(0, 0.06, 0.2), Vector3(0.006, 0.006, 0.15), "metal"],
		[Vector3(0, 0.06, 0.07), Vector3(0.012, 0.012, 0.025), "bolt_red"]]},
	"knife": {"grip": "knife", "stow": "hand", "parts": [
		[Vector3(0, 0, 0), Vector3(0.016, 0.02, 0.045), "gun_grip"],
		[Vector3(0, 0.005, 0.13), Vector3(0.006, 0.02, 0.085), "metal"]]},
	"axe": {"grip": "axe", "stow": "hand", "parts": [
		[Vector3(0, 0, 0.22), Vector3(0.02, 0.02, 0.4), "wood_dark"],
		[Vector3(0, 0.07, 0.56), Vector3(0.015, 0.1, 0.06), "red_metal"],
		[Vector3(0, -0.08, 0.56), Vector3(0.012, 0.06, 0.02), "metal"]]},
	"pipe": {"grip": "club", "stow": "hand", "parts": [
		[Vector3(0, 0, 0.26), Vector3(0.022, 0.022, 0.34), "metal"],
		[Vector3(0, 0, 0.58), Vector3(0.032, 0.032, 0.035), "gun_dark"]]},
	"knuckles": {"grip": "fist", "stow": "hand", "parts": [
		[Vector3(0, -0.02, 0.07), Vector3(0.07, 0.025, 0.015), "metal"],
		[Vector3(0, -0.05, 0.05), Vector3(0.05, 0.012, 0.03), "metal"]]},
	"bottle": {"grip": "throw", "stow": "hand", "parts": [
		[Vector3(0, 0.04, 0), Vector3(0.045, 0.09, 0.045), "i_bottle"],
		[Vector3(0, 0.17, 0), Vector3(0.02, 0.05, 0.02), "i_bottle"]]},
	"alarm": {"grip": "throw", "stow": "hand", "parts": [
		[Vector3(0, 0.03, 0.02), Vector3(0.07, 0.07, 0.04), "i_alarm"]]},
	"brick": {"grip": "throw", "stow": "hand", "parts": [
		[Vector3(0, 0, 0.02), Vector3(0.11, 0.055, 0.065), "i_brick"]]},
	"shuriken": {"grip": "throw", "stow": "hand", "parts": [
		[Vector3(0, 0, 0.06), Vector3(0.1, 0.01, 0.1), "i_shuriken"]]},
	"grenade": {"grip": "throw", "stow": "hand", "parts": [
		[Vector3(0, 0.01, 0.02), Vector3(0.05, 0.07, 0.05), "i_grenade"]]},
	"extinguisher": {"grip": "heavy", "stow": "hand", "parts": [
		[Vector3(0, 0.02, 0.04), Vector3(0.07, 0.2, 0.07), "red_metal"],
		[Vector3(0, 0.25, 0.04), Vector3(0.03, 0.04, 0.03), "gun_dark"]]},
	"coffee": {"grip": "consume", "stow": "hand", "parts": [
		[Vector3(0, 0.03, 0.03), Vector3(0.04, 0.06, 0.04), "white"]]},
	"energy": {"grip": "consume", "stow": "hand", "parts": [
		[Vector3(0, 0.04, 0.03), Vector3(0.03, 0.07, 0.03), "i_energy"]]},
	"medkit": {"grip": "consume", "stow": "hand", "parts": [
		[Vector3(0, 0.0, 0.05), Vector3(0.1, 0.07, 0.04), "i_medkit"]]},
	# 0.16: куртка бандита (свёрнутая) и ключ-карта логова (для предмета на полу)
	"disguise": {"grip": "consume", "stow": "hand", "parts": [
		[Vector3(0, 0.0, 0.06), Vector3(0.13, 0.06, 0.1), "i_disguise"]]},
	"keycard": {"grip": "consume", "stow": "hand", "parts": [
		[Vector3(0, 0.0, 0.03), Vector3(0.07, 0.01, 0.045), "i_keycard"]]},
	"bags": {"grip": "consume", "stow": "hand", "parts": [
		[Vector3(0, 0.0, 0.05), Vector3(0.1, 0.05, 0.08), "i_bags"]]},
	"ammo": {"grip": "consume", "stow": "hand", "parts": [
		[Vector3(0, 0.08, 0.0), Vector3(0.22, 0.1, 0.14), "i_ammo"]]},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func grip(id: String) -> String:
	return DEFS[id].grip if DEFS.has(id) else ""


static func stow(id: String) -> String:
	return DEFS[id].stow if DEFS.has(id) else "hand"


static func muzzle(id: String) -> Vector3:
	return DEFS[id].get("muzzle", Vector3(0, 0, 0.2)) if DEFS.has(id) else Vector3.ZERO


static func build_mesh(id: String) -> ArrayMesh:
	var k := MeshKit.new()
	for part in DEFS[id].parts:
		k.box(Transform3D.IDENTITY, part[0], part[1], MeshKit.all_faces(part[2], "", true), null, Color(0.62, 0.62, 0.62))
	return k.commit()
