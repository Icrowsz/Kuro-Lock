class_name Goalkeeper
extends Node2D
## Goleiro autônomo: age sozinho, sem ser controlado pelo jogador.
##
## O Field cria um goleiro por time automaticamente (spawn_goalkeepers). Se preferir,
## coloque um nó com este script na cena e defina o "team": o Field não cria outro
## para esse time. Time 0 defende o gol da esquerda; time 1, o da direita.
##
## COMPORTAMENTO
## 1) Bola na grande área (qualquer altura, desde que ninguém a esteja segurando):
##    o goleiro se PREPARA por "prepare_rounds" rodadas (uma rodada = um ciclo completo de
##    turnos, ou seja, team_count turnos terminando). Se alguém interagir com a bola nesse
##    tempo (chute, passe, carrinho, empurrão...), o preparo recomeça.
##    Passado o tempo, o goleiro SALTA na bola e a segura.
## 2) Com a bola nas mãos, repete o ciclo: espera o mesmo tempo e LANÇA a bola para um
##    aliado aleatório de longo alcance (preferindo quem está fora da área).
##    A bola vai no nível VOANDO (jogadores adversários SUSPENSOS, que pularam, podem
##    interceptar) e, ao chegar no aliado, cai no CHÃO.
## 3) Chute em direção ao gol (ação Chutar, habilidade ou carrinho): ao entrar na área
##    acontece uma disputa de sorte. A chance de o chute vencer o goleiro vem do chute
##    (padrão 30%, voleio 35%, bola voando 40%). Se vencer, a bola segue; se perder, o
##    goleiro defende e fica com a bola (e entra no ciclo do item 2).

enum State { IDLE, PREPARING, DIVING, HOLDING, THROWING }

## Time que o goleiro defende (0 = gol da esquerda, 1 = gol da direita)
@export var team: int = 0

@export_group("Preparo e lançamento")
@export var prepare_rounds: int = 1            # rodadas de preparo (antes de saltar e antes de lançar)
@export var throw_range: float = 900.0         # alcance do lançamento (px)
@export var throw_speed: float = 700.0         # velocidade da bola no ar (px/s)
@export var throw_rise_time: float = 0.2       # tempo para a bola subir ao nível Voando
@export var throw_land_time: float = 0.25      # tempo da queda ao chegar no aliado
@export var intercept_radius: float = 40.0     # adversário suspenso a esta distância intercepta

@export_group("Defesa")
@export var home_offset: float = 40.0          # distância da linha de fundo onde o goleiro fica
@export var dive_speed: float = 1100.0         # velocidade ao ir na bola (px/s)
@export var walk_speed: float = 220.0          # velocidade ao voltar para a posição
@export var catch_radius: float = 26.0         # a esta distância da bola o goleiro a segura
@export var max_dive_time: float = 1.5         # trava de segurança do salto
@export var hold_height: float = 24.0          # altura da bola nas mãos
@export var jump_height: float = 45.0          # altura do salto (visual)

@export_group("Visual")
@export var body_radius: float = 20.0
@export var keeper_color: Color = Color(0.98, 0.82, 0.15)

var state: State = State.IDLE:
	set(value):
		state = value
		queue_redraw()
var height: float = 0.0:
	set(value):
		height = value
		queue_redraw()

var field: Field
var ball: Ball
var manager: MatchManager

var _turns_left: int = 0
var _interaction_mark: int = 0
var _catch_forced: bool = false
var _dive_time: float = 0.0
var _token: int = 0                 # muda ao cancelar: corrotinas antigas se encerram
var _move_tween: Tween
var _jump_tween: Tween


func _ready() -> void:
	add_to_group("goalkeepers")
	_late_setup.call_deferred()  # espera Field, Ball e MatchManager existirem


func _late_setup() -> void:
	field = get_tree().get_first_node_in_group("field") as Field
	ball = get_tree().get_first_node_in_group("ball") as Ball
	manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if field == null or ball == null:
		push_warning("Goalkeeper: Field ou Ball não encontrados; o goleiro não vai agir.")
		return

	global_position = _home_position()
	ball.was_reset.connect(_on_ball_reset)
	if manager:
		manager.turn_ended.connect(_on_turn_ended)
		manager.match_ended.connect(_on_match_ended)
	else:
		push_warning("Goalkeeper: MatchManager não encontrado; o preparo por rodadas não vai andar.")


# ---------- API ----------

