class_name Lorenzo
extends Player
## Lorenzo. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Zombie Dribble / Buh! (ação de habilidade; recarga de 2 rodadas, compartilhada entre
##      as duas variantes e o Undead Pass). Só com o Lorenzo NO CHÃO.
##      - Bola próxima e no chão: Zombie Dribble -> a bola gruda nos pés dele e começa uma ação
##        de Correr normal (não gasta o limite de Correr do turno), mas com os controles
##        INVERTIDOS (W vira S, A vira D...). Durante a corrida a bola não pode ser roubada.
##        No fim, se houver um aliado a até 300 px, libera o complemento Undead Pass.
##      - Sem bola próxima: Buh! -> escolhe uma direção e dá um avanço (dash). Inimigo no caminho
##        é atordoado (sem ações) pela rodada atual e o Lorenzo passa direto; se encontrar a
##        bola, o avanço para ali e libera o Undead Pass também.
##      - Undead Pass (complemento GRATUITO): passe rasteiro com alcance de 300 px.
## 2. Yo.. / Horrific Intercept (ação de habilidade; recarga de 2 rodadas, compartilhada).
##      - Lorenzo no chão: Yo.. -> vai até um inimigo (qualquer estado) e o marca por 3 rodadas,
##        ou até o Lorenzo se afastar demais dele: -10% de chance em qualquer chute, MUITO mais
##        lento e com o Correr mais curto.
##      - Lorenzo suspenso + bola suspensa/voando por perto: Horrific Intercept -> avança até a
##        bola, domina suspenso e dá um passe alto (suspenso) para o 2º aliado mais próximo.
## 3. Ace Eater / Cemetery (ação de habilidade; recarga de 3 rodadas, compartilhada).
##      - Ace Eater: marca um inimigo num alcance gigante por 3 rodadas. Ele não pode receber
##        passes e tem -15% de chance nos chutes.
##      - Cemetery (automático, enquanto a marca existir): se um marcado TENTA chutar (ou um
##        passe chega até ele), o efeito contamina o aliado mais próximo dele que ainda não
##        estava marcado, os dois CAEM, e a marca dos dois é renovada. Isso se repete a cada
##        novo chute/passe dos marcados.
##
## ASSUMIÇÕES (o pedido não definiu; ajuste nos @export abaixo):
##  - Alcance do Yo.. (260), alcance do Ace Eater (1800), alcance do Horrific Intercept (230),
##    distância do Buh! (300) e do "se afastar" do Yo.. (300) foram escolhidos por mim.
##  - Yo.. / Ace Eater são habilidades com duração: a recarga conta a partir do FIM do efeito
##    (igual ao Aiku). Desligue em "cooldown_after_effect" para contar a partir do uso.
##  - O -15% do Ace Eater é uma penalidade de chute SEPARADA do Yo.. (as duas somam).
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Lorenzo". Registre o personagem (character_id "lorenzo") onde
## você registra os outros no menu de formação.
##
## Animações opcionais (SpriteFrames): zombie_dribble, zombie_run (corrida invertida), buh, yo,
## horrific_intercept, horrific_pass, ace_eater. As que faltarem usam os fallbacks do Player.

const SKILL_ZOMBIE: StringName = &"zombie_dribble"   # Zombie Dribble OU Buh! (depende da bola)
const SKILL_UNDEAD: StringName = &"undead_pass"
const SKILL_YO: StringName = &"yo"                   # Yo.. OU Horrific Intercept (depende da altura)
const SKILL_ACE: StringName = &"ace_eater"

## Grupos de recarga (as variantes e os complementos compartilham o mesmo)
const CD_ZOMBIE: StringName = &"cd_zombie"
const CD_YO: StringName = &"cd_yo"
const CD_ACE: StringName = &"cd_ace"

const PURPLE := Color(0.62, 0.25, 0.95)
const PURPLE_LIGHT := Color(0.82, 0.62, 1.0)
const PURPLE_DARK := Color(0.24, 0.08, 0.40)

@export_group("Geral")
## true = a recarga das habilidades com duração (Yo.., Ace Eater) conta a partir do FIM do efeito
@export var cooldown_after_effect: bool = true

