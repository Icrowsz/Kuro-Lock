class_name Fukaku
extends Goalkeeper
## Fukaku: goleiro que escolhe o lançamento e é forte contra chute rasteiro.
##
## PASSIVAS
## - Lançamento dirigido: em vez de sortear um aliado, o jogador do time dele ESCOLHE para
##   quem lançar (clique num companheiro dentro do alcance; clique direito ou Esc sorteia).
##   Com 0 ou 1 aliado ao alcance, não pergunta.
## - Vantagem contra chute com a bola no chão: a chance do chute cai ground_shot_penalty
##   (6 pontos). "No chão" = nível Chão (Heights) quando o chute entra na área dele.

@export_group("Fukaku")
## Quanto o chute com a bola no chão perde de chance
@export_range(0.0, 1.0) var ground_shot_penalty: float = 0.06


func _init() -> void:
	keeper_id = "fukaku"
	display_name = "Fukaku"
	keeper_color = Color(0.7, 1.0, 0.75)


func modify_shot_chance(chance: float, shot_ball: Ball) -> float:
	if shot_ball.get_level() == Heights.Level.GROUND:
		return maxf(chance - ground_shot_penalty, 0.0)
	return chance


func lets_player_pick_throw() -> bool:
	return manager != null and _allies_in_range().size() > 1


func _ask_throw_target() -> Player:
	_waiting_for_player = true
	_say("%s: escolha para quem lançar a bola!" % _keeper_label())
	var picked: Player = await manager.pick_throw_target(self, throw_range)
	_waiting_for_player = false
	return picked


func _allies_in_range() -> Array[Player]:
	var result: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team and global_position.distance_to(p.global_position) <= throw_range:
			result.append(p)
	return result
