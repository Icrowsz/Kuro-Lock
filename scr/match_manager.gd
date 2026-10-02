class_name MatchManager
extends Node
## Controla ações < turnos < rodadas.
##
## - Rodada: todos os times jogam um turno (começa pelo "starting_team").
## - Turno: um time escolhe o Protagonista e gasta as ações disponíveis.
## - Ações: Protagonista tem gerais + habilidade próprias; os Secundários
##   dividem entre o time inteiro uma pool de ações gerais + habilidade.

signal state_changed
signal turn_started(team: int)
signal turn_ended(team: int)
signal round_started(round_number: int)
signal round_ended(round_number: int)
## Gol marcado. goal = {order, team, scorer, assist, own_goal, round}
signal goal_scored(goal: Dictionary)
signal match_ended(winner: int)
## Aviso de algo que o goleiro fez (defesa, lançamento...). O HUD mostra o texto.
signal keeper_event(text: String, team: int)
## Montagem das formações começou (a primeira vez e a cada vez que a partida recomeça)
signal formation_started
## Formações confirmadas: a partida vai começar
signal match_started

enum Phase {
	CHOOSING_PROTAGONIST,
	CHOOSING_ACTION,
	AIMING,
	EXECUTING,
	CHOOSING_PASS_VARIANT,  # Passe: escolhendo Rasteiro ou Alto
	CHOOSING_PASS_TARGET,   # Passe: clicando no companheiro que recebe
	MATCH_OVER,             # Fim de jogo: alguém fez os gols necessários
	KEEPERS_ACTING,         # Entre turnos: os goleiros estão agindo sozinhos
	FORMATION,              # Antes da partida: cada time monta a própria formação
}
enum PassVariant { GROUND, HIGH }
## Passe alto em andamento: NONE -> FLYING (pairando no nível Voando) -> RECEIVED (Suspenso, no alvo)
enum PassStage { NONE, FLYING, RECEIVED }
## STAND_UP (Levantar) é temporária: só aparece para jogadores derrubados
enum GeneralAction { RUN, JUMP, SLIDE, SHOOT, PASS, STAND_UP }

const GENERAL_ACTION_NAMES := {
	GeneralAction.RUN: "Correr",
	GeneralAction.JUMP: "Pular",
	GeneralAction.SLIDE: "Carrinho",
	GeneralAction.SHOOT: "Chutar",
	GeneralAction.PASS: "Passe",
	GeneralAction.STAND_UP: "Levantar",
}

const PASS_VARIANT_NAMES := {
	PassVariant.GROUND: "Passe rasteiro",
	PassVariant.HIGH: "Passe alto",
}

@export_group("Partida")
@export var team_count: int = 2
@export var starting_team: int = 0
@export var team_names: Array[String] = ["Vermelho", "Azul"]
@export var auto_stand_up_rounds: int = 2   # derrubado levanta sozinho depois de tantas rodadas
@export var goals_to_win: int = 3           # quem fizer esse número de gols primeiro vence
@export var show_score_hud: bool = true     # cria sozinho o placar, o aviso de gol e o resumo final
@export var keeper_wait_timeout: float = 8.0   # trava de segurança: máximo que o jogo espera os goleiros

@export_group("Formações")
@export var use_formation_setup: bool = true          # antes da partida, cada time monta e confirma a formação
@export var reset_positions_after_goal: bool = true   # depois de um gol, todo mundo volta à posição da formação
@export var reposition_time: float = 0.8              # quanto tempo os jogadores levam para voltar (0 = na hora)

@export_group("Ações do Protagonista")
@export var protagonist_general_actions: int = 2
@export var protagonist_skill_actions: int = 1

@export_group("Ações dos Secundários (divididas pelo time)")
@export var secondary_general_actions: int = 1
@export var secondary_skill_actions: int = 1

