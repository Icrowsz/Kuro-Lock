class_name Zantetsu
extends Player
## Zantetsu. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Bullet Train (ação de habilidade): avanço (dash) numa direção escolhida com WASD.
##      Pode ser usado no chão ou suspenso; se for suspenso, ele cai no chão ao fim do avanço.
##      Recarga de 2 rodadas, compartilhada com o A-Train.
##    1.1 A-Train (complemento GRATUITO): se o Bullet Train encostou num inimigo (mesmo nível de
##      altura) no meio da trajetória, o avanço para ali e libera o A-Train, que dá mais um
##      avanço, mais curto, em outra direção. Vale até o fim do turno do time dele (mesma rodada).
##      Não gasta ação de habilidade (igual ao Draconic Header do Shidou).
## 2. Rails (ação de habilidade): cria um trilho cinza translúcido com metade do comprimento do
##      campo, centrado nele. Ele precisa ficar DENTRO do trilho durante as 2 rodadas em que ele
##      existe; se sair antes, fica atordoado por 1 rodada (sem ações gerais nem habilidades).
##      Dentro do trilho o Correr é bem mais rápido (dá para ir de uma ponta à outra).
##      Recarga de 3 rodadas.
## 3. Lefty Dumb (ação de habilidade): chute rasteiro com uma curva fraca (30% de chance de gol;
##      +5% se estiver dentro do Rails). Recarga de 2 rodadas, compartilhada com a variante.
##    3.1 Idiot Volley (variante automática quando ele está suspenso): pequeno avanço ainda
##      suspenso; se no caminho ele encontrar a bola também suspensa, dá um voleio (mesma chance,
##      +5% no Rails; também com a curva fraca).
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Zantetsu".
##
## Animações opcionais (SpriteFrames): "bullet_train", "a_train", "rails", "lefty_dumb",
## "idiot_volley" e "dash" (toca durante o avanço; sem ela usa "run"). Quem não existir é pulado.

const SKILL_BULLET_TRAIN: StringName = &"bullet_train"
const SKILL_A_TRAIN: StringName = &"a_train"
const SKILL_RAILS: StringName = &"rails"
const SKILL_KICK: StringName = &"lefty_dumb"

## Grupos de recarga (Bullet Train + A-Train compartilham; Lefty Dumb + Idiot Volley também)
const CD_TRAIN: StringName = &"cd_train"
const CD_RAILS: StringName = &"cd_rails"
const CD_KICK: StringName = &"cd_kick"

## Qual chute da habilidade 3 cabe agora (altura do Zantetsu)
enum KickVariant { NONE, LEFTY, VOLLEY }

## Fim da escolha de direção do avanço (Vector2.ZERO = cancelado)
signal dir_chosen(direction: Vector2)

@export_group("Bullet Train / A-Train")
@export var train_distance: float = 330.0          # alcance do Bullet Train
@export var train_duration: float = 0.35
@export var a_train_distance: float = 170.0        # o A-Train é mais curto
@export var a_train_duration: float = 0.25
@export var train_cooldown: int = 2                # recarga (rodadas), compartilhada
@export var stop_on_enemy_contact: bool = true     # o Bullet Train para ao encostar no inimigo
@export var contact_margin: float = 8.0            # folga extra além dos dois raios de corpo

@export_group("Rails")
@export_range(0.1, 1.0) var rails_length_ratio: float = 0.5  # comprimento do trilho / comprimento do campo
@export var rails_thickness: float = 125.0         # largura (espessura) do trilho
@export var rails_rounds: int = 2                  # rodadas em que ele existe e em que o Zantetsu precisa ficar dentro
@export var rails_stun_rounds: int = 1             # atordoamento se sair antes da hora
@export var rails_cooldown: int = 3
@export var rails_run_speed_mult: float = 2.3      # velocidade do Correr dentro do trilho

@export_group("Lefty Dumb / Idiot Volley")
@export_range(0.0, 1.0) var chance_lefty: float = 0.30
@export_range(0.0, 1.0) var chance_idiot_volley: float = 0.30
@export_range(0.0, 1.0) var rails_shot_bonus: float = 0.05    # +5% dentro do Rails
@export var kick_cooldown: int = 2                 # recarga (rodadas), igual para as 2 variantes
@export var curve_total_degrees: float = 25.0      # curva FRACA: quanto a bola entorta no total
@export var curve_duration: float = 0.8            # em quanto tempo ela entorta
@export var curve_to_left: bool = true             # chute de canhoto: entorta para a esquerda de quem chuta
@export var volley_dash_distance: float = 150.0    # avanço curto do Idiot Volley
@export var volley_dash_duration: float = 0.3
@export var volley_catch_radius: float = 60.0      # distância em que ele "encontra" a bola suspensa
@export var idiot_volley_qte: bool = false         # true = o voleio também roda o QTE fácil (como os voleios gerais)

