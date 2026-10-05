class_name Bachira
extends Player
## Bachira Meguru. Mais um personagem do time, com 3 habilidades:
##
## 1. Bon! (ação de habilidade, com 2 variantes automáticas pela altura; recarga de 2 rodadas,
##      compartilhada):
##      - Bachira e bola NÃO os dois suspensos (e a bola ao alcance) -> Bon!: chute que põe a
##          bola no nível Voando antes de ela cair de novo (30%). Sem QTE com a bola no chão;
##          se a bola estiver mais alta, o QTE é o do chute comum daquela situação.
##      - Bachira e bola os dois suspensos -> Bee Shot: voleio SEM QTE (40%).
##
## 2. Step Overs (ação de habilidade; recarga de 3 rodadas): com Bachira e a bola no chão, ele
##      faz as passadas na bola e atordoa os (até) 2 inimigos mais próximos, bem perto dele:
##      eles ficam sem poder usar as ações gerais Carrinho e Correr no PRÓXIMO turno do time
##      deles (step_stun_turns).
##
## 3. Unleash Instinct (ação de habilidade; recarga de 3 rodadas): com a bola, Bachira arma um
##      counter. Se um inimigo acertar um Carrinho nele (os dois no chão, bola ao alcance), o
##      counter dispara sozinho, fora do turno dele: ele desvia (salta por cima do carrinho) e
##      ganha UMA ação geral extra, que vale para tudo MENOS o Correr (extra_general_no_run_left).
##      Por padrão a bola também fica grudada nele até o fim da rodada, como no Gremlin Taunt
##      do Charles (instinct_sticks_ball).
##
## Como montar a cena: igual aos outros — Nova Cena Herdada de player.tscn -> anexe este
## script ao nó raiz -> renomeie o nó raiz para "Bachira".
##
## Animações opcionais (se faltar alguma, o jogo só pula): bon, bee_shot, step_overs,
## unleash_instinct.
##
## PEÇAS NO RESTO DO PROJETO (já aplicadas nos arquivos devolvidos junto com este):
## - player.gd: o campo extra_general_no_run_left.
## - match_manager.gd: general_left_for()/_consume_general() passam a conhecer a ação, para a
##   ação extra "sem Correr" não valer no Correr.
## - player.gd (da conversa anterior): o carrinho inimigo respeita a trava da bola.

const SKILL_SHOT: StringName = &"bon"
const SKILL_STEP: StringName = &"step_overs"
const SKILL_INSTINCT: StringName = &"unleash_instinct"

## Grupos de recarga (as variantes do Bon! compartilham o mesmo)
const CD_SHOT: StringName = &"cd_shot"
const CD_STEP: StringName = &"cd_step"
const CD_INSTINCT: StringName = &"cd_instinct"

## Variante da habilidade 1, pela altura do Bachira x altura da bola
enum ShotVariant { NONE, BON, BEE }

@export_group("Bon! / Bee Shot")
@export_range(0.0, 1.0) var chance_bon: float = 0.30
@export_range(0.0, 1.0) var chance_bee: float = 0.40
@export var bon_peak_level: Heights.Level = Heights.Level.FLYING   # até onde a bola sobe no Bon!
@export var shot_cooldown: int = 2                                  # igual para as 2 variantes

@export_group("Step Overs")
@export var step_range: float = 170.0          # "bem próximos": distância máxima até o inimigo
@export var step_max_targets: int = 2
## Quantos turnos do time inimigo o atordoamento dura (1 = o próximo turno deles)
@export var step_stun_turns: int = 1
@export var step_cooldown: int = 3

@export_group("Unleash Instinct")
@export var instinct_cooldown: int = 3
@export var instinct_extra_generals: int = 1           # ações gerais extras (menos Correr)
@export var instinct_sticks_ball: bool = true          # a bola fica grudada nele até o fim da rodada
@export var instinct_stick_extra_rounds: int = 0       # rodadas que a bola continua grudada DEPOIS da rodada do counter

@export_group("Visual do chute")
## Aura + partículas dos chutes de habilidade. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

