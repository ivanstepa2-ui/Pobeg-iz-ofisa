class_name Items
extends RefCounted
## Каталог предметов и таблица наград за взлом.
## Категории (по ТЗ):
##  WEAPON   — оружие: убивает, но шумит;
##  HEAL     — лечение;
##  DISTRACT — только отвлекает (не сбивает с ног);
##  KNOCK    — отвлекает ИЛИ нокаутирует (не убивает);
##  LETHAL   — отвлекает ИЛИ убивает (без нокдауна);
##  MELEE    — холодное оружие (нож, топор): удар вместо кулака; сзади — убивает.
## Правило: выстрел в спину из любого огнестрела убивает. Болтовка убивает любого моба с одного выстрела.
## Болтовка, узи, нож, топор, кастет — только лут с людей (за взлом ПК не выпадают). Труба — из компьютеров.

enum Cat { WEAPON, HEAL, DISTRACT, KNOCK, LETHAL, MELEE, SPECIAL }   # SPECIAL — 0.16: маскировка (потом пакеты), ключ-карта

const CAT_NAMES := {
	Cat.WEAPON: "Оружие", Cat.HEAL: "Лечение", Cat.DISTRACT: "Отвлечение",
	Cat.KNOCK: "Нокаут", Cat.LETHAL: "Смертельное", Cat.MELEE: "Холодное", Cat.SPECIAL: "Особое",
}
const CAT_COLORS := {
	Cat.WEAPON: Color(1.0, 0.55, 0.3), Cat.HEAL: Color(0.45, 1.0, 0.5), Cat.DISTRACT: Color(0.55, 0.8, 1.0),
	Cat.KNOCK: Color(1.0, 0.85, 0.35), Cat.LETHAL: Color(1.0, 0.35, 0.35), Cat.MELEE: Color(0.85, 0.75, 1.0),
	Cat.SPECIAL: Color(1.0, 0.6, 0.85),
}

