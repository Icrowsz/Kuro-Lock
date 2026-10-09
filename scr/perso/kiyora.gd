class_name Kiyora
extends Player
## Kiyora. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias.
## NÃO precisa de nenhuma edição em outros arquivos.
##
## 1. Dance Battle (ação de habilidade, recarga de 2 rodadas): com a bola ao alcance (no chão ou
##      suspensa) e o Kiyora no chão, ele PUXA a bola e a GRUDA nele: ela acompanha o Kiyora e os
##      adversários não conseguem tocar nela nem mover para longe (mesma trava do Zero Reset
##      Turn / Glam: spell_owner). Se um inimigo tentar interagir (correr/deslizar para perto
##      da bola ou dar Carrinho no Kiyora), o inimigo cai e o Kiyora libera o BACKSPIN: pelas
##      próximas 3 rodadas, as habilidades dele ficam melhores. A bola solta no fim do
##      próximo turno do adversário (ou quando alguém da equipe dele mexer nela).
## 2. Borderline (ação de habilidade, recarga de 2 rodadas, compartilhada com a variante):
##      passe alto (bola no chão ou suspensa, Kiyora no chão) que sobe a Voando no caminho.
##      O Kiyora escolhe DOIS aliados e a bola vai para o que tiver MENOS gols (empate = sorteio).
##    Even the Gods (com o Backspin ativo): igual, mas o Kiyora também escolhe a parte do campo
##      onde a bola cai (perto do aliado que vai receber).
## 3. Windmill / Twister / Six-Step (ação de habilidade, recarga de 2 rodadas, compartilhada;
##      a variante muda sozinha):
##      - Windmill (bola no chão e ao alcance): giro e passe rasteiro para o aliado mais próximo
##      - Twister (Backspin ativo; bola no chão OU suspensa): passe para o aliado mais próximo em
##        que a bola sobe a Voando e chega Suspensa
##      - Six-Step (bola longe): carrinho mais longo; se encontrar a bola, vira um passe rasteiro
##        simples para o aliado mais próximo
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Kiyora".
##
## Animações opcionais (SpriteFrames; hit_frames diz o frame de impacto de cada uma):
## "dance_battle", "borderline", "even_the_gods", "windmill", "twister". Sem elas, nada quebra.
## (O Six-Step usa a animação "slide" do carrinho e o passe usa "pass".)

const SKILL_DANCE: StringName = &"dance_battle"
const SKILL_BORDER: StringName = &"borderline"
const SKILL_WIND: StringName = &"windmill"

## Grupos de recarga (as variantes de cada habilidade compartilham o mesmo)
const CD_DANCE: StringName = &"cd_dance"
const CD_BORDER: StringName = &"cd_border"
const CD_WIND: StringName = &"cd_wind"

enum PassSkill { NONE, BORDERLINE, GODS }
enum WindSkill { NONE, WINDMILL, TWISTER, SIX_STEP }

## Azul escuro esverdeado
const TEAL := Color(0.05, 0.30, 0.38)
const TEAL_LIGHT := Color(0.28, 0.68, 0.64)

@export_group("Dance Battle")
@export var dance_cooldown: int = 2
@export var dance_pull_time: float = 0.25          # tempo que a bola leva para ser puxada
@export var dance_ball_offset: float = 24.0        # a bola fica grudada à frente dele
@export var dance_trigger_radius: float = 75.0     # inimigo agindo a esta distância da bola = tentou interagir
## Duração do Backspin, em rodadas depois da atual
@export var backspin_rounds: int = 3

@export_group("Borderline / Even the Gods")
@export var border_cooldown: int = 2               # recarga, igual para as duas variantes
## Even the Gods: a bola cai no máximo a esta distância do aliado que vai receber
@export var gods_land_radius: float = 500.0

@export_group("Windmill / Twister / Six-Step")
@export var wind_cooldown: int = 2                 # recarga, igual para as 3 variantes
@export var six_step_slide_mult: float = 1.8       # Six-Step: carrinho mais longo que o normal

