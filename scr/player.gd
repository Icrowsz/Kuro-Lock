class_name Player
extends CharacterBody2D
## Jogador base. Personagens com habilidades próprias são cenas herdadas
## desta, com um script que estende Player e sobrescreve use_skill().
##
## Estrutura da cena (player.tscn):
## Player (CharacterBody2D)  <- este script
##  ├─ Sprite2D              (opcional: arraste em "Tint Sprite" / "Visual Root")
##  ├─ AnimatedSprite2D      (opcional: animações do personagem; veja a seção ANIMAÇÃO)
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

# Nomes das animações que o Player toca sozinho (crie com estes nomes na SpriteFrames).
# Os que você não criar são pulados: nada quebra, o personagem só usa o fallback abaixo.
const ANIM_IDLE := &"idle"                 # parado (loop)
const ANIM_RUN := &"run"                   # correndo (loop)
const ANIM_JUMP := &"jump"                 # no ar, nível Suspenso
const ANIM_FLY := &"fly"                   # no ar, nível Voando
const ANIM_SLIDE := &"slide"               # carrinho
const ANIM_AIM := &"aim"                   # mirando (loop)
const ANIM_FALL := &"fall"                 # ao ser derrubado (toca uma vez, depois vira "down")
const ANIM_DOWN := &"down"                 # caído no chão
const ANIM_STAND_UP := &"stand_up"         # levantando (a duração passa a ser a da animação)
const ANIM_KICK := &"kick"                 # chute no chão
const ANIM_KICK_HIGH := &"kick_high"       # jogador no chão, bola suspensa
const ANIM_VOLLEY := &"volley"             # voleio
const ANIM_FLYING_KICK := &"flying_kick"   # bola voando
const ANIM_PASS := &"pass"                 # passe rasteiro
const ANIM_PASS_HIGH := &"pass_high"       # passe alto
## Se a animação não existe, tenta a próxima da lista
const ANIM_FALLBACK: Dictionary = {
	&"fly": &"jump",
	&"jump": &"idle",
	&"run": &"idle",
	&"aim": &"idle",
	&"slide": &"run",
	&"down": &"idle",
	&"kick_high": &"kick",
	&"volley": &"kick",
	&"flying_kick": &"volley",
	&"pass_high": &"pass",
	&"pass": &"kick",
}
## Trava de segurança: nenhuma espera por animação passa disso (segundos)
const ACTION_TIMEOUT: float = 3.0

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

@export_group("Animação")
## AnimatedSprite2D do personagem. Vazio = procura um filho chamado "AnimatedSprite2D".
@export var animated_sprite: AnimatedSprite2D
## O desenho original olha para a direita? (desmarque se foi desenhado olhando para a esquerda)
@export var sprite_faces_right: bool = true
## Frame (começa em 0) em que o chute realmente acerta a bola, por animação.
## Ex: {"kick": 3, "backheel_shot": 5}. Sem entrada = o chute sai logo no começo da animação.
@export var hit_frames: Dictionary = {}
## Com sprite, o placeholder some; este anel no chão mostra a cor do time
@export var draw_team_marker: bool = true

## Qual personagem é este (o menu de formação usa para trocar). Os herdados definem no _init.
var character_id: String = "base"

var state: State = State.IDLE
var run_time_left: float = 0.0
## Quantas vezes já usou Correr / Carrinho neste turno (o MatchManager zera no começo do turno do time)
var runs_this_turn: int = 0
var slides_this_turn: int = 0
## Rodadas que o jogador já passou derrubado (o MatchManager o levanta sozinho depois de 2)
var rounds_down: int = 0

## Efeitos vindos de habilidades de OUTROS jogadores (ex: Orbital Orbital / Sharp Sharp do
## Kurona). Quem aplica é quem desliga; reset_for_new_match zera tudo.
## Imune a carrinho: o carrinho passa por baixo (o jogador faz um pulinho) e não derruba.
var slide_immune: bool = false
## Soma no alcance do Passe (px) e no tempo do Correr (s)
var pass_range_bonus: float = 0.0
var run_time_bonus: float = 0.0
## Chance de gol extra que vale só no PRÓXIMO chute deste jogador (é gasta ao chutar)
var next_shot_bonus: float = 0.0
## Multiplicador de força que vale só no PRÓXIMO kick_ball (gasto ao chutar). Ex: Kablamo do Shidou
var next_kick_force_mult: float = 1.0
## Ações de habilidade extras só DESTE jogador (ex: Obsessive Lover do Shidou). O MatchManager
## gasta estas primeiro, antes da pool do time.
var extra_skill_left: int = 0:
	set(v):
		print(name, " extra_skill_left: ", extra_skill_left, " -> ", v)
		print_stack()
		extra_skill_left = v
