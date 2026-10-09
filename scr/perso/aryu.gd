class_name Aryu
extends Player
## Aryu. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias.
## Visual: marrom, e todas as habilidades soltam estrelinhas brancas.
##
## 1. Elegant Header / Vain Block (mesma recarga: 2 rodadas; a variante é escolhida sozinha):
##      - Bola ao alcance e SUSPENSA/VOANDO -> Elegant Header: ele sobe até a bola, no nível
##        dela, e cabeceia (repele) na direção mirada. Conta como tentativa de gol (disputa com o goleiro).
##      - Sem bola ao alcance, mas com um INIMIGO suspenso/voando ao alcance -> Vain Block: ele vai
##        até o inimigo, ocupa o lugar dele (mesma altura), empurra e derruba o inimigo.
## 2. Glam! (recarga de 2 rodadas) + complemento Mirror Glam (grátis, recarga compartilhada):
##      - Bola próxima: Aryu SEGURA a bola. Dura até o fim do próximo turno do adversário.
##      - Se um adversário chegar perto, Aryu e a bola desviam (a bola fica protegida) e libera o
##        Mirror Glam: um passe rasteiro simples, que NÃO gasta ação de habilidade, usável até o
##        fim do próximo turno do time da Aryu.
## 3. Shooting Star (recarga de 3 rodadas, dura 2 rodadas):
##      - Aryu perto da grande área que defende E suspenso/voando: ele vai até o gol (no ar) e fecha
##        uma parte com o corpo. Chutes do adversário perdem 12% de chance de gol.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Aryu".

const SKILL_HEADER: StringName = &"elegant_header"   # também é o Vain Block (variante)
const SKILL_GLAM: StringName = &"glam"
const SKILL_MIRROR: StringName = &"mirror_glam"
const SKILL_STAR: StringName = &"shooting_star"

## Grupos de recarga (as variantes e o complemento compartilham o do pai)
const CD_HEADER: StringName = &"cd_header"
const CD_GLAM: StringName = &"cd_glam"
const CD_STAR: StringName = &"cd_star"

const BROWN: Color = Color(0.55, 0.33, 0.15)

enum HeaderVariant { NONE, HEADER, BLOCK }
## NONE = sem Glam; HOLDING = segurando a bola; MIRROR = desviou, Mirror Glam liberado
enum GlamState { NONE, HOLDING, MIRROR }

@export_group("Elegant Header / Vain Block")
@export var header_range: float = 150.0          # alcance até a bola (Elegant Header)
@export var header_power: float = 520.0          # velocidade da bola repelida (px/s)
@export_range(0.0, 1.0) var header_chance: float = 0.35   # chance de o cabeceio vencer o goleiro
@export var header_peak_level: Heights.Level = Heights.Level.SUSPENDED
@export var header_dash_time: float = 0.22       # tempo que ele leva para chegar na bola
@export var block_range: float = 260.0           # alcance até o inimigo (Vain Block)
@export var block_dash_time: float = 0.25
@export var block_push_distance: float = 120.0   # quanto o inimigo é empurrado
@export var header_cooldown: int = 2             # recarga (rodadas), igual para as duas variantes

@export_group("Glam!")
@export var glam_range: float = 90.0             # "bola próxima"
@export var glam_grab_time: float = 0.15
@export var glam_ball_offset: float = 22.0       # a bola fica à frente dele
@export var glam_trigger_radius: float = 75.0    # adversário a esta distância da bola = tentou interagir
@export var glam_dodge_distance: float = 160.0
@export var glam_dodge_time: float = 0.25
@export var glam_cooldown: int = 2

@export_group("Shooting Star")
@export var star_area_margin: float = 120.0      # "perto da área": folga em volta da grande área que ele defende
@export var star_goal_gap: float = 40.0          # distância da linha do gol onde ele se posiciona
@export_range(0.0, 1.0) var star_cover_ratio: float = 0.6   # o quanto ele se desloca para o lado da bola
@export var star_dash_time: float = 0.3
@export_range(0.0, 1.0) var shooting_penalty: float = 0.12   # -12% na chance de gol dos chutes adversários
@export var star_rounds: int = 2                 # duração total em rodadas (contando a atual)
@export var star_cooldown: int = 3

