class_name PieceZone
extends Node2D
## Peça de quebra-cabeça desenhada no campo (habilidade "Pieces" do Isagi).
## Ela só marca uma área e se desenha; quem aplica o efeito é o personagem,
## que pergunta com contains().
##
## Fica logo acima da grama e atrás de jogadores e bola (igual ao PassMarker).

enum Kind { ATTACK, MIDFIELD, DEFENSE }

var kind: Kind = Kind.ATTACK
var size: Vector2 = Vector2(320.0, 380.0)
var color: Color = Color.WHITE
var label: String = ""

## Isagi está em cima desta peça? (acende mais forte)
var highlighted: bool = false:
	set(value):
		if value == highlighted:
			return
		highlighted = value
		queue_redraw()

# Encaixes de cada borda: +1 = pino para fora, -1 = encaixe para dentro, 0 = reta
var knob_top: int = 1
var knob_right: int = 0
var knob_bottom: int = -1
var knob_left: int = 0

var _outline: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	visible = false          # nasce escondida: só aparece quando o Isagi usa o Pieces
	z_index = -4000          # acima do campo (-4096), abaixo de tudo que usa a profundidade pelo y
	z_as_relative = false


func _ready() -> void:
	_outline = _build_outline()
	queue_redraw()


## Mostra a peça com um pequeno efeito de entrada
func appear() -> void:
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.85, 0.85)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.4)
	tw.tween_property(self, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Some com um fade (as rodadas do Pieces acabaram)
func disappear() -> void:
	highlighted = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: visible = false)


## Esconde na hora (partida nova)
func hide_now() -> void:
	visible = false
	highlighted = false


## A posição (global) está dentro da peça? (usa o retângulo; os encaixes são só enfeite)
func contains(global_pos: Vector2) -> bool:
	return Rect2(global_position - size * 0.5, size).has_point(global_pos)


func _draw() -> void:
	if _outline.size() < 3:
		return
	var fill_alpha: float = 0.32 if highlighted else 0.16
	var line_alpha: float = 1.0 if highlighted else 0.7
	draw_colored_polygon(_outline, Color(color, fill_alpha))
	var closed: PackedVector2Array = _outline.duplicate()
	closed.append(_outline[0])
	draw_polyline(closed, Color(color, line_alpha), 3.0)

	if label != "":
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(-size.x * 0.5, 8.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 1, 1, 0.85))


# ---------- FORMATO DE QUEBRA-CABEÇA ----------

## Contorno no sentido horário (topo -> direita -> base -> esquerda), com pino/encaixe
## redondo no meio de cada borda que tiver um.
func _build_outline() -> PackedVector2Array:
	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	var pts := PackedVector2Array()
	pts.append_array(_edge(Vector2(-hw, -hh), Vector2(hw, -hh), Vector2.UP, knob_top))
	pts.append_array(_edge(Vector2(hw, -hh), Vector2(hw, hh), Vector2.RIGHT, knob_right))
	pts.append_array(_edge(Vector2(hw, hh), Vector2(-hw, hh), Vector2.DOWN, knob_bottom))
	pts.append_array(_edge(Vector2(-hw, hh), Vector2(-hw, -hh), Vector2.LEFT, knob_left))
	return pts


## Pontos de a até b (sem repetir b, que é o começo da próxima borda).
## "outward" aponta para fora da peça; knob decide se o meio da borda sai (+1) ou entra (-1).
func _edge(a: Vector2, b: Vector2, outward: Vector2, knob: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var length: float = a.distance_to(b)
	var radius: float = length * 0.14
	var steps: int = 48
	for i in steps:
		var t: float = float(i) / float(steps)
		var off: float = 0.0
		if knob != 0:
			var d: float = (t - 0.5) * length   # distância até o meio da borda
			if absf(d) < radius:
				off = sqrt(radius * radius - d * d) * float(knob)
		pts.append(a.lerp(b, t) + outward * off)
	return pts
