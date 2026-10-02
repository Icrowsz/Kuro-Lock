class_name Formations
extends RefCounted
## Formações prontas e as contas para posicionar um time na sua metade do campo.
##
## Notação: números separados por "-", da PRÓPRIA DEFESA para o ataque (jogadores de linha,
## sem o goleiro). "1-2-2" = 1 defensor, 2 meias e 2 atacantes.
##
## Para criar ou trocar formações, edite só a tabela PRESETS (a chave é quantos jogadores
## de linha o time tem). Quem tem um número de jogadores que não está na tabela recebe
## uma formação automática.

const PRESETS := {
	3: ["2-1", "1-1-1"],
	4: ["1-1-2", "1-2-1"],
	5: ["1-2-2", "2-1-2", "2-2-1"],
	6: ["2-3-1", "3-2-1", "2-2-2", "1-3-2", "3-1-2", "2-1-2-1"],
	# 8x8: goleiro + 7 jogadores de linha
	7: ["3-3-1", "2-3-2", "3-2-2", "2-4-1", "4-2-1", "2-2-3", "3-1-2-1"],
}

## Apelido de cada formação (aparece ao passar o mouse no botão)
const NICKNAMES := {
	"2-3-1": "Meio-campo povoado",
	"3-2-1": "Defensiva, um atacante",
	"2-2-2": "Quadrado equilibrado",
	"1-3-2": "Ofensiva",
	"3-1-2": "Defesa forte e dois atacantes",
	"2-1-2-1": "Losango",
	"3-3-1": "Equilibrada",
	"2-3-2": "Ofensiva equilibrada",
	"3-2-2": "Defesa sólida, dois atacantes",
	"2-4-1": "Meio-campo forte",
	"4-2-1": "Retranca",
	"2-2-3": "Ataque total",
	"3-1-2-1": "Losango com três na defesa",
}

## Onde ficam a primeira e a última linha, como fração da metade do campo contada a partir
## da linha de fundo do time (0.3 = 30% do caminho até o meio).
const DEPTH_FIRST := 0.30
const DEPTH_LAST := 0.80

## Folga (px) para o jogador não ficar em cima da linha de fundo, da lateral ou do meio-campo
const EDGE_MARGIN := 40.0


## Lista de formações para um time com esse número de jogadores de linha
static func presets_for(player_count: int) -> Array[String]:
	var result: Array[String] = []
	if PRESETS.has(player_count):
		for f in PRESETS[player_count]:
			result.append(f)
	else:
		result.append(_auto_formation(player_count))
	return result


## Apelido da formação (vazio se não tiver)
static func nickname(formation: String) -> String:
	return NICKNAMES.get(formation, "")


## Formação automática: distribui em linhas de até 2 jogadores (sobra vai para a defesa)
static func _auto_formation(count: int) -> String:
	var parts: PackedStringArray = []
	var left: int = count
	while left > 0:
		var n: int = mini(2, left)
		parts.append(str(n))
		left -= n
	return "-".join(parts)


static func parse(formation: String) -> Array[int]:
	var lines: Array[int] = []
	for s in formation.split("-"):
		if s.is_valid_int() and int(s) > 0:
			lines.append(int(s))
	return lines


## Posições (GLOBAIS) dos espaços da formação para o time, na ordem defesa -> ataque.
## Time 0 defende o gol da esquerda e o time 1, o da direita (igual ao Field).
static func slots(formation: String, team: int, field: Field) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var lines: Array[int] = parse(formation)
	if lines.is_empty():
		return result

	var half: Vector2 = field.pitch_size * 0.5
	var dir: float = -1.0 if team == 0 else 1.0

	for i in lines.size():
		var t: float = 0.5 if lines.size() == 1 else float(i) / float(lines.size() - 1)
		var depth: float = lerpf(DEPTH_FIRST, DEPTH_LAST, t)
		var x: float = dir * half.x * (1.0 - depth)

		var n: int = lines[i]
		var half_span: float = minf(half.y * (0.30 + 0.20 * float(n - 1)), half.y * 0.8)
		for k in n:
			var y: float = 0.0 if n == 1 else lerpf(-half_span, half_span, float(k) / float(n - 1))
			result.append(field.to_global(Vector2(x, y)))
	return result


## Retângulo (coordenadas LOCAIS do campo) em que o time pode posicionar seus jogadores:
## a própria metade do campo, com uma folga nas bordas.
static func team_area(team: int, field: Field) -> Rect2:
	var half: Vector2 = field.pitch_size * 0.5
	var x0: float = -half.x + EDGE_MARGIN if team == 0 else EDGE_MARGIN
	var x1: float = -EDGE_MARGIN if team == 0 else half.x - EDGE_MARGIN
	return Rect2(x0, -half.y + EDGE_MARGIN, x1 - x0, (half.y - EDGE_MARGIN) * 2.0)


## Distribui os jogadores pelos espaços: cada espaço (em ordem) fica com o jogador livre
## mais próximo, para ninguém atravessar o campo à toa. Devolve {Player: posição global}.
static func assign(players: Array[Player], slot_positions: Array[Vector2]) -> Dictionary:
	var free: Array[Player] = players.duplicate()
	var result := {}
	for s in slot_positions:
		if free.is_empty():
			break
		var best: Player = free[0]
		for p in free:
			if p.global_position.distance_to(s) < best.global_position.distance_to(s):
				best = p
		result[best] = s
		free.erase(best)
	return result