const DEFS := {
	"pistol": {"name": "Пистолет", "cat": Cat.WEAPON, "desc": "убивает, громко", "amount": 6, "max": 6,
		"dmg": 50, "noise": 16.0, "range": 16.0, "cd": 0.35, "pellets": 1, "spread": 0.03},
	"shotgun": {"name": "Дробовик", "cat": Cat.WEAPON, "desc": "убивает в упор, очень громко", "amount": 4, "max": 4,
		"dmg": 18, "noise": 24.0, "range": 9.0, "cd": 0.9, "pellets": 7, "spread": 0.22},
	"silenced": {"name": "ПБ с глушителем", "cat": Cat.WEAPON, "desc": "убивает тихо", "amount": 5, "max": 5,
		"dmg": 50, "noise": 3.0, "range": 14.0, "cd": 0.45, "pellets": 1, "spread": 0.02},
	"rifle": {"name": "Болтовка", "cat": Cat.WEAPON, "desc": "убивает любого с одного выстрела", "amount": 2, "max": 2,
		"dmg": 999, "noise": 20.0, "range": 24.0, "cd": 1.3, "pellets": 1, "spread": 0.004},
	# 0.15 (пока только вид — у офисников; в награды и лут ещё не входят, числа предварительные):
	"revolver": {"name": "Револьвер", "cat": Cat.WEAPON, "desc": "бьёт сильнее пистолета, громко", "amount": 6, "max": 6,
		"dmg": 80, "noise": 18.0, "range": 16.0, "cd": 0.6, "pellets": 1, "spread": 0.02},
	"nailgun": {"name": "Гвоздомёт", "cat": Cat.WEAPON, "desc": "12 гвоздей, тише и медленнее узи", "amount": 12, "max": 12,
		"dmg": 25, "noise": 6.0, "range": 10.0, "cd": 0.3, "pellets": 1, "spread": 0.05},
	"crossbow": {"name": "Арбалет", "cat": Cat.WEAPON, "desc": "сильный и бесшумный", "amount": 3, "max": 4,
		"dmg": 150, "noise": 1.5, "range": 20.0, "cd": 1.4, "pellets": 1, "spread": 0.004},
	# 0.19: M4A1-S — у элиты на крыше (финал); с глушителем, очередь по 3, тихо
	"m4": {"name": "M4A1-S", "cat": Cat.WEAPON, "desc": "очередь по 3, с глушителем — тихо", "amount": 15, "max": 15,
		"dmg": 30, "noise": 3.0, "range": 18.0, "cd": 0.4, "pellets": 1, "spread": 0.03, "burst": 3},
	"uzi": {"name": "Узи", "cat": Cat.WEAPON, "desc": "очередь по 3 патрона, шумно", "amount": 10, "max": 15,
		"dmg": 20, "noise": 14.0, "range": 12.0, "cd": 0.45, "pellets": 1, "spread": 0.07, "burst": 3},
	# холодное: amount — число УДАРОВ (тратится только при попадании). back/front — что делает удар
	# сзади / спереди: kill — насмерть, knock — вырубает на knock секунд (толстяка — никогда), dmg — урон.
	"knife": {"name": "Нож", "cat": Cat.MELEE, "desc": "тихо; сзади — убивает", "amount": 5, "max": 5,
		"dmg": 25, "noise": 1.5, "cd": 0.45, "reach": 1.4, "swing": 0.3, "back": "kill", "front": "dmg"},
	"axe": {"name": "Пожарный топор", "cat": Cat.MELEE, "desc": "мощно; сзади — убивает", "amount": 3, "max": 3,
		"dmg": 50, "noise": 5.0, "cd": 1.0, "reach": 1.6, "swing": 0.5, "back": "kill", "front": "dmg"},
	"pipe": {"name": "Труба", "cat": Cat.MELEE, "desc": "сзади — оглушает на 2,5 с", "amount": 5, "max": 5,
		"dmg": 20, "noise": 3.0, "cd": 0.6, "reach": 1.5, "swing": 0.35, "back": "knock", "front": "dmg", "knock": 2.5},
	"knuckles": {"name": "Кастет", "cat": Cat.MELEE, "desc": "вырубает любого, кроме толстяка", "amount": 2, "max": 3,
		"dmg": 20, "noise": 1.5, "cd": 0.5, "reach": 1.2, "swing": 0.25, "back": "knock", "front": "knock", "knock": 162.0},
	"coffee": {"name": "Кофе", "cat": Cat.HEAL, "desc": "+25 здоровья", "amount": 1, "max": 2, "heal": 25},
	"medkit": {"name": "Аптечка", "cat": Cat.HEAL, "desc": "+60 здоровья", "amount": 1, "max": 1, "heal": 60},
	"energy": {"name": "Энергетик", "cat": Cat.HEAL, "desc": "+10 и ускорение", "amount": 1, "max": 1, "heal": 10, "boost": 10.0},
	"bottle": {"name": "Бутылка", "cat": Cat.DISTRACT, "desc": "только отвлекает", "amount": 2, "max": 3, "noise": 10.0},
	"alarm": {"name": "Будильник", "cat": Cat.DISTRACT, "desc": "звенит 6 сек, отвлекает", "amount": 1, "max": 2, "noise": 12.0},
	"brick": {"name": "Кирпич", "cat": Cat.KNOCK, "desc": "отвлекает или нокаутирует", "amount": 1, "max": 2, "noise": 9.0, "knock": 9.0},
	"extinguisher": {"name": "Огнетушитель", "cat": Cat.KNOCK, "desc": "облако: нокаут всех рядом", "amount": 1, "max": 1,
		"noise": 12.0, "knock": 8.0, "radius": 2.8},
	"shuriken": {"name": "Сюрикен", "cat": Cat.LETHAL, "desc": "отвлекает или тихо убивает", "amount": 2, "max": 3, "noise": 6.0},
	"grenade": {"name": "Граната", "cat": Cat.LETHAL, "desc": "отвлекает или убивает всех рядом", "amount": 1, "max": 2,
		"noise": 30.0, "radius": 3.3},
	# 0.16: особое — не тратится по ходу, действует до конца этажа. Маскировка — в охраняемой комнате логова.
	"disguise": {"name": "Куртка бандита", "cat": Cat.SPECIAL, "desc": "надень — бандиты примут за своего до конца этажа",
		"amount": 1, "max": 1},
	# ключ-карта логова: в инвентарь не идёт — подобрал, и лифт открыт (game._update_pickups)
	"keycard": {"name": "Ключ-карта", "cat": Cat.SPECIAL, "desc": "открывает лифт логова", "amount": 1, "max": 1},
	# 0.17: пакеты на ноги — из укреплённого офиса; надел — шаги и бег бесшумны до конца этажа
	"bags": {"name": "Пакеты на ноги", "cat": Cat.SPECIAL, "desc": "надень — шаги и бег бесшумны до конца этажа",
		"amount": 1, "max": 1},
	# 0.18: ящик с патронами поля битвы — в инвентарь не идёт: подобрал — всё огнестрельное до потолка
	"ammo": {"name": "Ящик с патронами", "cat": Cat.SPECIAL, "desc": "заряжает всё огнестрельное", "amount": 1, "max": 1},
}
const ORDER := ["crossbow", "m4", "rifle", "revolver", "pistol", "silenced", "uzi", "nailgun", "shotgun", "axe", "knife", "pipe", "knuckles", "shuriken", "grenade", "brick", "extinguisher", "bottle", "alarm", "coffee", "energy", "medkit", "disguise", "bags"]
const THROWN := ["bottle", "alarm", "brick", "extinguisher", "shuriken", "grenade"]
## Можно ли попасть предметом во врага (бутылка и будильник просто летят в точку).
const HITS_ENEMY := ["brick", "extinguisher", "shuriken", "grenade"]