@export_group("Visual do chute")
## Aura + partículas dos chutes. Vazio = usa o estilo padrão do Zantetsu (veja _make_kick_fx)
@export var kick_fx: KickFX

# --- estado ---
var _a_train_ready: bool = false
var _a_train_until_round: int = -1
var _rail: RailZone = null
var _rail_until_round: int = -1
## Atordoado (por sair do Rails) até o fim desta rodada (-1 = não está)
var _stunned_until_round: int = -1
var _base_move_speed: float = 0.0

var _dashing: bool = false
var _dash_token: int = 0

var _picking_dir: bool = false
var _pick_dir: Vector2 = Vector2.ZERO
var _pick_range: float = 0.0


func _init() -> void:
	character_id = "zantetsu"   # o menu de formação usa isto para saber quem é quem
	display_name = "Zantetsu"


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_base_move_speed = move_speed
	_hook_manager.call_deferred()


## Aço + faíscas alaranjadas
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.72, 0.78, 0.86)
	fx.trail_width = 12.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(1.0, 0.72, 0.3)
	fx.amount = 20
	fx.lifetime = 0.45
	fx.speed_min = 20.0
	fx.speed_max = 90.0
	fx.gravity = Vector2(0.0, 140.0)
	fx.spin = 240.0
	fx.scale_min = 0.12
	fx.scale_max = 0.28
	fx.burst_amount = 12
	fx.burst_speed = 200.0
	return fx


func _exit_tree() -> void:
	_remove_rail(false)


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)
		m.turn_ended.connect(_on_turn_ended)


func _on_round_started(round_number: int) -> void:
	# O trilho some quando as rodadas dele acabam
	if _rail != null and round_number > _rail_until_round:
		_remove_rail()
	if _a_train_ready and round_number > _a_train_until_round:
		_a_train_ready = false
	queue_redraw()


## O A-Train só vale no turno do time do Zantetsu (a mesma rodada em que o Bullet Train encostou)
func _on_turn_ended(ended_team: int) -> void:
	if ended_team == team and _a_train_ready:
		_a_train_ready = false
		queue_redraw()


# ---------- ESCOLHA DE DIREÇÃO (WASD) ----------
# WASD escolhe (diagonais valem), Espaço/Enter/clique esquerdo confirma, Esc/clique direito cancela.

func _pick_direction(range_px: float) -> Vector2:
	_picking_dir = true
	_pick_dir = Vector2.ZERO
	_pick_range = range_px
	queue_redraw()
	var dir: Vector2 = await dir_chosen
	_picking_dir = false
	queue_redraw()
	return dir


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not _picking_dir:
		return
	var left_click: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if event.is_action_pressed("ui_accept") or left_click:
		get_viewport().set_input_as_handled()
		if _pick_dir != Vector2.ZERO:   # só confirma depois de escolher uma direção
			dir_chosen.emit(_pick_dir)
		return
	var right_click: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_RIGHT
	if event.is_action_pressed("ui_cancel") or right_click:
		get_viewport().set_input_as_handled()
		dir_chosen.emit(Vector2.ZERO)


# ---------- AVANÇO (DASH) ----------

## Primeiro ponto do segmento a->b que entra no círculo (c, r). Vector2.INF = não entra.
static func _segment_circle_entry(a: Vector2, b: Vector2, c: Vector2, r: float) -> Vector2:
	var d: Vector2 = b - a
	var f: Vector2 = a - c
	var cc: float = f.dot(f) - r * r
	if cc <= 0.0:
		# Já começa encostado: só conta se estiver indo na direção do inimigo
		return a if d.dot(-f) > 0.0 else Vector2.INF
	var aa: float = d.dot(d)
	if aa < 0.0001:
		return Vector2.INF
	var bb: float = 2.0 * f.dot(d)
	var disc: float = bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return Vector2.INF
	var t: float = (-bb - sqrt(disc)) / (2.0 * aa)
	if t < 0.0 or t > 1.0:
		return Vector2.INF
	return a + d * t