@export_group("Chutar - QTE")
@export var volley_qte_keys: int = 3                  # voleio: quantas teclas
@export var volley_qte_time_per_key: float = 0.9      # voleio: segundos por tecla
@export var flying_qte_keys: int = 5                  # bola voando: mais teclas...
@export var flying_qte_time_per_key: float = 0.6      # ...menos tempo (e teclas extras no pool)

@export_group("Passe")
@export var ground_pass_range: float = 400.0           # alcance do passe rasteiro (px)
@export var high_pass_range: float = 500.0             # alcance do passe alto (um pouco maior)
@export var ground_pass_speed: float = 700.0           # velocidade do passe rasteiro (px/s)
@export var ground_pass_intercept_radius: float = 30.0 # inimigo a esta distância da bola intercepta
@export var high_pass_flight_time: float = 0.9         # tempo da bola até subir ao nível Voando
@export var high_pass_arrive_time: float = 0.4         # tempo da descida até o alvo (nível Suspenso)

var round_number: int = 0
var turns_played: int = 0
var current_team: int = 0
var phase: Phase = Phase.CHOOSING_PROTAGONIST

## Placar e histórico de gols (na ordem em que aconteceram).
## Cada gol: {order, team, scorer, assist, own_goal, round} — nomes guardados como texto.
var scores: Array[int] = []
var goal_log: Array[Dictionary] = []
var match_over: bool = false
var winner: int = -1

## Passe em escolha (lido pelo menu) e passe alto em andamento
var pass_variant: PassVariant = PassVariant.GROUND
var pass_hint: String = ""   # aviso na escolha do alvo (ex: "fora do alcance")
var _pass_stage: PassStage = PassStage.NONE
var _pass_team: int = -1
var _pass_target: Player = null
var _pass_origin: Vector2 = Vector2.ZERO      # onde estava quem passou (o alcance é medido daqui)
var _pass_aim_point: Vector2 = Vector2.ZERO   # onde o alvo estava quando o passe saiu
var _pass_marker: PassMarker = null

var protagonist: Player = null
var active_player: Player = null   # quem vai executar a próxima ação

## Os jogadores estão voltando às posições depois de um gol (ninguém age nesse intervalo)
var _repositioning: bool = false

var protagonist_general_left: int = 0
var protagonist_skill_left: int = 0
var secondary_general_left: int = 0
var secondary_skill_left: int = 0


func _ready() -> void:
	add_to_group("match_manager")  # os goleiros encontram o manager por aqui
	# Adia um frame para garantir que todos os jogadores já entraram no grupo
	_setup.call_deferred()


func _setup() -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		register_player(p)

	scores.resize(team_count)
	scores.fill(0)

	var field := get_tree().get_first_node_in_group("field") as Field
	if field:
		field.goal_scored.connect(_on_goal_scored)
		field.ball_reset_after_goal.connect(_on_ball_reset_after_goal)
	else:
		push_warning("MatchManager: nenhum Field encontrado; os gols não serão contados.")

	if show_score_hud:
		var hud := ScoreHud.new()
		hud.manager = self
		add_child(hud)

	if use_formation_setup:
		await _run_formation()
	else:
		_save_home_positions()  # sem tela de formação: vale a posição em que os jogadores estão na cena
	_start_match()


# ---------- FORMAÇÕES ----------

## Liga um jogador ao manager (clique para escolher). A tela de formação chama isto
## quando troca um personagem por outro, porque o jogador novo nasce depois do _setup.
func register_player(p: Player) -> void:
	if not p.clicked.is_connected(_on_player_clicked):
		p.clicked.connect(_on_player_clicked)


## Abre a tela de formação e espera todos os times confirmarem
func _run_formation() -> void:
	_set_phase(Phase.FORMATION)
	formation_started.emit()
	var screen := FormationSetup.new()
	screen.manager = self
	add_child(screen)
	await screen.finished
	_save_home_positions()


## A posição de cada jogador agora vira a "casa" dele (para onde volta depois de um gol)
func _save_home_positions() -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		p.home_position = p.global_position


func _start_match() -> void:
	match_started.emit()
	start_round()


