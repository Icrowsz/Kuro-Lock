class_name TeamStyle
extends RefCounted
## Nome e cor de cada time. É daqui que o jogo inteiro (jogadores, goleiros, placar, menus)
## lê a cor do time, para a escolha feita na tela de formação valer em todo lugar.
##
## Os valores escolhidos ficam guardados enquanto o jogo está aberto (inclusive se a cena
## for recarregada); ao fechar e abrir o jogo, volta tudo ao padrão.

const MAX_NAME_LENGTH: int = 14

## Cor padrão de cada time (índice = número do time)
const DEFAULT_COLORS: Array[Color] = [
	Color(0.9, 0.22, 0.27),   # Time 0: vermelho
	Color(0.11, 0.44, 0.88),  # Time 1: azul
]

## Cores que dá para escolher na formação (nenhuma verde, para não sumir no gramado)
const PALETTE: Array[Dictionary] = [
	{"name": "Vermelho", "color": Color(0.9, 0.22, 0.27)},
	{"name": "Azul", "color": Color(0.11, 0.44, 0.88)},
	{"name": "Amarelo", "color": Color(0.98, 0.82, 0.18)},
	{"name": "Laranja", "color": Color(0.97, 0.52, 0.15)},
	{"name": "Roxo", "color": Color(0.58, 0.33, 0.85)},
	{"name": "Ciano", "color": Color(0.12, 0.78, 0.85)},
	{"name": "Rosa", "color": Color(0.95, 0.45, 0.70)},
	{"name": "Branco", "color": Color(0.96, 0.96, 0.96)},
]

static var _colors: Dictionary = {}   # time -> cor escolhida
static var _names: Dictionary = {}    # time -> nome escolhido


static func color_of(team: int) -> Color:
	if _colors.has(team):
		return _colors[team]
	return DEFAULT_COLORS[team % DEFAULT_COLORS.size()]


static func set_color(team: int, color: Color) -> void:
	_colors[team] = color


## Nome escolhido pelo jogador, ou "fallback" (o nome padrão do MatchManager) se não escolheu
static func name_of(team: int, fallback: String) -> String:
	return _names.get(team, fallback)


## Texto vazio = volta ao nome padrão
static func set_team_name(team: int, text: String) -> void:
	var clean: String = text.strip_edges()
	if clean == "":
		_names.erase(team)
	else:
		_names[team] = clean.substr(0, MAX_NAME_LENGTH)


## Há nome escolhido para este time? (a tela de formação usa para preencher o campo)
static func has_custom_name(team: int) -> bool:
	return _names.has(team)
