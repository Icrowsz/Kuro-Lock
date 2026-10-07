class_name MatchManager
extends Node
## Controla ações < turnos < rodadas < tempos.
##
## - Rodada: todos os times jogam um turno (começa pelo "starting_team").
## - Turno: um time escolhe o Protagonista e gasta as ações disponíveis.
## - Ações: Protagonista tem gerais + habilidade próprias; os Secundários
##   dividem entre o time inteiro uma pool de ações gerais + habilidade.
##
## TEMPOS E FIM DE JOGO
## - A partida tem 1º e 2º tempo, cada um com "rounds_per_half" rodadas
##   (padrão 25 + 25 = 50 rodadas de tempo normal).
## - Quem fizer "goals_to_win" gols primeiro (padrão 3) vence na hora,
##   em qualquer tempo (inclusive na prorrogação).
## - Se ninguém chegar lá, ao fim da rodada 50 quem tiver mais gols vence.
## - Empatado ao fim do tempo normal: começa a prorrogação ("extra_time_rounds"
##   rodadas, padrão 15) em modo GOL DE OURO — o primeiro gol (de qualquer
##   time, inclusive contra) decide a partida na hora.
## - Se a prorrogação acabar sem ninguém marcar, a partida termina empatada
##   (match_ended é emitido com winner = -1).

signal state_changed
signal turn_started(team: int)
signal turn_ended(team: int)
signal round_started(round_number: int)
signal round_ended(round_number: int)
## Trocou de tempo (1 = primeiro tempo, 2 = segundo tempo). Não dispara de novo
## na prorrogação (use extra_time_started para isso).
signal half_started(half: int)
## Tempo normal (1º + 2º) terminou empatado: começou a prorrogação (gol de ouro).
signal extra_time_started
## Gol marcado. goal = {order, team, scorer, assist, own_goal, round}
signal goal_scored(goal: Dictionary)
## winner = -1 quando a partida termina empatada (prorrogação esgotada sem gols)
signal match_ended(winner: int)
## Aviso de algo que o goleiro fez (defesa, lançamento...). O HUD mostra o texto.
signal keeper_event(text: String, team: int)
## Uma habilidade que pede um companheiro (ex: Puppets do Rin) recebeu a resposta (null = cancelou)
signal skill_target_picked(target: Player)
## Uma habilidade que pede um PONTO do campo (ex: Rabona Cross do Charles) recebeu a
## resposta (Vector2.INF = cancelou)
signal skill_point_picked(point: Vector2)
## Um passe saiu (rasteiro, alto ou de habilidade). Habilidades que dependem de passes (ex: Metavision do Niko) ouvem aqui.
signal pass_completed(passer: Player, target: Player)
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
	TEAM_EFFECTS,           # Fim de turno: efeitos que agem sozinhos (ex: 1-2 do Kurona)
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

@export_group("Tempo de jogo")
@export var rounds_per_half: int = 20         # rodadas de cada tempo (1º + 2º = tempo normal)
@export var extra_time_rounds: int = 10       # rodadas da prorrogação (gol de ouro), se empatar

@export_group("Formações")
@export var use_formation_setup: bool = true          # antes da partida, cada time monta e confirma a formação
@export var reset_positions_after_goal: bool = true   # depois de um gol, todo mundo volta à posição da formação
@export var reposition_time: float = 0.8              # quanto tempo os jogadores levam para voltar (0 = na hora)

@export_group("MVP")
@export var mvp_goal_points: int = 1          # pontos por gol (gol contra não pontua)
@export var mvp_assist_points: int = 1        # pontos por assistência
@export var mvp_win_points: int = 1           # pontos para cada jogador do time vencedor
@export var mvp_golden_goal_points: int = 2   # gol de ouro (o que desempata na prorrogação) vale isto

@export_group("Ações do Protagonista")
@export var protagonist_general_actions: int = 3
@export var protagonist_skill_actions: int = 1

@export_group("Ações dos Secundários (divididas pelo time)")
@export var secondary_general_actions: int = 2
@export var secondary_skill_actions: int = 1

@export_group("Chutar - QTE")
@export var volley_qte_keys: int = 3                  # voleio: quantas teclas
@export var volley_qte_time_per_key: float = 0.9      # voleio: segundos por tecla
@export var flying_qte_keys: int = 5                  # bola voando: mais teclas...
@export var flying_qte_time_per_key: float = 0.6      # ...menos tempo (e teclas extras no pool)

@export_group("Passe")
@export var ground_pass_range: float = 450.0           # alcance do passe rasteiro (px)
@export var high_pass_range: float = 550.0             # alcance do passe alto (um pouco maior)
@export var ground_pass_speed: float = 700.0           # velocidade do passe rasteiro (px/s)
@export var ground_pass_intercept_radius: float = 30.0 # inimigo a esta distância da bola intercepta
@export var high_pass_flight_time: float = 0.9         # tempo da bola até subir ao nível Voando
@export var high_pass_arrive_time: float = 0.4         # tempo da descida até o alvo (nível Suspenso)

var round_number: int = 0
var turns_played: int = 0
var current_team: int = 0
var phase: Phase = Phase.CHOOSING_PROTAGONIST

## 1 = primeiro tempo, 2 = segundo tempo. Fica parado em 2 durante a prorrogação.
var current_half: int = 1
## true durante a prorrogação: qualquer gol (até contra) decide a partida na hora
var in_extra_time: bool = false

## Placar e histórico de gols (na ordem em que aconteceram).
## Cada gol: {order, team, scorer, assist, own_goal, round} — nomes guardados como texto.
var scores: Array[int] = []
var goal_log: Array[Dictionary] = []
var match_over: bool = false
var winner: int = -1

## Estatísticas por jogador para o MVP (chave = instance id do Player).
## Cada entrada: {name, character_id, team, goals, assists, golden, win, points, image}
var player_stats: Dictionary = {}
## O MVP da partida (vazio = ninguém pontuou). Preenchido ANTES do match_ended ser emitido.
## Mesmas chaves de uma entrada de player_stats.
var mvp: Dictionary = {}