## O Field avisa quando a bola volta ao centro depois de um gol
func _on_ball_reset_after_goal() -> void:
	if match_over or phase == Phase.FORMATION or not reset_positions_after_goal:
		return
	return_players_home(reposition_time)


## Todos os jogadores voltam à posição da formação (e ninguém age enquanto isso)
func return_players_home(duration: float) -> void:
	_repositioning = true
	state_changed.emit()
	for p: Player in get_tree().get_nodes_in_group("players"):
		p.return_home(duration)
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
	_repositioning = false
	state_changed.emit()


## Chamado pelo botão do fim de jogo: zera a partida e volta para a montagem das formações
func return_to_formation() -> void:
	if not match_over:
		return

	match_over = false
	winner = -1
	scores.fill(0)
	goal_log.clear()
	round_number = 0
	turns_played = 0
	current_team = starting_team
	protagonist = null
	active_player = null
	protagonist_general_left = 0
	protagonist_skill_left = 0
	secondary_general_left = 0
	secondary_skill_left = 0
	pass_variant = PassVariant.GROUND
	pass_hint = ""
	_repositioning = false
	_clear_pending_pass()
	_hide_pass_preview()
	_clear_roles()

	var field := get_tree().get_first_node_in_group("field") as Field
	if field:
		field.reset_ball()  # também manda os goleiros para casa (eles ouvem o reset da bola)
	for p: Player in get_tree().get_nodes_in_group("players"):
		p.reset_for_new_match()
		p.global_position = p.home_position
	for k: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
		k.restart()

	await _run_formation()
	_start_match()


# ---------- RODADA / TURNO ----------

func start_round() -> void:
	round_number += 1
	_auto_stand_up()
	turns_played = 0
	current_team = starting_team
	round_started.emit(round_number)
	_begin_turn()


func _begin_turn() -> void:
	# Quem pulou pousa quando chega o turno do próprio time de novo
	# (= o pulo dura uma rodada inteira, inclusive o turno do adversário)
	for p in get_team_players(current_team):
		p.land()
		p.has_run_this_turn = false

	_update_pass_on_turn_start()

	_clear_roles()
	protagonist = null
	active_player = null
	protagonist_general_left = 0
	protagonist_skill_left = 0
	secondary_general_left = 0
	secondary_skill_left = 0
	turn_started.emit(current_team)
	_set_phase(Phase.CHOOSING_PROTAGONIST)


func _end_turn() -> void:
	if match_over:
		return

	# Passe alto que chegou neste turno e ninguém tocou: cai para o chão
	if _pass_stage == PassStage.RECEIVED and current_team == _pass_team:
		var ball: Ball = _get_ball()
		if ball and ball.hovering and not ball.is_held():
			ball.release_hover()
		_clear_pending_pass()

	_clear_roles()
	turn_ended.emit(current_team)
	turns_played += 1

	# Entre os turnos os goleiros agem sozinhos (preparo, salto, lançamento):
	# o jogo espera eles terminarem antes de começar o próximo turno
	await _wait_for_keepers()
	if match_over:
		return

	if turns_played >= team_count:
		round_ended.emit(round_number)
		start_round()
	else:
		current_team = (current_team + 1) % team_count
		_begin_turn()


## Chamado pelo botão "Encerrar turno"
func request_end_turn() -> void:
	if phase == Phase.CHOOSING_ACTION:
		_end_turn()


# ---------- SELEÇÃO ----------

func _on_player_clicked(player: Player) -> void:
	# Só o time da vez pode ser clicado, e nunca durante uma ação, mira ou escolha de variante
	if phase == Phase.EXECUTING or phase == Phase.AIMING or phase == Phase.MATCH_OVER \
			or phase == Phase.KEEPERS_ACTING or phase == Phase.FORMATION or _repositioning \
			or phase == Phase.CHOOSING_PASS_VARIANT or player.team != current_team:
		return

	# Passe: o companheiro clicado recebe a bola
	if phase == Phase.CHOOSING_PASS_TARGET:
		if player != active_player:
			if can_pass_to(active_player, player, pass_variant):
				_execute_pass(player)
			else:
				pass_hint = "%s está fora do alcance!" % player.get_display_name()
				state_changed.emit()
		return

	if phase == Phase.CHOOSING_PROTAGONIST:
		select_protagonist(player)
	else:
		set_active_player(player)


