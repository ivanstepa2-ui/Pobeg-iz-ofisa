class_name PS1PostFX
extends CanvasLayer
## Полноэкранный пост-эффект: 15-битный цвет + дизеринг. Добавь узел в любую 3D-сцену.
## Рисуется поверх 3D, но под HUD (у HUD слой должен быть выше, например 10+).

@export_range(2.0, 255.0) var color_levels: float = 31.0:
	set(v):
		color_levels = v
		_apply()
@export_range(0.0, 1.0) var dither_strength: float = 1.0:
	set(v):
		dither_strength = v
		_apply()

var _rect: ColorRect


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ps1_post.gdshader")
	_rect.material = mat
	add_child(_rect)
	_apply()


func _apply() -> void:
	if _rect == null:
		return
	var mat := _rect.material as ShaderMaterial
	mat.set_shader_parameter("color_levels", color_levels)
	mat.set_shader_parameter("dither_strength", dither_strength)