## Ações GERAIS extras só DESTE jogador (ex: Gremlin Taunt do Charles, quando ele desvia de
## um Carrinho). Mesma ideia do extra_skill_left, mas para Correr/Pular/Carrinho/Chutar/Passe.
var extra_general_left: int = 0
## Igual ao extra_general_left, mas NÃO vale para o Correr (ex: Unleash Instinct do Bachira:
## "mais uma ação geral, menos a de Correr"). O MatchManager gasta esta primeiro nas outras ações.
var extra_general_no_run_left: int = 0
var _hop_tween: Tween

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

## Travado por uma habilidade de controle de outro jogador (ex: Snake Lunge/Bloom do
## Aiku). null = livre. Quem travou pode soltar antes da hora com clear_lock()
## (ex: se afastar demais do alvo).
var locked_by: Node2D = null
## true = só a habilidade fica bloqueada; as ações gerais continuam liberadas (usado
## pelo Bloom, que já derruba o inimigo por conta própria, e aí quem bloqueia as
## gerais é o próprio is_down). false = bloqueia TUDO (gerais + habilidade).
var lock_skills_only: bool = false
var _lock_until_round: int = -1

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

## Para que lado o personagem olha: 1 = direita, -1 = esquerda
var facing: float = 1.0
var _has_art: bool = false                 # tem AnimatedSprite2D com SpriteFrames?
var _action_anim: StringName = &""         # animação de ação (chute, habilidade...) em andamento
var _action_token: int = 0                 # muda a cada ação nova/cancelada (evita esperas penduradas)

## Gerenciador da partida (guardado depois da primeira busca)
var _manager: MatchManager = null
## Recarga das habilidades: grupo -> primeira rodada em que ela volta a poder ser usada
var _cooldown_ready: Dictionary = {}


func _ready() -> void:
	add_to_group("players")
	_ensure_input_map()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING  # visão de cima, sem gravidade
	input_pickable = true
	input_event.connect(_on_input_event)

	if tint_sprite:
		tint_sprite.modulate = get_team_color()
		draw_placeholder = false

	facing = _default_facing()
	refresh_art()


## Procura o AnimatedSprite2D e liga/desliga o modo "com arte". Chame de novo se trocar
## a SpriteFrames por código depois do _ready.
func refresh_art() -> void:
	if animated_sprite == null:
		animated_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_has_art = animated_sprite != null and animated_sprite.sprite_frames != null
	if _has_art:
		draw_placeholder = false   # a arte substitui o círculo
	_lift_node = visual_root if visual_root else (animated_sprite if _has_art else tint_sprite)
	if _lift_node:
		_lift_base_pos = _lift_node.position + Vector2(0.0, height)   # posição "no chão"
	queue_redraw()


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
	run_time_left = run_duration + run_time_bonus
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
		if other.height_level != Heights.Level.GROUND or other.slide_immune:
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)
			# Imune (ex: Orbital Orbital): pula por cima do carrinho que se aproxima
			if other.slide_immune and other.team != team \
					and global_position.distance_to(other.global_position) <= slide_hit_radius * 2.0:
				other.hop_over()
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
		if other.height_level != Heights.Level.GROUND or other.slide_immune:
			continue
		if global_position.distance_to(other.global_position) <= slide_hit_radius:
			_slide_hit_players.append(other)
			# Counter reativo (ex: Gremlin Taunt do Charles): se ele disparar, quem dá o
			# carrinho é que acaba caindo, então o knock_down() normal aqui é pulado.
			if other.try_counter_slide(self):
				continue
			other.knock_down()

	var ball := get_tree().get_first_node_in_group("ball") as Ball
	if ball and not ball.is_held() and not ball.is_locked_for(team) and not _slide_hit_ball \
			and ball.get_level() == Heights.Level.GROUND:
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
	if ball.is_locked_for(team):   # presa por um feitiço do time adversário (Arresto Momentum)
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
## Sobrescreva para permitir Correr fora do chão (ex: Once More do Chigiri, suspenso) ou
## mudar o limite de usos por turno. Padrão: só no chão, até max_runs_per_turn vezes.
func can_run() -> bool:
	return height_level == Heights.Level.GROUND and runs_this_turn < max_runs_per_turn