@export_group("Visual do chute")
## Aura + partículas dos passes de habilidade. Vazio = azul esverdeado (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: dance_battle, borderline, windmill.
@export var skill_icons: Dictionary = {}

## Backspin vale até o fim desta rodada (-1 = inativo)
var _backspin_until_round: int = -1
## Dance Battle: a bola está grudada no Kiyora
var _trap_on: bool = false
var _trap_triggered: bool = false   # um inimigo já caiu nesta janela (o Backspin já foi liberado)
var _trap_touches: int = 0          # qualquer toque depois disto solta a bola
var _trap_ring: TrapRing = null
## Muda a cada Dance Battle / partida nova: uma espera antiga percebe e para
var _dance_token: int = 0
## Six-Step em andamento
var _six_step_active: bool = false
var _six_step_ball_found: bool = false


func _init() -> void:
	character_id = "kiyora"          # o menu de formação usa isto para saber quem é quem
	display_name = "Kiyora"          # aparece no placar de gols e no menu (troque aqui se quiser)


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_hook_manager.call_deferred()   # o MatchManager entra na árvore no mesmo frame


## Azul escuro esverdeado
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = TEAL
	fx.trail_width = 14.0
	fx.particle_color = TEAL_LIGHT
	fx.amount = 22
	fx.lifetime = 0.55
	fx.speed_min = 15.0
	fx.speed_max = 70.0
	fx.gravity = Vector2(0.0, -40.0)
	fx.spin = 300.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 14
	fx.burst_speed = 220.0
	return fx


func _exit_tree() -> void:
	_end_trap(true)


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)
		m.turn_ended.connect(_on_turn_ended)
	var ball: Ball = _get_ball()
	if ball:
		ball.was_reset.connect(_on_ball_reset)


## Dance Battle: sem ninguém tocar, a bola solta no fim do turno do adversário
func _on_turn_ended(ended_team: int) -> void:
	if _trap_on and ended_team != team:
		_end_trap(true)


func _on_ball_reset() -> void:
	_end_trap(false)   # gol / reposição: a bola já foi solta pelo próprio Ball


func _on_round_started(_round_number: int) -> void:
	queue_redraw()   # a aura do Backspin some quando as rodadas acabam


func is_backspin_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _backspin_until_round >= 0 and m.round_number <= _backspin_until_round


# ---------- ALIADOS (alcance / escolha) ----------

## Companheiros que o Kiyora consegue alcançar com o passe da variante (rasteiro ou alto)
func _pass_candidates(variant: int) -> Array[Player]:
	var result: Array[Player] = []
	var m: MatchManager = _get_manager()
	if m == null:
		return result
	for p: Player in m.get_team_players(team):
		if m.can_pass_to(self, p, variant):
			result.append(p)
	return result


func _nearest_ally(variant: int) -> Player:
	var best: Player = null
	var best_dist: float = INF
	for p in _pass_candidates(variant):
		var d: float = global_position.distance_to(p.global_position)
		if d < best_dist:
			best = p
			best_dist = d
	return best


func _can_receive_high(p: Player) -> bool:
	var m: MatchManager = _get_manager()
	return m != null and is_instance_valid(p) and m.can_pass_to(self, p, MatchManager.PassVariant.HIGH)


func _can_receive_high_except(p: Player, skip: Player) -> bool:
	return p != skip and _can_receive_high(p)


# ---------- DANCE BATTLE ----------

## Onde a bola fica grudada: à frente do Kiyora
func _trap_point() -> Vector2:
	return global_position + Vector2(facing * dance_ball_offset, 0.0)


