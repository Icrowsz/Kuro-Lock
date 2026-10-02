class_name Player
extends CharacterBody2D
## Jogador base. Personagens com habilidades próprias são cenas herdadas
## desta, com um script que estende Player e sobrescreve use_skill().
##
## Estrutura da cena (player.tscn):
## Player (CharacterBody2D)  <- este script
##  ├─ Sprite2D              (opcional: arraste em "Tint Sprite" / "Visual Root")
##  └─ CollisionShape2D      (necessário para o clique do mouse)

signal clicked(player: Player)
signal run_finished
signal slide_finished
## Fim da mira: direção escolhida (Vector2.ZERO = cancelado)
signal aim_finished(direction: Vector2)

enum State { IDLE, RUNNING, SLIDING }
enum Role { NONE, PROTAGONIST, SECONDARY }
## Tipo de chute possível agora (depende da altura do jogador e da bola)
enum KickType { NONE, GROUND, VOLLEY, FLYING, HIGH_BALL }

@export var team: int = 0:
	set(value):
		team = value
		queue_redraw()
@export var move_speed: float = 300.0
@export var run_duration: float = 1.5
@export var max_runs_per_turn: int = 2          # quantas vezes o Correr pode ser usado por turno
@export var skill_name: String = "Habilidade"
## Nome mostrado no jogo (placar de gols, menu...). Vazio = usa o nome do nó.
@export var display_name: String = ""

@export_group("Pular")
@export var jump_rise_time: float = 0.25
@export var land_time: float = 0.2

@export_group("Carrinho")
@export var slide_distance: float = 220.0      # quanto o jogador desliza
@export var slide_duration: float = 0.4
@export var max_slides_per_turn: int = 1        # quantas vezes o Carrinho pode ser usado por turno
@export var slide_hit_radius: float = 55.0     # "próximo": raio que acerta inimigos e bola
@export var slide_ball_power: float = 800.0

@export_group("Levantar")
@export var stand_up_time: float = 0.5

@export_group("Chutar")
@export var kick_range: float = 70.0            # distância (no chão) máxima até a bola
@export var kick_aim_range: float = 120.0       # tamanho da seta de mira
@export var kick_force_ground: float = 100.0     # chute fraco (jogador e bola no chão)
@export var kick_force_volley: float = 120.0     # voleio (jogador suspenso, bola no chão/suspensa)
@export var kick_force_flying: float = 140.0     # bola voando (QTE mais difícil)
@export var kick_force_high_ball: float = 100.0  # jogador no chão, bola suspensa (QTE)
@export var kick_force_to_speed: float = 10.0   # força 50 -> 500 px/s na bola
@export var volley_peak_level: Heights.Level = Heights.Level.SUSPENDED   # até onde a bola sobe no voleio
@export var flying_peak_level: Heights.Level = Heights.Level.SUSPENDED   # idem, quando a bola estava voando
@export_range(0.0, 1.0) var qte_fail_power_mult: float = 0.2   # força que sobra se errar o QTE (bola fraquinha)
@export_range(0.0, 90.0) var qte_fail_max_angle: float = 30.0  # desvio máximo (graus) se errar o QTE

@export_group("Chance de gol (disputa com o goleiro)")
## Chance de o chute vencer o goleiro. Se perder o sorteio, o goleiro fica com a bola.
@export_range(0.0, 1.0) var shot_chance_default: float = 0.30   # chute no chão e bola alta
@export_range(0.0, 1.0) var shot_chance_volley: float = 0.35    # voleio
@export_range(0.0, 1.0) var shot_chance_flying: float = 0.40    # bola voando

@export_group("Colisão com a bola")
@export var body_radius: float = 18.0           # raio do corpo para a bola bater/ser empurrada

@export_group("Visual")
@export var visual_root: Node2D                # nó que sobe quando o jogador pula
@export var tint_sprite: Sprite2D              # pintado com a cor do time (e sobe, se não houver Visual Root)
@export var draw_placeholder: bool = true      # círculo colorido enquanto não há sprite
@export var draw_shadow: bool = true
@export var placeholder_radius: float = 18.0

## Qual personagem é este (o menu de formação usa para trocar). Os herdados definem no _init.
var character_id: String = "base"

var state: State = State.IDLE
var run_time_left: float = 0.0
## Quantas vezes já usou Correr / Carrinho neste turno (o MatchManager zera no começo do turno do time)
var runs_this_turn: int = 0
var slides_this_turn: int = 0
## Rodadas que o jogador já passou derrubado (o MatchManager o levanta sozinho depois de 2)
var rounds_down: int = 0