## Passe em escolha (lido pelo menu) e passe alto em andamento
var pass_variant: PassVariant = PassVariant.GROUND
var pass_hint: String = ""   # aviso na escolha do alvo (ex: "fora do alcance")
var _pass_stage: PassStage = PassStage.NONE
var _pass_team: int = -1
var _pass_target: Player = null
var _pass_origin: Vector2 = Vector2.ZERO      # onde estava quem passou (o alcance é medido daqui)
var _pass_aim_point: Vector2 = Vector2.ZERO   # onde o alvo estava quando o passe saiu
var _pass_marker: PassMarker = null
var _pass_max_range: float = 0.0              # alcance do passe alto em andamento (0 = o padrão)

var protagonist: Player = null
var active_player: Player = null   # quem vai executar a próxima ação

## Habilidade esperando o jogador clicar num alvo (ver pick_ally_for_skill)
var _picking_skill_target: bool = false
var _skill_target_actor: Node2D = null   # Player (habilidade) ou Goalkeeper (lançamento)
var _skill_target_range: float = 0.0
## true = só companheiros contam como alvo válido; false = só inimigos
var _skill_target_same_team: bool = true
## Filtro extra opcional (ex: só inimigos "no chão"). Vazio = qualquer um do time certo serve.
var _skill_target_filter: Callable = Callable()

## Habilidade esperando o jogador clicar num PONTO do campo (ver pick_point_for_skill)
var _picking_skill_point: bool = false
var _skill_point_actor: Player = null
var _skill_point_range: float = 0.0
var _skill_point_marker: PassMarker = null

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
	player_stats.clear()
	mvp = {}
	round_number = 0
	turns_played = 0
	current_half = 1
	in_extra_time = false
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
	_picking_skill_target = false
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
	_update_half()
	_auto_stand_up()
	turns_played = 0
	current_team = starting_team
	round_started.emit(round_number)
	_begin_turn()


## Primeiro tempo = rodadas 1..rounds_per_half; segundo tempo = o resto do
## tempo normal. Na prorrogação o "tempo" fica parado em 2 (não existe 3º/4º).
func _update_half() -> void:
	if in_extra_time:
		return
	var new_half: int = 2 if round_number > rounds_per_half else 1
	if new_half != current_half:
		current_half = new_half
		half_started.emit(current_half)


func _begin_turn() -> void:
	# Quem pulou pousa quando chega o turno do próprio time de novo
	# (= o pulo dura uma rodada inteira, inclusive o turno do adversário)
	for p in get_team_players(current_team):
		p.land()
		p.runs_this_turn = 0
		p.slides_this_turn = 0

	_update_pass_on_turn_start()

	_clear_roles()
	protagonist = null
	active_player = null
	protagonist_general_left = 0
	protagonist_skill_left = 0
	secondary_general_left = 0
	secondary_skill_left = 0
	turn_started.emit(current_team)
	# O lançamento do goleiro começa no turn_started: espera ele terminar (e, se o goleiro deixa
	# o jogador escolher o alvo, espera a escolha) antes de abrir o turno
	await _wait_for_keepers()
	if match_over:
		return
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

	# Efeitos de fim de turno do time (ex: o 1-2 do Sharp Sharp do Kurona)
	await _run_turn_end_effects(current_team)
	if match_over:
		return

	# Entre os turnos os goleiros agem sozinhos (preparo, salto, lançamento):
	# o jogo espera eles terminarem antes de começar o próximo turno
	await _wait_for_keepers()
	if match_over:
		return

	if turns_played >= team_count:
		round_ended.emit(round_number)
		if _handle_round_limit():
			return   # a partida terminou (tempo normal decidido, ou prorrogação esgotada)
		start_round()
	else:
		current_team = (current_team + 1) % team_count
		_begin_turn()


## Chamado logo depois que uma rodada termina. Decide o fim de jogo por tempo:
## - Fim do tempo normal (rodada 50): quem tiver mais gols vence; empatado,
##   começa a prorrogação.
## - Fim da prorrogação (rodada 65): ninguém marcou -> empate.
## Devolve true se a partida terminou (quem chamou não deve iniciar outra rodada).
func _handle_round_limit() -> bool:
	var regular_total: int = rounds_per_half * 2

	if not in_extra_time:
		if round_number < regular_total:
			return false
		var top_team: int = _team_with_most_goals()
		if top_team != -1:
			_end_match(top_team)
			return true
		_start_extra_time()
		return false   # empatado: a prorrogação já começou, a rodada 51 segue normalmente

	if round_number >= regular_total + extra_time_rounds:
		_end_match(-1)   # prorrogação esgotada sem ninguém marcar: empate
		return true
	return false


## Time com mais gols no placar. -1 se os melhores estiverem empatados entre si.
func _team_with_most_goals() -> int:
	var best: int = -1
	var best_score: int = -1
	var tied: bool = false
	for t in team_count:
		if scores[t] > best_score:
			best_score = scores[t]
			best = t
			tied = false
		elif scores[t] == best_score:
			tied = true
	return -1 if tied else best


func _start_extra_time() -> void:
	in_extra_time = true
	extra_time_started.emit()
	state_changed.emit()


## Chamado pelo botão "Encerrar turno"
func request_end_turn() -> void:
	if phase == Phase.CHOOSING_ACTION:
		_end_turn()


# ---------- SELEÇÃO ----------