@export_group("Zombie Dribble / Buh! / Undead Pass")
@export var zombie_ball_range: float = 90.0      # "bola próxima": distância máxima até a bola
@export var zombie_cooldown: int = 2
@export var dribble_ball_offset: float = 30.0    # distância da bola até o corpo (nos "pés")
@export var undead_range: float = 300.0          # alcance do Undead Pass (aliado)
@export var undead_ball_range: float = 110.0     # a bola precisa estar tão perto dele para o passe
@export var buh_aim_range: float = 220.0         # tamanho da seta de mira do Buh!
@export var buh_distance: float = 300.0          # distância do avanço
@export var buh_duration: float = 0.35
@export var buh_hit_radius: float = 50.0         # alcance para atordoar inimigos e "encontrar" a bola
@export var buh_stun_rounds: int = 1             # rodadas de atordoamento (1 = só a rodada atual)

@export_group("Yo.. / Horrific Intercept")
@export var yo_range: float = 260.0              # alcance para escolher o inimigo
@export var yo_dash_time: float = 0.25
@export var yo_stop_distance: float = 40.0       # até onde chega perto do inimigo
@export var yo_leash_range: float = 300.0        # se afastar além disso solta o inimigo antes da hora
@export var yo_rounds: int = 3
@export_range(0.0, 1.0) var yo_shot_penalty: float = 0.10
@export_range(0.05, 1.0) var yo_speed_mult: float = 0.4      # velocidade do Correr do marcado
@export_range(0.05, 1.0) var yo_run_time_mult: float = 0.5   # duração do Correr do marcado
@export var yo_cooldown: int = 2
@export var intercept_range: float = 230.0       # alcance até a bola suspensa/voando
@export var intercept_dash_time: float = 0.2
@export var intercept_pass_range: float = 650.0  # alcance mínimo do passe alto (cresce se o aliado estiver mais longe)

@export_group("Ace Eater / Cemetery")
@export var ace_range: float = 1000.0            # "alcance gigante"
@export var ace_rounds: int = 3
@export_range(0.0, 1.0) var ace_shot_penalty: float = 0.15
@export var ace_cooldown: int = 3

@export_group("Visual do chute")
## Aura + partículas do passe do Horrific Intercept. Vazio = usa o estilo roxo padrão
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: zombie_dribble, undead_pass, yo, ace_eater
@export var skill_icons: Dictionary = {}

# --- Zombie Dribble ---
var _dribbling: bool = false
var _dribble_ball: Ball = null
var _prev_spell_owner: Player = null
## O complemento Undead Pass está liberado neste turno?
var _undead_ready: bool = false

# --- Yo.. ---
var _yo_target: Player = null
var _yo_until: int = -1

# --- Ace Eater / Cemetery: jogador marcado -> {"until": int, "fx": MarkFX} ---
var _marks: Dictionary = {}
var _last_cemetery_msec: Dictionary = {}

# --- Visual ---
var _pulse: float = 0.0
var _pulse_target: Vector2 = Vector2.ZERO


func _init() -> void:
	character_id = "lorenzo"    # o menu de formação usa isto para saber quem é quem
	display_name = "Lorenzo"


func _ready() -> void:
	super()
	add_to_group("control_sources")   # Yo.. (Correr), Ace Eater (passes) e Cemetery (chutes) agem sobre os outros
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_connect_manager.call_deferred()


## Liga nos sinais do MatchManager (adiado: ele pode ainda não existir no _ready)
func _connect_manager() -> void:
	var m: MatchManager = _get_manager()
	if m == null:
		return
	if not m.pass_completed.is_connected(_on_pass_completed):
		m.pass_completed.connect(_on_pass_completed)
	if not m.turn_ended.is_connected(_on_turn_ended):
		m.turn_ended.connect(_on_turn_ended)


## Roxo-fantasma; as partículas giram devagar feito almas
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = PURPLE
	fx.additive = true
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.DOT
	fx.particle_color = PURPLE_LIGHT
	fx.amount = 20
	fx.lifetime = 0.55
	fx.speed_min = 15.0
	fx.speed_max = 60.0
	fx.swirl = 70.0
	fx.damping = 16.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 12
	fx.burst_speed = 170.0
	return fx


func _on_turn_ended(_team: int) -> void:
	# O complemento (Undead Pass) só vale no turno em que foi liberado
	if _undead_ready:
		_undead_ready = false
		queue_redraw()