@export_group("Visual")
## Aura + partículas do passe/cabeceio. Vazio = usa o estilo padrão da Aryu (marrom + estrelas brancas)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: elegant_header, glam, mirror_glam, shooting_star.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}

var _glam_state: GlamState = GlamState.NONE
var _glam_touches: int = 0
var _dodging: bool = false

var _star_until_round: int = -1
var _star_penalty: float = 0.0

var _star_burst_fx: CPUParticles2D
var _star_stream_fx: CPUParticles2D
var _aura_drawn: int = -1


func _init() -> void:
	character_id = "aryu"        # o menu de formação usa isto para saber quem é quem
	display_name = "Aryu"


func _ready() -> void:
	super()
	add_to_group("control_sources")   # é assim que o Player enxerga shot_penalty_on()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_build_star_particles()
	_hook_manager.call_deferred()


## Marrom, com estrelinhas brancas
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = BROWN
	fx.trail_width = 14.0
	# Se o seu KickFX tiver um formato de estrela, usa; senão cai no quadrado
	if KickFX.Shape.has("STAR"):
		fx.shape = KickFX.Shape["SQUARE"]
	else:
		fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(1.0, 1.0, 1.0)
	fx.amount = 20
	fx.lifetime = 0.6
	fx.speed_min = 15.0
	fx.speed_max = 70.0
	fx.gravity = Vector2(0.0, -50.0)
	fx.spin = 240.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 12
	fx.burst_speed = 200.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.turn_ended.connect(_on_turn_ended)
		m.round_started.connect(_on_round_started)
	var ball: Ball = _get_ball()
	if ball:
		ball.was_reset.connect(_on_ball_reset)


func _on_round_started(_round_number: int) -> void:
	queue_redraw()   # a aura do Star some quando a duração acaba


func _on_ball_reset() -> void:
	_end_glam(false)   # gol / reposição: a bola já foi solta pelo próprio Ball


## Glam: sem interação, solta a bola no fim do turno adversário. Com o Mirror Glam liberado,
## ele vale até o fim do próximo turno do time da Aryu.
func _on_turn_ended(ended_team: int) -> void:
	match _glam_state:
		GlamState.HOLDING:
			if ended_team != team and not _dodging:
				_end_glam(true)
		GlamState.MIRROR:
			if ended_team == team:
				_end_glam(true)


# ---------- UTIL ----------

func _get_field() -> Field:
	return get_tree().get_first_node_in_group("field") as Field


## Mantém uma posição (global) dentro do campo
func _clamp_to_pitch(global_p: Vector2) -> Vector2:
	var field: Field = _get_field()
	if field == null:
		return global_p
	var half: Vector2 = field.pitch_size * 0.5 - Vector2(20.0, 20.0)
	var l: Vector2 = field.to_local(global_p)
	l.x = clampf(l.x, -half.x, half.x)
	l.y = clampf(l.y, -half.y, half.y)
	return field.to_global(l)


## Vai (posição + altura) até um ponto, ficando no nível indicado
func _dash_to(dest: Vector2, target_height: float, level: Heights.Level, duration: float) -> void:
	height_level = level
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", dest, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "height", target_height, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(duration).timeout