func select_protagonist(player: Player) -> void:
	if phase != Phase.CHOOSING_PROTAGONIST or player.team != current_team:
		return

	protagonist = player
	for p in get_team_players(current_team):
		p.role = Player.Role.PROTAGONIST if p == protagonist else Player.Role.SECONDARY

	protagonist_general_left = protagonist_general_actions
	protagonist_skill_left = protagonist_skill_actions
	secondary_general_left = secondary_general_actions
	secondary_skill_left = secondary_skill_actions

	set_active_player(protagonist)
	_set_phase(Phase.CHOOSING_ACTION)


## Troca quem vai agir (Protagonista ou algum Secundário do time)
func set_active_player(player: Player) -> void:
	if active_player:
		active_player.is_active = false
	active_player = player
	active_player.is_active = true
	state_changed.emit()


# ---------- AÇÕES ----------

func can_act() -> bool:
	return phase == Phase.CHOOSING_ACTION and active_player != null and not _repositioning


func general_left_for(player: Player) -> int:
	if player == null:
		return 0
	return protagonist_general_left if player == protagonist else secondary_general_left


func skill_left_for(player: Player) -> int:
	if player == null:
		return 0
	return protagonist_skill_left if player == protagonist else secondary_skill_left


func total_actions_left() -> int:
	return protagonist_general_left + protagonist_skill_left \
		+ secondary_general_left + secondary_skill_left


## Regras de disponibilidade das ações gerais para quem está agindo
func can_use_general(action: GeneralAction) -> bool:
	if not can_act() or general_left_for(active_player) <= 0:
		return false

	var p: Player = active_player

	# Derrubado: só Levantar (que, por sua vez, só existe para derrubados)
	if action == GeneralAction.STAND_UP:
		return p.is_down
	if p.is_down:
		return false

	match action:
		# Correr: só no chão e uma vez por turno
		GeneralAction.RUN:
			return p.height_level == Heights.Level.GROUND and not p.has_run_this_turn
		# Pular e Carrinho só a partir do chão
		GeneralAction.JUMP, GeneralAction.SLIDE:
			return p.height_level == Heights.Level.GROUND
		# Chutar: precisa haver um chute possível (perto da bola, altura alcançável)
		GeneralAction.SHOOT:
			return p.get_kick_type(_get_ball()) != Player.KickType.NONE
		# Passar: mesma exigência do chute (bola ao alcance) + ter um companheiro para receber
		GeneralAction.PASS:
			return p.get_kick_type(_get_ball()) != Player.KickType.NONE \
				and (_has_pass_target(p, PassVariant.GROUND) or _has_pass_target(p, PassVariant.HIGH))
	return true