func _on_pass_completed(_passer: Player, target: Player) -> void:
	# Um passe chegou num marcado (ex: passe de habilidade, que não passa pelo bloqueio do menu)
	if target != null and _marks.has(target):
		_cemetery_trigger(target)


# ---------- ZOMBIE DRIBBLE / BUH! ----------

## A bola está "próxima" o bastante para o Zombie Dribble? (no chão, livre e ao alcance)
func _ball_is_near() -> bool:
	var ball: Ball = _get_ball()
	return ball != null and _ball_is_free(ball) \
		and ball.get_level() == Heights.Level.GROUND \
		and global_position.distance_to(ball.global_position) <= zombie_ball_range


func _ball_is_free(ball: Ball) -> bool:
	return not ball.is_held() and not ball.is_locked_for(team)


func _zombie_skill_name() -> String:
	return "Zombie Dribble" if _ball_is_near() else "Buh!"


func _use_zombie() -> bool:
	if _ball_is_near():
		return await _use_zombie_dribble()
	return await _use_buh()


func _use_zombie_dribble() -> bool:
	var ball: Ball = _get_ball()
	if ball == null:
		return false

	face_towards(ball.global_position - global_position)
	await play_action(&"zombie_dribble", ANIM_RUN)
	_begin_dribble(ball)

	# É um Correr normal, mas sem gastar o limite de Correr do turno (a ação é de habilidade)
	var runs_before: int = runs_this_turn
	start_run()
	runs_this_turn = runs_before
	await run_finished

	_end_dribble()
	start_cooldown(CD_ZOMBIE, zombie_cooldown)
	_undead_ready = true   # só aparece de fato se houver um aliado a até 300 px (ver _can_undead)
	queue_redraw()
	return true


## Cola a bola nos pés: física parada, sem colidir com ninguém e travada para o time adversário
func _begin_dribble(ball: Ball) -> void:
	_dribbling = true
	_dribble_ball = ball
	_prev_spell_owner = ball.spell_owner
	ball.register_touch(self)
	ball.collisions_paused = true
	ball.spell_owner = self
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	if not ball.was_reset.is_connected(_end_dribble):
		ball.was_reset.connect(_end_dribble)   # gol / reinício: solta tudo


func _end_dribble() -> void:
	if _dribble_ball != null and is_instance_valid(_dribble_ball):
		_dribble_ball.collisions_paused = false
		_dribble_ball.spell_owner = _prev_spell_owner if is_instance_valid(_prev_spell_owner) else null
		_dribble_ball.velocity = Vector2.ZERO
		if _dribble_ball.was_reset.is_connected(_end_dribble):
			_dribble_ball.was_reset.disconnect(_end_dribble)
	_dribbling = false
	_dribble_ball = null
	_prev_spell_owner = null


func _physics_process(delta: float) -> void:
	super(delta)
	if _dribbling:
		_glue_ball(delta)


## A bola fica um pouco à frente do corpo, na direção em que ele corre
func _glue_ball(delta: float) -> void:
	if _dribble_ball == null or not is_instance_valid(_dribble_ball):
		_dribbling = false
		_dribble_ball = null
		return
	var dir := Vector2(facing, 0.0)
	if velocity.length() > 20.0:
		dir = velocity.normalized()
	var wanted: Vector2 = global_position + dir * dribble_ball_offset
	_dribble_ball.global_position = _dribble_ball.global_position.lerp(wanted, clampf(delta * 20.0, 0.0, 1.0))
	_dribble_ball.velocity = Vector2.ZERO
	_dribble_ball.vel_z = 0.0
	_dribble_ball.height = 0.0


## Controles invertidos enquanto dribla
func _get_run_input() -> Vector2:
	var dir: Vector2 = super()
	return -dir if _dribbling else dir


func _desired_anim() -> StringName:
	if _dribbling and _has_art and state == State.RUNNING and velocity.length_squared() > 25.0 \
			and animated_sprite.sprite_frames.has_animation(&"zombie_run"):
		return &"zombie_run"
	return super()


# ---------- BUH! ----------

func _use_buh() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var dir: Vector2 = await m.aim_for_skill(self, buh_aim_range)
	if dir == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	face_towards(dir)
	await play_action(&"buh", ANIM_SLIDE)
	await _run_buh_dash(dir)
	start_cooldown(CD_ZOMBIE, zombie_cooldown)
	return true