func _on_player_clicked(player: Player) -> void:
	# Habilidade esperando um PONTO do campo (ex: Rabona Cross): clicar num jogador
	# conta como escolher o local onde ele está
	if _picking_skill_point:
		_try_pick_skill_point(player.global_position)
		return
	# Habilidade esperando um companheiro (ex: Puppets): só o clique no alvo interessa
	if _picking_skill_target:
		_try_pick_skill_target(player)
		return

	# Só o time da vez pode ser clicado, e nunca durante uma ação, mira ou escolha de variante
	if phase == Phase.EXECUTING or phase == Phase.AIMING or phase == Phase.MATCH_OVER \
			or phase == Phase.KEEPERS_ACTING or phase == Phase.FORMATION or _repositioning \
			or phase == Phase.TEAM_EFFECTS \
			or phase == Phase.CHOOSING_PASS_VARIANT or player.team != current_team:
		return

	# Passe: o companheiro clicado recebe a bola
	if phase == Phase.CHOOSING_PASS_TARGET:
		if player != active_player:
			if can_pass_to(active_player, player, pass_variant):
				_execute_pass(player)
			elif player.is_pass_blocked():
				pass_hint = "%s está marcado e não pode receber passes!" % player.get_display_name()
				state_changed.emit()
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


## action = -1: total de ações gerais sobrando (menu/contadores). Com uma ação (GeneralAction),
## só conta o que serve para ELA: a extra "sem Correr" (ex: Unleash Instinct do Bachira) não
## vale para o Correr.
func general_left_for(player: Player, action: int = -1) -> int:
	if player == null:
		return 0
	var pool: int = protagonist_general_left if player == protagonist else secondary_general_left
	var total: int = pool + player.extra_general_left
	if action != GeneralAction.RUN:
		total += player.extra_general_no_run_left
	return total


## Ações de habilidade de quem age: a pool do papel (Protagonista ou Secundários) + as extras só dele
func skill_left_for(player: Player) -> int:
	if player == null:
		return 0
	var pool: int = protagonist_skill_left if player == protagonist else secondary_skill_left
	return pool + player.extra_skill_left


func total_actions_left() -> int:
	var extras: int = 0
	for p in get_team_players(current_team):
		extras += p.extra_skill_left + p.extra_general_left + p.extra_general_no_run_left
	return protagonist_general_left + protagonist_skill_left \
		+ secondary_general_left + secondary_skill_left + extras


## Regras de disponibilidade das ações gerais para quem está agindo
func can_use_general(action: GeneralAction) -> bool:
	if not can_act() or general_left_for(active_player, action) <= 0:
		return false

	var p: Player = active_player

	# Derrubado: só Levantar (que, por sua vez, só existe para derrubados)
	if action == GeneralAction.STAND_UP:
		return p.is_down
	# Derrubado ou travado (ex: Snake Lunge do Aiku): nenhuma ação geral
	if p.is_down or p.is_locked() or p.is_generals_suppressed():   # suppressed: ex. Body Core do Niko
		return false
	# Uma ação específica removida (ex: Obsessive Hater do Shidou)
	if p.is_general_action_blocked(action):
		return false

	match action:
		# Correr: por padrão só no chão e até 2 vezes por turno (ver can_run() no player.gd;
		# o Once More do Chigiri libera Correr também suspenso)
		GeneralAction.RUN:
			return p.can_run()
		# Carrinho: só no chão e apenas 1 vez por turno
		GeneralAction.SLIDE:
			return p.height_level == Heights.Level.GROUND and p.slides_this_turn < p.max_slides_per_turn
		# Pular só a partir do chão
		GeneralAction.JUMP:
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
			_consume_general(GeneralAction.RUN)
			_set_phase(Phase.EXECUTING)
			actor.start_run()
			await actor.run_finished
			_after_action()

		GeneralAction.JUMP:
			_consume_general(GeneralAction.JUMP)
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
			_consume_general(GeneralAction.SLIDE)
			_set_phase(Phase.EXECUTING)
			actor.start_slide(dir)
			await actor.slide_finished
			_after_action()

		GeneralAction.STAND_UP:
			_consume_general(GeneralAction.STAND_UP)
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
			_consume_general(GeneralAction.SHOOT)
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
	if not _picking_skill_target and not _picking_skill_point \
			and phase != Phase.CHOOSING_PASS_VARIANT and phase != Phase.CHOOSING_PASS_TARGET:
		return

	# Escolha de ponto do campo: clique esquerdo em qualquer lugar (que não seja em
	# cima de um jogador, já tratado por _on_player_clicked) confirma o local
	if _picking_skill_point and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_try_pick_skill_point(_skill_point_actor.get_global_mouse_position())
		return

	var cancel: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel = true
	if cancel:
		get_viewport().set_input_as_handled()
		if _picking_skill_target:
			skill_target_picked.emit(null)
		elif _picking_skill_point:
			skill_point_picked.emit(Vector2.INF)
		else:
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
	_consume_general(GeneralAction.PASS)
	_set_phase(Phase.EXECUTING)
	if pass_variant == PassVariant.GROUND:
		await _run_ground_pass(actor, target, ball)
	else:
		await _run_high_pass(actor, target, ball)
	_after_action()


## Passe rasteiro "avulso", fora do fluxo normal da ação Passe (menu -> variante ->
## alvo). Usado por habilidades que dão um passe com regras próprias (ex: Viper Tackle
## do Aiku, que passa com alcance reduzido ao encontrar a bola no meio do carrinho).
## Mesmo comportamento do passe comum: anima, a bola rola até o alvo, aliados no
## caminho não atrapalham e um inimigo no chão perto da trajetória intercepta.
func run_ground_pass(passer: Player, target: Player, ball: Ball) -> void:
	await _run_ground_pass(passer, target, ball)


## Passe rasteiro: a bola rola pelo chão até encostar no alvo (mesmo se estava suspensa).
## Aliados no caminho não atrapalham; inimigo no chão que chegue perto da trajetória
## intercepta e a bola para ali. Inimigo suspenso não alcança a bola: ela passa direto.
func _run_ground_pass(passer: Player, target: Player, ball: Ball) -> void:
	# Animação do passe: a bola só sai no frame de impacto (hit_frames["pass"]).
	# Sem arte ou sem a animação, segue direto como antes.
	passer.face_towards(target.global_position - passer.global_position)
	if not await passer.play_action(Player.ANIM_PASS):
		return   # ação cancelada (ex: a partida reiniciou)

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
	pass_completed.emit(passer, target)