func _push_player(p: Player, dest_global: Vector2) -> void:
	var tw := create_tween()
	tw.tween_property(p, "global_position", _clamp_to_pitch(dest_global), 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------- ELEGANT HEADER / VAIN BLOCK ----------

func _ball_in_header_reach(ball: Ball) -> bool:
	if ball == null or ball.is_held() or ball.is_locked_for(team) or _glam_state != GlamState.NONE:
		return false
	if ball.get_level() == Heights.Level.GROUND:    # só bola suspensa ou voando
		return false
	return global_position.distance_to(ball.global_position) <= header_range


func _is_block_target(p: Player) -> bool:
	return p.team != team and not p.is_down and p.height_level != Heights.Level.GROUND


func _block_targets() -> Array[Player]:
	var list: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if _is_block_target(p) and global_position.distance_to(p.global_position) <= block_range:
			list.append(p)
	return list


## Que variante cabe agora? Com a bola ao alcance é Header; sem ela, mas com inimigo no ar, é Block.
func get_header_variant() -> HeaderVariant:
	if is_down:
		return HeaderVariant.NONE
	if _ball_in_header_reach(_get_ball()):
		return HeaderVariant.HEADER
	if not _block_targets().is_empty():
		return HeaderVariant.BLOCK
	return HeaderVariant.NONE


func _header_skill_name() -> String:
	return "Vain Block" if get_header_variant() == HeaderVariant.BLOCK else "Elegant Header"


func _use_header_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_header_variant():
		HeaderVariant.HEADER:
			return await _do_elegant_header(m)
		HeaderVariant.BLOCK:
			return await _do_vain_block(m)
	return false


func _do_elegant_header(m: MatchManager) -> bool:
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter saído do alcance enquanto ele mirava
	var ball: Ball = _get_ball()
	if get_header_variant() != HeaderVariant.HEADER:
		return false

	# Vai até a bola, no nível dela, parando "atrás" dela (do lado oposto ao da mira)
	var level: Heights.Level = ball.get_level()
	var gap: float = body_radius + ball.collision_radius + 2.0
	face_towards(aim)
	await _dash_to(ball.global_position - aim * gap, Heights.to_height(level), level, header_dash_time)

	if not await play_action(&"elegant_header", ANIM_VOLLEY):
		return false

	# Tentativa de gol: mesma conta do kick_ball (bônus e penalidades de habilidades de outros jogadores)
	var chance: float = clampf(header_chance + take_next_shot_bonus() + get_team_shot_bonus(ball) \
		- get_shot_debuff() - get_opponent_shot_penalty(), 0.0, 1.0)
	# A bola sai até o pico do nível escolhido
	var rise: float = maxf(0.0, Heights.to_height(header_peak_level) - ball.height)
	ball.kick(aim, header_power, Heights.lift_for_peak(rise, ball.gravity), self, chance)
	ball.play_fx(kick_fx)
	_star_burst()
	start_cooldown(CD_HEADER, header_cooldown)
	await get_tree().create_timer(0.15).timeout
	return true


func _do_vain_block(m: MatchManager) -> bool:
	var target: Player = await m.pick_ally_for_skill(self, block_range, true, _is_block_target)
	if target == null or not _is_block_target(target):
		return false   # cancelou (ou o alvo já pousou): não gasta a ação

	var level: Heights.Level = target.height_level
	var spot: Vector2 = target.global_position
	var push_dir: Vector2 = spot - global_position
	push_dir = push_dir.normalized() if push_dir.length() > 1.0 else Vector2(facing, 0.0)
	face_towards(push_dir)

	if not await play_action(&"vain_block"):
		return false

	# Vai até o inimigo e assume o lugar (e a altura) dele
	await _dash_to(spot, Heights.to_height(level), level, block_dash_time)

	# Empurra e derruba o inimigo
	target.knock_down()
	_push_player(target, spot + push_dir * block_push_distance)
	_star_burst()
	start_cooldown(CD_HEADER, header_cooldown)
	await get_tree().create_timer(0.25).timeout
	return true


# ---------- GLAM! + MIRROR GLAM ----------

func _can_glam() -> bool:
	var ball: Ball = _get_ball()
	if ball == null or is_down or ball.is_held() or ball.is_locked_for(team):
		return false
	if not can_reach_level(ball.get_level()):
		return false
	return global_position.distance_to(ball.global_position) <= glam_range


func _hold_point() -> Vector2:
	return global_position + Vector2(facing * glam_ball_offset, 0.0)


func _use_glam(m: MatchManager) -> bool:
	if not _can_glam():
		return false
	face_towards(_get_ball().global_position - global_position)
	if not await play_action(&"glam"):
		return false

	var ball: Ball = _get_ball()
	if not _can_glam():   # a bola pode ter saído do alcance durante a animação
		return false

	m.clear_pending_pass()                 # passe alto em andamento: a bola agora é da Aryu
	ball.register_touch(self)
	ball.hover_to(_hold_point(), height, glam_grab_time)
	await get_tree().create_timer(glam_grab_time).timeout

	_glam_touches = ball.interaction_count   # qualquer toque depois disto solta a bola
	ball.spell_owner = self                  # adversários não conseguem tocar na bola enquanto ela está com a Aryu
	_glam_state = GlamState.HOLDING
	start_cooldown(CD_GLAM, glam_cooldown)
	_star_burst()
	queue_redraw()
	return true


## Enquanto segura a bola: ela acompanha a Aryu; no turno adversário, quem chegar perto faz a Aryu desviar
func _physics_process(delta: float) -> void:
	super(delta)
	if _glam_state == GlamState.NONE:
		return
	var ball: Ball = _get_ball()
	if ball == null:
		_end_glam(false)
		return
	# Alguém tocou/chutou a bola, ou ela foi solta por fora: o Glam acabou
	if ball.interaction_count != _glam_touches or not ball.hovering or ball.is_held():
		_end_glam(false)
		return
	if is_down:   # derrubado: perde a bola
		_end_glam(true)
		return

	ball.global_position = _hold_point()
	ball.height = height

	if _glam_state == GlamState.HOLDING and not _dodging:
		_check_glam_trigger(ball)


func _check_glam_trigger(ball: Ball) -> void:
	var m: MatchManager = _get_manager()
	# Só o turno do adversário conta (no turno da própria Aryu ninguém "tenta" nada)
	if m == null or m.match_over or m.current_team == team:
		return
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team or p.is_down or not p.can_reach_level(ball.get_level()):
			continue
		var radius: float = maxf(glam_trigger_radius, p.kick_range + 5.0)
		if p.global_position.distance_to(ball.global_position) <= radius:
			_glam_dodge(p.global_position)
			return


## Aryu e a bola saem de perto de quem tentou interagir; o Mirror Glam é liberado
func _glam_dodge(from: Vector2) -> void:
	_dodging = true
	var away: Vector2 = global_position - from
	if away.length() < 1.0:
		away = Vector2(-facing, 0.0)
	var dest: Vector2 = _clamp_to_pitch(global_position + away.normalized() * glam_dodge_distance)
	face_towards(-away)
	_star_burst()
	var tw := create_tween()
	tw.tween_property(self, "global_position", dest, glam_dodge_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(glam_dodge_time).timeout
	_dodging = false
	if _glam_state == GlamState.HOLDING:
		_glam_state = GlamState.MIRROR
		queue_redraw()


## release = true solta a bola (cai e rola); false = a bola já foi tocada/solta por outro
func _end_glam(release: bool) -> void:
	if _glam_state == GlamState.NONE:
		return
	_glam_state = GlamState.NONE
	_dodging = false
	var ball: Ball = _get_ball()
	if release and ball != null and ball.hovering and not ball.is_held():
		ball.release_hover()
	queue_redraw()


func _ally_in_pass_range(m: MatchManager) -> bool:
	for other: Player in m.get_team_players(team):
		if other != self and m.can_pass_to(self, other, MatchManager.PassVariant.GROUND):
			return true
	return false


## Mirror Glam: passe rasteiro simples (reta) para um companheiro
func _use_mirror(m: MatchManager) -> bool:
	var reach: float = m.pass_range_for(MatchManager.PassVariant.GROUND, self)
	var target: Player = await m.pick_ally_for_skill(self, reach)
	if target == null:
		return false
	var ball: Ball = _get_ball()
	if ball == null or _glam_state != GlamState.MIRROR:
		return false

	_glam_state = GlamState.NONE   # o complemento foi gasto
	queue_redraw()
	_star_burst()
	# curve_ratio 0 = reta; é o passe rasteiro normal, só que com a aura marrom e a animação própria
	await m.run_curved_ground_pass(self, target, ball, 0.0, 1.0, &"mirror_glam", kick_fx)
	# Se o passe não saiu (alvo colado, por exemplo), a bola não fica presa
	if ball.hovering and not ball.is_held():
		ball.release_hover()
	return true


## O Mirror Glam não gasta ação de habilidade (já foi "pago" pelo Glam!)
func skill_is_free(skill_id: StringName) -> bool:
	return skill_id == SKILL_MIRROR


## Com o Mirror Glam liberado o turno não acaba sozinho, para dar tempo de usá-lo
func has_free_followup() -> bool:
	return _glam_state == GlamState.MIRROR and not is_down


# ---------- SHOOTING STAR ----------

func is_star_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _star_until_round >= 0 and m.round_number <= _star_until_round


func _near_goal_area() -> bool:
	var field: Field = _get_field()
	if field == null:
		return false
	var rect: Rect2 = field.get_penalty_area_rect(team).grow(star_area_margin)
	return rect.has_point(field.to_local(global_position))


## Só dá para usar suspenso ou voando
func _is_airborne() -> bool:
	return height_level != Heights.Level.GROUND


func _star_skill_name() -> String:
	return "Shooting Star (ativa)" if is_star_active() else skill_label("Shooting Star", CD_STAR)


## Ponto de bloqueio: na frente do gol, do lado em que está a bola
func _star_block_point(field: Field) -> Vector2:
	var half_x: float = field.pitch_size.x * 0.5
	var dir: float = -1.0 if team == 0 else 1.0   # time 0 defende o gol da esquerda
	var limit: float = field.goal_width * 0.5 - body_radius - 6.0
	var y: float = 0.0
	var ball: Ball = _get_ball()
	if ball:
		y = clampf(field.to_local(ball.global_position).y * star_cover_ratio, -limit, limit)
	return field.to_global(Vector2(half_x * dir - dir * star_goal_gap, y))


func _use_star(m: MatchManager) -> bool:
	var field: Field = _get_field()
	if field == null or not _near_goal_area() or not _is_airborne():
		return false

	face_towards(field.get_defend_goal_center(team) - global_position)
	if not await play_action(&"shooting_star"):
		return false

	# Vai até o gol, mantendo a altura (ele chega no ar)
	await _dash_to(_star_block_point(field), height, height_level, star_dash_time)

	_star_until_round = m.round_number + star_rounds - 1   # a rodada atual conta
	_star_penalty = shooting_penalty
	start_cooldown(CD_STAR, star_cooldown)
	_star_burst()
	queue_redraw()
	return true


## Chamado pelo Player.get_opponent_shot_penalty(): quanto ESTA jogadora tira da chance de gol
## do chute de um adversário (0.10 = -10%). Derrubada, ela não bloqueia nada.
func shot_penalty_on(_shooter: Player) -> float:
	if is_down or not is_star_active():
		return 0.0
	return _star_penalty


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_HEADER, "name": skill_label(_header_skill_name(), CD_HEADER)})
	var glam_name: String = "Glam! (segurando)" if _glam_state != GlamState.NONE \
		else skill_label("Glam!", CD_GLAM)
	list.append({"id": SKILL_GLAM, "name": glam_name})
	if _glam_state == GlamState.MIRROR:
		list.append({"id": SKILL_MIRROR, "name": "Mirror Glam (grátis)"})
	list.append({"id": SKILL_STAR, "name": _star_skill_name()})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_HEADER:
			return not is_on_cooldown(CD_HEADER) and get_header_variant() != HeaderVariant.NONE
		SKILL_GLAM:
			return _glam_state == GlamState.NONE and not is_on_cooldown(CD_GLAM) and _can_glam()
		SKILL_MIRROR:
			var m: MatchManager = _get_manager()
			return m != null and _glam_state == GlamState.MIRROR and not _dodging \
				and _ally_in_pass_range(m)
		SKILL_STAR:
			return not is_star_active() and not is_on_cooldown(CD_STAR) and _near_goal_area() \
				and _is_airborne()
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match skill_id:
		SKILL_HEADER:
			return await _use_header_skill()
		SKILL_GLAM:
			return await _use_glam(m)
		SKILL_MIRROR:
			return await _use_mirror(m)
		SKILL_STAR:
			return await _use_star(m)
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_HEADER:
			var header_text: String = "Elegant Header: com a bola ao alcance (até %d px) e suspensa ou voando, vai até ela no nível dela e a cabeceia na direção mirada. É uma tentativa de gol (%d%% de chance)." % [
				int(header_range), int(round(header_chance * 100.0))]
			var block_text: String = "Vain Block: sem bola ao alcance, mas com um inimigo suspenso ou voando (até %d px), vai até ele, ocupa o lugar e a altura dele, e o empurra e derruba." % int(block_range)
			match get_header_variant():
				HeaderVariant.HEADER:
					title = "Elegant Header"
					text = header_text
				HeaderVariant.BLOCK:
					title = "Vain Block"
					text = block_text
				_:
					title = "Elegant Header / Vain Block"
					text = header_text + "\n" + block_text
			text += "\nRecarga: %d rodadas, compartilhada entre as duas." % header_cooldown
		SKILL_GLAM:
			title = "Glam!"
			text = "Com a bola próxima (até %d px), Aryu a segura. Dura até o fim do próximo turno do adversário: se alguém chegar perto, Aryu e a bola desviam e liberam o Mirror Glam.\nRecarga: %d rodadas." % [
				int(glam_range), glam_cooldown]
		SKILL_MIRROR:
			title = "Mirror Glam"
			text = "Passe rasteiro simples para um companheiro. Não gasta ação de habilidade e vale até o fim do próximo turno do seu time. Recarga compartilhada com o Glam!"
		SKILL_STAR:
			title = "Shooting Star"
			text = "Perto da grande área que defende e suspensa ou voando, Aryu vai até o gol e fecha uma parte com o corpo. Por %d rodadas, os chutes adversários perdem %d%% de chance de gol.\nRecarga: %d rodadas." % [
				star_rounds, int(round(shooting_penalty * 100.0)), star_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_end_glam(true)
	_glam_state = GlamState.NONE
	_dodging = false
	_star_until_round = -1
	_star_penalty = 0.0
	queue_redraw()


# ---------- ESTRELINHAS BRANCAS ----------

## Textura de estrela de 5 pontas, desenhada por código (não precisa de arquivo)
static func _make_star_texture() -> ImageTexture:
	var size: int = 24
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var pts := PackedVector2Array()
	for i in 10:
		var r: float = (size * 0.5 - 1.0) if i % 2 == 0 else (size * 0.2)
		var a: float = -PI / 2.0 + float(i) * PI / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	for y in size:
		for x in size:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _build_star_particles() -> void:
	var tex: ImageTexture = _make_star_texture()
	_star_burst_fx = _make_star_particles(tex, true)
	_star_stream_fx = _make_star_particles(tex, false)


func _make_star_particles(tex: Texture2D, burst: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.local_coords = false                 # as estrelas ficam no mundo, não andam com ela
	p.one_shot = burst
	p.emitting = false
	p.explosiveness = 1.0 if burst else 0.0
	p.amount = 14 if burst else 5
	p.lifetime = 0.8 if burst else 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 16.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0.0, -30.0)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 110.0 if burst else 40.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	p.color = Color.WHITE
	add_child(p)
	return p


## Explosão de estrelinhas em volta da Aryu (toda habilidade chama)
func _star_burst() -> void:
	if _star_burst_fx == null:
		return
	_star_burst_fx.position = Vector2(0.0, -height - 12.0)
	_star_burst_fx.restart()
	_star_burst_fx.emitting = true


# ---------- LOOP / VISUAL ----------

func _aura_key() -> int:
	return (1 if is_star_active() else 0) | (2 if _glam_state != GlamState.NONE else 0)


func _process(delta: float) -> void:
	super(delta)
	var key: int = _aura_key()
	if key != _aura_drawn:
		_aura_drawn = key
		queue_redraw()
	# Estrelinhas contínuas enquanto Glam!/Star estão valendo
	if _star_stream_fx:
		_star_stream_fx.position = Vector2(0.0, -height - 12.0)
		var want: bool = key != 0
		if _star_stream_fx.emitting != want:
			_star_stream_fx.emitting = want


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)
	# Anel marrom enquanto Shooting Star está valendo
	if is_star_active():
		draw_arc(center, placeholder_radius + 8.0, 0.0, TAU, 40, Color(BROWN, 0.9), 3.0)
	# Anel marrom fino enquanto segura a bola (Glam!)
	if _glam_state != GlamState.NONE:
		draw_arc(center, placeholder_radius + 4.0, 0.0, TAU, 40, Color(BROWN, 0.7), 2.0)