## Avanço em linha reta: atordoa os inimigos que encontrar (passando direto por eles) e
## para na bola, se a encontrar (liberando o Undead Pass).
func _run_buh_dash(direction: Vector2) -> void:
	var dir: Vector2 = direction.normalized()
	var ball: Ball = _get_ball()
	var stunned: Array[Player] = []
	var elapsed: float = 0.0

	_set_dash_exceptions(true)   # passa direto por todo mundo
	while elapsed < buh_duration:
		await get_tree().physics_frame
		var dt: float = get_physics_process_delta_time()
		elapsed += dt
		var frac: float = clampf(1.0 - elapsed / buh_duration, 0.0, 1.0)
		velocity = dir * (2.0 * buh_distance / buh_duration) * frac
		move_and_slide()
		queue_redraw()

		for other: Player in get_tree().get_nodes_in_group("players"):
			if other.team == team or other.is_down or other in stunned:
				continue
			if other.height_level != Heights.Level.GROUND:
				continue
			if global_position.distance_to(other.global_position) <= buh_hit_radius:
				stunned.append(other)
				if not other.is_locked():   # não encurta uma trava mais forte que já exista
					other.apply_lock(self, buh_stun_rounds, false)
					_play_pulse(other.global_position)

		if ball != null and _ball_is_free(ball) and ball.get_level() == Heights.Level.GROUND \
				and global_position.distance_to(ball.global_position) <= buh_hit_radius:
			ball.register_touch(self)
			ball.velocity = Vector2.ZERO
			_undead_ready = true
			break

	velocity = Vector2.ZERO
	_set_dash_exceptions(false)
	_nudge_out_of_players(dir)


func _set_dash_exceptions(on: bool) -> void:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		if on:
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)
		else:
			remove_collision_exception_with(other)
			other.remove_collision_exception_with(self)


## Se o avanço terminou por cima de alguém, empurra um pouco para a frente até ficar livre
func _nudge_out_of_players(dir: Vector2) -> void:
	for _i in 8:
		var overlapping: bool = false
		for other: Player in get_tree().get_nodes_in_group("players"):
			if other != self and other.height_level == height_level \
					and global_position.distance_to(other.global_position) < body_radius + other.body_radius:
				overlapping = true
				break
		if not overlapping:
			return
		global_position += dir * 10.0


# ---------- UNDEAD PASS (complemento gratuito) ----------

func _has_ally_within(range_px: float) -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other != self and other.team == team \
				and global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


func _can_undead() -> bool:
	if not _undead_ready or is_down:
		return false
	var ball: Ball = _get_ball()
	if ball == null or not _ball_is_free(ball):
		return false
	if global_position.distance_to(ball.global_position) > undead_ball_range:
		return false
	return _has_ally_within(undead_range)


func _use_undead_pass() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or not _can_undead():
		return false
	var target: Player = await m.pick_ally_for_skill(self, undead_range)
	if target == null:
		return false   # cancelou: o complemento continua disponível
	await m.run_ground_pass(self, target, ball)
	_undead_ready = false
	queue_redraw()
	return true


# ---------- YO.. ----------

func _has_yo_target() -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team != team and global_position.distance_to(other.global_position) <= yo_range:
			return true
	return false


func _use_yo() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or not _has_yo_target():
		return false
	var target: Player = await m.pick_ally_for_skill(self, yo_range, true)
	if target == null:
		return false   # cancelou: não gasta a ação

	face_towards(target.global_position - global_position)
	await play_action(&"yo", ANIM_SLIDE)
	await _dash_to(target, yo_dash_time, yo_stop_distance)
	_play_pulse(target.global_position)

	var round_now: int = get_current_round()
	_yo_target = target
	_yo_until = round_now + yo_rounds - 1
	# O efeito de chute já some sozinho se o Lorenzo se afastar além de yo_leash_range
	target.apply_shot_debuff(yo_shot_penalty, _yo_until, self, yo_leash_range)
	start_cooldown(CD_YO, yo_cooldown, _cooldown_start(yo_rounds))
	queue_redraw()
	return true


## O Yo.. está valendo para este jogador agora? (usado pelos ganchos de Correr do Player)
func _yo_active_on(p: Player) -> bool:
	return _yo_target != null and p == _yo_target and is_instance_valid(_yo_target)