func do_general_action(action: GeneralAction) -> void:
	if not can_use_general(action):
		return

	var actor: Player = active_player

	match action:
		GeneralAction.RUN:
			_consume_general()
			_set_phase(Phase.EXECUTING)
			actor.start_run()
			await actor.run_finished
			_after_action()

		GeneralAction.JUMP:
			_consume_general()
			_set_phase(Phase.EXECUTING)
			await actor.jump()
			_after_action()

		GeneralAction.SLIDE:
			# Primeiro mira; só gasta a ação se o jogador confirmar
			_set_phase(Phase.AIMING)
			actor.begin_aim(actor.slide_distance)
			var dir: Vector2 = await actor.aim_finished
			if dir == Vector2.ZERO:
				_set_phase(Phase.CHOOSING_ACTION)
				return
			_consume_general()
			_set_phase(Phase.EXECUTING)
			actor.start_slide(dir)
			await actor.slide_finished
			_after_action()

		GeneralAction.STAND_UP:
			_consume_general()
			_set_phase(Phase.EXECUTING)
			await actor.stand_up()
			_after_action()

		GeneralAction.SHOOT:
			var ball: Ball = _get_ball()
			var kind: Player.KickType = actor.get_kick_type(ball)
			# Primeiro mira; só gasta a ação se o jogador confirmar
			_set_phase(Phase.AIMING)
			actor.begin_aim(actor.kick_aim_range)
			var kick_dir: Vector2 = await actor.aim_finished
			if kick_dir == Vector2.ZERO:
				_set_phase(Phase.CHOOSING_ACTION)
				return
			_consume_general()
			_set_phase(Phase.EXECUTING)
			# Chão = sem QTE; voleio e bola voando têm QTE
			var qte_ok: bool = true
			if kind != Player.KickType.GROUND and not actor.skips_qte():
				qte_ok = await _run_qte(kind)
			await actor.kick_ball(ball, kick_dir, kind, qte_ok)
			_after_action()

		GeneralAction.PASS:
			# Não gasta a ação ainda: primeiro a variante, depois o alvo (dá para cancelar)
			_set_phase(Phase.CHOOSING_PASS_VARIANT)

		_:
			# Ainda não implementadas: não gastam ação
			print("Ação '%s' ainda não implementada." % GENERAL_ACTION_NAMES[action])


# ---------- PASSE ----------

## Chamado pelos botões "Passe rasteiro" / "Passe alto"
func choose_pass_variant(variant: PassVariant) -> void:
	if phase != Phase.CHOOSING_PASS_VARIANT:
		return
	if not can_choose_pass_variant(variant):
		return
	pass_variant = variant
	pass_hint = ""
	_show_pass_preview()
	_set_phase(Phase.CHOOSING_PASS_TARGET)


## Botão "Cancelar passe", clique direito ou Esc: volta sem gastar a ação
func cancel_pass() -> void:
	if phase == Phase.CHOOSING_PASS_VARIANT or phase == Phase.CHOOSING_PASS_TARGET:
		_hide_pass_preview()
		_set_phase(Phase.CHOOSING_ACTION)


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.CHOOSING_PASS_VARIANT and phase != Phase.CHOOSING_PASS_TARGET:
		return
	var cancel: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel = true
	if cancel:
		get_viewport().set_input_as_handled()
		cancel_pass()


func _execute_pass(target: Player) -> void:
	var actor: Player = active_player
	var ball: Ball = _get_ball()
	# Segurança: a bola pode ter saído do alcance enquanto o jogador escolhia
	if actor.get_kick_type(ball) == Player.KickType.NONE:
		_hide_pass_preview()
		_set_phase(Phase.CHOOSING_ACTION)
		return

	_hide_pass_preview()
	_consume_general()
	_set_phase(Phase.EXECUTING)
	if pass_variant == PassVariant.GROUND:
		await _run_ground_pass(actor, target, ball)
	else:
		await _run_high_pass(actor, target, ball)
	_after_action()


## Passe rasteiro: a bola rola pelo chão até encostar no alvo (mesmo se estava suspensa).
## Aliados no caminho não atrapalham; inimigo no chão que chegue perto da trajetória
## intercepta e a bola para ali. Inimigo suspenso não alcança a bola: ela passa direto.
func _run_ground_pass(passer: Player, target: Player, ball: Ball) -> void:
	var start: Vector2 = ball.global_position
	var to_target: Vector2 = target.global_position - start
	var dist: float = to_target.length()
	# A bola para ENCOSTANDO no alvo (e não por dentro dele)
	var travel: float = dist - (ball.collision_radius + target.body_radius + 2.0)
	if travel < 1.0:
		return

	var dir: Vector2 = to_target / dist
	var slow_zone: float = minf(travel * 0.4, 160.0)  # reta final: a bola vai "amortecendo"

	ball.kick_ground(dir, ground_pass_speed, passer, Ball.NO_SHOT)  # passe não é chute
	ball.height = 0.0
	ball.collisions_paused = true
	ball.trail_enabled = true

	var time_left: float = travel / ground_pass_speed * 2.5 + 1.0  # trava de segurança
	while time_left > 0.0:
		await get_tree().physics_frame
		time_left -= get_physics_process_delta_time()

		if _find_interceptor(passer.team, ball) != null:
			break
		var remaining: float = travel - start.distance_to(ball.global_position)
		if remaining <= 2.0:
			ball.global_position = start + dir * travel
			break
		# Velocidade constante e, na reta final, vai diminuindo até quase parar no alvo
		var speed: float = ground_pass_speed * clampf(remaining / slow_zone, 0.15, 1.0)
		ball.velocity = dir * speed

	ball.velocity = Vector2.ZERO
	ball.collisions_paused = false
	ball.trail_enabled = false