## Passe rasteiro CURVILÍNEO (ex: Tactical do Niko): a bola faz um arco no chão (curva de Bézier)
## em vez de uma reta. curve_ratio = o quanto ela se desvia da reta, como fração da distância
## (0.25 = desvio máximo de 25% do comprimento do passe). bend_sign = +1 / -1 escolhe o lado da curva.
## Mesmas regras do passe rasteiro: aliados no caminho não atrapalham, inimigo no chão que chegue
## perto da trajetória intercepta, inimigo suspenso passa por baixo. fx = aura da bola (opcional).
func run_curved_ground_pass(passer: Player, target: Player, ball: Ball, curve_ratio: float,
		bend_sign: float, anim: StringName = &"", fx: KickFX = null) -> void:
	passer.face_towards(target.global_position - passer.global_position)
	var pass_anim: StringName = anim if anim != &"" else Player.ANIM_PASS
	if not await passer.play_action(pass_anim, Player.ANIM_PASS):
		return   # ação cancelada (ex: a partida reiniciou)

	var start: Vector2 = ball.global_position
	var to_target: Vector2 = target.global_position - start
	var dist: float = to_target.length()
	var gap: float = ball.collision_radius + target.body_radius + 2.0   # a bola para ENCOSTANDO no alvo
	if dist - gap < 1.0:
		return
	var end_point: Vector2 = start + to_target / dist * (dist - gap)
	var control: Vector2 = curve_control_point(start, end_point, curve_ratio, bend_sign)

	# Curva pré-calculada em pontos, com o comprimento acumulado (a bola anda em velocidade constante)
	var steps: int = 40
	var points: Array[Vector2] = [start]
	var lengths: Array[float] = [0.0]
	for i in range(1, steps + 1):
		var pt: Vector2 = curve_point(start, control, end_point, float(i) / float(steps))
		lengths.append(lengths[i - 1] + pt.distance_to(points[i - 1]))
		points.append(pt)
	var total: float = lengths[steps]

	ball.kick_ground((points[1] - start).normalized(), ground_pass_speed, passer, Ball.NO_SHOT)  # passe não é chute
	ball.height = 0.0
	ball.collisions_paused = true
	ball.trail_enabled = true
	if fx:
		ball.play_fx(fx)

	var travelled: float = 0.0
	var slow_zone: float = minf(total * 0.4, 160.0)   # reta final: a bola vai "amortecendo"
	var time_left: float = total / ground_pass_speed * 2.5 + 1.0   # trava de segurança
	while time_left > 0.0:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		time_left -= delta

		if _find_interceptor(passer.team, ball) != null:
			break
		var remaining: float = total - travelled
		if remaining <= 2.0:
			ball.global_position = end_point
			break
		var speed: float = ground_pass_speed * clampf(remaining / slow_zone, 0.15, 1.0)
		travelled = minf(travelled + speed * delta, total)
		# A bola é conduzida até o ponto da curva em que ela deveria estar agora
		var wanted: Vector2 = _point_along_curve(points, lengths, travelled)
		ball.velocity = (wanted - ball.global_position) / delta

	ball.velocity = Vector2.ZERO
	ball.collisions_paused = false
	ball.trail_enabled = false
	pass_completed.emit(passer, target)


## Ponto de controle da curva: o meio do caminho é empurrado para o lado "bend_sign" (+1 / -1)
## de forma que o desvio máximo da bola seja curve_ratio x a distância do passe.
static func curve_control_point(from: Vector2, to: Vector2, curve_ratio: float, bend_sign: float) -> Vector2:
	var chord: Vector2 = to - from
	if chord.length() < 0.001:
		return from
	var normal: Vector2 = chord.orthogonal().normalized()
	# Numa curva quadrática o desvio máximo é METADE do deslocamento do ponto de controle
	return (from + to) * 0.5 + normal * bend_sign * chord.length() * curve_ratio * 2.0