func _use_dance() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or get_kick_type(ball) == KickType.NONE:
		return false

	face_towards(ball.global_position - global_position)
	if not await play_action(&"dance_battle"):
		return false   # ação cancelada (ex: a partida reiniciou)
	# A bola pode ter saído do alcance durante a animação
	if not is_instance_valid(ball) or get_kick_type(ball) == KickType.NONE:
		return false

	_end_trap(false)
	_dance_token += 1
	var token: int = _dance_token

	# PUXA a bola: ela desliza (e desce, se estava suspensa) até ficar colada no Kiyora
	m.clear_pending_pass()          # passe alto em andamento: a bola agora é do Kiyora
	ball.register_touch(self)
	ball.hover_to(_trap_point(), 0.0, dance_pull_time)
	ball.play_fx(kick_fx)
	await get_tree().create_timer(dance_pull_time + 0.02).timeout
	if token != _dance_token or not is_instance_valid(ball) or m.match_over:
		return false

	# GRUDA: a bola fica pairando colada nele e travada para os adversários (Ball.is_locked_for)
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.spell_owner = self
	_trap_touches = ball.interaction_count   # qualquer toque depois disto solta a bola
	_trap_on = true
	_trap_triggered = false
	_trap_ring = TrapRing.new()
	_trap_ring.ring_color = TEAL_LIGHT
	_trap_ring.core_color = TEAL
	ball.add_child(_trap_ring)

	start_cooldown(CD_DANCE, dance_cooldown)
	return true


## Enquanto a bola está grudada: ela acompanha o Kiyora e, no turno do adversário, um inimigo
## que age (corre/desliza) perto da bola dispara o contra-ataque.
func _physics_process(delta: float) -> void:
	super(delta)
	_update_trap()


func _update_trap() -> void:
	if not _trap_on:
		return
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or m.match_over:
		_end_trap(false)
		return
	# Alguém do time dele tocou/chutou a bola, ou ela foi solta/segurada por fora: acabou
	if ball.spell_owner != self or not ball.hovering or ball.is_held() \
			or ball.interaction_count != _trap_touches:
		_end_trap(false)
		return
	if is_down:   # derrubado: perde a bola
		_end_trap(true)
		return

	ball.global_position = _trap_point()
	ball.height = 0.0

	# "Tentar interagir" só conta no turno do adversário e só uma vez por janela
	if _trap_triggered or m.current_team == team:
		return
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down or other.state == State.IDLE \
				or not other.can_reach_level(ball.get_level()):
			continue
		var radius: float = maxf(dance_trigger_radius, other.kick_range + 5.0)
		if other.global_position.distance_to(ball.global_position) <= radius:
			_dance_trigger(other, false)
			return


## Um inimigo tentou interagir: ele cai e o Backspin liga. A bola continua grudada.
func _dance_trigger(enemy: Player, from_slide: bool) -> void:
	var m: MatchManager = _get_manager()
	if _trap_triggered or m == null:
		return
	_trap_triggered = true

	# Quem estava correndo é parado. Quem deu Carrinho (from_slide) é derrubado sem interromper o
	# carrinho dele no meio do próprio _check_slide_hits: o carrinho acaba sozinho logo depois.
	if not from_slide:
		enemy._stop_current_action()
	enemy.knock_down()
	var pulse := PulseRing.new()
	pulse.ring_color = TEAL_LIGHT
	enemy.add_child(pulse)
	hop_over()   # o pulinho de quem desvia/dança

	_backspin_until_round = m.round_number + backspin_rounds
	queue_redraw()


## O Carrinho de um inimigo contra o Kiyora (com a bola grudada) conta como tentar interagir:
## o Kiyora desvia e quem deu o carrinho é que cai.
func try_counter_slide(attacker: Player) -> bool:
	if not _trap_on or _trap_triggered or is_down or attacker.team == team:
		return false
	attacker._slide_hit_ball = true   # o resto do carrinho não tenta chutar a bola
	_dance_trigger(attacker, true)
	return true


## release = true solta a bola (ela fica onde está); false = ela já foi tocada/solta por outro
func _end_trap(release: bool) -> void:
	var was_on: bool = _trap_on
	_trap_on = false
	_trap_triggered = false
	if _trap_ring != null and is_instance_valid(_trap_ring):
		_trap_ring.queue_free()
	_trap_ring = null
	if was_on and release:
		var ball: Ball = _get_ball()
		if ball != null and is_instance_valid(ball) and ball.spell_owner == self:
			ball.release_hover()   # volta a gravidade e a trava some


