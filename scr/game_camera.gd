class_name GameCamera
extends Camera2D
## Câmera do jogo. Anexe este script ao nó Camera2D da cena Main.
##
## - Clicou num jogador do time da vez (e ele virou o jogador que vai agir): a câmera dá zoom
##   nele e ACOMPANHA a jogada (corrida, carrinho...). Quando a bola sai em velocidade, a
##   câmera passa a seguir a bola, para dar para ver o chute.
## - Tecla C: volta ao enquadramento normal. Apertar C de novo volta ao jogador.
## - Volta sozinha ao normal quando o turno acaba, quando sai gol e quando a partida começa.
## - Na escolha do alvo do Passe o zoom abre um pouco, para dar para ver os companheiros.
##
## Não mexe em nada do MatchManager: só escuta o sinal `clicked` dos jogadores e lê
## active_player / phase / turn_ended / goal_scored do MatchManager.

const ACTION_TOGGLE: StringName = &"toggle_camera"

## Zoom ao focar, em múltiplos do zoom normal da câmera (1.6 = 60% mais perto)
@export var focus_zoom: float = 1.8
## Zoom enquanto escolhe o alvo do Passe
@export var pass_target_zoom: float = 1.15
## Velocidade da transição (maior = mais rápido)
@export var smooth_speed: float = 6.0
## Segue a bola quando ela sai em velocidade durante a jogada
@export var follow_ball_in_motion: bool = true
@export var ball_speed_threshold: float = 120.0
## Não deixa a câmera mostrar muito além do campo (a borda de fora do campo, em px)
@export var clamp_to_field: bool = true
@export var field_margin: float = 150.0

var _home_position: Vector2
var _home_zoom: Vector2
var _focused: bool = false
var _manager: MatchManager = null


func _ready() -> void:
	_ensure_input_map()
	_home_position = global_position
	_home_zoom = zoom
	_setup.call_deferred()   # o MatchManager e os jogadores entram na árvore no mesmo frame


## Cria a ação "toggle_camera" (tecla C) caso você ainda não tenha criado no InputMap
static func _ensure_input_map() -> void:
	if InputMap.has_action(ACTION_TOGGLE):
		return
	InputMap.add_action(ACTION_TOGGLE)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_C
	InputMap.action_add_event(ACTION_TOGGLE, ev)


func _setup() -> void:
	_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if _manager:
		_manager.turn_ended.connect(_on_reset)
		_manager.goal_scored.connect(_on_reset)
		_manager.match_started.connect(_on_reset)
		_manager.formation_started.connect(_on_reset)

	for p: Player in get_tree().get_nodes_in_group("players"):
		_watch(p)
	get_tree().node_added.connect(_on_node_added)   # jogadores criados depois (troca de formação)


func _on_node_added(node: Node) -> void:
	if node is Player:
		_watch.call_deferred(node)


func _watch(p: Player) -> void:
	if is_instance_valid(p) and not p.clicked.is_connected(_on_player_clicked):
		p.clicked.connect(_on_player_clicked)


func _on_reset(_arg = null) -> void:
	_focused = false


func _on_player_clicked(player: Player) -> void:
	# Espera o MatchManager tratar o clique primeiro: só foca se o jogador virou o que vai agir
	await get_tree().process_frame
	if _manager == null or not is_instance_valid(player):
		return
	if _manager.active_player == player and player.team == _manager.current_team:
		_focused = true


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION_TOGGLE) or event.is_echo():
		return
	if _minigame_running():
		return   # QTE / jogo de digitar usam o teclado: não rouba a tecla
	if _focused:
		_focused = false
	elif _manager != null and _manager.active_player != null:
		_focused = true


## Tem um QTE ou o jogo de digitar rodando agora? (eles são filhos do MatchManager)
func _minigame_running() -> bool:
	if _manager == null:
		return false
	for child in _manager.get_children():
		if child is QTE or child is TypingGame:
			return true
	return false


func _process(delta: float) -> void:
	var target_pos: Vector2 = _home_position
	var target_zoom: Vector2 = _home_zoom

	if _focused:
		var actor: Player = _manager.active_player if _manager else null
		if actor == null or not is_instance_valid(actor) \
				or _manager.phase == MatchManager.Phase.MATCH_OVER:
			_focused = false
		else:
			var z: float = focus_zoom
			if _manager.phase == MatchManager.Phase.CHOOSING_PASS_TARGET:
				z = pass_target_zoom
			target_zoom = _home_zoom * z
			target_pos = actor.global_position + Vector2(0.0, -actor.height * 0.5)
			# Bola saindo em velocidade (chute, passe): acompanha ela
			if follow_ball_in_motion and _manager.phase == MatchManager.Phase.EXECUTING:
				var ball := get_tree().get_first_node_in_group("ball") as Ball
				if ball != null and not ball.is_held() and _ball_is_moving(ball):
					target_pos = ball.global_position + Vector2(0.0, -ball.height * 0.5)
			if clamp_to_field:
				target_pos = _clamp_to_field(target_pos, target_zoom)

	var t: float = 1.0 - exp(-smooth_speed * delta)   # suavização independente do FPS
	global_position = global_position.lerp(target_pos, t)
	zoom = zoom.lerp(target_zoom, t)


func _ball_is_moving(ball: Ball) -> bool:
	return ball.velocity.length() > ball_speed_threshold \
		or (not ball.hovering and ball.height > 1.0)


## Mantém a janela da câmera dentro do campo (+ margem). Se a janela é maior que o campo,
## centraliza no campo.
func _clamp_to_field(pos: Vector2, for_zoom: Vector2) -> Vector2:
	var field := get_tree().get_first_node_in_group("field") as Field
	if field == null:
		return pos
	var half_view: Vector2 = get_viewport_rect().size / for_zoom * 0.5
	var half_field: Vector2 = field.pitch_size * 0.5 + Vector2(field_margin, field_margin)
	var center: Vector2 = field.global_position
	var limit := Vector2(maxf(half_field.x - half_view.x, 0.0), maxf(half_field.y - half_view.y, 0.0))
	return Vector2(
		center.x + clampf(pos.x - center.x, -limit.x, limit.x),
		center.y + clampf(pos.y - center.y, -limit.y, limit.y))