func get_shot_chance(kind: KickType) -> float:
	match kind:
		KickType.VOLLEY:
			return shot_chance_volley
		KickType.FLYING:
			return shot_chance_flying
	return shot_chance_default


## Aplica o chute na bola. qte_success = false enfraquece e desvia o chute.
## chance_override >= 0 troca a chance padrão do tipo de chute (habilidades usam isso).
## fx = aura + partículas que acompanham a bola (null = sem efeito).
## anim = animação da habilidade (vazio = a do tipo de chute: kick, volley...).
func kick_ball(ball: Ball, direction: Vector2, kind: KickType, qte_success: bool = true,
		chance_override: float = -1.0, ignore_self_collision: bool = false,
		fx: KickFX = null, anim: StringName = &"") -> void:
	# Multiplicador de força do próximo chute (gasto aqui, mesmo se a ação for cancelada)
	var force_mult: float = next_kick_force_mult
	next_kick_force_mult = 1.0
	# Animação do chute: a bola só sai no frame de impacto (hit_frames). Sem arte, segue direto.
	# `anim` = animação própria da habilidade (cai em "kick" se o personagem não tiver)
	var kick_anim: StringName = anim if anim != &"" else _kick_anim_for(kind)
	if not await play_action(kick_anim, ANIM_KICK):
		return   # ação cancelada (ex: a partida reiniciou)

	var force: float = kick_force_ground
	match kind:
		KickType.VOLLEY:
			force = kick_force_volley
		KickType.FLYING:
			force = kick_force_flying
		KickType.HIGH_BALL:
			force = kick_force_high_ball

	force *= force_mult
	var dir: Vector2 = direction.normalized()
	if not qte_success:
		force *= qte_fail_power_mult
		dir = dir.rotated(deg_to_rad(randf_range(-qte_fail_max_angle, qte_fail_max_angle)))
	var speed: float = force * kick_force_to_speed
	var chance: float = chance_override if chance_override >= 0.0 else get_shot_chance(kind)
	if chance >= 0.0:
		# + bônus do próximo chute (ex: Sharp Sharp do Kurona, gasto aqui) - penalidades (ex: Expelliarmus do Ness)
		# + bônus de companheiros (ex: Metavision do Niko)
		# - penalidade de adversários por perto (ex: Tricheur's Metavision do Charles)
		chance = clampf(chance + take_next_shot_bonus() + get_team_shot_bonus(ball) - get_shot_debuff()
			- get_opponent_shot_penalty(), 0.0, 1.0)

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

	# Aura + partículas da habilidade (depois do kick, que já registrou o toque)
	if fx:
		ball.play_fx(fx)

	await get_tree().create_timer(0.15).timeout

	# Errou o QTE: o jogador se desequilibra e cai (Levantar, ou espera 2 rodadas)
	if not qte_success:
		knock_down()


## Pega (e zera) o bônus de chance do próximo chute
func take_next_shot_bonus() -> float:
	var bonus: float = next_shot_bonus
	next_shot_bonus = 0.0
	return bonus


