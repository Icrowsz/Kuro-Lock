class_name Gagamaru
extends Goalkeeper
## Gagamaru: goleiro com armazenamento de defesa.
##
## PASSIVA (Armazenamento): ele tem uma reserva de max_storage (48 pontos). A cada chute gasta
## spend_per_shot (8) da reserva para derrubar a chance do chute:
##   chute 50% x defesa 50%  ->  chute 42% x defesa 58%   (reserva 48 -> 40)
## Cada chute DEFENDIDO devolve recover_per_save (4) à reserva, até o máximo. Se restar menos que
## 8, gasta só o que tem; reserva zerada = sem efeito. Recomeça cheia a cada partida.
## A reserva aparece numa barra em cima do goleiro.

@export_group("Armazenamento")
@export_range(0.0, 1.0) var max_storage: float = 0.48
## Quanto gasta por chute (some da reserva e do chute)
@export_range(0.0, 1.0) var spend_per_shot: float = 0.08
## Quanto recupera a cada chute defendido
@export_range(0.0, 1.0) var recover_per_save: float = 0.04

var storage: float = 0.48:
	set(value):
		storage = clampf(value, 0.0, max_storage)
		queue_redraw()


func _init() -> void:
	keeper_id = "gagamaru"
	display_name = "Gagamaru"
	keeper_color = Color(0.85, 0.7, 1.0)
	storage = max_storage


func modify_shot_chance(chance: float, _shot_ball: Ball) -> float:
	# Não gasta mais do que a reserva tem, nem mais do que o chute tem para perder
	var spend: float = minf(spend_per_shot, minf(storage, chance))
	if spend <= 0.0:
		return chance
	storage -= spend
	return chance - spend


func on_shot_resolved(beaten: bool) -> void:
	if not beaten:
		storage += recover_per_save


func contest_note() -> String:
	return "reserva %d%%" % int(round(storage * 100.0))


func reset_for_new_match() -> void:
	storage = max_storage


func _draw() -> void:
	super()
	# Barra da reserva em cima da cabeça
	var w: float = 46.0
	var pos := Vector2(-w * 0.5, -height - _visual_top() - 14.0)
	var frac: float = storage / max_storage if max_storage > 0.0 else 0.0
	draw_rect(Rect2(pos, Vector2(w, 6.0)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(pos, Vector2(w * frac, 6.0)), Color(0.45, 0.85, 1.0))
	draw_rect(Rect2(pos, Vector2(w, 6.0)), Color(1, 1, 1, 0.8), false, 1.0)