## 0.13 — слоты: в каждом слоте носишь ОДИН вид предмета со своим запасом
## (например, 3 бутылки ИЛИ 2 кирпича). Другой вид в занятый слот — только заменой (старое падает на пол с запасом).
const SLOTS := {
	"pistol": ["pistol", "silenced", "revolver"],
	"throw": ["bottle", "alarm", "brick", "extinguisher"],  # метаемое: отвлечь / нокаут
	"lethal": ["shuriken", "grenade"],                      # смертельное метаемое
	"long": ["uzi", "rifle", "shotgun", "nailgun", "m4"],         # длинноствол
	"crossbow": ["crossbow"],                               # арбалет — отдельный слот
	"melee": ["knife", "axe", "pipe", "knuckles"],          # холодное — одно
	"heal": ["coffee", "medkit", "energy"],                 # лечение — одно
	"special": ["disguise", "bags"],                        # особое — маскировка или пакеты (0.16–0.17)
}
const SLOT_NAMES := {"pistol": "Пистолет", "throw": "Метаемое", "lethal": "Смертельное", "long": "Длинноствол",
	"crossbow": "Арбалет", "melee": "Холодное", "heal": "Лечение", "special": "Особое"}


static func slot_of(id: String) -> String:
	for s in SLOTS:
		if id in SLOTS[s]:
			return s
	return ""


const FLAVOR := ["в ящике стола", "в системном блоке", "под клавиатурой", "в тумбочке",
	"в коробке из-под пиццы", "за монитором", "в папке «Отчёты 2019»", "в кармане пиджака на стуле"]


static func def(id: String) -> Dictionary:
	return DEFS[id]


## Потолок запаса: больше max одного предмета не унести (лишнее остаётся лежать на полу).
static func cap(id: String) -> int:
	return DEFS[id].get("max", 99)


static func icon(id: String) -> Texture2D:
	return OfficeTex.get_tex("i_" + id)


## Случайная награда. Подкручиваем шансы: мало здоровья — чаще лечение, нечем кидаться — чаще отвлечение.
static func roll_reward(rng: RandomNumberGenerator, hp_ratio: float, inv: Dictionary) -> Dictionary:
	var w := {
		"pistol": 12.0, "shotgun": 7.0, "silenced": 3.0,
		"coffee": 7.0, "medkit": 4.2, "energy": 4.2,   # лечение реже (0.6: ×0.7)
		"bottle": 14.0, "alarm": 8.0,
		"brick": 12.0, "extinguisher": 6.0,
		"shuriken": 10.0, "grenade": 6.0,
		"pipe": 9.0,
	}
	if hp_ratio < 0.5:
		for k in ["coffee", "medkit", "energy"]: w[k] *= 1.6
	var throwables := 0
	for k in THROWN: throwables += inv.get(k, 0)
	if throwables < 2:
		for k in ["bottle", "brick", "shuriken"]: w[k] *= 1.8
	var total := 0.0
	for k in w: total += w[k]
	var r := rng.randf() * total
	var id: String = "bottle"
	for k in w:
		r -= w[k]
		if r <= 0.0:
			id = k
			break
	var amount: int = DEFS[id].amount
	if id == "shuriken" and rng.randf() < 0.4: amount += 1
	if id == "bottle" and rng.randf() < 0.3: amount += 1
	return {"id": id, "amount": amount, "flavor": FLAVOR[rng.randi_range(0, FLAVOR.size() - 1)]}