## O MatchManager espera o goleiro terminar antes de começar o próximo turno
func is_busy() -> bool:
	return state == State.DIVING or state == State.THROWING


## Volta ao estado de começo de partida (usado quando o jogo recomeça depois do fim de jogo)
func restart() -> void:
	if field == null or ball == null:
		return
	set_physics_process(true)   # o fim de jogo desliga o goleiro
	_cancel_all()
	_turns_left = 0
	_catch_forced = false
	_interaction_mark = ball.interaction_count
	global_position = _home_position()


## Interrompe o que o goleiro está fazendo (e solta a bola, se estiver com ela)
func cancel_action() -> void:
	var had_ball: bool = ball != null and ball.held_by == self
	_cancel_all()
	if had_ball:
		ball.release_hover()


# ---------- LOOP ----------

func _physics_process(delta: float) -> void:
	if field == null or ball == null or (manager != null and manager.match_over):
		return
	z_index = int(global_position.y)

	match state:
		State.IDLE:
			_process_idle(delta)
		State.PREPARING:
			_process_preparing(delta)
		State.DIVING:
			_process_diving(delta)
		State.HOLDING:
			_process_holding(delta)
		State.THROWING:
			pass  # a corrotina _throw_ball controla a bola


func _process_idle(delta: float) -> void:
	if _try_shot_contest():
		return
	_walk_home(delta)
	if _ball_in_area() and not ball.is_held():
		_begin_preparing()


func _process_preparing(delta: float) -> void:
	if _try_shot_contest():
		return
	_walk_home(delta)
	if not _ball_in_area() or ball.is_held():
		state = State.IDLE
		return
	# Alguém interagiu com a bola: o preparo recomeça do zero
	if ball.interaction_count != _interaction_mark:
		_begin_preparing()


func _process_diving(delta: float) -> void:
	_dive_time += delta
	if ball.is_held():
		state = State.IDLE  # outra pessoa (ou outro goleiro) pegou a bola
		return

	var target: Vector2 = ball.global_position
	global_position = global_position.move_toward(target, dive_speed * delta)

	var close: bool = global_position.distance_to(target) <= catch_radius
	# Defesa de um chute: a bola NUNCA passa do goleiro (ele a segura na linha)
	var passed: bool = _catch_forced and _ball_passed_line()
	var timeout: bool = _dive_time >= max_dive_time
	if close or passed or (_catch_forced and timeout):
		_catch_ball()
	elif timeout:
		state = State.IDLE  # não alcançou a bola


func _process_holding(delta: float) -> void:
	_walk_home(delta)  # volta para a posição carregando a bola
	if ball.held_by != self:
		_cancel_all()  # alguém tirou a bola
		return
	ball.global_position = global_position
	ball.height = hold_height + height


func _walk_home(delta: float) -> void:
	if _move_tween and _move_tween.is_valid():
		return
	global_position = global_position.move_toward(_home_position(), walk_speed * delta)


# ---------- PREPARO (conta turnos) ----------

func _begin_preparing() -> void:
	state = State.PREPARING
	_turns_left = _turns_needed()
	_interaction_mark = ball.interaction_count


func _turns_needed() -> int:
	var turns_per_round: int = manager.team_count if manager else 2
	return maxi(1, prepare_rounds) * turns_per_round


func _on_turn_ended(_ended_team: int) -> void:
	match state:
		State.PREPARING:
			_turns_left -= 1
			if _turns_left > 0:
				return
			if _ball_in_area() and not ball.is_held():
				_start_catch(false)
			else:
				state = State.IDLE
		State.HOLDING:
			_turns_left -= 1
			if _turns_left <= 0:
				_throw_ball()


# ---------- DISPUTA DO CHUTE ----------

## Chute em direção ao gol que acabou de entrar na área: sorteia contra a chance do chute.
## Devolve true se a disputa aconteceu.
func _try_shot_contest() -> bool:
	if not ball.has_pending_shot() or ball.shot_team == team or ball.is_held():
		return false
	if not _ball_in_area() or not _shot_on_target():
		return false

	var chance: float = ball.pending_shot_chance
	ball.pending_shot_chance = Ball.NO_SHOT  # cada chute só é disputado uma vez
	var beaten: bool = randf() < chance
	_announce_contest(chance, beaten)

	if beaten:
		_dive_and_miss()
	else:
		_start_catch(true)
	return true