## Unleash Instinct está armado, esperando um Carrinho inimigo disparar o counter
var _instinct_armed: bool = false
## A bola está grudada no Bachira até o fim desta rodada (-1 = não está)
var _stuck_until_round: int = -1
## Inimigos atordoados pelo Step Overs: jogador -> quantos turnos do time dele ainda faltam
var _stunned: Dictionary = {}


func _init() -> void:
	character_id = "bachira"   # o menu de formação usa isto para saber quem é quem
	display_name = "Bachira"


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	# O Step Overs tira ações gerais dos inimigos (ver blocks_general_action), então o
	# Bachira entra no mesmo grupo dos outros efeitos de controle (Niko, Shidou...)
	add_to_group("control_sources")
	_hook_manager.call_deferred()


## Amarelo vivo; as partículas são "estrelinhas" quadradas que giram e sobem
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(1.0, 0.85, 0.2)
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(1.0, 0.95, 0.6)
	fx.amount = 22
	fx.lifetime = 0.55
	fx.speed_min = 15.0
	fx.speed_max = 70.0
	fx.gravity = Vector2(0.0, -60.0)
	fx.spin = 360.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 14
	fx.burst_speed = 220.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)
		m.turn_ended.connect(_on_turn_ended)


func _on_round_started(new_round: int) -> void:
	# A rodada do counter acabou: a bola desgruda e volta ao jogo normal
	if _stuck_until_round >= 0 and new_round > _stuck_until_round:
		_release_stuck_ball()
	queue_redraw()


## O atordoamento dura os turnos do time INIMIGO: cada vez que o turno de um time acaba, os
## atordoados daquele time perdem um turno de atordoamento
func _on_turn_ended(ended_team: int) -> void:
	if _stunned.is_empty():
		return
	for p in _stunned.keys():
		if not is_instance_valid(p):
			_stunned.erase(p)
			continue
		if p.team != ended_team:
			continue
		_stunned[p] = int(_stunned[p]) - 1
		if int(_stunned[p]) <= 0:
			_stunned.erase(p)
	queue_redraw()


# ---------- DERRUBADO: desarma o counter ----------

func knock_down() -> void:
	super()
	_instinct_armed = false
	queue_redraw()


# ---------- HABILIDADE 1: BON! / BEE SHOT ----------

func get_shot_variant() -> ShotVariant:
	var ball: Ball = _get_ball()
	# get_kick_type já confere: derrubado, bola na mão do goleiro, presa, longe demais, altura inalcançável
	if get_kick_type(ball) == KickType.NONE:
		return ShotVariant.NONE
	if height_level == Heights.Level.SUSPENDED and ball.get_level() == Heights.Level.SUSPENDED:
		return ShotVariant.BEE
	return ShotVariant.BON


func _shot_skill_name() -> String:
	return "Bee Shot" if get_shot_variant() == ShotVariant.BEE else "Bon!"


func _use_shot_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or get_shot_variant() == ShotVariant.NONE:
		return false

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele mirava: confere de novo
	var ball: Ball = _get_ball()
	var variant: ShotVariant = get_shot_variant()
	if variant == ShotVariant.NONE:
		return false
	var base_kind: KickType = get_kick_type(ball)   # o chute comum que caberia nesta situação

	var qte_ok: bool = true
	var chance: float = chance_bee
	var anim: StringName = &"bee_shot"
	if variant == ShotVariant.BON:
		chance = chance_bon
		anim = &"bon"
		# Bola no chão = sem QTE (como o chute no chão); mais alta = o QTE do chute comum
		if base_kind != KickType.GROUND and not skips_qte():
			qte_ok = await m.run_qte(base_kind)
	# Bee Shot: voleio sem QTE

	# Os dois usam o chute de voleio (a bola sobe). No Bon! o pico passa a ser bon_peak_level
	# (Voando); o kick_ball lê o pico DEPOIS da animação, então o ajuste fica até ele terminar.
	var previous_peak: Heights.Level = volley_peak_level
	if variant == ShotVariant.BON:
		volley_peak_level = bon_peak_level
	# Errou o QTE = chute fraquinho, sem aura
	await kick_ball(ball, aim, KickType.VOLLEY, qte_ok, chance, false,
		kick_fx if qte_ok else null, anim)
	volley_peak_level = previous_peak

	start_cooldown(CD_SHOT, shot_cooldown)
	return true