## Gancho (grupo control_sources): o marcado pelo Yo.. corre bem mais devagar...
func run_speed_mult_on(p: Player) -> float:
	return yo_speed_mult if _yo_active_on(p) else 1.0


## ...e por menos tempo
func run_time_mult_on(p: Player) -> float:
	return yo_run_time_mult if _yo_active_on(p) else 1.0


## Acompanha o Yo..: acaba quando as rodadas passam ou o Lorenzo se afasta demais
func _watch_yo() -> void:
	if not is_instance_valid(_yo_target):
		_yo_target = null
		return
	var round_now: int = get_current_round()
	if round_now > _yo_until:
		_yo_target = null   # a recarga já foi iniciada no uso
		queue_redraw()
		return
	if global_position.distance_to(_yo_target.global_position) > yo_leash_range:
		_yo_target = null   # se afastou: solta antes da hora (o debuff de chute some junto)
		if cooldown_after_effect:
			start_cooldown(CD_YO, yo_cooldown, round_now + 1)
		queue_redraw()


## Recarga contada a partir do fim de um efeito com duração (ou a partir de agora)
func _cooldown_start(effect_rounds: int) -> int:
	return get_current_round() + (effect_rounds if cooldown_after_effect else 0)


## O Lorenzo avança até ficar perto do alvo (sem entrar por cima dele)
func _dash_to(target: Player, time: float, stop_distance: float) -> void:
	var offset: Vector2 = global_position - target.global_position
	var dist: float = offset.length()
	if dist < 1.0:
		return
	var dest: Vector2 = target.global_position + offset / dist * stop_distance
	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", dest, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


# ---------- HORRIFIC INTERCEPT (variante do Yo.., Lorenzo suspenso) ----------