func _find_interceptor(team: int, ball: Ball) -> Player:
	var level: Heights.Level = ball.get_level()
	for other: Player in get_tree().get_nodes_in_group("players"):
		# Só intercepta quem está no MESMO nível da bola: inimigo suspenso "saltou" por cima dela
		if other.team == team or other.is_down or other.height_level != level:
			continue
		if other.global_position.distance_to(ball.global_position) <= ground_pass_intercept_radius:
			return other
	return null


## Passe alto: a bola sai do chão, sobe ao nível Voando no MEIO do caminho e PAIRA lá.
## Quando o turno do time volta (_update_pass_on_turn_start) ela vai até o ponto de chegada,
## no nível Suspenso. Uma marca no chão mostra onde ela vai chegar.
func _run_high_pass(passer: Player, target: Player, ball: Ball) -> void:
	ball.register_touch(passer)  # o passe alto não usa kick(), então registra o toque aqui
	_pass_origin = passer.global_position
	_pass_aim_point = target.global_position
	_spawn_pass_marker(passer.team, _pass_aim_point, ball)

	var midpoint: Vector2 = (ball.global_position + _pass_aim_point) * 0.5
	var tween: Tween = ball.hover_to(midpoint, Heights.FLYING_HEIGHT, high_pass_flight_time)
	await tween.finished
	_pass_stage = PassStage.FLYING
	_pass_team = passer.team
	_pass_target = target


## Onde o passe alto pousa: no alvo, se ele ainda está dentro do alcance (medido de onde o
## passe saiu). Se ele se afastou demais, a bola cai onde o alvo estava quando o passe saiu.
func _pass_landing_point() -> Vector2:
	if _pass_target != null \
			and _pass_target.global_position.distance_to(_pass_origin) <= high_pass_range:
		return _pass_target.global_position
	return _pass_aim_point


func _process(_delta: float) -> void:
	if _pass_stage == PassStage.NONE:
		return
	var ball: Ball = _get_ball()
	# Alguém chutou (ou a bola foi reposta): o passe alto acabou
	if ball == null or not ball.hovering or ball.is_held():
		_clear_pending_pass()
		return
	# A marca acompanha o alvo enquanto ele estiver ao alcance
	if _pass_stage == PassStage.FLYING and _pass_marker != null:
		_pass_marker.global_position = _pass_landing_point()


## Começo de cada turno: resolve o que aconteceu com o passe alto em andamento
func _update_pass_on_turn_start() -> void:
	if _pass_stage == PassStage.NONE:
		return
	var ball: Ball = _get_ball()
	if ball == null or not ball.hovering or ball.is_held():
		_clear_pending_pass()
		return
	# Turno de quem passou: a bola chega ao ponto de chegada, no nível Suspenso
	if _pass_stage == PassStage.FLYING and current_team == _pass_team:
		ball.hover_to(_pass_landing_point(), Heights.SUSPENDED_HEIGHT, high_pass_arrive_time)
		_remove_pass_marker()
		_pass_stage = PassStage.RECEIVED