# ---------- BORDERLINE / EVEN THE GODS ----------

func get_pass_skill() -> PassSkill:
	return PassSkill.GODS if is_backspin_active() else PassSkill.BORDERLINE


func _use_border() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or get_kick_type(ball) == KickType.NONE:
		return false
	var gods: bool = get_pass_skill() == PassSkill.GODS
	var high_range: float = m.pass_range_for(MatchManager.PassVariant.HIGH, self)

	# Escolhe dois aliados (se só houver um ao alcance, é ele). Cancelar qualquer escolha cancela a habilidade.
	var first: Player = await m.pick_ally_for_skill(self, high_range, false, _can_receive_high)
	if first == null or m.match_over:
		return false
	var chosen: Array[Player] = [first]
	var others: int = 0
	for p in _pass_candidates(MatchManager.PassVariant.HIGH):
		if p != first:
			others += 1
	if others > 0:
		var second: Player = await m.pick_ally_for_skill(self, high_range, false,
			_can_receive_high_except.bind(first))
		if second == null or m.match_over:
			return false
		chosen.append(second)

	var receiver: Player = _fewest_goals(m, chosen)

	if not gods:
		# Borderline: passe alto de habilidade até quem tem menos gols
		await m.run_skill_high_pass(self, receiver, ball, high_range, &"borderline", kick_fx)
	else:
		# Even the Gods: ele também escolhe onde a bola cai (perto de quem vai receber)
		var point: Vector2 = await m.pick_point_for_skill(self, high_range)
		if point == Vector2.INF or m.match_over:
			return false
		var offset: Vector2 = (point - receiver.global_position).limit_length(gods_land_radius)
		await _gods_pass(m, ball, receiver.global_position + offset)

	start_cooldown(CD_BORDER, border_cooldown)
	return true


## Quem tem menos gols entre os escolhidos (empate = sorteio entre os empatados)
func _fewest_goals(m: MatchManager, players: Array[Player]) -> Player:
	var best: Array[Player] = []
	var best_goals: int = 1000000
	for p in players:
		var goals: int = int(m._stats_for(p)["goals"])
		if goals < best_goals:
			best_goals = goals
			best = [p]
		elif goals == best_goals:
			best.append(p)
	return best.pick_random()


## Passe alto que pousa num PONTO do campo (mesmo fluxo do passe alto comum): a bola sobe a
## Voando no meio do caminho e, quando o turno do time volta, desce até o ponto, Suspensa.
func _gods_pass(m: MatchManager, ball: Ball, point: Vector2) -> void:
	face_towards(point - global_position)
	if not await play_action(&"even_the_gods", ANIM_PASS_HIGH):
		return   # ação cancelada (ex: a partida reiniciou)
	ball.register_touch(self)   # o passe alto não usa kick(), então registra o toque aqui
	var midpoint: Vector2 = (ball.global_position + point) * 0.5
	var tween: Tween = ball.hover_to(midpoint, Heights.FLYING_HEIGHT, m.high_pass_flight_time)
	ball.play_fx(kick_fx)
	await tween.finished
	m.begin_point_pass(team, point)
	m._spawn_pass_marker(team, point, ball)   # a marca no chão mostra onde a bola vai cair


# ---------- WINDMILL / TWISTER / SIX-STEP ----------

func get_wind_skill() -> WindSkill:
	var reach: KickType = get_kick_type(_get_ball())
	if height_level != Heights.Level.GROUND:
		return WindSkill.NONE
	if reach == KickType.NONE:
		return WindSkill.SIX_STEP   # sem a bola por perto: carrinho
	if is_backspin_active():
		return WindSkill.TWISTER    # bola no chão OU suspensa
	if reach == KickType.GROUND:
		return WindSkill.WINDMILL   # só bola no chão
	return WindSkill.NONE


func _wind_skill_name() -> String:
	match get_wind_skill():
		WindSkill.TWISTER:
			return "Twister"
		WindSkill.SIX_STEP:
			return "Six-Step"
	return "Windmill"


