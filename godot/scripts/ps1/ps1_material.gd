class_name PS1Material
extends RefCounted
## Фабрика PS1-материалов. Все материалы игры создаются через неё,
## чтобы настройки дрожания/аффинности были одинаковыми во всей игре.

const SHADER_OPAQUE: Shader = preload("res://shaders/ps1.gdshader")
const SHADER_CUTOUT: Shader = preload("res://shaders/ps1_cutout.gdshader")
const SHADER_UNSHADED: Shader = preload("res://shaders/ps1_unshaded.gdshader")
const SHADER_UNSHADED_CUTOUT: Shader = preload("res://shaders/ps1_unshaded_cutout.gdshader")

## Кэш, чтобы одинаковые материалы не плодились (меньше draw-call'ов и памяти).
static var _cache: Dictionary = {}
## Все материалы, включая уникальные (для глобальных настроек).
static var _all: Array[ShaderMaterial] = []
static var snap := 1.0
static var affine := 1.0


static func create(texture: Texture2D, tint: Color = Color.WHITE, uv_scale: Vector2 = Vector2.ONE,
		cutout: bool = false, unshaded: bool = false) -> ShaderMaterial:
	var key := [texture.get_rid() if texture else RID(), tint, uv_scale, cutout, unshaded]
	if _cache.has(key):
		return _cache[key]
	var mat := create_unique(texture, tint, uv_scale, cutout, unshaded)
	_cache[key] = mat
	return mat


## Отдельный экземпляр (например, персонажам с собственным тинтом освещения).
static func create_unique(texture: Texture2D, tint: Color = Color.WHITE, uv_scale: Vector2 = Vector2.ONE,
		cutout: bool = false, unshaded: bool = false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if unshaded:
		mat.shader = SHADER_UNSHADED_CUTOUT if cutout else SHADER_UNSHADED
	else:
		mat.shader = SHADER_CUTOUT if cutout else SHADER_OPAQUE
	mat.set_shader_parameter("albedo_texture", texture)
	mat.set_shader_parameter("albedo_color", tint)
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("snap_strength", snap)
	mat.set_shader_parameter("affine_strength", affine)
	_all.append(mat)
	return mat


static func release(mat: ShaderMaterial) -> void:
	_all.erase(mat)


## Глобальная «сила» PS1-эффекта (для меню настроек: кому-то дрожание мешает).
static func set_global_strength(snap_v: float, affine_v: float) -> void:
	snap = snap_v
	affine = affine_v
	for mat in _all:
		mat.set_shader_parameter("snap_strength", snap)
		mat.set_shader_parameter("affine_strength", affine)


## Пиксельная текстура-шахматка — заглушка.
static func make_checker(a: Color, b: Color, size: int = 32, cell: int = 8) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([a, b, size])
	for y in size:
		for x in size:
			var c := a if (int(x / cell) + int(y / cell)) % 2 == 0 else b
			var n := rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n))
	return ImageTexture.create_from_image(img)