func _clear_pending_pass() -> void:
	_pass_stage = PassStage.NONE
	_pass_team = -1
	_pass_target = null
	_remove_pass_marker()


func _spawn_pass_marker(team: int, pos: Vector2, ball: Ball) -> void:
	_remove_pass_marker()
	_pass_marker = PassMarker.new()
	_pass_marker.color = Player.TEAM_COLORS[team % Player.TEAM_COLORS.size()].lightened(0.4)
	ball.get_parent().add_child(_pass_marker)
	_pass_marker.global_position = pos


func _remove_pass_marker() -> void:
	if _pass_marker != null and is_instance_valid(_pass_marker):
		_pass_marker.fade_out()
	_pass_marker = null


func pass_range_for(variant: PassVariant) -> float:
	return high_pass_range if variant == PassVariant.HIGH else ground_pass_range


## O alvo é companheiro (outro jogador do time) e está dentro do alcance da variante?
func can_pass_to(passer: Player, target: Player, variant: PassVariant) -> bool:
	if target == passer or target.team != passer.team:
		return false
	return passer.global_position.distance_to(target.global_position) <= pass_range_for(variant)


func _has_pass_target(passer: Player, variant: PassVariant) -> bool:
	for other in get_team_players(passer.team):
		if can_pass_to(passer, other, variant):
			return true
	return false


## Usado pelo menu: a variante só habilita se houver alguém ao alcance
func can_choose_pass_variant(variant: PassVariant) -> bool:
	return active_player != null and _has_pass_target(active_player, variant)


## Desenha o alcance em volta de quem passa e destaca os companheiros alcançáveis
func _show_pass_preview() -> void:
	active_player.range_preview = pass_range_for(pass_variant)
	for other in get_team_players(current_team):
		other.is_pass_option = can_pass_to(active_player, other, pass_variant)


func _hide_pass_preview() -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		p.range_preview = 0.0
		p.is_pass_option = false


## A habilidade (pelo id) pode ser usada agora por quem está agindo?
func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not can_act() or skill_left_for(active_player) <= 0:
		return false
	return active_player.can_use_skill(skill_id)


## Chamado pelos botões de habilidade do menu. A ação só é gasta se a habilidade
## foi realmente usada (cancelar a mira, por exemplo, não gasta nada).
func do_skill_action(skill_id: StringName = &"default") -> void:
	if not can_use_skill(skill_id):
		return

	var actor: Player = active_player
	_set_phase(Phase.EXECUTING)
	var used: bool = await actor.use_skill(skill_id)
	if not used:
		_set_phase(Phase.CHOOSING_ACTION)
		return

	_consume_skill()
	_after_action()


## Mira para uma habilidade de personagem. Devolve a direção (Vector2.ZERO = cancelou).
func aim_for_skill(actor: Player, range_px: float) -> Vector2:
	_set_phase(Phase.AIMING)
	actor.begin_aim(range_px)
	var dir: Vector2 = await actor.aim_finished
	_set_phase(Phase.EXECUTING)
	return dir


## Versão pública do QTE para as habilidades dos personagens (devolve true se acertou)
func run_qte(kind: Player.KickType) -> bool:
	return await _run_qte(kind)


## Roda o QTE do tipo de chute e devolve true se o jogador acertou tudo
func _run_qte(kind: Player.KickType) -> bool:
	var qte := QTE.new()
	add_child(qte)
	if kind == Player.KickType.FLYING:
		qte.start(QTE.HARD_KEYS, flying_qte_keys, flying_qte_time_per_key, "Bola no ar!")
	else:
		var title: String = "Voleio!" if kind == Player.KickType.VOLLEY else "Bola alta!"
		qte.start(QTE.EASY_KEYS, volley_qte_keys, volley_qte_time_per_key, title)
	var ok: bool = await qte.finished
	return ok


func _get_ball() -> Ball:
	return get_tree().get_first_node_in_group("ball") as Ball


func _consume_general() -> void:
	if active_player == protagonist:
		protagonist_general_left -= 1
	else:
		secondary_general_left -= 1


