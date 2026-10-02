class_name PassMarker
extends Node2D
## Marca no chão onde o passe alto vai chegar: dois anéis achatados que pulsam de leve.
## Fica logo acima da grama e atrás de jogadores e bola.

var color: Color = Color.WHITE
var radius: float = 22.0

var _t: float = 0.0


func _init() -> void:
	z_index = -4000          # acima do campo (-4096), abaixo de tudo que usa a profundidade pelo y
	z_as_relative = false


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))  # achatado, como a sombra
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(color, 0.35 + 0.35 * pulse), 2.5)
	draw_arc(Vector2.ZERO, radius * 0.5, 0.0, TAU, 32, Color(color, 0.25), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
