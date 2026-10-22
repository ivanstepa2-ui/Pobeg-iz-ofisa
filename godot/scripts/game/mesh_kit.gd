class_name MeshKit
extends RefCounted
## Сборщик low-poly геометрии: квады и коробки с UV на всю текстуру,
## вершинный цвет = запечённый свет. Одна поверхность на текстуру.

## Грани коробки: ключ, нормаль, углы (низ-лево, низ-право, верх-право, верх-лево снаружи), отражать U.
const BOX_FACES := [
	["f", Vector3(0, 0, 1), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)], false],
	["b", Vector3(0, 0, -1), [Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)], false],
	["r", Vector3(1, 0, 0), [Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)], false],
	["l", Vector3(-1, 0, 0), [Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)], true],
	["t", Vector3(0, 1, 0), [Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)], false],
	["d", Vector3(0, -1, 0), [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)], false],
]
## Направление сетки (0=-z,1=+x,2=+z,3=-x) -> грань AABB.
const FACE_KEY := ["b", "r", "f", "l"]
const CUTOUT := {"leaves": true, "papers": true, "stain": true, "clock": true, "i_extinguisher": true,
	"graffiti1": true, "graffiti2": true, "graffiti3": true, "helipad": true}   # 0.16: граффити логова; 0.19: площадка

var surf: Dictionary = {}
var _white := Color(0.62, 0.62, 0.62, 1.0)


func _st(tex: String) -> SurfaceTool:
	if not surf.has(tex):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surf[tex] = st
	return surf[tex]


func quad(tex: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, flip_u: bool = false,
		uv0: Vector2 = Vector2.ZERO, uv1: Vector2 = Vector2.ONE) -> void:
	var st := _st(tex)
	var u0 := uv1.x if flip_u else uv0.x
	var u1 := uv0.x if flip_u else uv1.x
	var verts := [[a, Vector2(u0, uv1.y), ca], [b, Vector2(u1, uv1.y), cb], [c, Vector2(u1, uv0.y), cc],
		[a, Vector2(u0, uv1.y), ca], [c, Vector2(u1, uv0.y), cc], [d, Vector2(u0, uv0.y), cd]]
	for v in verts:
		st.set_color(v[2])
		st.set_uv(v[1])
		st.add_vertex(v[0])


## Квад одного цвета.
func quad_flat(tex: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	quad(tex, a, b, c, d, col, col, col, col)


## Коробка: xf — трансформ, center/half — в локальных координатах.
## faces: {"f","b","r","l","t","d"} -> имя текстуры (нет ключа — грань не рисуется).
## light: Callable(pos: Vector3, normal: Vector3) -> Color, либо null (тогда цвет flat).
## v_range — какая часть текстуры по вертикали идёт на боковые грани (для ноги из двух частей: бедро/голень).
func box(xf: Transform3D, center: Vector3, half: Vector3, faces: Dictionary, light = null, flat: Color = Color(0.62, 0.62, 0.62),
		v_range: Vector2 = Vector2(0, 1)) -> void:
	for F in BOX_FACES:
		if not faces.has(F[0]):
			continue
		var n: Vector3 = (xf.basis * F[1]).normalized()
		var P: Array = []
		var C: Array = []
		for s in F[2]:
			var p: Vector3 = xf * (center + s * half)
			P.append(p)
			C.append(light.call(p, n) if light != null else flat)
		var side: bool = F[0] in ["f", "b", "l", "r"]
		var uv0 := Vector2(0, v_range.x) if side else Vector2.ZERO
		var uv1 := Vector2(1, v_range.y) if side else Vector2.ONE
		quad(faces[F[0]], P[0], P[1], P[2], P[3], C[0], C[1], C[2], C[3], F[3], uv0, uv1)


func aabb(p0: Vector3, p1: Vector3, faces: Dictionary, light = null, flat: Color = Color(0.62, 0.62, 0.62)) -> void:
	box(Transform3D.IDENTITY, (p0 + p1) * 0.5, (p1 - p0) * 0.5, faces, light, flat)


static func all_faces(tex: String, top: String = "", bottom: bool = false) -> Dictionary:
	var f := {"f": tex, "b": tex, "r": tex, "l": tex, "t": top if top != "" else tex}
	if bottom:
		f["d"] = tex
	return f


func is_empty() -> bool:
	return surf.is_empty()


## Собрать ArrayMesh; материалы — общие из кэша PS1Material (unshaded, свет в вершинах).
func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var texs: Array = []
	for tex in surf.keys():
		var st: SurfaceTool = surf[tex]
		st.commit(mesh)
		var i := mesh.get_surface_count() - 1
		mesh.surface_set_material(i, PS1Material.create(OfficeTex.get_tex(tex), Color.WHITE, Vector2.ONE, CUTOUT.has(tex), true))
		texs.append(tex)
	mesh.set_meta("texs", texs)
	return mesh