## A bola vai cruzar a linha de fundo dentro da boca do gol e abaixo do travessão?
## (mesma regra que o Field usa para dar o gol)
func _shot_on_target() -> bool:
	var crossing: Vector2 = _predict_goal_crossing()
	if not crossing.is_finite():
		return false
	var half_mouth: float = field.goal_width * 0.5 - field.post_radius - field.ball_hit_radius
	return absf(crossing.x) < half_mouth \
		and crossing.y < field.crossbar_height - field.crossbar_thickness


## (y no campo, altura) onde a bola cruzaria a linha de fundo; Vector2.INF se não vai para o gol
func _predict_goal_crossing() -> Vector2:
	var dir: int = _dir()
	var p: Vector2 = field.to_local(ball.global_position)
	var v: Vector2 = ball.velocity
	if v.length() < 40.0 or v.x * dir <= 0.0:
		return Vector2.INF
	var gx: float = field.pitch_size.x * 0.5 * dir
	var t: float = (gx - p.x) / v.x
	if t < 0.0:
		return Vector2.INF
	var y: float = p.y + v.y * t
	var h: float = ball.height + ball.vel_z * t - 0.5 * ball.gravity * t * t
	return Vector2(y, h)


## O chute venceu a disputa: o goleiro se joga na direção da bola, mas não alcança (só visual)
func _dive_and_miss() -> void:
	var crossing: Vector2 = _predict_goal_crossing()
	var local_home: Vector2 = _home_local()
	var shot_y: float = crossing.x if crossing.is_finite() else local_home.y
	# Vai só até a metade do caminho: fica curto
	var miss_point: Vector2 = field.to_global(Vector2(local_home.x, lerpf(local_home.y, shot_y, 0.5)))

	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", miss_point, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_play_jump()


# ---------- SALTAR NA BOLA E SEGURAR ----------

func _start_catch(forced: bool) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	state = State.DIVING
	_catch_forced = forced
	_dive_time = 0.0


func _catch_ball() -> void:
	global_position = ball.global_position
	ball.clear_touches()  # a posse recomeça do zero: próximo toque é de quem receber
	ball.hold(self)
	_turns_left = _turns_needed()
	state = State.HOLDING
	_play_jump()
	if not _catch_forced:
		_say("Goleiro do %s saltou na bola!" % _team_name(team))


func _ball_passed_line() -> bool:
	var p: Vector2 = field.to_local(ball.global_position)
	return (p.x - _home_local().x) * _dir() > 0.0


# ---------- LANÇAMENTO ----------

func _throw_ball() -> void:
	state = State.THROWING  # antes de qualquer await: o MatchManager já vê o goleiro ocupado
	var token: int = _token

	var target: Player = _pick_throw_target()
	if target == null:
		ball.release_hover()
		state = State.IDLE
		return
	_say("Goleiro do %s lança a bola!" % _team_name(team))

	var start: Vector2 = ball.global_position
	var duration: float = clampf(start.distance_to(_landing_point(target, start)) / throw_speed, 0.6, 2.5)
	ball.trail_enabled = true

	# Voo: a bola vai ao aliado no nível Voando
	var elapsed: float = 0.0
	while elapsed < duration:
		await get_tree().physics_frame
		if not _throw_alive(token):
			return
		elapsed += get_physics_process_delta_time()
		var t: float = clampf(elapsed / duration, 0.0, 1.0)
		ball.global_position = start.lerp(_landing_point(target, start), t)
		var rise: float = smoothstep(0.0, 1.0, clampf(elapsed / throw_rise_time, 0.0, 1.0))
		ball.height = lerpf(hold_height, Heights.FLYING_HEIGHT, rise)

		# Só intercepta quando já está no nível Voando
		if elapsed >= throw_rise_time:
			var hit: Player = _find_interceptor()
			if hit != null:
				_intercepted(hit)
				return

	# Chegou no alvo: cai no chão
	var fall: float = 0.0
	while fall < throw_land_time:
		await get_tree().physics_frame
		if not _throw_alive(token):
			return
		fall += get_physics_process_delta_time()
		var f: float = clampf(fall / throw_land_time, 0.0, 1.0)
		ball.height = lerpf(Heights.FLYING_HEIGHT, 0.0, f * f)

	ball.height = 0.0
	ball.release_hover()  # física volta: a bola fica no chão, parada
	state = State.IDLE


func _throw_alive(token: int) -> bool:
	if token != _token or ball.held_by != self:
		return false
	return manager == null or not manager.match_over


