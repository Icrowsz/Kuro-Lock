class_name Renoir
extends Goalkeeper
## Renoir: goleiro de área grande e lançamento longo.
##
## PASSIVAS
## - Área de defesa maior: ele salta em bolas que ainda estão FORA da grande área (cresce
##   area_extra_depth em direção ao meio do campo e area_extra_side para os lados).
## - Lançamento maior: throw_range (o padrão é 900).
## - Vantagem contra chute com a bola suspensa: a chance do chute cai suspended_shot_penalty
##   (8 pontos). "Suspensa" = a bola está no nível Suspenso (Heights) no momento em que o
##   chute entra na área de defesa dele.
##
## Os números da área e do lançamento ficam no _init (é a forma de mudar o padrão de um
## export herdado). Ajuste ali.

@export_group("Renoir")
## Quanto o chute com a bola suspensa perde de chance
@export_range(0.0, 1.0) var suspended_shot_penalty: float = 0.08


func _init() -> void:
	keeper_id = "renoir"
	display_name = "Renoir"
	keeper_color = Color(1.0, 0.93, 0.72)
	area_extra_depth = 110.0   # a grande área tem 220 de profundidade: fica com 330
	area_extra_side = 70.0     # e 480 de largura: fica com 620
	throw_range = 1300.0       # o campo tem 1600 de comprimento


func modify_shot_chance(chance: float, shot_ball: Ball) -> float:
	if shot_ball.get_level() == Heights.Level.SUSPENDED:
		return maxf(chance - suspended_shot_penalty, 0.0)
	return chance