func _use_wind() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	var variant: WindSkill = get_wind_skill()
	if m == null or ball == null or variant == WindSkill.NONE:
		return false

	match variant:
		WindSkill.WINDMILL:
			var target: Player = _nearest_ally(MatchManager.PassVariant.GROUND)
			if target == null:
				return false
			# Giro + passe rasteiro (curva 0 = reta), com a aura do personagem
			await m.run_curved_ground_pass(self, target, ball, 0.0, 1.0, &"windmill", kick_fx)
		WindSkill.TWISTER:
			var target: Player = _nearest_ally(MatchManager.PassVariant.HIGH)
			if target == null:
				return false
			# Passe alto de habilidade: sobe a Voando e chega Suspensa no aliado
			await m.run_skill_high_pass(self, target, ball,
				m.pass_range_for(MatchManager.PassVariant.HIGH, self), &"twister", kick_fx)
		WindSkill.SIX_STEP:
			if not await _use_six_step(m):
				return false
	start_cooldown(CD_WIND, wind_cooldown)
	return true


## Six-Step: carrinho mais longo. Se encontrar a bola, o carrinho acaba ali e vira um passe rasteiro.
func _use_six_step(m: MatchManager) -> bool:
	var base_distance: float = slide_distance
	var aim: Vector2 = await m.aim_for_skill(self, base_distance * six_step_slide_mult)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	_six_step_active = true
	_six_step_ball_found = false
	slide_distance = base_distance * six_step_slide_mult
	start_slide(aim)
	slides_this_turn = maxi(0, slides_this_turn - 1)   # é habilidade: não gasta o limite de Carrinhos do turno
	await slide_finished
	slide_distance = base_distance
	_six_step_active = false

	var ball: Ball = _get_ball()
	if _six_step_ball_found and is_instance_valid(ball) and not m.match_over:
		var target: Player = _nearest_ally(MatchManager.PassVariant.GROUND)
		if target != null:
			await m.run_curved_ground_pass(self, target, ball, 0.0, 1.0, &"", kick_fx)
		else:
			ball.kick_ground(aim, slide_ball_power, self, Ball.NO_SHOT)   # sem aliado: só empurra a bola
	return true


