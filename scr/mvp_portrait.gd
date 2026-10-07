class_name MvpPortrait
extends Control
## Imagem do MVP no resumo final: a imagem do personagem (Player.get_mvp_image())
## dentro de uma moldura com a cor do time. Sem imagem, desenha um círculo do time
## com a inicial do nome.

@export var portrait_size: Vector2 = Vector2(160, 160)
@export var pixel_art: bool = false   # true = sem suavização (para pixel art)

var _texture: Texture2D = null
var _color: Color = Color.WHITE
var _initial: String = "?"


func setup(texture: Texture2D, team_color: Color, display_name: String) -> void:
	_texture = texture
	_color = team_color
	_initial = display_name.substr(0, 1).to_upper() if display_name != "" else "?"
	custom_minimum_size = portrait_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size if size != Vector2.ZERO else portrait_size)
	draw_rect(box, Color(0, 0, 0, 0.35))
	draw_rect(box, _color, false, 3.0)

	if _texture != null:
		# Cabe na moldura sem distorcer
		var inner: Rect2 = box.grow(-6.0)
		var factor: float = minf(inner.size.x / _texture.get_width(), inner.size.y / _texture.get_height())
		var draw_size: Vector2 = _texture.get_size() * factor
		draw_texture_rect(_texture, Rect2(inner.position + (inner.size - draw_size) * 0.5, draw_size), false)
		return

	# Sem imagem: círculo do time com a inicial
	var center: Vector2 = box.size * 0.5
	draw_circle(center, box.size.x * 0.32, _color.darkened(0.3))
	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(box.size.x * 0.4)
	var text_size: Vector2 = font.get_string_size(_initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 2.0),
		_initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
