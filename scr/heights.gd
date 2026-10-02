class_name Heights
extends RefCounted
## Níveis de altura do jogo. Valores são "exemplo": ajuste as constantes
## abaixo para o tamanho que ficar bom na sua tela.
##
##   GROUND    (0)   -> no chão
##   SUSPENDED (+50) -> suspenso (bola chutada, jogador que pulou)
##   FLYING    (+100)-> voando (bola em situações específicas)
##
## Regra de alcance: duas coisas interagem se estão no mesmo nível ou em
## níveis vizinhos. Chão alcança chão e suspenso; suspenso alcança
## chão, suspenso e voando; voando alcança suspenso e voando.

enum Level { GROUND, SUSPENDED, FLYING }

const GROUND_HEIGHT: float = 0.0
const SUSPENDED_HEIGHT: float = 50.0
const FLYING_HEIGHT: float = 100.0


static func to_height(level: Level) -> float:
	match level:
		Level.SUSPENDED:
			return SUSPENDED_HEIGHT
		Level.FLYING:
			return FLYING_HEIGHT
	return GROUND_HEIGHT


## Converte uma altura contínua (ex: a da bola) no nível mais próximo
static func from_height(h: float) -> Level:
	if h < (GROUND_HEIGHT + SUSPENDED_HEIGHT) * 0.5:
		return Level.GROUND
	if h < (SUSPENDED_HEIGHT + FLYING_HEIGHT) * 0.5:
		return Level.SUSPENDED
	return Level.FLYING


## Níveis iguais ou vizinhos conseguem interagir
static func can_reach(a: Level, b: Level) -> bool:
	return absi(a - b) <= 1


static func level_name(level: Level) -> String:
	match level:
		Level.SUSPENDED:
			return "Suspenso"
		Level.FLYING:
			return "Voando"
	return "Chão"


## Velocidade vertical inicial para a bola atingir um pico de altura
static func lift_for_peak(peak_height: float, gravity: float) -> float:
	return sqrt(2.0 * gravity * peak_height)