## O carrinho do Six-Step trata a bola aqui (passe) em vez do chute padrão do carrinho
func _check_slide_hits() -> void:
	if not _six_step_active:
		super()
		return
	_slide_hit_ball = true   # impede o chute padrão na bola; os inimigos continuam caindo normalmente
	super()
	if _six_step_ball_found:
		return
	var ball: Ball = _get_ball()
	if ball and not ball.is_held() and not ball.is_locked_for(team) \
			and ball.get_level() == Heights.Level.GROUND \
			and global_position.distance_to(ball.global_position) <= slide_hit_radius:
		_six_step_ball_found = true
		slide_time_left = 0.0   # encontrou a bola: o carrinho termina aqui


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var dance_name: String = "Dance Battle (grudada)" if _trap_on else skill_label("Dance Battle", CD_DANCE)
	list.append({"id": SKILL_DANCE, "name": dance_name})
	var border_name: String = "Even the Gods" if get_pass_skill() == PassSkill.GODS else "Borderline"
	list.append({"id": SKILL_BORDER, "name": skill_label(border_name, CD_BORDER)})
	list.append({"id": SKILL_WIND, "name": skill_label(_wind_skill_name(), CD_WIND)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_DANCE:
			return not _trap_on and not is_on_cooldown(CD_DANCE) \
				and height_level == Heights.Level.GROUND \
				and get_kick_type(_get_ball()) != KickType.NONE
		SKILL_BORDER:
			return not is_on_cooldown(CD_BORDER) and height_level == Heights.Level.GROUND \
				and get_kick_type(_get_ball()) != KickType.NONE \
				and not _pass_candidates(MatchManager.PassVariant.HIGH).is_empty()
		SKILL_WIND:
			if is_on_cooldown(CD_WIND):
				return false
			match get_wind_skill():
				WindSkill.SIX_STEP:
					return true
				WindSkill.WINDMILL:
					return _nearest_ally(MatchManager.PassVariant.GROUND) != null
				WindSkill.TWISTER:
					return _nearest_ally(MatchManager.PassVariant.HIGH) != null
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_DANCE:
			return await _use_dance()
		SKILL_BORDER:
			return await _use_border()
		SKILL_WIND:
			return await _use_wind()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_DANCE:
			title = "Dance Battle"
			text = ("Com a bola ao alcance (no chão ou suspensa) e o Kiyora no chão, ele puxa a bola e a gruda nele: "
				+ "ela acompanha o Kiyora e os adversários não conseguem tocar nela. "
				+ "Se um inimigo tentar interagir (correr ou deslizar para perto, ou dar Carrinho nele), o inimigo cai e o Kiyora libera o Backspin: "
				+ "por %d rodadas, as habilidades dele ficam melhores (Even the Gods e Twister). "
				+ "A bola solta no fim do próximo turno do adversário.\n"
				+ "Recarga: %d rodadas.") % [backspin_rounds, dance_cooldown]
		SKILL_BORDER:
			title = "Even the Gods" if get_pass_skill() == PassSkill.GODS else "Borderline"
			text = ("Passe alto que sobe a Voando no caminho. Escolha dois aliados: a bola vai para o que tiver "
				+ "MENOS gols (empate = sorteio).\n"
				+ "• Even the Gods (com o Backspin ativo): você também escolhe onde a bola cai, perto de quem vai receber.\n"
				+ "Recarga: %d rodadas, compartilhada entre as duas.") % border_cooldown
		SKILL_WIND:
			title = _wind_skill_name()
			text = ("A variante muda sozinha:\n"
				+ "• Windmill (bola no chão e ao alcance): giro e passe rasteiro para o aliado mais próximo.\n"
				+ "• Twister (Backspin ativo; bola no chão ou suspensa): a bola sobe a Voando e chega Suspensa no aliado mais próximo.\n"
				+ "• Six-Step (bola longe): carrinho mais longo; se encontrar a bola, vira um passe rasteiro simples.\n"
				+ "Recarga: %d rodadas, compartilhada entre as três.") % wind_cooldown
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_dance_token += 1   # uma espera de Dance Battle em andamento percebe e para
	_end_trap(true)
	_backspin_until_round = -1
	if _six_step_active:
		_six_step_active = false
	queue_redraw()


# ---------- VISUAL ----------

func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Backspin ativo: anel azul-esverdeado "girando" (3 arcos) com um fio claro por dentro
	if is_backspin_active():
		var r: float = placeholder_radius + 8.0
		for i in 3:
			var a0: float = TAU * float(i) / 3.0
			draw_arc(center, r, a0, a0 + TAU / 3.0 * 0.7, 10, Color(TEAL_LIGHT, 0.95), 3.0)
		draw_arc(center, r - 4.0, 0.0, TAU, 40, Color(TEAL, 0.9), 2.0)


## Anel que gira em volta da bola armada pelo Dance Battle
class TrapRing extends Node2D:
	var ring_color: Color = Color(0.28, 0.68, 0.64)
	var core_color: Color = Color(0.05, 0.30, 0.38)

	func _ready() -> void:
		z_index = 5

	func _process(delta: float) -> void:
		rotation += delta * 3.5
		queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(core_color, 0.9), 2.0)
		for i in 3:
			var a0: float = TAU * float(i) / 3.0
			draw_arc(Vector2.ZERO, 22.0, a0, a0 + 1.4, 10, ring_color, 3.0)


## Anel que se abre e some (usado no inimigo que caiu no Dance Battle)
class PulseRing extends Node2D:
	var ring_color: Color = Color(0.28, 0.68, 0.64)
	var _time: float = 0.0
	const LIFE: float = 0.5

	func _ready() -> void:
		z_index = 10

	func _process(delta: float) -> void:
		_time += delta
		if _time >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_time / LIFE, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 18.0 + 30.0 * k, 0.0, TAU, 32, Color(ring_color, 1.0 - k), 3.0)