## Papel na rodada (definido pelo MatchManager)
var role: Role = Role.NONE:
	set(value):
		role = value
		queue_redraw()

## É quem vai agir agora (protagonista ou um secundário escolhido)
var is_active: bool = false:
	set(value):
		is_active = value
		queue_redraw()

## Altura atual (visual, contínua) e nível discreto usado nas regras
var height: float = 0.0:
	set(value):
		height = value
		_update_visual()
var height_level: Heights.Level = Heights.Level.GROUND

## Derrubado por um carrinho: só pode usar a ação geral Levantar
var is_down: bool = false:
	set(value):
		is_down = value
		_update_visual()

## Escolha do alvo do Passe (preenchido pelo MatchManager): círculo de alcance
## em volta de quem passa e anel verde nos companheiros que dá para alcançar
var range_preview: float = 0.0:
	set(value):
		range_preview = value
		queue_redraw()
var is_pass_option: bool = false:
	set(value):
		is_pass_option = value
		queue_redraw()

# Mira
var is_aiming: bool = false
var aim_direction: Vector2 = Vector2.RIGHT
var aim_range: float = 0.0

# Carrinho em andamento
var slide_dir: Vector2 = Vector2.RIGHT
var slide_time_left: float = 0.0
var _slide_hit_players: Array[Player] = []
var _slide_hit_ball: bool = false

## Posição da formação confirmada (definida pelo MatchManager). É para cá que o jogador
## volta depois de um gol e quando a partida recomeça.
var home_position: Vector2 = Vector2.ZERO
var _home_tween: Tween

var _lift_node: Node2D
var _lift_base_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("players")
	_ensure_input_map()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING  # visão de cima, sem gravidade
	input_pickable = true
	input_event.connect(_on_input_event)

	if tint_sprite:
		tint_sprite.modulate = get_team_color()
		draw_placeholder = false

	_lift_node = visual_root if visual_root else tint_sprite
	if _lift_node:
		_lift_base_pos = _lift_node.position


func get_display_name() -> String:
	return display_name if display_name != "" else String(name)


## A cor vem do TeamStyle (o jogador escolhe na tela de formação)
func get_team_color() -> Color:
	return TeamStyle.color_of(team)


## Chame depois que a cor do time mudar (o sprite pintado e o desenho se atualizam)
func refresh_team_color() -> void:
	if tint_sprite:
		tint_sprite.modulate = get_team_color()
	queue_redraw()


## Este jogador consegue interagir com algo neste nível? (usado por Chutar/Passe etc.)
func can_reach_level(target: Heights.Level) -> bool:
	return Heights.can_reach(height_level, target)


# ---------- INPUT / SELEÇÃO ----------

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


## Cria as ações WASD no InputMap caso você ainda não tenha criado
static func _ensure_input_map() -> void:
	var keys := {
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_up": KEY_W,
		"move_down": KEY_S,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)


# ---------- MIRA (clique esquerdo confirma, direito/Esc cancela) ----------

func begin_aim(range_px: float) -> void:
	aim_range = range_px
	is_aiming = true
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_aiming:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_finish_aim(aim_direction)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_finish_aim(Vector2.ZERO)
	elif event.is_action_pressed("ui_cancel"):
		_finish_aim(Vector2.ZERO)


## Cancela a mira por código (ex: a partida acabou enquanto o jogador mirava)
func cancel_aim() -> void:
	if not is_aiming:
		return
	is_aiming = false
	queue_redraw()
	aim_finished.emit(Vector2.ZERO)


func _finish_aim(direction: Vector2) -> void:
	is_aiming = false
	get_viewport().set_input_as_handled()
	queue_redraw()
	aim_finished.emit(direction)


# ---------- AÇÃO GERAL: CORRER ----------

## Move livremente com WASD por run_duration segundos
func start_run() -> void:
	runs_this_turn += 1
	run_time_left = run_duration
	state = State.RUNNING


