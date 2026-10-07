class_name BLMan
extends Goalkeeper
## BL Man: goleiro adaptável.
##
## PASSIVA (Adaptável): quando o chute está "parelho" com a defesa, ele se adapta e vira o jogo.
## Se a diferença entre a chance do chute e a chance de defesa for de até adapt_threshold
## (10 pontos), o chute perde adapt_bonus (8 pontos) e a defesa ganha o mesmo.
##   Ex: chute 45% x defesa 55% (diferença 10)  ->  chute 37% x defesa 63%
##   Ex: chute 52% x defesa 48% (diferença 4)   ->  chute 44% x defesa 56%
## Chute muito melhor ou muito pior que a defesa (diferença acima do limite) não muda.
## A chance de defesa é sempre 100% - chance do chute.

@export_group("Adaptação")
## Diferença máxima (em pontos) entre chute e defesa para ele se adaptar. É "até": o exemplo
## 45% x 55% tem diferença exatamente 10 e conta.
@export_range(0.0, 1.0) var adapt_threshold: float = 0.10
## Quanto o chute perde (e a defesa ganha) quando ele se adapta
@export_range(0.0, 1.0) var adapt_bonus: float = 0.08


func _init() -> void:
	keeper_id = "bl_man"
	display_name = "BL Man"
	keeper_color = Color(0.82, 0.88, 1.0)


func modify_shot_chance(chance: float, _shot_ball: Ball) -> float:
	var save_chance: float = 1.0 - chance
	# O + 0.001 é por causa do float: 0.55 - 0.45 dá 0.10000000000000003 e ficaria de fora
	if absf(save_chance - chance) <= adapt_threshold + 0.001:
		return maxf(chance - adapt_bonus, 0.0)
	return chance