## Pulinho visual por cima de um carrinho (não muda o nível de altura, então a bola e as
## regras continuam tratando o jogador como "no chão")
func hop_over(peak: float = 34.0, duration: float = 0.45) -> void:
	if (_hop_tween and _hop_tween.is_valid()) or is_down or height_level != Heights.Level.GROUND:
		return
	_hop_tween = create_tween()
	_hop_tween.tween_property(self, "height", peak, duration * 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hop_tween.tween_property(self, "height", Heights.GROUND_HEIGHT, duration * 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ---------- DERRUBADO / LEVANTAR ----------

func knock_down() -> void:
	land()  # quem estava suspenso cai no chão também
	is_down = true
	rounds_down = 0
	_play_oneshot(ANIM_FALL)


## Ação geral temporária: só existe enquanto o jogador está derrubado
func stand_up() -> void:
	if _play_oneshot(ANIM_STAND_UP):
		await wait_action_end()   # com animação, quem manda na duração é ela
	else:
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
	facing = _default_facing()
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
	facing = _default_facing()
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
	slide_immune = false
	pass_range_bonus = 0.0
	run_time_bonus = 0.0
	next_shot_bonus = 0.0
	next_kick_force_mult = 1.0
	extra_skill_left = 0
	extra_general_left = 0
	extra_general_no_run_left = 0
	if _hop_tween and _hop_tween.is_valid():
		_hop_tween.kill()
	_cooldown_ready.clear()
	clear_status_effects()
	clear_lock()
	queue_redraw()


## Para corrida, carrinho ou mira em andamento avisando quem estava esperando (o MatchManager)
func _stop_current_action() -> void:
	_cancel_action()
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


# ---------- RECARGA (COOLDOWN) DAS HABILIDADES ----------

func _get_manager() -> MatchManager:
	if _manager == null:
		_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	return _manager


func _get_ball() -> Ball:
	return get_tree().get_first_node_in_group("ball") as Ball


func get_current_round() -> int:
	var m: MatchManager = _get_manager()
	return m.round_number if m else 0


## Quantas rodadas faltam para o grupo de habilidades voltar. 0 = disponível.
func cooldown_rounds_left(group: StringName) -> int:
	if not _cooldown_ready.has(group):
		return 0
	return maxi(0, int(_cooldown_ready[group]) - get_current_round())


func is_on_cooldown(group: StringName) -> bool:
	return cooldown_rounds_left(group) > 0


## Foto das recargas e devolução dela. O MatchManager usa quando uma habilidade é cancelada
## (Esc / clique direito na mira) para a recarga que ela tenha iniciado não ficar valendo.
func snapshot_cooldowns() -> Dictionary:
	return _cooldown_ready.duplicate()


func restore_cooldowns(snapshot: Dictionary) -> void:
	_cooldown_ready = snapshot.duplicate()


## Começa a recarga de um grupo de habilidades (as variantes de uma habilidade usam o mesmo grupo).
## A contagem começa em from_round (padrão: a rodada atual) e dura "rounds" rodadas:
## usou na rodada 5 com recarga 2 -> volta na rodada 7.
## Habilidades com duração (Pieces, Metavision, Destroyer Mode) passam from_round = rodada
## seguinte ao fim do efeito, para a recarga contar "a partir do fim do efeito".
func start_cooldown(group: StringName, rounds: int, from_round: int = -1) -> void:
	if from_round < 0:
		from_round = get_current_round()
	_cooldown_ready[group] = from_round + rounds


## Nome para o menu: acrescenta a recarga restante enquanto ela existir
func skill_label(base_name: String, group: StringName) -> String:
	var left: int = cooldown_rounds_left(group)
	return base_name if left <= 0 else "%s (recarga %d)" % [base_name, left]


# ---------- TRAVA (bloqueio de ações por uma habilidade de outro jogador) ----------

## Trava este jogador: "rounds" rodadas (contando a atual) sem poder agir (ou, com
## skills_only, só sem poder usar habilidade). Quem chamou (by) pode usar clear_lock()
## para soltar antes da hora.
func apply_lock(by: Node2D, rounds: int, skills_only: bool = false) -> void:
	locked_by = by
	lock_skills_only = skills_only
	var m: MatchManager = _get_manager()
	_lock_until_round = (m.round_number if m else 0) + rounds - 1
	queue_redraw()


func clear_lock() -> void:
	locked_by = null
	lock_skills_only = false
	_lock_until_round = -1
	queue_redraw()


## A trava ainda vale e bloqueia as ações GERAIS agora? (false quando lock_skills_only,
## já que aí quem bloqueia as gerais é o is_down da queda, não a trava em si)
func is_locked() -> bool:
	if locked_by == null or lock_skills_only:
		return false
	return _check_lock_round()


## A trava ainda vale e bloqueia a HABILIDADE agora? (vale tanto no bloqueio total
## quanto no lock_skills_only)
func is_skill_locked() -> bool:
	if locked_by == null:
		return false
	return _check_lock_round()


## A rodada da trava ainda não passou? Se já passou, solta sozinho (e devolve false).
func _check_lock_round() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or m.round_number > _lock_until_round:
		clear_lock()
		return false
	return true


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
	return not is_down and not is_skill_locked() and not is_skills_suppressed()


## Executa a habilidade. Pode usar await (mira, QTE, animações).
## Devolve true se a habilidade foi mesmo usada; false = cancelada/sem efeito, e aí o
## MatchManager NÃO gasta a ação de habilidade.
func use_skill(_skill_id: StringName = &"default") -> bool:
	print("%s não tem habilidade implementada." % name)
	return false


## ---------- EFEITOS DE CONTROLE E BÔNUS DE OUTROS JOGADORES (ex: Niko) ----------
## Quem aplica um efeito entra no grupo "control_sources" e implementa
## suppresses_skills_of(p) / suppresses_generals_of(p). Assim o efeito vale enquanto a
## condição dele for verdadeira, sem mexer na trava (apply_lock) dos outros personagens.

## Alguma habilidade de um adversário (ex: Watchtower do Niko) está proibindo as habilidades deste jogador agora?
func is_skills_suppressed() -> bool:
	for src in get_tree().get_nodes_in_group("control_sources"):
		if src != self and src.has_method("suppresses_skills_of") and src.suppresses_skills_of(self):
			return true
	return false


## Alguma habilidade de um adversário (ex: Obsessive Hater do Shidou) tirou ESTA ação geral
## (MatchManager.GeneralAction) deste jogador agora? Quem aplica implementa blocks_general_action(p, action).
func is_general_action_blocked(action: int) -> bool:
	for src in get_tree().get_nodes_in_group("control_sources"):
		if src != self and src.has_method("blocks_general_action") and src.blocks_general_action(self, action):
			return true
	return false


## Alguma habilidade de um adversário (ex: Body Core do Niko) está proibindo as ações gerais deste jogador agora?
func is_generals_suppressed() -> bool:
	for src in get_tree().get_nodes_in_group("control_sources"):
		if src != self and src.has_method("suppresses_generals_of") and src.suppresses_generals_of(self):
			return true
	return false


## Soma dos bônus de chance de gol que os COMPANHEIROS dão a este chute (ex: Metavision do Niko)
func get_team_shot_bonus(ball: Ball) -> float:
	var total: float = 0.0
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p != self and p.team == team:
			total += p.shot_bonus_for_ally(self, ball)
	return total


## Soma das penalidades de chance de gol que habilidades de ADVERSÁRIOS dão a este chute
## (ex: Tricheur's Metavision do Charles). Quem aplica entra no grupo "control_sources" e
## implementa shot_penalty_on(shooter) -> float (0.10 = -10%).
func get_opponent_shot_penalty() -> float:
	var total: float = 0.0
	for src in get_tree().get_nodes_in_group("control_sources"):
		if src is Player and src.team != team and src.has_method("shot_penalty_on"):
			total += src.shot_penalty_on(self)
	return total


## Sobrescreva: bônus (0.05 = +5%) que ESTE jogador dá ao chute de um companheiro
func shot_bonus_for_ally(_shooter: Player, _ball: Ball) -> float:
	return 0.0


## Esta habilidade NÃO gasta ação de habilidade agora? (ex: o Draconic Header do Shidou, que é
## o complemento do Demonic Rush e já foi "pago" por ele). Sobrescreva nos personagens.
func skill_is_free(_skill_id: StringName) -> bool:
	return false


## Este jogador tem um complemento gratuito esperando? Se sim, o turno não acaba sozinho
## mesmo sem ações sobrando, para dar tempo de usá-lo.
func has_free_followup() -> bool:
	return false


## Este jogador pula os QTEs dos chutes agora? (ex: Metavision do Isagi)
func skips_qte() -> bool:
	return false


## Counter reativo: alguém (attacker) acabou de acertar um Carrinho NELE (ex: Gremlin
## Taunt do Charles). Devolve true se um counter disparou — aí quem chamou (o
## atacante, dentro de _check_slide_hits) NÃO aplica o knock_down() normal, porque
## quem implementa já decidiu sozinho o que acontece (e normalmente derruba o
## atacante). Sobrescreva nos personagens que tiverem esse tipo de habilidade.
func try_counter_slide(_attacker: Player) -> bool:
	return false


## Efeito que age sozinho quando o turno do TIME deste jogador acaba (ex: o 1-2 do Sharp
## Sharp do Kurona). O MatchManager chama on_turn_end() em quem devolver true aqui e ESPERA
## ela terminar antes de começar o próximo turno (pode usar await).
func has_turn_end_effect() -> bool:
	return false


func on_turn_end() -> void:
	pass


# ---------- EFEITOS DE STATUS (vindos de habilidades de outros jogadores) ----------
# Ex: Expelliarmus (chute pior) e Confundo (habilidades embaralhadas) do Ness.

## Penalidades de chute em andamento: {amount, until_round, source, break_distance}
var _shot_debuffs: Array[Dictionary] = []
## Confuso até o fim desta rodada (-1 = não está confuso)
var confused_until_round: int = -1
var _confusion_order: Array[int] = []
## Último estado desenhado dos status (para redesenhar só quando muda)
var _status_drawn: int = 0


## Tira "amount" da chance de gol dos chutes deste jogador até o fim da rodada until_round.
## Se break_distance > 0, o efeito acaba para sempre quando "source" ficar mais longe que isso.
## Uma mesma origem só tem um efeito por vez (aplicar de novo renova).
func apply_shot_debuff(amount: float, until_round: int, source: Node2D,
		break_distance: float = 0.0) -> void:
	for i in range(_shot_debuffs.size() - 1, -1, -1):
		if _shot_debuffs[i]["source"] == source:
			_shot_debuffs.remove_at(i)
	_shot_debuffs.append({
		"amount": amount,
		"until_round": until_round,
		"source": source,
		"break_distance": break_distance,
	})
	queue_redraw()


## Soma das penalidades de chute valendo agora (já descarta as que expiraram ou quebraram)
func get_shot_debuff() -> float:
	var round_now: int = get_current_round()
	var total: float = 0.0
	for i in range(_shot_debuffs.size() - 1, -1, -1):
		var d: Dictionary = _shot_debuffs[i]
		var src: Variant = d["source"]
		var alive: bool = is_instance_valid(src) and round_now <= int(d["until_round"])
		if alive and float(d["break_distance"]) > 0.0:
			alive = global_position.distance_to((src as Node2D).global_position) \
				<= float(d["break_distance"])
		if not alive:
			_shot_debuffs.remove_at(i)
			continue
		total += float(d["amount"])
	return total


## Confunde o jogador até o fim da rodada until_round (os botões de habilidade dele são embaralhados)
func apply_confusion(until_round: int) -> void:
	confused_until_round = until_round
	_confusion_order.clear()
	queue_redraw()


func is_confused() -> bool:
	if confused_until_round < 0:
		return false
	if get_current_round() > confused_until_round:
		confused_until_round = -1
		_confusion_order.clear()
		return false
	return true


## Ordem embaralhada (índices 0..count-1) dos botões de habilidade de quem está confuso.
## Fica fixa durante a confusão; nunca devolve a ordem original quando há 2+ habilidades.
func get_confusion_order(count: int) -> Array[int]:
	if _confusion_order.size() != count:
		_confusion_order.clear()
		for i in count:
			_confusion_order.append(i)
		if count > 1:
			for _try in 8:
				_confusion_order.shuffle()
				if _confusion_order[0] != 0:
					break
	return _confusion_order


## Alguma habilidade deste jogador está em recarga? (o Reparo do Ness só mira quem tem)
func has_cooldown_active() -> bool:
	for group in _cooldown_ready:
		if cooldown_rounds_left(group) > 0:
			return true
	return false


## Reduz em "rounds" a recarga de até "count" habilidades em recarga (as mais demoradas primeiro).
## Devolve quantas foram reduzidas.
func reduce_cooldowns(count: int, rounds: int) -> int:
	var active: Array = []
	for group in _cooldown_ready:
		if cooldown_rounds_left(group) > 0:
			active.append(group)
	active.sort_custom(func(a, b) -> bool:
		return cooldown_rounds_left(a) > cooldown_rounds_left(b))
	var reduced: int = mini(count, active.size())
	for i in reduced:
		_cooldown_ready[active[i]] = int(_cooldown_ready[active[i]]) - rounds
	return reduced


## Zera confusão e penalidades (partida nova)
func clear_status_effects() -> void:
	_shot_debuffs.clear()
	confused_until_round = -1
	_confusion_order.clear()
	_status_drawn = 0


## Muda quando um status aparece/some: o _process redesenha só nesse momento
func _status_visual_key() -> int:
	return (1 if is_confused() else 0) | (2 if get_shot_debuff() > 0.0 else 0) \
		| (4 if next_shot_bonus > 0.0 else 0)


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
	var status_key: int = _status_visual_key()
	if status_key != _status_drawn:
		_status_drawn = status_key
		queue_redraw()
	_update_animation()


# ---------- ANIMAÇÃO ----------
# Como funciona:
#  1. ESTADOS (parado, correndo, no ar, carrinho, caído...) são escolhidos sozinhos por
#     _desired_anim(), olhando o estado do jogador a cada frame. Nada para chamar.
#  2. AÇÕES (chute, habilidade...) são tocadas por cima do estado com play_action() e,
#     quando acabam, o personagem volta ao estado normal.
#  3. Animação que não existe na SpriteFrames é pulada (ou usa o fallback): dá para ir
#     desenhando um personagem aos poucos, e quem ainda não tem arte segue com o placeholder.

## Qual animação o ESTADO atual pede? Os personagens podem sobrescrever (chame super())
## para variar por situação, ex: Rin com o Destroyer Mode ligado usa "idle_destroyer".
func _desired_anim() -> StringName:
	if is_down:
		return ANIM_DOWN
	if state == State.SLIDING:
		return ANIM_SLIDE
	if height > 1.0:
		return ANIM_FLY if height_level == Heights.Level.FLYING else ANIM_JUMP
	if is_aiming:
		return ANIM_AIM
	if state == State.RUNNING and velocity.length_squared() > 25.0:
		return ANIM_RUN
	return ANIM_IDLE


## Animação padrão de cada tipo de chute (o ANIM_FALLBACK cobre as que faltarem)
func _kick_anim_for(kind: KickType) -> StringName:
	match kind:
		KickType.HIGH_BALL:
			return ANIM_KICK_HIGH
		KickType.VOLLEY:
			return ANIM_VOLLEY
		KickType.FLYING:
			return ANIM_FLYING_KICK
	return ANIM_KICK


## Toca uma animação de AÇÃO por cima do estado e devolve quando ela chega ao frame de
## impacto (hit_frames): é aí que o efeito acontece (a bola sai, a peça aparece...).
## A animação segue sozinha depois e o personagem volta ao estado normal.
## fallback = animação a usar se a principal não existir.
## Devolve false se a ação foi cancelada no meio (aí quem chamou deve desistir).
## Sem arte ou sem a animação: devolve true na hora, e nada quebra.
func play_action(anim: StringName, fallback: StringName = &"") -> bool:
	if not _has_art:
		return true
	var a: StringName = _resolve_anim(anim)
	if a == &"" and fallback != &"":
		a = _resolve_anim(fallback)
	if a == &"":
		return true
	_start_action(a)

	var token: int = _action_token
	var hit: int = _hit_frame_of(a)
	var waited: float = 0.0
	# Polling por frame (e não por sinal): se a animação for trocada/cortada, nada fica pendurado
	while token == _action_token and animated_sprite.is_playing() \
			and animated_sprite.frame < hit and waited < ACTION_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return token == _action_token


## Espera a animação de ação atual terminar
func wait_action_end() -> void:
	if not _has_art:
		return
	var token: int = _action_token
	var waited: float = 0.0
	while _action_anim != &"" and token == _action_token \
			and animated_sprite.is_playing() and waited < ACTION_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()


## Vira o personagem para uma direção (só importa o lado: esquerda/direita).
## A mira, a corrida e o carrinho já viram sozinhos; use para passes e coisas assim.
func face_towards(dir: Vector2) -> void:
	if absf(dir.x) > 0.1:
		facing = signf(dir.x)


func _default_facing() -> float:
	return 1.0 if team == 0 else -1.0   # o time 0 ataca para a direita


func _start_action(a: StringName) -> void:
	_action_token += 1
	_action_anim = a
	animated_sprite.sprite_frames.set_animation_loop(a, false)   # ação precisa terminar
	animated_sprite.stop()
	animated_sprite.play(a)
	animated_sprite.frame = 0   # recomeça do início mesmo se for a mesma animação de antes


## Toca uma ação sem esperar (e sem fallback). Devolve false se não houver essa animação.
func _play_oneshot(anim: StringName) -> bool:
	if not _has_art:
		return false
	var a: StringName = _resolve_anim(anim, false)
	if a == &"":
		return false
	_start_action(a)
	return true


func _cancel_action() -> void:
	_action_token += 1
	_action_anim = &""


func _hit_frame_of(a: StringName) -> int:
	return int(hit_frames.get(String(a), hit_frames.get(a, 0)))


## Procura a animação na SpriteFrames, seguindo o ANIM_FALLBACK. &"" = não existe.
func _resolve_anim(anim: StringName, use_fallback: bool = true) -> StringName:
	var frames: SpriteFrames = animated_sprite.sprite_frames
	var a: StringName = anim
	for _i in 4:
		if frames.has_animation(a):
			return a
		if not use_fallback or not ANIM_FALLBACK.has(a):
			break
		a = StringName(ANIM_FALLBACK[a])
	return &""


func _update_animation() -> void:
	if not _has_art:
		return
	_update_facing()

	# Uma ação (chute, habilidade...) em andamento manda mais que o estado
	if _action_anim != &"":
		if animated_sprite.is_playing() and animated_sprite.animation == _action_anim:
			return
		_action_anim = &""   # terminou: volta ao estado normal

	var want: StringName = _resolve_anim(_desired_anim())
	# Só troca quando muda (play() a cada frame reiniciaria a animação)
	if want != &"" and animated_sprite.animation != want:
		animated_sprite.play(want)
	elif want != &"" and not animated_sprite.is_playing() and animated_sprite.sprite_frames.get_animation_loop(want):
		animated_sprite.play(want)   # animação em loop que parou (ex: logo depois de uma ação)


func _update_facing() -> void:
	if is_aiming:
		face_towards(aim_direction)
	elif state == State.SLIDING:
		face_towards(slide_dir)
	elif state == State.RUNNING:
		face_towards(velocity)
	animated_sprite.flip_h = (facing < 0.0) == sprite_faces_right


# ---------- VISUAL (sem precisar de assets) ----------

func _update_visual() -> void:
	queue_redraw()
	if _lift_node:
		_lift_node.position = _lift_base_pos + Vector2(0.0, -height)
		# Placeholder/sprite estático deita quando derrubado; com animação, quem deita é a "down"
		_lift_node.rotation = (PI / 2.0) if (is_down and not _has_art) else 0.0


func _draw() -> void:
	var team_color: Color = get_team_color()
	var ring_radius: float = placeholder_radius + 12.0

	# Sombra no chão (encolhe quando o jogador está no alto)
	if draw_shadow:
		var shadow_scale: float = lerpf(1.0, 0.65, clampf(height / Heights.FLYING_HEIGHT, 0.0, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, placeholder_radius * shadow_scale, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Com sprite: anel da cor do time no chão (o placeholder, que tinha a cor, não existe mais)
	if _has_art and draw_team_marker:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, placeholder_radius + 2.0, 0.0, TAU, 32, Color(team_color, 0.9), 3.0)
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

	# Anel tracejado verde-oliva em quem está travado por uma habilidade de controle
	# (ex: Snake Lunge/Bloom do Aiku)
	if locked_by != null:
		var lock_color := Color(0.55, 0.78, 0.2, 0.85)
		var lock_center := Vector2(0.0, -height)
		var segments: int = 10
		for i in segments:
			if i % 2 == 0:
				var a0: float = TAU * float(i) / float(segments)
				var a1: float = TAU * float(i + 1) / float(segments)
				draw_arc(lock_center, placeholder_radius + 9.0, a0, a1, 6, lock_color, 3.0)

	# Status de habilidades de outros jogadores: "?" = confuso, anel rosa = chute enfraquecido
	if is_confused():
		draw_string(ThemeDB.fallback_font, Vector2(ring_radius * 0.6, -ring_radius - height),
			"?", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(1.0, 0.55, 0.9))
	if not _shot_debuffs.is_empty() and get_shot_debuff() > 0.0:
		draw_arc(Vector2(0.0, -height), placeholder_radius + 16.0, 0.0, TAU, 32,
			Color(1.0, 0.4, 0.8, 0.8), 2.0)

	# Anel verde-claro fino = tem bônus de chance no próximo chute (ex: Sharp Sharp do Kurona)
	if next_shot_bonus > 0.0:
		draw_arc(Vector2(0.0, -height), placeholder_radius + 21.0, 0.0, TAU, 32,
			Color(0.55, 1.0, 0.65, 0.85), 2.0)

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
		var frac: float = clampf(run_time_left / (run_duration + run_time_bonus), 0.0, 1.0)
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