func _process_run(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * move_speed
	move_and_slide()

	run_time_left -= delta
	queue_redraw()
	if run_time_left <= 0.0:
		velocity = Vector2.ZERO
		state = State.IDLE
		queue_redraw()
		run_finished.emit()


# ---------- AÇÃO GERAL: PULAR ----------

## Sobe para o nível Suspenso. O MatchManager chama land() quando a duração acaba.
func jump() -> void:
	height_level = Heights.Level.SUSPENDED
	var tw := create_tween()
	tw.tween_property(self, "height", Heights.SUSPENDED_HEIGHT, jump_rise_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


func land() -> void:
	if height_level == Heights.Level.GROUND:
		return
	height_level = Heights.Level.GROUND
	var tw := create_tween()
	tw.tween_property(self, "height", Heights.GROUND_HEIGHT, land_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ---------- AÇÃO GERAL: CARRINHO ----------

func start_slide(direction: Vector2) -> void:
	slides_this_turn += 1
	slide_dir = direction.normalized()
	slide_time_left = slide_duration
	_slide_hit_players.clear()
	_slide_hit_ball = false
	state = State.SLIDING


func _process_slide(delta: float) -> void:
	slide_time_left -= delta
	# Desacelera linearmente: a distância total percorrida = slide_distance
	var frac: float = clampf(slide_time_left / slide_duration, 0.0, 1.0)
	velocity = slide_dir * (2.0 * slide_distance / slide_duration) * frac
	_update_slide_collision_exceptions()
	move_and_slide()

	_check_slide_hits()
	queue_redraw()

	if slide_time_left <= 0.0:
		_clear_slide_collision_exceptions()
		velocity = Vector2.ZERO
		state = State.IDLE
		queue_redraw()
		slide_finished.emit()


## Quem está suspenso (pulou) não bloqueia o carrinho: o corpo físico dele é
## ignorado e o jogador que desliza passa direto por baixo.
func _update_slide_collision_exceptions() -> void:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		if other.height_level != Heights.Level.GROUND:
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)
		else:
			remove_collision_exception_with(other)
			other.remove_collision_exception_with(self)


func _clear_slide_collision_exceptions() -> void:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		remove_collision_exception_with(other)
		other.remove_collision_exception_with(self)


## A rasteira só acerta quem está no CHÃO: quem pulou desvia do carrinho.
func _check_slide_hits() -> void:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down or other in _slide_hit_players:
			continue
		if other.height_level != Heights.Level.GROUND:
			continue
		if global_position.distance_to(other.global_position) <= slide_hit_radius:
			_slide_hit_players.append(other)
			other.knock_down()

	var ball := get_tree().get_first_node_in_group("ball") as Ball
	if ball and not ball.is_held() and not _slide_hit_ball and ball.get_level() == Heights.Level.GROUND:
		if global_position.distance_to(ball.global_position) <= slide_hit_radius:
			_slide_hit_ball = true
			# A bola vai na MESMA direção do carrinho
			ball.kick_ground(slide_dir, slide_ball_power, self)


# ---------- AÇÃO GERAL: CHUTAR ----------

## Que tipo de chute esse jogador consegue dar na bola agora?
## - Jogador no chão (e bola alcançável)        -> GROUND (fraco, sem QTE) se a bola está no chão;
##                                                  HIGH_BALL (com QTE) se a bola está suspensa
## - Jogador suspenso + bola no chão ou suspensa -> VOLLEY (QTE)
## - Jogador suspenso + bola voando              -> FLYING (QTE difícil)
## NONE = não dá para chutar (longe, nível inalcançável ou derrubado)
func get_kick_type(ball: Ball) -> KickType:
	if ball == null or is_down or ball.is_held():  # bola na mão do goleiro não dá para chutar
		return KickType.NONE
	if global_position.distance_to(ball.global_position) > kick_range:
		return KickType.NONE

	var ball_level: Heights.Level = ball.get_level()
	if not can_reach_level(ball_level):
		return KickType.NONE

	if height_level == Heights.Level.GROUND:
		if ball_level == Heights.Level.SUSPENDED:
			return KickType.HIGH_BALL
		return KickType.GROUND
	if ball_level == Heights.Level.FLYING:
		return KickType.FLYING
	return KickType.VOLLEY


## Chance de o chute vencer o goleiro, conforme o tipo (habilidades de chute podem usar também)
func get_shot_chance(kind: KickType) -> float:
	match kind:
		KickType.VOLLEY:
			return shot_chance_volley
		KickType.FLYING:
			return shot_chance_flying
	return shot_chance_default


## Aplica o chute na bola. qte_success = false enfraquece e desvia o chute.
## chance_override >= 0 troca a chance padrão do tipo de chute (habilidades usam isso).
func kick_ball(ball: Ball, direction: Vector2, kind: KickType, qte_success: bool = true,
		chance_override: float = -1.0, ignore_self_collision: bool = false) -> void:
	var force: float = kick_force_ground
	match kind:
		KickType.VOLLEY:
			force = kick_force_volley
		KickType.FLYING:
			force = kick_force_flying
		KickType.HIGH_BALL:
			force = kick_force_high_ball

	var dir: Vector2 = direction.normalized()
	if not qte_success:
		force *= qte_fail_power_mult
		dir = dir.rotated(deg_to_rad(randf_range(-qte_fail_max_angle, qte_fail_max_angle)))
	var speed: float = force * kick_force_to_speed
	var chance: float = chance_override if chance_override >= 0.0 else get_shot_chance(kind)

	if kind == KickType.GROUND or kind == KickType.HIGH_BALL:
		ball.kick_ground(dir, speed, self, chance)
	else:
		# Sobe só o que falta até o pico do nível (se a bola já está mais alta, só cai)
		var peak_level: Heights.Level = volley_peak_level if kind == KickType.VOLLEY else flying_peak_level
		var rise: float = maxf(0.0, Heights.to_height(peak_level) - ball.height)
		ball.kick(dir, speed, Heights.lift_for_peak(rise, ball.gravity), self, chance)

	# Habilidades como o Backheel Shot: a bola passa direto por quem chutou
	if ignore_self_collision:
		ball.ignore_player_until_stopped(self)

	await get_tree().create_timer(0.15).timeout

	# Errou o QTE: o jogador se desequilibra e cai (Levantar, ou espera 2 rodadas)
	if not qte_success:
		knock_down()


# ---------- DERRUBADO / LEVANTAR ----------

func knock_down() -> void:
	land()  # quem estava suspenso cai no chão também
	is_down = true
	rounds_down = 0


## Ação geral temporária: só existe enquanto o jogador está derrubado
func stand_up() -> void:
	await get_tree().create_timer(stand_up_time).timeout
	is_down = false
	rounds_down = 0


## Levanta na hora, sem gastar ação (o MatchManager usa depois de algumas rodadas derrubado)
func get_up_now() -> void:
	is_down = false
	rounds_down = 0


# ---------- VOLTAR À FORMAÇÃO ----------

## Volta para a posição da formação (deslizando em "duration" segundos; 0 = na hora).
## Interrompe o que estiver fazendo e deixa o jogador em pé, no chão e pronto para jogar.
func return_home(duration: float = 0.0) -> void:
	_stop_current_action()
	land()
	get_up_now()

	if _home_tween and _home_tween.is_valid():
		_home_tween.kill()
	if duration <= 0.0:
		global_position = home_position
		return
	_home_tween = create_tween()
	_home_tween.tween_property(self, "global_position", home_position, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Zera tudo o que é da partida anterior (a posição fica por conta de quem chama).
## Personagens com estado próprio (recargas de habilidade, bônus...) podem sobrescrever
## esta função, chamando super() no começo.
func reset_for_new_match() -> void:
	_stop_current_action()
	if _home_tween and _home_tween.is_valid():
		_home_tween.kill()
	height_level = Heights.Level.GROUND
	height = Heights.GROUND_HEIGHT
	get_up_now()
	runs_this_turn = 0
	slides_this_turn = 0
	role = Role.NONE
	is_active = false
	range_preview = 0.0
	is_pass_option = false
	queue_redraw()


## Para corrida, carrinho ou mira em andamento avisando quem estava esperando (o MatchManager)
func _stop_current_action() -> void:
	if is_aiming:
		cancel_aim()
	match state:
		State.RUNNING:
			velocity = Vector2.ZERO
			state = State.IDLE
			queue_redraw()
			run_finished.emit()
		State.SLIDING:
			_clear_slide_collision_exceptions()
			velocity = Vector2.ZERO
			state = State.IDLE
			queue_redraw()
			slide_finished.emit()


# ---------- AÇÕES DE HABILIDADE ----------

## Habilidades ativas do personagem: cada uma vira um botão no menu.
## Formato de cada item: {"id": StringName, "name": String}. O nome pode mudar com a
## situação (ex: uma habilidade com variantes); o id nunca muda.
## Sobrescreva nos personagens herdados.
func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": &"default", "name": skill_name})
	return list


## A habilidade pode ser usada agora? (o MatchManager ainda confere se sobrou ação de
## habilidade). Personagens sobrescrevem para pôr as condições próprias, chamando super().
func can_use_skill(_skill_id: StringName = &"default") -> bool:
	return not is_down


## Executa a habilidade. Pode usar await (mira, QTE, animações).
## Devolve true se a habilidade foi mesmo usada; false = cancelada/sem efeito, e aí o
## MatchManager NÃO gasta a ação de habilidade.
func use_skill(_skill_id: StringName = &"default") -> bool:
	print("%s não tem habilidade implementada." % name)
	return false


## Este jogador pula os QTEs dos chutes agora? (ex: Metavision do Isagi)
func skips_qte() -> bool:
	return false


# ---------- LOOP ----------

func _physics_process(delta: float) -> void:
	z_index = int(global_position.y)  # profundidade, igual à bola

	match state:
		State.RUNNING:
			_process_run(delta)
		State.SLIDING:
			_process_slide(delta)


func _process(_delta: float) -> void:
	if is_aiming:
		var to_mouse: Vector2 = get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			aim_direction = to_mouse.normalized()
		queue_redraw()


# ---------- VISUAL (sem precisar de assets) ----------

func _update_visual() -> void:
	queue_redraw()
	if _lift_node:
		_lift_node.position = _lift_base_pos + Vector2(0.0, -height)
		_lift_node.rotation = (PI / 2.0) if is_down else 0.0


func _draw() -> void:
	var team_color: Color = get_team_color()
	var ring_radius: float = placeholder_radius + 12.0

	# Sombra no chão (encolhe quando o jogador está no alto)
	if draw_shadow:
		var shadow_scale: float = lerpf(1.0, 0.65, clampf(height / Heights.FLYING_HEIGHT, 0.0, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, placeholder_radius * shadow_scale, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Corpo placeholder (achatado se derrubado, esticado se deslizando)
	if draw_placeholder:
		var body_color: Color = team_color.darkened(0.4) if is_down else team_color
		var rot: float = 0.0
		var scl := Vector2.ONE
		if state == State.SLIDING:
			rot = slide_dir.angle()
			scl = Vector2(1.6, 0.7)
		elif is_down:
			scl = Vector2(1.6, 0.6)
		draw_set_transform(Vector2(0.0, -height), rot, scl)
		draw_circle(Vector2.ZERO, placeholder_radius, body_color)
		draw_arc(Vector2.ZERO, placeholder_radius, 0.0, TAU, 32, body_color.darkened(0.5), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# "X" em cima de quem está derrubado
	if is_down:
		var c := Vector2(0.0, -height)
		draw_line(c + Vector2(-8, -8), c + Vector2(8, 8), Color.WHITE, 3.0)
		draw_line(c + Vector2(-8, 8), c + Vector2(8, -8), Color.WHITE, 3.0)

	# Anel do papel: dourado = Protagonista, branco fino = Secundário
	match role:
		Role.PROTAGONIST:
			draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 40, Color.GOLD, 3.0)
		Role.SECONDARY:
			draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 2.0)

	# Seta em cima de quem vai agir
	if is_active:
		var top: float = -ring_radius - 8.0 - height
		draw_colored_polygon(
			PackedVector2Array([Vector2(-9, top - 16), Vector2(9, top - 16), Vector2(0, top)]),
			Color.WHITE
		)

	# Tempo restante da corrida
	if state == State.RUNNING:
		var frac: float = clampf(run_time_left / run_duration, 0.0, 1.0)
		draw_arc(Vector2.ZERO, ring_radius + 8.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color.CYAN, 3.0)

	# Alcance do passe (círculo em volta de quem passa) e companheiros alcançáveis
	if range_preview > 0.0:
		draw_arc(Vector2.ZERO, range_preview, 0.0, TAU, 96, Color(1, 1, 1, 0.4), 2.0)
	if is_pass_option:
		draw_arc(Vector2.ZERO, ring_radius + 5.0, 0.0, TAU, 40, Color.LIME_GREEN, 3.0)

	# Indicador de mira
	if is_aiming:
		var start: Vector2 = aim_direction * (placeholder_radius + 4.0)
		var end: Vector2 = aim_direction * (placeholder_radius + aim_range)
		var side: Vector2 = aim_direction.orthogonal() * 10.0
		draw_line(start, end, Color.ORANGE, 4.0)
		draw_colored_polygon(
			PackedVector2Array([end + aim_direction * 14.0, end + side, end - side]),
			Color.ORANGE
		)