# ---------- HABILIDADE 2: STEP OVERS ----------

## Bachira e bola no chão (e ao alcance)
func _step_overs_ready() -> bool:
	if is_down or height_level != Heights.Level.GROUND:
		return false
	var ball: Ball = _get_ball()
	return ball != null and get_kick_type(ball) == KickType.GROUND


## Os (até) step_max_targets inimigos mais próximos que dá para enganar: de pé, no chão e
## dentro de step_range
func _step_targets() -> Array[Player]:
	var found: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team or p.is_down or p.height_level != Heights.Level.GROUND:
			continue
		if global_position.distance_to(p.global_position) > step_range:
			continue
		found.append(p)
	found.sort_custom(func(a: Player, b: Player) -> bool:
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	if found.size() > step_max_targets:
		found.resize(step_max_targets)
	return found


func _use_step_overs() -> bool:
	if not _step_overs_ready() or _step_targets().is_empty():
		return false
	await play_action(&"step_overs")
	# Confere de novo depois da animação (a bola ou os inimigos podem ter mudado)
	if not _step_overs_ready():
		return false
	var targets: Array[Player] = _step_targets()
	if targets.is_empty():
		return false
	for e: Player in targets:
		_stunned[e] = step_stun_turns
	start_cooldown(CD_STEP, step_cooldown)
	queue_redraw()
	return true


## Chamado pelo is_general_action_blocked() do player.gd, em quem vai agir: atordoado não
## pode Correr nem dar Carrinho (as outras ações gerais continuam livres)
func blocks_general_action(p: Player, action: int) -> bool:
	if not _stunned.has(p):
		return false
	return action == MatchManager.GeneralAction.RUN or action == MatchManager.GeneralAction.SLIDE


# ---------- HABILIDADE 3: UNLEASH INSTINCT ----------

## "Com a bola": bola no chão e ao alcance, Bachira no chão (o carrinho só acerta quem está no chão)
func _can_arm_instinct() -> bool:
	return _step_overs_ready()   # mesma condição: os dois no chão, bola ao alcance


func _instinct_skill_name() -> String:
	return "Unleash Instinct (armado)" if _instinct_armed else "Unleash Instinct"


func _use_instinct() -> bool:
	if not _can_arm_instinct():
		return false
	await play_action(&"unleash_instinct")
	_instinct_armed = true
	start_cooldown(CD_INSTINCT, instinct_cooldown)
	queue_redraw()
	return true


## Counter: chamado pelo ATACANTE (dentro de _check_slide_hits do player.gd) quando o
## Carrinho dele ia acertar o Bachira.
func try_counter_slide(attacker: Player) -> bool:
	if not _instinct_armed or is_down:
		return false
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false
	# Se a situação mudou (ele pulou, a bola subiu, rolou para longe...) o counter não existe
	# mais, mas continua armado até ele realmente disparar uma vez com a bola nos pés.
	if height_level != Heights.Level.GROUND or ball.is_held() \
			or ball.get_level() != Heights.Level.GROUND \
			or global_position.distance_to(ball.global_position) > kick_range:
		return false

	_instinct_armed = false
	_run_instinct_dodge(attacker, m)
	return true


## Dispara fora da vez do Bachira: ele desvia (pulinho visual por cima do carrinho, sem mudar
## o nível de altura) e ganha uma ação geral extra que NÃO vale para o Correr, guardada para a
## próxima vez que ele agir (não dá para abrir um menu no meio do turno do adversário).
func _run_instinct_dodge(attacker: Player, m: MatchManager) -> void:
	hop_over()
	extra_general_no_run_left += instinct_extra_generals
	if instinct_sticks_ball:
		_stick_ball(attacker, m)
	queue_redraw()


## A bola gruda no Bachira durante o counter e FICA grudada até o fim da rodada (ou até
## alguém do time dele tocar nela de novo). Mesma mecânica do Gremlin Taunt do Charles:
## - hovering = true desliga a física da bola, então ninguém empurra ela correndo;
## - spell_owner = self é a trava que o projeto já tem (a do Arresto Momentum do Ness):
##   is_locked_for() faz o chute dos adversários devolver NONE e o carrinho também respeita;
## - o _process() mantém a bola nos pés dele (se ele andar, ela vai junto).
func _stick_ball(attacker: Player, m: MatchManager) -> void:
	var ball: Ball = _get_ball()
	if ball == null:
		return
	m.clear_pending_pass()   # a bola não pode ficar presa a um passe alto em andamento
	ball.release_hover()     # limpa qualquer trava/pairo anterior
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.pending_shot_chance = Ball.NO_SHOT
	ball.hovering = true
	ball.spell_owner = self
	_place_stuck_ball(ball)
	ball.register_touch(self)
	attacker._slide_hit_ball = true   # o resto do carrinho dele não tenta chutar a bola
	_stuck_until_round = m.round_number + instinct_stick_extra_rounds


func _place_stuck_ball(ball: Ball) -> void:
	var offset: Vector2 = Vector2(facing, 0.0) * (body_radius + ball.collision_radius + 2.0)
	ball.global_position = global_position + offset


## Mantém a bola grudada enquanto o efeito durar. Se alguém do time dele chutou/passou (o
## kick() da bola chama release_hover(), que limpa o spell_owner), o efeito acaba.
func _update_stuck_ball() -> void:
	if _stuck_until_round < 0:
		return
	var ball: Ball = _get_ball()
	if ball == null or ball.spell_owner != self or not ball.hovering:
		_stuck_until_round = -1   # a bola já foi solta por outro meio
		return
	_place_stuck_ball(ball)


func _release_stuck_ball() -> void:
	_stuck_until_round = -1
	var ball: Ball = _get_ball()
	if ball != null and ball.spell_owner == self:
		ball.release_hover()   # volta a gravidade e a trava some


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_SHOT, "name": skill_label(_shot_skill_name(), CD_SHOT)})
	list.append({"id": SKILL_STEP, "name": skill_label("Step Overs", CD_STEP)})
	list.append({"id": SKILL_INSTINCT, "name": skill_label(_instinct_skill_name(), CD_INSTINCT)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_SHOT:
			return not is_on_cooldown(CD_SHOT) and get_shot_variant() != ShotVariant.NONE
		SKILL_STEP:
			# precisa de alguém para enganar: sem inimigo perto a habilidade seria desperdiçada
			return not is_on_cooldown(CD_STEP) and _step_overs_ready() and not _step_targets().is_empty()
		SKILL_INSTINCT:
			# sem rearmar enquanto já está armado
			return not is_on_cooldown(CD_INSTINCT) and not _instinct_armed and _can_arm_instinct()
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_SHOT:
			return await _use_shot_skill()
		SKILL_STEP:
			return await _use_step_overs()
		SKILL_INSTINCT:
			return await _use_instinct()
	return false


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_instinct_armed = false
	_stunned.clear()
	_release_stuck_ball()
	queue_redraw()


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	_update_stuck_ball()
	# Anel armado e "estrelinhas" nos atordoados giram: precisa redesenhar toda hora
	if _instinct_armed or not _stunned.is_empty():
		queue_redraw()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Anel amarelo-esverdeado enquanto o Unleash Instinct está armado, esperando o carrinho
	if _instinct_armed:
		var pulse: float = 1.0 + 0.1 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		draw_arc(center, (placeholder_radius + 11.0) * pulse, 0.0, TAU, 32,
			Color(0.8, 1.0, 0.2, 0.9), 2.0)

	# Estrelinhas girando sobre a cabeça de cada inimigo atordoado pelo Step Overs
	var t: float = Time.get_ticks_msec() / 1000.0
	for e in _stunned.keys():
		if not is_instance_valid(e):
			continue
		var head: Vector2 = to_local(e.global_position) + Vector2(0.0, -e.height - e.placeholder_radius - 14.0)
		for i in 3:
			var ang: float = t * 5.0 + TAU * float(i) / 3.0
			var pos: Vector2 = head + Vector2(cos(ang) * 12.0, sin(ang) * 4.0)
			draw_circle(pos, 3.0, Color(1.0, 0.9, 0.25, 0.95))