## Aliados do Lorenzo, do mais perto para o mais longe
func _allies_by_distance() -> Array[Player]:
	var list: Array[Player] = []
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other != self and other.team == team:
			list.append(other)
	list.sort_custom(func(a: Player, b: Player) -> bool:
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	return list


## O 2º aliado mais próximo (se só existir um aliado, é ele mesmo)
func _second_nearest_ally() -> Player:
	var list: Array[Player] = _allies_by_distance()
	if list.is_empty():
		return null
	return list[1] if list.size() >= 2 else list[0]


func _has_intercept_target() -> bool:
	if is_down or height_level != Heights.Level.SUSPENDED:
		return false
	var ball: Ball = _get_ball()
	if ball == null or not _ball_is_free(ball):
		return false
	if ball.get_level() == Heights.Level.GROUND:
		return false   # só bola suspensa ou voando
	if global_position.distance_to(ball.global_position) > intercept_range:
		return false
	return _second_nearest_ally() != null


func _use_intercept() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or not _has_intercept_target():
		return false

	face_towards(ball.global_position - global_position)
	await play_action(&"horrific_intercept", ANIM_JUMP)

	# Avança até a bola enquanto ela é "dominada": para no ar, no nível Suspenso
	var point: Vector2 = ball.global_position
	m.clear_pending_pass()   # se era um passe alto no ar, ele acaba aqui
	ball.hover_to(point, Heights.SUSPENDED_HEIGHT, intercept_dash_time)
	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", point, intercept_dash_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	ball.register_touch(self)
	_play_pulse(ball.global_position)

	var target: Player = _second_nearest_ally()
	if target == null:
		ball.release_hover()
	else:
		var dist: float = global_position.distance_to(target.global_position)
		await m.run_skill_high_pass(self, target, ball, maxf(intercept_pass_range, dist + 20.0),
			&"horrific_pass", kick_fx)
	start_cooldown(CD_YO, yo_cooldown)
	return true


# ---------- ACE EATER / CEMETERY ----------

func _has_ace_target() -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team != team and global_position.distance_to(other.global_position) <= ace_range:
			return true
	return false


func _use_ace() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or not _has_ace_target():
		return false
	var target: Player = await m.pick_ally_for_skill(self, ace_range, true)
	if target == null:
		return false   # cancelou: não gasta a ação

	face_towards(target.global_position - global_position)
	await play_action(&"ace_eater")
	_clear_all_marks()   # uma nova marca substitui a corrente de Cemetery anterior
	_add_mark(target, get_current_round() + ace_rounds - 1, false)
	_play_pulse(target.global_position)
	start_cooldown(CD_ACE, ace_cooldown, _cooldown_start(ace_rounds))
	return true


func _mark_alive(p: Variant) -> bool:
	return is_instance_valid(p) and _marks.has(p)


## Gancho (grupo control_sources): marcado pelo Ace Eater não recebe passes
func blocks_pass_to(p: Player) -> bool:
	return _mark_alive(p)


## Gancho (chamado pela Ball via Player.on_shot_attempt): um jogador chutou
func on_opponent_shot_attempt(shooter: Player) -> void:
	if shooter.team == team:
		return
	_cemetery_trigger(shooter)


## CEMETERY: um marcado tentou chutar (ou recebeu um passe). Ele cai, a marca dele é renovada
## e o efeito pula para o aliado mais próximo que ainda não estava marcado (que também cai).
func _cemetery_trigger(victim: Player) -> void:
	if not _mark_alive(victim):
		return
	# Evita disparar duas vezes no mesmo instante (ex: chute + passe)
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - int(_last_cemetery_msec.get(victim, -1000)) < 80:
		return
	_last_cemetery_msec[victim] = now_ms

	var until: int = get_current_round() + ace_rounds - 1
	_add_mark(victim, until, true)   # já marcado: só renova (e vira "do Cemetery")
	victim.knock_down()

	var next: Player = _nearest_unmarked_ally_of(victim)
	if next != null:
		_add_mark(next, until, true)
		next.knock_down()
		_play_pulse(next.global_position)


func _nearest_unmarked_ally_of(p: Player) -> Player:
	var best: Player = null
	var best_dist: float = INF
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == p or other.team != p.team or _marks.has(other):
			continue
		var d: float = p.global_position.distance_to(other.global_position)
		if d < best_dist:
			best_dist = d
			best = other
	return best


## Marca (ou renova a marca de) um jogador: -ace_shot_penalty nos chutes até a rodada "until"
func _add_mark(p: Player, until: int, from_cemetery: bool) -> void:
	if _marks.has(p):
		var info: Dictionary = _marks[p]
		info["until"] = until
		var old_fx: MarkFX = info["fx"] as MarkFX
		if old_fx != null and is_instance_valid(old_fx):
			if from_cemetery:
				old_fx.cemetery = true
			p.apply_shot_debuff(ace_shot_penalty, until, old_fx)   # mesma origem = renova
		return
	var fx := MarkFX.new()
	fx.victim = p
	fx.cemetery = from_cemetery
	p.add_child(fx)
	_marks[p] = {"until": until, "fx": fx}
	# A origem do efeito é a própria marca: some junto com ela e soma com o Yo.. (origem diferente)
	p.apply_shot_debuff(ace_shot_penalty, until, fx)


func _remove_mark(p: Variant) -> void:
	if not _marks.has(p):
		return
	var info: Dictionary = _marks[p]
	var fx: MarkFX = info["fx"] as MarkFX
	if fx != null and is_instance_valid(fx):
		fx.queue_free()
	_marks.erase(p)
	_last_cemetery_msec.erase(p)


func _clear_all_marks() -> void:
	for p in _marks.keys():
		_remove_mark(p)


func _prune_marks() -> void:
	var round_now: int = get_current_round()
	for p in _marks.keys():
		var info: Dictionary = _marks[p]
		if not is_instance_valid(p) or round_now > int(info["until"]):
			_remove_mark(p)


# ---------- LOOP ----------

func _process(delta: float) -> void:
	super(delta)
	if not _marks.is_empty():
		_prune_marks()
	if _yo_target != null:
		_watch_yo()
	if _dribbling or _yo_target != null:
		queue_redraw()


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func _yo_skill_name() -> String:
	return "Horrific Intercept" if height_level == Heights.Level.SUSPENDED else "Yo.."


func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_ZOMBIE, "name": skill_label(_zombie_skill_name(), CD_ZOMBIE)})
	if _undead_ready:
		list.append({"id": SKILL_UNDEAD, "name": "Undead Pass"})
	list.append({"id": SKILL_YO, "name": skill_label(_yo_skill_name(), CD_YO)})
	list.append({"id": SKILL_ACE, "name": skill_label("Ace Eater", CD_ACE)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_ZOMBIE:
			return not is_on_cooldown(CD_ZOMBIE) and height_level == Heights.Level.GROUND
		SKILL_UNDEAD:
			return _can_undead()
		SKILL_YO:
			if is_on_cooldown(CD_YO):
				return false
			if height_level == Heights.Level.GROUND:
				return _has_yo_target()
			return _has_intercept_target()
		SKILL_ACE:
			return not is_on_cooldown(CD_ACE) and _has_ace_target()
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_ZOMBIE:
			return await _use_zombie()
		SKILL_UNDEAD:
			return await _use_undead_pass()
		SKILL_YO:
			if height_level == Heights.Level.SUSPENDED:
				return await _use_intercept()
			return await _use_yo()
		SKILL_ACE:
			return await _use_ace()
	return false


## O Undead Pass não gasta ação de habilidade: já foi "pago" pelo Zombie Dribble / Buh!
func skill_is_free(skill_id: StringName) -> bool:
	return skill_id == SKILL_UNDEAD


## Com o Undead Pass liberado (e usável), o turno não acaba sozinho para dar tempo de usá-lo
func has_free_followup() -> bool:
	return _undead_ready and _can_undead()


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_ZOMBIE:
			if _ball_is_near():
				title = "Zombie Dribble"
				text = "Com a bola próxima e no chão, cola ela nos pés e começa um Correr normal, mas com os controles INVERTIDOS. A bola não pode ser roubada durante a corrida.\nNo fim, com um aliado a até %d px, libera o Undead Pass." % int(undead_range)
			else:
				title = "Buh!"
				text = "Sem a bola próxima: escolhe uma direção e avança %d px. Inimigos no caminho ficam atordoados pela rodada e o Lorenzo passa direto. Se encontrar a bola, para nela e libera o Undead Pass." % int(buh_distance)
			text += "\nRecarga: %d rodadas (compartilhada com a outra variante e o Undead Pass)." % zombie_cooldown
		SKILL_UNDEAD:
			title = "Undead Pass"
			text = "Complemento gratuito: passe rasteiro para um aliado a até %d px." % int(undead_range)
		SKILL_YO:
			if height_level == Heights.Level.SUSPENDED:
				title = "Horrific Intercept"
				text = "Suspenso, com a bola suspensa ou voando a até %d px: avança até ela, domina suspenso e dá um passe alto para o 2º aliado mais próximo." % int(intercept_range)
			else:
				title = "Yo.."
				text = "No chão: vai até um inimigo (em qualquer estado) a até %d px e o marca por %d rodadas, ou até o Lorenzo se afastar mais de %d px.\nO marcado tem -%d%% em qualquer chute, corre bem mais devagar e por menos tempo." % [
					int(yo_range), yo_rounds, int(yo_leash_range), _pct(yo_shot_penalty)]
			text += "\nRecarga: %d rodadas (compartilhada entre as duas)." % yo_cooldown
		SKILL_ACE:
			title = "Ace Eater"
			text = ("Marca um inimigo num alcance gigante (%d px) por %d rodadas: ele não pode receber passes e tem -%d%% nos chutes.\n"
				+ "CEMETERY: se um marcado tentar chutar (ou receber um passe), o efeito contamina o aliado mais próximo dele, os dois CAEM, e a marca é renovada. Isso continua se espalhando.\n"
				+ "Recarga: %d rodadas (compartilhada com o Cemetery).") % [
				int(ace_range), ace_rounds, _pct(ace_shot_penalty), ace_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_end_dribble()
	_undead_ready = false
	_yo_target = null
	_yo_until = -1
	_clear_all_marks()
	_pulse = 0.0
	queue_redraw()


# ---------- VISUAL (predominantemente roxo) ----------

func _play_pulse(target_global: Vector2) -> void:
	_pulse_target = target_global
	_pulse = 1.0
	var tw: Tween = create_tween()
	tw.tween_method(_set_pulse, 1.0, 0.0, 0.4)


func _set_pulse(value: float) -> void:
	_pulse = value
	queue_redraw()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Pulso (Buh!, Yo.., Ace Eater, Cemetery): anel que se fecha e um raio até o alvo
	if _pulse > 0.0:
		var ring: float = lerpf(placeholder_radius + 60.0, placeholder_radius, _pulse)
		draw_arc(center, ring, 0.0, TAU, 40, Color(PURPLE, _pulse), 3.0)
		draw_line(center, to_local(_pulse_target), Color(PURPLE_LIGHT, _pulse * 0.8), 2.0)

	# Zombie Dribble: aura roxa na bola e aviso de controles invertidos
	if _dribbling:
		if _dribble_ball != null and is_instance_valid(_dribble_ball):
			var bp: Vector2 = to_local(_dribble_ball.global_position)
			var beat: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
			draw_arc(bp, 17.0 + beat * 3.0, 0.0, TAU, 24, Color(PURPLE, 0.9), 2.5)
			draw_arc(bp, 23.0 + beat * 4.0, 0.0, TAU, 24, Color(PURPLE_LIGHT, 0.4), 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(-34.0, -placeholder_radius - 36.0 - height),
			"INVERTIDO", HORIZONTAL_ALIGNMENT_CENTER, 68, 13, PURPLE_LIGHT)

	# Yo..: fio tracejado roxo até o marcado
	if _yo_target != null and is_instance_valid(_yo_target):
		var tp: Vector2 = to_local(_yo_target.global_position) + Vector2(0.0, -_yo_target.height)
		draw_dashed_line(center, tp, Color(PURPLE, 0.55), 2.0, 8.0)
		draw_arc(tp, _yo_target.placeholder_radius + 14.0, 0.0, TAU, 28, Color(PURPLE, 0.7), 2.0)


## Marca roxa em cima do inimigo (Ace Eater) e lápide ao lado de quem caiu pelo Cemetery.
## É filha do jogador marcado, então acompanha ele; o Lorenzo a cria e a remove.
class MarkFX extends Node2D:
	var victim: Player = null
	var cemetery: bool = false
	var _t: float = 0.0

	func _ready() -> void:
		z_index = 1500   # (relativo ao jogador) fica por cima de todo mundo

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if victim == null or not is_instance_valid(victim):
			return
		var lift: float = victim.height
		var r: float = victim.placeholder_radius
		var purple := Color(0.62, 0.25, 0.95)
		var light := Color(0.82, 0.62, 1.0)

		# Anel girando no chão em volta do marcado
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		for i in 6:
			var a0: float = _t * 1.6 + TAU * float(i) / 6.0
			draw_arc(Vector2.ZERO, r + 10.0, a0, a0 + 0.55, 8, Color(purple, 0.85), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Losango roxo flutuando em cima da cabeça, com um "olho"
		var c := Vector2(0.0, -(r + 38.0) - lift + sin(_t * 3.0) * 3.0)
		var pts := PackedVector2Array([
			c + Vector2(0.0, -13.0), c + Vector2(10.0, 0.0),
			c + Vector2(0.0, 13.0), c + Vector2(-10.0, 0.0)])
		draw_colored_polygon(pts, Color(0.5, 0.18, 0.85, 0.95))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, light, 2.0)
		draw_circle(c, 3.5, Color(0.1, 0.0, 0.2))
		draw_circle(c, 1.5, light)

		# Cemetery: lápide ao lado de quem está caído
		if cemetery and victim.is_down:
			var o := Vector2(r + 24.0, 6.0)
			var stone := Color(0.36, 0.28, 0.5)
			draw_set_transform(o + Vector2(0.0, 3.0), 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_rect(Rect2(o + Vector2(-9.0, -20.0), Vector2(18.0, 24.0)), stone)
			draw_circle(o + Vector2(0.0, -20.0), 9.0, stone)
			draw_arc(o + Vector2(0.0, -20.0), 9.0, PI, TAU, 12, light, 2.0)
			draw_line(o + Vector2(-9.0, -20.0), o + Vector2(-9.0, 4.0), light, 2.0)
			draw_line(o + Vector2(9.0, -20.0), o + Vector2(9.0, 4.0), light, 2.0)
			draw_line(o + Vector2(-9.0, 4.0), o + Vector2(9.0, 4.0), light, 2.0)
			draw_line(o + Vector2(0.0, -24.0), o + Vector2(0.0, -8.0), light, 2.0)
			draw_line(o + Vector2(-5.0, -18.0), o + Vector2(5.0, -18.0), light, 2.0)