## Inimigo (no MESMO nível de altura, em pé) que o avanço from->to encosta. {} = nenhum.
func _find_enemy_contact(from: Vector2, to: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self or other.team == team or other.is_down \
				or other.height_level != height_level:
			continue
		var reach: float = body_radius + other.body_radius + contact_margin
		var entry: Vector2 = _segment_circle_entry(from, to, other.global_position, reach)
		if entry == Vector2.INF:
			continue
		var d: float = from.distance_to(entry)
		if d < best_dist:
			best_dist = d
			best = {"enemy": other, "point": entry}
	return best


## A bola está suspensa e perto o bastante para o Idiot Volley?
func _volley_can_reach(ball: Ball) -> bool:
	return ball != null and not ball.is_held() and not ball.is_locked_for(team) \
		and ball.get_level() == Heights.Level.SUSPENDED \
		and global_position.distance_to(ball.global_position) <= volley_catch_radius


## Durante o avanço ele atravessa os outros jogadores (o contato é decidido por distância)
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


## Avanço em linha reta (começa rápido e vai freando; anda "distance" no total).
## stop_on_enemy: para ao encostar num inimigo. stop_on_ball: para ao encontrar a bola suspensa.
## Devolve {"enemy": Player ou null, "ball": bool}. A altura não muda aqui (quem chama pousa).
func _run_dash(dir: Vector2, distance: float, duration: float, stop_on_enemy: bool = false,
		stop_on_ball: bool = false) -> Dictionary:
	var result: Dictionary = {"enemy": null, "ball": false}
	dir = dir.normalized()
	_dash_token += 1
	var token: int = _dash_token
	_dashing = true
	face_towards(dir)
	_set_dash_exceptions(true)
	var ball: Ball = _get_ball()
	var peak_speed: float = 2.0 * distance / duration
	var elapsed: float = 0.0

	while elapsed < duration:
		await get_tree().physics_frame
		if token != _dash_token:
			break   # ação cancelada (a partida reiniciou, por exemplo)
		elapsed += get_physics_process_delta_time()
		var frac: float = clampf(1.0 - elapsed / duration, 0.0, 1.0)
		velocity = dir * peak_speed * frac
		var before: Vector2 = global_position
		move_and_slide()

		if stop_on_enemy:
			var contact: Dictionary = _find_enemy_contact(before, global_position)
			if not contact.is_empty():
				global_position = contact["point"]
				result["enemy"] = contact["enemy"]
				break
		if stop_on_ball and _volley_can_reach(ball):
			result["ball"] = true
			break

	velocity = Vector2.ZERO
	_set_dash_exceptions(false)
	_dashing = false
	queue_redraw()
	return result


# ---------- 1. BULLET TRAIN ----------

func _use_bullet_train() -> bool:
	var dir: Vector2 = await _pick_direction(train_distance)
	if dir == Vector2.ZERO:
		return false   # cancelou: não gasta a ação
	if not await play_action(&"bullet_train"):
		return false

	var airborne: bool = height_level != Heights.Level.GROUND
	var result: Dictionary = await _run_dash(dir, train_distance, train_duration, stop_on_enemy_contact)
	if airborne:
		land()   # suspenso: cai no chão ao fim do avanço

	if result["enemy"] != null:
		_unlock_a_train()
	start_cooldown(CD_TRAIN, train_cooldown)
	return true


# ---------- 1.1 A-TRAIN ----------

func is_a_train_ready() -> bool:
	var m: MatchManager = _get_manager()
	return _a_train_ready and not is_down and m != null and m.round_number <= _a_train_until_round


func _unlock_a_train() -> void:
	var m: MatchManager = _get_manager()
	if m == null:
		return
	_a_train_ready = true
	_a_train_until_round = m.round_number
	queue_redraw()


func _use_a_train() -> bool:
	if not is_a_train_ready():
		return false
	var dir: Vector2 = await _pick_direction(a_train_distance)
	if dir == Vector2.ZERO:
		return false   # cancelou: o complemento continua disponível
	if not await play_action(&"a_train"):
		return false

	_a_train_ready = false
	queue_redraw()
	var airborne: bool = height_level != Heights.Level.GROUND
	await _run_dash(dir, a_train_distance, a_train_duration)
	if airborne:
		land()
	start_cooldown(CD_TRAIN, train_cooldown)   # recarga compartilhada (mesma rodada: não muda nada)
	return true


## Complemento gratuito: não gasta ação de habilidade e mantém o turno aberto até ser usado
func skill_is_free(skill_id: StringName) -> bool:
	return skill_id == SKILL_A_TRAIN and is_a_train_ready()


func has_free_followup() -> bool:
	return is_a_train_ready()


# ---------- 2. RAILS ----------

func _rail_is_active() -> bool:
	var m: MatchManager = _get_manager()
	return _rail != null and is_instance_valid(_rail) and m != null \
		and m.round_number <= _rail_until_round


## Está dentro do trilho (e ele ainda está valendo)?
func _in_rail() -> bool:
	return _rail_is_active() and _rail.contains(global_position)


func _use_rails() -> bool:
	var m: MatchManager = _get_manager()
	var field := get_tree().get_first_node_in_group("field") as Field
	if m == null or field == null:
		return false

	_remove_rail()
	var size := Vector2(field.pitch_size.x * rails_length_ratio, rails_thickness)
	var half: Vector2 = field.pitch_size * 0.5
	var mine: Vector2 = field.to_local(global_position)
	# Centrado nele, mas sem sair do campo
	var lim_x: float = maxf(half.x - size.x * 0.5, 0.0)
	var lim_y: float = maxf(half.y - size.y * 0.5, 0.0)
	var center := Vector2(clampf(mine.x, -lim_x, lim_x), clampf(mine.y, -lim_y, lim_y))
	# Se ele estiver fora das linhas, o trilho nasce em cima dele (ele tem que começar dentro)
	if not Rect2(center - size * 0.5, size).has_point(mine):
		center = mine

	_rail = RailZone.new()
	_rail.size = size
	field.add_child(_rail)
	_rail.z_as_relative = false
	_rail.z_index = -4000   # acima da grama e das redes, abaixo de jogadores e bola
	_rail.global_position = field.to_global(center)
	_rail.appear()

	_rail_until_round = m.round_number + rails_rounds - 1   # a rodada atual conta
	start_cooldown(CD_RAILS, rails_cooldown)
	queue_redraw()
	return true


func _remove_rail(animated: bool = true) -> void:
	if _rail != null and is_instance_valid(_rail):
		if animated:
			_rail.fade_out()
		else:
			_rail.queue_free()
	_rail = null
	_rail_until_round = -1


## Saiu do trilho antes da hora: o trilho se desfaz e ele fica atordoado
func _stun_for_leaving_rail() -> void:
	var m: MatchManager = _get_manager()
	if m == null:
		return
	_remove_rail()
	# apply_lock conta a rodada atual: +1 para valer a próxima rodada inteira
	apply_lock(self, rails_stun_rounds + 1)
	_stunned_until_round = m.round_number + rails_stun_rounds
	queue_redraw()


func _is_stunned() -> bool:
	return _stunned_until_round >= 0 and get_current_round() <= _stunned_until_round


## A saída só é conferida quando ele está parado (correr/avançar para fora e voltar é livre)
func _check_rail_exit() -> void:
	if not _rail_is_active() or _dashing or _picking_dir or state != State.IDLE:
		return
	if not _rail.contains(global_position):
		_stun_for_leaving_rail()


## Dentro do trilho o Correr é mais rápido (conferido a cada frame)
func _process_run(delta: float) -> void:
	if _in_rail():
		move_speed = _base_move_speed * rails_run_speed_mult
	super(delta)
	move_speed = _base_move_speed


# ---------- 3. LEFTY DUMB / 3.1 IDIOT VOLLEY ----------

func _kick_variant() -> KickVariant:
	if height_level == Heights.Level.SUSPENDED:
		return KickVariant.VOLLEY
	if height_level == Heights.Level.GROUND and get_kick_type(_get_ball()) == KickType.GROUND:
		return KickVariant.LEFTY
	return KickVariant.NONE


func _kick_skill_name() -> String:
	return "Idiot Volley" if height_level == Heights.Level.SUSPENDED else "Lefty Dumb"


func _rail_bonus() -> float:
	return rails_shot_bonus if _in_rail() else 0.0


func _use_lefty_dumb() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele mirava: confere de novo
	if _kick_variant() != KickVariant.LEFTY:
		return false
	var ball: Ball = _get_ball()
	var chance: float = minf(chance_lefty + _rail_bonus(), 1.0)
	await kick_ball(ball, aim, KickType.GROUND, true, chance, false, kick_fx, &"lefty_dumb")
	_curve_ball(ball)   # sem await: a curva acontece enquanto a bola anda
	start_cooldown(CD_KICK, kick_cooldown)
	return true


func _use_idiot_volley() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or height_level != Heights.Level.SUSPENDED:
		return false
	var dir: Vector2 = await _pick_direction(volley_dash_distance)
	if dir == Vector2.ZERO:
		return false   # cancelou antes de avançar: não gasta a ação

	# Avanço curto, ainda suspenso; para se encontrar a bola suspensa
	var result: Dictionary = await _run_dash(dir, volley_dash_distance, volley_dash_duration, false, true)
	start_cooldown(CD_KICK, kick_cooldown)
	if not result["ball"] or m.match_over:
		return true   # não achou a bola: foi só o avanço

	# Achou: mira o voleio. Cancelar aqui não desfaz o avanço, então chuta na direção do avanço.
	begin_aim(kick_aim_range)
	var kick_dir: Vector2 = await aim_finished
	if kick_dir == Vector2.ZERO:
		kick_dir = dir
	if m.match_over:
		return true

	var ball: Ball = _get_ball()
	if not _volley_can_reach(ball):
		return true   # a bola saiu do alcance enquanto ele mirava
	var qte_ok: bool = true
	if idiot_volley_qte and not skips_qte():
		qte_ok = await m.run_qte(KickType.VOLLEY)
	var chance: float = minf(chance_idiot_volley + _rail_bonus(), 1.0)
	await kick_ball(ball, kick_dir, KickType.VOLLEY, qte_ok, chance, false,
		kick_fx if qte_ok else null, &"idiot_volley")
	if qte_ok:
		_curve_ball(ball)
	return true


## Curva fraca: gira a direção da bola um pouquinho a cada frame, até acabar o tempo,
## alguém tocar nela, ela ser segurada/ficar pairando ou quase parar.
func _curve_ball(ball: Ball) -> void:
	if ball == null or curve_duration <= 0.0:
		return
	var touches: int = ball.interaction_count
	var per_second: float = deg_to_rad(curve_total_degrees) / curve_duration \
		* (-1.0 if curve_to_left else 1.0)   # na tela (y para baixo), ângulo negativo = esquerda de quem anda
	var t: float = 0.0
	while t < curve_duration:
		await get_tree().physics_frame
		if not is_instance_valid(ball) or ball.interaction_count != touches \
				or ball.hovering or ball.is_held() or ball.velocity.length() < 40.0:
			return
		var delta: float = get_physics_process_delta_time()
		t += delta
		ball.velocity = ball.velocity.rotated(per_second * delta)


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_BULLET_TRAIN, "name": skill_label("Bullet Train", CD_TRAIN)})
	list.append({"id": SKILL_A_TRAIN,
		"name": "A-Train (grátis)" if is_a_train_ready() else "A-Train (bloqueado)"})
	var rails_name: String = "Rails (ativo)" if _rail_is_active() else skill_label("Rails", CD_RAILS)
	list.append({"id": SKILL_RAILS, "name": rails_name})
	list.append({"id": SKILL_KICK, "name": skill_label(_kick_skill_name(), CD_KICK)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_BULLET_TRAIN:
			return not is_on_cooldown(CD_TRAIN)
		SKILL_A_TRAIN:
			return is_a_train_ready()
		SKILL_RAILS:
			# sem recriar enquanto está valendo nem durante a recarga
			return not _rail_is_active() and not is_on_cooldown(CD_RAILS)
		SKILL_KICK:
			return not is_on_cooldown(CD_KICK) and _kick_variant() != KickVariant.NONE
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_BULLET_TRAIN:
			return await _use_bullet_train()
		SKILL_A_TRAIN:
			return await _use_a_train()
		SKILL_RAILS:
			if not await play_action(&"rails"):   # o trilho aparece no frame de impacto
				return false
			return _use_rails()
		SKILL_KICK:
			if _kick_variant() == KickVariant.VOLLEY:
				return await _use_idiot_volley()
			return await _use_lefty_dumb()
	return false


# ---------- AÇÃO CANCELADA / PARTIDA NOVA ----------

## Corta avanço e escolha de direção em andamento (a partida reiniciou, por exemplo)
func _stop_current_action() -> void:
	_dash_token += 1
	if _picking_dir:
		dir_chosen.emit(Vector2.ZERO)
	super()


func reset_for_new_match() -> void:
	super()
	_a_train_ready = false
	_a_train_until_round = -1
	_stunned_until_round = -1
	_remove_rail(false)
	_dashing = false
	_picking_dir = false
	move_speed = _base_move_speed
	queue_redraw()


# ---------- LOOP / VISUAL ----------

func _physics_process(delta: float) -> void:
	super(delta)
	_check_rail_exit()


func _process(delta: float) -> void:
	super(delta)
	if _picking_dir:
		var m: MatchManager = _get_manager()
		if m != null and m.match_over:
			dir_chosen.emit(Vector2.ZERO)
		else:
			var v: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if v.length() > 0.1 and v.normalized() != _pick_dir:
				_pick_dir = v.normalized()
				face_towards(_pick_dir)
				queue_redraw()
	if _rail != null and is_instance_valid(_rail):
		_rail.highlighted = _in_rail()


## Durante o avanço usa a animação "dash" (se existir) ou "run"
func _desired_anim() -> StringName:
	if _dashing and height <= 1.0 and not is_down:
		if _has_art and animated_sprite.sprite_frames.has_animation(&"dash"):
			return &"dash"
		return ANIM_RUN
	return super()


func _draw_label(pos: Vector2, text: String, color: Color, font_size: int = 14) -> void:
	draw_string(ThemeDB.fallback_font, pos + Vector2(-100.0, 0.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, 200.0, font_size, color)


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)
	var ring: float = placeholder_radius + 12.0

	# A-Train disponível: anel dourado + etiqueta
	if is_a_train_ready():
		draw_arc(center, placeholder_radius + 8.0, 0.0, TAU, 40, Color(1.0, 0.75, 0.25, 0.95), 2.0)
		_draw_label(center + Vector2(0.0, -ring - 28.0), "A-TRAIN", Color(1.0, 0.8, 0.3))

	# Atordoado por sair do Rails: três estrelinhas em cima da cabeça
	if _is_stunned():
		for offset: Vector2 in [Vector2(-11.0, -6.0), Vector2(0.0, -13.0), Vector2(11.0, -6.0)]:
			draw_circle(center + Vector2(0.0, -ring) + offset, 3.5, Color(1.0, 0.9, 0.3))

	# Escolhendo a direção do avanço (WASD)
	if _picking_dir:
		if _pick_dir != Vector2.ZERO:
			var d: Vector2 = _pick_dir
			var start: Vector2 = center + d * (placeholder_radius + 4.0)
			var end: Vector2 = center + d * (placeholder_radius + _pick_range)
			var side: Vector2 = d.orthogonal() * 9.0
			var col := Color(0.75, 0.85, 1.0, 0.95)
			draw_line(start, end, col, 4.0)
			draw_colored_polygon(
				PackedVector2Array([end + d * 13.0, end + side, end - side]), col)
		_draw_label(center + Vector2(0.0, ring + 26.0),
			"WASD: direção  |  Espaço/clique: confirmar  |  Esc: cancelar",
			Color(1, 1, 1, 0.9), 12)


# ---------- O TRILHO ----------

## Trilho de trem cinza translúcido (um retângulo centrado no próprio nó)
class RailZone extends Node2D:
	var size: Vector2 = Vector2(800.0, 110.0)
	## Fica um pouco mais forte quando o Zantetsu está dentro
	var highlighted: bool = false:
		set(value):
			if value != highlighted:
				highlighted = value
				queue_redraw()

	func contains(global_pos: Vector2) -> bool:
		return Rect2(-size * 0.5, size).has_point(to_local(global_pos))

	func appear() -> void:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.25)

	func fade_out() -> void:
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)

	func _draw() -> void:
		var rect := Rect2(-size * 0.5, size)
		draw_rect(rect, Color(0.55, 0.57, 0.60, 0.38 if highlighted else 0.28))

		# Dormentes
		var x: float = rect.position.x + 14.0
		while x < rect.end.x:
			draw_line(Vector2(x, rect.position.y + size.y * 0.1),
				Vector2(x, rect.end.y - size.y * 0.1), Color(0.25, 0.25, 0.28, 0.45), 5.0)
			x += 30.0

		# Os dois trilhos de aço
		var ry: float = size.y * 0.3
		var steel := Color(0.85, 0.87, 0.92, 0.75)
		draw_line(Vector2(rect.position.x, -ry), Vector2(rect.end.x, -ry), steel, 4.0)
		draw_line(Vector2(rect.position.x, ry), Vector2(rect.end.x, ry), steel, 4.0)

		draw_rect(rect, Color(0.8, 0.82, 0.86, 0.6), false, 2.0)