func _consume_skill() -> void:
	if active_player == protagonist:
		protagonist_skill_left -= 1
	else:
		secondary_skill_left -= 1


func _after_action() -> void:
	# Partida acabou durante a ação: não volta para a escolha de ações
	if match_over:
		return

	# Acabaram todas as ações do time -> passa o turno
	if total_actions_left() <= 0:
		_end_turn()
		return

	# Se o secundário em ação esgotou a pool, volta para o Protagonista
	if active_player != protagonist \
			and general_left_for(active_player) + skill_left_for(active_player) <= 0:
		set_active_player(protagonist)

	_set_phase(Phase.CHOOSING_ACTION)


## Quem está derrubado há 2 rodadas levanta sozinho, sem gastar ação
func _auto_stand_up() -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if not p.is_down:
			continue
		p.rounds_down += 1
		if p.rounds_down >= auto_stand_up_rounds:
			p.get_up_now()


# ---------- GOLEIROS ----------

func _any_keeper_busy() -> bool:
	for k: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
		if k.is_busy():
			return true
	return false


## Espera os goleiros terminarem o que estão fazendo (salto, lançamento...)
func _wait_for_keepers() -> void:
	if not _any_keeper_busy():
		return
	_set_phase(Phase.KEEPERS_ACTING)
	var time_left: float = keeper_wait_timeout
	while _any_keeper_busy() and not match_over and time_left > 0.0:
		await get_tree().physics_frame
		time_left -= get_physics_process_delta_time()
	# Trava de segurança: se algo emperrar, o jogo segue
	for k: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
		if k.is_busy():
			k.cancel_action()


## Os goleiros avisam o que fizeram por aqui; o HUD mostra
func announce_keeper(text: String, team: int) -> void:
	keeper_event.emit(text, team)


# ---------- GOLS E PLACAR ----------

## Chamado pelo Field quando a bola entra. Quem fez o gol = último a tocar na bola;
## assistência = o toque anterior, se for um companheiro do autor.
## Gol contra (último toque foi de quem defende) não tem assistência.
func _on_goal_scored(scoring_team: int) -> void:
	if match_over or scoring_team < 0 or scoring_team >= scores.size():
		return

	var ball: Ball = _get_ball()
	var scorer: Player = ball.last_toucher if ball else null
	var assist: Player = ball.previous_toucher if ball else null
	var own_goal: bool = scorer != null and scorer.team != scoring_team
	if scorer == null or own_goal or assist == null or assist.team != scoring_team:
		assist = null

	scores[scoring_team] += 1
	var goal := {
		"order": goal_log.size() + 1,
		"team": scoring_team,
		"scorer": scorer.get_display_name() if scorer else "Ninguém",
		"assist": assist.get_display_name() if assist else "",
		"own_goal": own_goal,
		"round": round_number,
	}
	goal_log.append(goal)
	goal_scored.emit(goal)
	state_changed.emit()

	if scores[scoring_team] >= goals_to_win:
		_end_match(scoring_team)


func _end_match(winning_team: int) -> void:
	match_over = true
	winner = winning_team
	_hide_pass_preview()
	# Se alguém estava mirando, cancela (a ação em andamento termina sem efeito)
	if active_player and active_player.is_aiming:
		active_player.cancel_aim()
	_clear_roles()
	_set_phase(Phase.MATCH_OVER)
	match_ended.emit(winner)


# ---------- UTIL ----------

func get_team_players(team: int) -> Array[Player]:
	var result: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team:
			result.append(p)
	return result


func get_team_name(team: int) -> String:
	if team < team_names.size():
		return team_names[team]
	return "Time %d" % team


func _clear_roles() -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		p.role = Player.Role.NONE
		p.is_active = false


func _set_phase(new_phase: Phase) -> void:
	# Depois do fim de jogo, nenhuma ação em andamento pode mudar a fase
	if match_over and new_phase != Phase.MATCH_OVER:
		return
	phase = new_phase
	state_changed.emit()