## A bola cai ENCOSTADA no aliado (do lado de onde veio), nunca em cima dele
func _landing_point(target: Player, from: Vector2) -> Vector2:
	var away: Vector2 = (from - target.global_position).normalized()
	return target.global_position + away * (ball.collision_radius + target.body_radius + 6.0)


## Aliado aleatório de longo alcance. Prefere quem está fora da área; se ninguém
## estiver ao alcance, lança para o aliado mais próximo.
func _pick_throw_target() -> Player:
	var allies: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team:
			allies.append(p)
	if allies.is_empty():
		return null

	var in_range: Array[Player] = []
	var outside_area: Array[Player] = []
	for p in allies:
		if global_position.distance_to(p.global_position) > throw_range:
			continue
		in_range.append(p)
		if not field.is_in_penalty_area(p.global_position, team):
			outside_area.append(p)

	if not outside_area.is_empty():
		return outside_area.pick_random()
	if not in_range.is_empty():
		return in_range.pick_random()

	var nearest: Player = allies[0]
	for p in allies:
		if global_position.distance_to(p.global_position) < global_position.distance_to(nearest.global_position):
			nearest = p
	return nearest


## Adversário que pulou (nível Suspenso alcança o Voando) e está debaixo da bola
func _find_interceptor() -> Player:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down:
			continue
		if not other.can_reach_level(Heights.Level.FLYING):
			continue
		if other.global_position.distance_to(ball.global_position) <= intercept_radius:
			return other
	return null


func _intercepted(by: Player) -> void:
	ball.release_hover()  # a gravidade volta: a bola cai onde foi interceptada
	ball.velocity = Vector2.ZERO
	ball.register_touch(by)
	state = State.IDLE
	_say("%s interceptou o lançamento!" % by.get_display_name(), by.team)


# ---------- RESET / CANCELAR ----------

func _on_ball_reset() -> void:
	_cancel_all()
	global_position = _home_position()


func _on_match_ended(_winner: int) -> void:
	_cancel_all()
	set_physics_process(false)


func _cancel_all() -> void:
	_token += 1
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if _jump_tween and _jump_tween.is_valid():
		_jump_tween.kill()
	height = 0.0
	state = State.IDLE


# ---------- UTIL ----------

## -1 para o time 0 (gol da esquerda), +1 para o time 1 (gol da direita)
func _dir() -> int:
	return -1 if team == 0 else 1


func _home_local() -> Vector2:
	var dir: int = _dir()
	return Vector2(field.pitch_size.x * 0.5 * dir - dir * home_offset, 0.0)


func _home_position() -> Vector2:
	return field.to_global(_home_local())


func _ball_in_area() -> bool:
	return field.is_in_penalty_area(ball.global_position, team)


func _play_jump() -> void:
	if _jump_tween and _jump_tween.is_valid():
		_jump_tween.kill()
	_jump_tween = create_tween()
	_jump_tween.tween_property(self, "height", jump_height, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_jump_tween.tween_property(self, "height", 0.0, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _team_name(t: int) -> String:
	return manager.get_team_name(t) if manager else "Time %d" % t


func _say(text: String, for_team: int = -1) -> void:
	if manager:
		manager.announce_keeper(text, team if for_team < 0 else for_team)


func _announce_contest(chance: float, beaten: bool) -> void:
	var pct: int = int(round(chance * 100.0))
	if beaten:
		var shooter: int = ball.shot_team if ball.shot_team >= 0 else team
		_say("O chute passou pelo goleiro! (%d%% de chance)" % pct, shooter)
	else:
		_say("DEFENDEU! Goleiro do %s pegou o chute (%d%% de chance)" % [_team_name(team), pct])


# ---------- VISUAL (placeholder: troque por sprite quando quiser) ----------

func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius, Color(0, 0, 0, 0.3))  # sombra no chão
	var center := Vector2(0, -height)
	draw_circle(center, body_radius, keeper_color)
	draw_arc(center, body_radius, 0.0, TAU, 32, Player.TEAM_COLORS[team % Player.TEAM_COLORS.size()], 4.0)
	match state:
		State.PREPARING:
			draw_arc(center, body_radius + 6.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.0)
		State.HOLDING:
			draw_arc(center, body_radius + 6.0, 0.0, TAU, 32, Color(0.4, 0.9, 1.0, 0.9), 2.0)