## Ponto da curva (Bézier quadrática) em t (0 = começo, 1 = fim)
static func curve_point(from: Vector2, control: Vector2, to: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return from * (u * u) + control * (2.0 * u * t) + to * (t * t)


## Ponto do caminho (lista de pontos + comprimento acumulado) depois de andar "dist" px
func _point_along_curve(points: Array[Vector2], lengths: Array[float], dist: float) -> Vector2:
	var last: int = points.size() - 1
	if dist >= lengths[last]:
		return points[last]
	for i in range(1, points.size()):
		if lengths[i] >= dist:
			var seg: float = lengths[i] - lengths[i - 1]
			var f: float = (dist - lengths[i - 1]) / seg if seg > 0.0001 else 1.0
			return points[i - 1].lerp(points[i], f)
	return points[last]


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
	# Animação do passe alto ("pass_high"; cai em "pass" e depois em "kick" se não existir)
	passer.face_towards(target.global_position - passer.global_position)
	if not await passer.play_action(Player.ANIM_PASS_HIGH):
		return

	ball.register_touch(passer)  # o passe alto não usa kick(), então registra o toque aqui
	_pass_origin = passer.global_position
	_pass_max_range = pass_range_for(PassVariant.HIGH, passer)
	_pass_aim_point = target.global_position
	_spawn_pass_marker(passer.team, _pass_aim_point, ball)

	var midpoint: Vector2 = (ball.global_position + _pass_aim_point) * 0.5
	var tween: Tween = ball.hover_to(midpoint, Heights.FLYING_HEIGHT, high_pass_flight_time)
	await tween.finished
	_pass_stage = PassStage.FLYING
	_pass_team = passer.team
	_pass_target = target
	pass_completed.emit(passer, target)


## Versão do passe alto para HABILIDADES (ex: Chilling Pass / No Look Cross do Hiori):
## mesmo comportamento do passe alto comum (_run_high_pass) — sobe a Voando no meio do
## caminho, pousa no alvo a Suspenso quando o turno do time voltar, cai sozinha se
## ninguém tocar — mas com animação própria, aura (fx) e um alcance que não precisa ser
## o high_pass_range padrão (cada habilidade tem o seu).
func run_skill_high_pass(passer: Player, target: Player, ball: Ball, range_px: float,
		anim: StringName = &"", fx: KickFX = null) -> void:
	passer.face_towards(target.global_position - passer.global_position)
	var pass_anim: StringName = anim if anim != &"" else Player.ANIM_PASS_HIGH
	if not await passer.play_action(pass_anim, Player.ANIM_PASS_HIGH):
		return   # ação cancelada (ex: a partida reiniciou)

	ball.register_touch(passer)  # o passe alto não usa kick(), então registra o toque aqui
	_pass_origin = passer.global_position
	_pass_max_range = range_px
	_pass_aim_point = target.global_position
	_spawn_pass_marker(passer.team, _pass_aim_point, ball)

	var midpoint: Vector2 = (ball.global_position + _pass_aim_point) * 0.5
	var tween: Tween = ball.hover_to(midpoint, Heights.FLYING_HEIGHT, high_pass_flight_time)
	if fx:
		ball.play_fx(fx)
	await tween.finished
	_pass_stage = PassStage.FLYING
	_pass_team = passer.team
	_pass_target = target
	pass_completed.emit(passer, target)


## Onde o passe alto pousa: no alvo, se ele ainda está dentro do alcance (medido de onde o
## passe saiu). Se ele se afastou demais, a bola cai onde o alvo estava quando o passe saiu.
func _pass_landing_point() -> Vector2:
	var limit: float = _pass_max_range if _pass_max_range > 0.0 else high_pass_range
	if _pass_target != null \
			and _pass_target.global_position.distance_to(_pass_origin) <= limit:
		return _pass_target.global_position
	return _pass_aim_point


func _process(_delta: float) -> void:
	if _picking_skill_point and _skill_point_marker != null and _skill_point_actor != null:
		var mouse: Vector2 = _skill_point_actor.get_global_mouse_position()
		var offset: Vector2 = mouse - _skill_point_actor.global_position
		if offset.length() > _skill_point_range:
			offset = offset.normalized() * _skill_point_range
		_skill_point_marker.global_position = _skill_point_actor.global_position + offset

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


## Para habilidades que mexem na bola pairando (ex: Ness): descarta o passe alto em andamento
func clear_pending_pass() -> void:
	_clear_pending_pass()


func _clear_pending_pass() -> void:
	_pass_max_range = 0.0
	_pass_stage = PassStage.NONE
	_pass_team = -1
	_pass_target = null
	_remove_pass_marker()


func _spawn_pass_marker(team: int, pos: Vector2, ball: Ball) -> void:
	_remove_pass_marker()
	_pass_marker = PassMarker.new()
	_pass_marker.color = TeamStyle.color_of(team).lightened(0.4)
	ball.get_parent().add_child(_pass_marker)
	_pass_marker.global_position = pos


func _remove_pass_marker() -> void:
	if _pass_marker != null and is_instance_valid(_pass_marker):
		_pass_marker.fade_out()
	_pass_marker = null


## passer (opcional) soma o bônus de alcance do jogador (ex: Orbital Orbital do Kurona)
func pass_range_for(variant: PassVariant, passer: Player = null) -> float:
	var base: float = high_pass_range if variant == PassVariant.HIGH else ground_pass_range
	return base + (passer.pass_range_bonus if passer != null else 0.0)


## O alvo é companheiro (outro jogador do time) e está dentro do alcance da variante?
func can_pass_to(passer: Player, target: Player, variant: PassVariant) -> bool:
	if target == passer or target.team != passer.team:
		return false
	if target.is_pass_blocked():   # ex: marcado pelo Ace Eater do Lorenzo
		return false
	return passer.global_position.distance_to(target.global_position) <= pass_range_for(variant, passer)


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
	active_player.range_preview = pass_range_for(pass_variant, active_player)
	for other in get_team_players(current_team):
		other.is_pass_option = can_pass_to(active_player, other, pass_variant)


func _hide_pass_preview() -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		p.range_preview = 0.0
		p.is_pass_option = false


## A habilidade (pelo id) pode ser usada agora por quem está agindo?
func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not can_act():
		return false
	# Sem ação de habilidade sobrando só passa quem é "gratuito" (ex: Draconic Header)
	if skill_left_for(active_player) <= 0 and not active_player.skill_is_free(skill_id):
		return false
	return active_player.can_use_skill(skill_id)


## A última mira / escolha de alvo / escolha de ponto de uma habilidade foi CANCELADA (Esc ou
## clique direito)? Vale a ÚLTIMA escolha: se a habilidade pede duas e a segunda deu certo, volta a false.
var _skill_pick_cancelled: bool = false


## Mostra no console o gasto das ações de habilidade (para depurar). Desligue depois.
@export var debug_skill_cost: bool = false


## Chamado pelos botões de habilidade do menu.
## A ação de habilidade é PAGA ANTES de a habilidade executar e DEVOLVIDA se ela for cancelada
## (Esc / clique direito na mira) ou não tiver sido usada. Assim o gasto não depende de nada
## que aconteça durante o await (troca de active_player, gol, etc.).
func do_skill_action(skill_id: StringName = &"default") -> void:
	if not can_use_skill(skill_id):
		_waste_confused_skill(skill_id)
		return

	var actor: Player = active_player
	var cooldowns_before: Dictionary = actor.snapshot_cooldowns()
	var payment: Dictionary = _pay_skill_cost(actor, skill_id)
	_skill_pick_cancelled = false
	_set_phase(Phase.EXECUTING)
	var used: bool = await actor.use_skill(skill_id)

	# Rede de segurança: se o jogador cancelou a mira/escolha, a habilidade NÃO foi usada, mesmo que
	# o script do personagem tenha devolvido true (ou já tenha iniciado a recarga) por engano
	var cancelled: bool = _skill_pick_cancelled
	_skill_pick_cancelled = false
	if cancelled:
		used = false
		if is_instance_valid(actor):
			actor.restore_cooldowns(cooldowns_before)

	if not used:
		_refund_skill_cost(payment)
		_set_phase(Phase.CHOOSING_ACTION)
		return

	_after_action()


## CONFUNDO: com os botões embaralhados ("???"), escolher uma habilidade que NÃO dá para usar
## (em recarga, sem alvo no alcance...) gasta a ação de habilidade mesmo assim e não devolve.
## Sem isso dava para clicar em todas até achar uma que funcione. Só vale para quem está
## confuso, e só se ainda sobrar ação de habilidade para gastar.
func _waste_confused_skill(skill_id: StringName) -> void:
	if not can_act() or active_player == null or not active_player.is_confused():
		return
	if skill_left_for(active_player) <= 0 or active_player.skill_is_free(skill_id):
		return   # nada para gastar
	var who: String = active_player.get_display_name()   # o _after_action pode trocar/limpar o active_player
	_pay_skill_cost(active_player, skill_id)   # sem recibo: nunca devolve
	_after_action()
	if phase == Phase.CHOOSING_ACTION:   # se o turno acabou, o aviso não faz sentido
		pass_hint = "%s está confuso: a habilidade escolhida não pôde ser usada e a ação foi gasta!" % who
		state_changed.emit()


## Gasta a ação de habilidade de quem vai usar a habilidade e devolve um "recibo" para
## _refund_skill_cost. Habilidades gratuitas (skill_is_free) não gastam nada.
## A ação extra só do jogador (ex: Obsessive Lover) é gasta primeiro e preserva a pool do time.
func _pay_skill_cost(actor: Player, skill_id: StringName) -> Dictionary:
	var receipt: Dictionary = {"actor": actor, "kind": &"none"}
	if actor.skill_is_free(skill_id):
		if debug_skill_cost:
			print("[skill] ", skill_id, " é gratuita: nada gasto")
		return receipt
	if actor.extra_skill_left > 0:
		actor.extra_skill_left -= 1
		receipt["kind"] = &"extra"
	elif actor == protagonist:
		protagonist_skill_left = maxi(0, protagonist_skill_left - 1)
		receipt["kind"] = &"protagonist"
	else:
		secondary_skill_left = maxi(0, secondary_skill_left - 1)
		receipt["kind"] = &"secondary"
	if debug_skill_cost:
		print("[skill] ", skill_id, " pagou de '", receipt["kind"], "' -> prot=",
			protagonist_skill_left, " sec=", secondary_skill_left, " extra=", actor.extra_skill_left)
	return receipt


func _refund_skill_cost(receipt: Dictionary) -> void:
	var actor: Player = receipt.get("actor") as Player
	match receipt.get("kind", &"none"):
		&"extra":
			if is_instance_valid(actor):
				actor.extra_skill_left += 1
		&"protagonist":
			protagonist_skill_left += 1
		&"secondary":
			secondary_skill_left += 1
	if debug_skill_cost:
		print("[skill] gasto devolvido (", receipt.get("kind", &"none"), ") -> prot=",
			protagonist_skill_left, " sec=", secondary_skill_left)


## Mira para uma habilidade de personagem. Devolve a direção (Vector2.ZERO = cancelou).
func aim_for_skill(actor: Player, range_px: float) -> Vector2:
	_set_phase(Phase.AIMING)
	actor.begin_aim(range_px)
	var dir: Vector2 = await actor.aim_finished
	_skill_pick_cancelled = (dir == Vector2.ZERO)
	_set_phase(Phase.EXECUTING)
	return dir


## Habilidade que precisa de um ALVO como alvo (ex: Puppets do Rin escolhe um companheiro;
## Snake Lunge/Bloom do Aiku escolhe um inimigo): mostra o alcance e destaca quem pode ser
## escolhido, e espera o clique. Devolve o escolhido (null = cancelou: clique direito ou Esc).
## A fase fica em "mirando" enquanto espera.
## enemies = true: só inimigos contam. false (padrão) = só companheiros.
## extra_filter(other: Player) -> bool, se dado, filtra ainda mais quem é "válido"
## (ex: só inimigos "no chão"); quem não passa no filtro não acende o anel verde e,
## se clicado, mostra um aviso em vez de ser escolhido.
func pick_ally_for_skill(actor: Player, range_px: float, enemies: bool = false,
		extra_filter: Callable = Callable()) -> Player:
	_picking_skill_target = true
	_skill_target_actor = actor
	_skill_target_range = range_px
	_skill_target_same_team = not enemies
	_skill_target_filter = extra_filter
	pass_hint = ""
	_set_phase(Phase.AIMING)
	actor.range_preview = range_px
	for other: Player in get_tree().get_nodes_in_group("players"):
		var team_ok: bool = (other.team == actor.team) if _skill_target_same_team \
			else (other.team != actor.team)
		var extra_ok: bool = not extra_filter.is_valid() or extra_filter.call(other)
		other.is_pass_option = other != actor and team_ok and extra_ok \
			and actor.global_position.distance_to(other.global_position) <= range_px
	var target: Player = await skill_target_picked
	_skill_pick_cancelled = (target == null)
	_picking_skill_target = false
	_skill_target_actor = null
	_skill_target_filter = Callable()
	_hide_pass_preview()
	_set_phase(Phase.EXECUTING)
	return target


## Habilidade que precisa de um LOCAL do campo como alvo (ex: Rabona Cross do Charles,
## que escolhe onde a bola vai cair em vez de um aliado). Mostra o alcance (o mesmo
## anel branco do Passe/pick_ally_for_skill) e uma marca acompanhando o mouse, e espera
## o clique. Devolve o ponto escolhido (Vector2.INF = cancelou: clique direito ou Esc).
## Clicar fora do alcance não cancela: só mostra o aviso e continua esperando.
func pick_point_for_skill(actor: Player, range_px: float) -> Vector2:
	_picking_skill_point = true
	_skill_point_actor = actor
	_skill_point_range = range_px
	pass_hint = ""
	_set_phase(Phase.AIMING)
	actor.range_preview = range_px
	_spawn_skill_point_marker(actor.team)
	var point: Vector2 = await skill_point_picked
	_skill_pick_cancelled = (point == Vector2.INF)
	_picking_skill_point = false
	_skill_point_actor = null
	actor.range_preview = 0.0
	_remove_skill_point_marker()
	_set_phase(Phase.EXECUTING)
	return point


func _try_pick_skill_point(point: Vector2) -> void:
	var actor: Player = _skill_point_actor
	if actor == null:
		return
	if actor.global_position.distance_to(point) <= _skill_point_range:
		skill_point_picked.emit(point)
	else:
		pass_hint = "Fora do alcance!"
		state_changed.emit()


func _spawn_skill_point_marker(team: int) -> void:
	_remove_skill_point_marker()
	var ball: Ball = _get_ball()
	if ball == null:
		return
	_skill_point_marker = PassMarker.new()
	_skill_point_marker.color = TeamStyle.color_of(team).lightened(0.4)
	ball.get_parent().add_child(_skill_point_marker)


func _remove_skill_point_marker() -> void:
	if _skill_point_marker != null and is_instance_valid(_skill_point_marker):
		_skill_point_marker.fade_out()
	_skill_point_marker = null


func _try_pick_skill_target(player: Player) -> void:
	var actor: Node2D = _skill_target_actor
	if actor == null or player == actor:
		return
	var actor_team: int = actor.get("team")
	var team_ok: bool = (player.team == actor_team) if _skill_target_same_team \
		else (player.team != actor_team)
	if not team_ok:
		return
	if _skill_target_filter.is_valid() and not _skill_target_filter.call(player):
		pass_hint = "%s não é um alvo válido agora!" % player.get_display_name()
		state_changed.emit()
		return
	if actor.global_position.distance_to(player.global_position) <= _skill_target_range:
		skill_target_picked.emit(player)
	else:
		pass_hint = "%s está fora do alcance!" % player.get_display_name()
		state_changed.emit()


## Habilidades que terminam num passe alto (ex: Puppets) avisam o manager: a bola fica
## pairando (Suspensa) no alvo até alguém tocar nela ou o turno do time acabar,
## igual ao Passe alto normal.
func register_skill_pass(passer_team: int, target: Player) -> void:
	_clear_pending_pass()
	_pass_stage = PassStage.RECEIVED
	_pass_team = passer_team
	_pass_target = target


## Começa o acompanhamento de um passe alto de habilidade que pousa num PONTO do
## campo, em vez de num aliado (ex: Rabona Cross do Charles: ele escolhe o local,
## não quem recebe). Quem chama já deve ter deixado a bola PAIRANDO (hover_to) no
## nível Voando, a caminho de landing_point; isto só liga o resto do fluxo do
## passe alto comum: quando o turno de "passer_team" voltar, a bola desce até
## landing_point no nível Suspenso (_update_pass_on_turn_start), e se ninguém
## tocar nela até o turno acabar, ela cai sozinha para o chão (_end_turn).
func begin_point_pass(passer_team: int, landing_point: Vector2) -> void:
	_clear_pending_pass()
	_pass_stage = PassStage.FLYING
	_pass_team = passer_team
	_pass_target = null
	_pass_aim_point = landing_point
	_pass_max_range = 0.0


## Minigame de digitação para as habilidades (devolve true se acertou a palavra a tempo)
func run_typing_game(title: String, words: Array[String], time_limit: float) -> bool:
	var game := TypingGame.new()
	add_child(game)
	game.start(String(words.pick_random()), time_limit, title)
	var ok: bool = await game.finished
	return ok


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


func _consume_general(action: int = -1) -> void:
	# A extra "sem Correr" (ex: Unleash Instinct do Bachira) é gasta primeiro, mas nunca no Correr
	if action != GeneralAction.RUN and active_player.extra_general_no_run_left > 0:
		active_player.extra_general_no_run_left -= 1
		return
	# A ação extra só do jogador (ex: Gremlin Taunt do Charles) é gasta primeiro e preserva a pool do time
	if active_player.extra_general_left > 0:
		active_player.extra_general_left -= 1
		return
	if active_player == protagonist:
		protagonist_general_left -= 1
	else:
		secondary_general_left -= 1


## Mantido por compatibilidade (algum script de personagem pode chamar): gasta uma ação
## de habilidade de quem está agindo agora. O do_skill_action já paga sozinho, não use os dois.
func _consume_skill() -> void:
	if active_player != null:
		_pay_skill_cost(active_player, &"")


func _after_action() -> void:
	# Partida acabou durante a ação: não volta para a escolha de ações
	if match_over:
		return

	# Complemento gratuito esperando (ex: Draconic Header): o turno não acaba sozinho
	var followup: bool = active_player != null and active_player.has_free_followup()

	# Acabaram todas as ações do time -> passa o turno
	if total_actions_left() <= 0 and not followup:
		_end_turn()
		return

	# Se o secundário em ação esgotou a pool, volta para o Protagonista
	if active_player != protagonist and not followup \
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


# ---------- EFEITOS DE FIM DE TURNO ----------

## Quem do time que acabou de jogar tem um efeito de fim de turno age agora (um de cada vez)
## e o jogo espera cada um terminar.
func _run_turn_end_effects(team: int) -> void:
	var runners: Array[Player] = []
	for p in get_team_players(team):
		if p.has_turn_end_effect():
			runners.append(p)
	if runners.is_empty():
		return
	_set_phase(Phase.TEAM_EFFECTS)
	for p in runners:
		await p.on_turn_end()
		if match_over:
			return


# ---------- GOLEIROS ----------

func _any_keeper_busy() -> bool:
	for k: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
		if k.is_busy():
			return true
	return false


func _any_keeper_waiting_for_player() -> bool:
	for k: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
		if k.is_waiting_for_player():
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
		# Esperando o jogador escolher o alvo do lançamento: o tempo limite não corre
		if not _any_keeper_waiting_for_player():
			time_left -= get_physics_process_delta_time()
	# Trava de segurança: se algo emperrar, o jogo segue
	for k: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
		if k.is_busy():
			k.cancel_action()


## Os goleiros avisam o que fizeram por aqui; o HUD mostra
func announce_keeper(text: String, team: int) -> void:
	keeper_event.emit(text, team)


## Goleiro que deixa o jogador escolher para quem lançar (ex: Fukaku). Mostra o alcance, destaca
## os companheiros que dá para alcançar e espera o clique. Devolve o escolhido (null = cancelou:
## clique direito ou Esc, ou a partida acabou). Não mexe na fase: quem chama (o fluxo dos
## goleiros) já a deixa em "goleiros agindo".
func pick_throw_target(keeper: Goalkeeper, range_px: float) -> Player:
	_picking_skill_target = true
	_skill_target_actor = keeper
	_skill_target_range = range_px
	_skill_target_same_team = true
	_skill_target_filter = Callable()
	pass_hint = ""
	keeper.range_preview = range_px
	for other: Player in get_tree().get_nodes_in_group("players"):
		other.is_pass_option = other.team == keeper.team \
			and keeper.global_position.distance_to(other.global_position) <= range_px
	var target: Player = await skill_target_picked
	_picking_skill_target = false
	_skill_target_actor = null
	if is_instance_valid(keeper):
		keeper.range_preview = 0.0
	_hide_pass_preview()
	return target


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
	_record_goal_stats(scorer, assist, own_goal)
	goal_scored.emit(goal)
	state_changed.emit()

	# Gol de ouro: na prorrogação, QUALQUER gol (inclusive contra) decide a
	# partida na hora, mesmo sem chegar em goals_to_win.
	if in_extra_time:
		_end_match(scoring_team)
	elif scores[scoring_team] >= goals_to_win:
		_end_match(scoring_team)


## winning_team = -1 para empate (prorrogação esgotada sem gols)
func _end_match(winning_team: int) -> void:
	match_over = true
	winner = winning_team
	mvp = _compute_mvp()
	if _picking_skill_target:
		skill_target_picked.emit(null)   # a habilidade que esperava um alvo termina sem efeito
	if _picking_skill_point:
		skill_point_picked.emit(Vector2.INF)   # idem para quem esperava um ponto do campo
	_hide_pass_preview()
	# Se alguém estava mirando, cancela (a ação em andamento termina sem efeito)
	if active_player and active_player.is_aiming:
		active_player.cancel_aim()
	_clear_roles()
	_set_phase(Phase.MATCH_OVER)
	match_ended.emit(winner)


# ---------- MVP ----------

## Ficha de estatísticas do jogador (cria na primeira vez que ele aparece)
func _stats_for(p: Player) -> Dictionary:
	var key: int = p.get_instance_id()
	if not player_stats.has(key):
		player_stats[key] = {
			"name": p.get_display_name(),
			"character_id": p.character_id,
			"team": p.team,
			"goals": 0,
			"assists": 0,
			"golden": false,
			"win": 0,
			"points": 0,
			"image": p.get_mvp_image(),
		}
	return player_stats[key]


## Soma os pontos de um gol. Na prorrogação qualquer gol decide o jogo (gol de ouro),
## então o autor leva mvp_golden_goal_points em vez de mvp_goal_points.
func _record_goal_stats(scorer: Player, assist: Player, own_goal: bool) -> void:
	if scorer != null and not own_goal:
		var s: Dictionary = _stats_for(scorer)
		s["goals"] += 1
		s["golden"] = in_extra_time
		s["points"] += mvp_golden_goal_points if in_extra_time else mvp_goal_points
	if assist != null:
		var a: Dictionary = _stats_for(assist)
		a["assists"] += 1
		a["points"] += mvp_assist_points


## Fim de jogo: todo jogador do time vencedor ganha o ponto da vitória e o MVP é
## quem somou mais. Empate de pontos: mais gols, depois mais assistências, depois
## quem é do time vencedor. Devolve {} se ninguém pontuou (ex: empate sem gols).
func _compute_mvp() -> Dictionary:
	if winner >= 0:
		for p in get_team_players(winner):
			var s: Dictionary = _stats_for(p)
			s["win"] = mvp_win_points
			s["points"] += mvp_win_points

	var best: Dictionary = {}
	for entry: Dictionary in player_stats.values():
		if entry["points"] <= 0:
			continue
		if best.is_empty() or _is_better_mvp(entry, best):
			best = entry
	return best


func _is_better_mvp(a: Dictionary, b: Dictionary) -> bool:
	if a["points"] != b["points"]:
		return a["points"] > b["points"]
	if a["goals"] != b["goals"]:
		return a["goals"] > b["goals"]
	if a["assists"] != b["assists"]:
		return a["assists"] > b["assists"]
	return a["team"] == winner and b["team"] != winner


# ---------- UTIL ----------

func get_team_players(team: int) -> Array[Player]:
	var result: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team:
			result.append(p)
	return result


## Nome do time: o que o jogador digitou na formação, ou o padrão (team_names)
func get_team_name(team: int) -> String:
	return TeamStyle.name_of(team, get_default_team_name(team))


func get_default_team_name(team: int) -> String:
	if team < team_names.size():
		return team_names[team]
	return "Time %d" % team


## Texto curto do momento da partida: "1º Tempo", "2º Tempo" ou "Prorrogação"
func time_label() -> String:
	if in_extra_time:
		return "Prorrogação"
	return "1º Tempo" if current_half == 1 else "2º Tempo"


## Rodada dentro do tempo atual (ex: 3 na 3ª rodada do 2º tempo, ou da prorrogação)
func round_in_half() -> int:
	if in_extra_time:
		return round_number - (rounds_per_half * 2)
	if current_half == 2:
		return round_number - rounds_per_half
	return round_number


## Quantas rodadas tem o tempo atual (a prorrogação pode ter uma duração diferente)
func rounds_in_current_half() -> int:
	return extra_time_rounds if in_extra_time else rounds_per_half


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
