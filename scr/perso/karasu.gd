class_name Karasu
extends Player
## Karasu. Mais um personagem do time, com 3 habilidades:
##
## 1. Corvine Feint (ação de habilidade; recarga de 3 rodadas):
##      Karasu, com a bola, entra em pose de Counter (asas roxas de corvo translúcidas) e
##      fica ARMADO. Se um inimigo acertar um Carrinho nele — com ele e a bola no chão, a
##      bola ao alcance — o counter dispara sozinho (fora do turno dele, igual ao Gremlin
##      Taunt do Charles): ele salta por cima do carrinho, a bola fica GRUDADA nele até o
##      fim da rodada (ver _stick_ball), e ele ganha:
##        - +1 ação de habilidade (extra_skill_left, guardada para quando ele agir);
##        - +0.6s no Correr, pelas próximas 3 rodadas;
##        - +6% na chance de gol dos chutes dele e dos aliados próximos (mesmas 3 rodadas).
##      Pode ser armado no chão ou suspenso; se estiver suspenso, ele cai para o chão ao usar.
##
## 2. Aerial Pass (ação de habilidade, com 3 variantes automáticas pela situação; recarga de
##      2 rodadas, compartilhada):
##      - Bola no chão e ao alcance -> Aerial Pass: passe que sobe ao nível Voando e desce
##          NO CHÃO, nos pés do aliado escolhido.
##      - Karasu e bola no mesmo nível, os dois Suspensos ou os dois Voando -> Dive Bomb
##          Assault: chute curvo (QTE: fácil se suspensos, difícil se voando).
##      - Bola longe (fora do alcance de chute) e Karasu no chão -> Raven Assault: um Carrinho
##          (derruba inimigos como o Carrinho comum). Se encostar na bola, o carrinho acaba
##          ali e ele faz um passe rasteiro para o aliado escolhido ANTES do carrinho.
##
## 3. Wings Block / Silent Steal (ação de habilidade; recarga de 3 rodadas, compartilhada):
##      - Karasu no chão -> Wings Block: agarra os (até) 2 inimigos mais próximos e os impede de
##          usar habilidades por 2 rodadas, ou até Karasu se afastar deles (wings_range).
##      - Karasu suspenso + bola Suspensa ou Voando por perto -> Silent Steal: ele alcança a
##          bola, domina e os dois descem até o chão.
##
## Como montar a cena: igual aos outros — Nova Cena Herdada de player.tscn -> anexe este
## script ao nó raiz -> renomeie o nó raiz para "Karasu".
##
## Animações opcionais (se faltar alguma, o jogo só pula): corvine_feint, aerial_pass,
## dive_bomb_assault, wings_block, silent_steal. O Raven Assault usa a "slide" e o passe, as
## mesmas do Carrinho e do Passe comuns.
##
## Depende do player.gd que já foi devolvido antes: o carrinho inimigo respeita a trava da
## bola (is_locked_for) em _check_slide_hits(), que é o que mantém a bola grudada no counter.

const SKILL_FEINT: StringName = &"corvine_feint"
const SKILL_ASSAULT: StringName = &"aerial_pass"
const SKILL_WINGS: StringName = &"wings_block"

## Grupos de recarga (as variantes de cada habilidade compartilham o mesmo)
const CD_FEINT: StringName = &"cd_feint"
const CD_ASSAULT: StringName = &"cd_assault"
const CD_WINGS: StringName = &"cd_wings"

## Variante da habilidade 2, pela situação (alturas e distância da bola)
enum AssaultVariant { NONE, AERIAL, DIVE_BOMB, RAVEN }
## Variante da habilidade 3, pela altura do Karasu
enum WingsVariant { NONE, BLOCK, STEAL }

@export_group("Corvine Feint")
@export var feint_cooldown: int = 3
@export var feint_rounds: int = 3                      # rodadas depois da atual, contadas a partir de quando o counter dispara
@export var feint_run_bonus: float = 0.6               # segundos a mais no Correr do Karasu
@export_range(0.0, 1.0) var feint_shot_bonus: float = 0.06   # +6% na chance de gol (dele e dos aliados próximos)
@export var feint_ally_range: float = 400.0            # "aliados próximos": distância até o Karasu
@export var feint_extra_skills: int = 1                # ações de habilidade extras só dele
@export var feint_stick_extra_rounds: int = 0          # rodadas que a bola continua grudada DEPOIS da rodada do counter

@export_group("Aerial Pass / Dive Bomb Assault / Raven Assault")
@export var assault_cooldown: int = 2                  # igual para as 3 variantes
@export var aerial_rise_time: float = 0.45             # tempo até a bola chegar ao nível Voando
@export var aerial_fall_time: float = 0.45             # tempo da descida até o aliado
@export_range(0.0, 1.0) var dive_bomb_chance: float = 0.50
@export_range(0.0, 90.0) var dive_bomb_curve_deg: float = 40.0   # o quanto a trajetória faz a curva (graus)
@export var dive_bomb_curve_time: float = 0.7          # em quanto tempo a bola faz a curva
@export var dive_bomb_bend: float = 1.0                # lado da curva (+1 / -1)

@export_group("Wings Block / Silent Steal")
@export var wings_cooldown: int = 3
@export var wings_rounds: int = 2                      # duração do bloqueio (contando a rodada atual)
@export var wings_range: float = 130.0                 # alcance para agarrar; se o inimigo ficar mais longe que isso, solta
@export var wings_max_targets: int = 2
@export var steal_range: float = 180.0                 # Silent Steal: o quanto longe ele alcança a bola
@export var steal_reach_time: float = 0.2
@export var steal_descend_time: float = 0.4

@export_group("Visual do chute")
## Aura + partículas dos chutes/passes de habilidade. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: corvine_feint, aerial_pass, wings_block.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}

## Corvine Feint está armado, esperando um Carrinho inimigo disparar o counter
var _feint_armed: bool = false
## Bônus do Corvine Feint vale até o fim desta rodada (-1 = inativo)
var _feint_until_round: int = -1
## A bola está grudada no Karasu até o fim desta rodada (-1 = não está)
var _stuck_until_round: int = -1
var _base_run_duration: float = 0.0

## Raven Assault em andamento: o carrinho procura a bola e, se encostar, vira um passe
var _raven_active: bool = false
var _raven_contact: bool = false

## Inimigos agarrados pelo Wings Block
var _grabbed: Array[Player] = []


func _init() -> void:
	character_id = "karasu"   # o menu de formação usa isto para saber quem é quem
	display_name = "Karasu"


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_base_run_duration = run_duration
	_hook_manager.call_deferred()


## Roxo escuro de corvo; as partículas são "penas" que sobem girando
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.5, 0.2, 0.85)
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(0.497, 0.472, 1.0, 1.0)
	fx.amount = 20
	fx.lifetime = 0.5
	fx.speed_min = 15.0
	fx.speed_max = 65.0
	fx.gravity = Vector2(0.0, -40.0)
	fx.spin = 280.0
	fx.scale_min = 0.15
	fx.scale_max = 0.3
	fx.burst_amount = 14
	fx.burst_speed = 200.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)


func _on_round_started(new_round: int) -> void:
	# A rodada do counter acabou: a bola desgruda e volta ao jogo normal
	if _stuck_until_round >= 0 and new_round > _stuck_until_round:
		_release_stuck_ball()
	queue_redraw()   # a aura do bônus e as asas somem quando acabam


# ---------- DERRUBADO: desarma o counter ----------

func knock_down() -> void:
	super()
	_feint_armed = false
	queue_redraw()


# ---------- HABILIDADE 1: CORVINE FEINT ----------

func is_feint_buff_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _feint_until_round >= 0 and m.round_number <= _feint_until_round


## "Com a bola": ela tem que estar ao alcance dele (get_kick_type já confere derrubado, bola
## na mão do goleiro, trava de feitiço, distância e altura alcançável). Pode estar no chão
## ou suspenso, mas não voando.
func _can_arm_feint() -> bool:
	if is_down or height_level == Heights.Level.FLYING:
		return false
	return get_kick_type(_get_ball()) != KickType.NONE


func _feint_skill_name() -> String:
	return "Corvine Feint (armada)" if _feint_armed else "Corvine Feint"


func _use_feint() -> bool:
	if not _can_arm_feint():
		return false
	if height_level != Heights.Level.GROUND:
		land()   # suspenso: cai para o chão ao usar
	await play_action(&"corvine_feint")
	_feint_armed = true
	start_cooldown(CD_FEINT, feint_cooldown)
	queue_redraw()
	return true


## Counter: chamado pelo ATACANTE (dentro de _check_slide_hits do player.gd) quando o
## Carrinho dele ia acertar o Karasu.
func try_counter_slide(attacker: Player) -> bool:
	if not _feint_armed or is_down:
		return false
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false
	# Se a situação mudou (ele pulou, a bola subiu ou ficou longe...) o counter não existe
	# mais, mas continua armado até ele realmente disparar uma vez com a bola nos pés.
	if height_level != Heights.Level.GROUND or ball.is_held() \
			or ball.get_level() != Heights.Level.GROUND \
			or global_position.distance_to(ball.global_position) > kick_range:
		return false

	_feint_armed = false
	_run_feint_counter(attacker, m)
	return true


## Dispara fora da vez do Karasu: ele salta por cima do carrinho (hop_over(), só visual), a
## bola gruda nele, e ele ganha a ação de habilidade extra e os bônus de 3 rodadas.
func _run_feint_counter(attacker: Player, m: MatchManager) -> void:
	hop_over()
	extra_skill_left += feint_extra_skills
	_feint_until_round = m.round_number + feint_rounds
	_stick_ball(attacker, m)
	queue_redraw()


## A bola gruda no Karasu durante o counter e FICA grudada até o fim da rodada (ou até
## alguém do time dele tocar nela de novo). Mesma ideia do Gremlin Taunt do Charles:
## - hovering = true desliga a física da bola, então ninguém empurra ela correndo;
## - spell_owner = self é a trava que o projeto já tem (a do Arresto Momentum do Ness):
##   is_locked_for() faz o chute dos adversários devolver NONE e o carrinho também respeita;
## - o _process() mantém a bola nos pés dele (se ele andar, ela vai junto).
## Marca também o Carrinho do atacante como já tendo "gasto" o toque na bola.
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
	attacker._slide_hit_ball = true
	_stuck_until_round = m.round_number + feint_stick_extra_rounds


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


## +0.6s no Correr enquanto o bônus do Corvine Feint durar (checado na hora em que a corrida começa)
func start_run() -> void:
	run_duration = _base_run_duration + (feint_run_bonus if is_feint_buff_active() else 0.0)
	super()


# ---------- BÔNUS DE CHUTE (Corvine Feint) ----------

func _shot_bonus() -> float:
	return feint_shot_bonus if is_feint_buff_active() else 0.0


## Vale também para o Chutar geral: base do tipo de chute + bônus
func get_shot_chance(kind: KickType) -> float:
	return minf(super(kind) + _shot_bonus(), 1.0)


## Bônus que o Karasu dá ao chute de um COMPANHEIRO próximo (chamado pelo
## get_team_shot_bonus() do player.gd quando o aliado chuta)
func shot_bonus_for_ally(shooter: Player, _ball: Ball) -> float:
	if not is_feint_buff_active():
		return 0.0
	if global_position.distance_to(shooter.global_position) > feint_ally_range:
		return 0.0
	return feint_shot_bonus


# ---------- HABILIDADE 2: AERIAL PASS / DIVE BOMB ASSAULT / RAVEN ASSAULT ----------

func get_assault_variant() -> AssaultVariant:
	var ball: Ball = _get_ball()
	if ball == null or is_down or ball.is_held() or ball.is_locked_for(team):
		return AssaultVariant.NONE

	var near: bool = global_position.distance_to(ball.global_position) <= kick_range
	if not near:
		# Sem a bola próxima: Raven Assault (carrinho), só no chão
		return AssaultVariant.RAVEN if height_level == Heights.Level.GROUND else AssaultVariant.NONE

	var ball_level: Heights.Level = ball.get_level()
	# Os dois no mesmo nível, suspensos ou voando
	if height_level != Heights.Level.GROUND and height_level == ball_level:
		return AssaultVariant.DIVE_BOMB
	# Bola no chão
	if ball_level == Heights.Level.GROUND and can_reach_level(ball_level):
		return AssaultVariant.AERIAL
	return AssaultVariant.NONE


func _assault_skill_name() -> String:
	match get_assault_variant():
		AssaultVariant.DIVE_BOMB:
			return "Dive Bomb Assault"
		AssaultVariant.RAVEN:
			return "Raven Assault"
	return "Aerial Pass"


## A variante atual pode ser usada? (as que passam a bola precisam de um aliado ao alcance)
func _assault_usable() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_assault_variant():
		AssaultVariant.AERIAL:
			return _has_ally_in_range(_aerial_range(m))
		AssaultVariant.DIVE_BOMB:
			return true
		AssaultVariant.RAVEN:
			return _has_ally_in_range(_raven_range(m))
	return false


func _aerial_range(m: MatchManager) -> float:
	return m.pass_range_for(MatchManager.PassVariant.HIGH, self)


func _raven_range(m: MatchManager) -> float:
	return m.pass_range_for(MatchManager.PassVariant.GROUND, self)


func _has_ally_in_range(range_px: float) -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	for other: Player in m.get_team_players(team):
		if other != self and global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


func _use_assault_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_assault_variant():
		AssaultVariant.AERIAL:
			return await _use_aerial_pass(m)
		AssaultVariant.DIVE_BOMB:
			return await _use_dive_bomb(m)
		AssaultVariant.RAVEN:
			return await _use_raven_assault(m)
	return false


## Aerial Pass: a bola sobe até o nível Voando no meio do caminho e desce NO CHÃO, encostando
## no aliado escolhido (a bola paira durante o voo, como no Passe Alto comum, mas aqui o passe
## já se resolve inteiro dentro da ação).
func _use_aerial_pass(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var target: Player = await m.pick_ally_for_skill(self, _aerial_range(m))
	if target == null:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele escolhia o alvo
	if get_assault_variant() != AssaultVariant.AERIAL:
		return false

	face_towards(target.global_position - global_position)
	if not await play_action(&"aerial_pass", ANIM_PASS_HIGH):
		return false   # ação cancelada (ex: a partida reiniciou)

	ball.register_touch(self)   # o passe alto não usa kick(), então registra o toque aqui
	if kick_fx:
		ball.fx_during_hover = true   # mantém a aura enquanto a bola paira
		ball.play_fx(kick_fx)

	var start: Vector2 = ball.global_position
	var to_target: Vector2 = target.global_position - start
	var dist: float = to_target.length()
	var gap: float = ball.collision_radius + target.body_radius + 2.0   # a bola para ENCOSTANDO no alvo
	var end_point: Vector2 = start
	if dist > 0.001:
		end_point = start + to_target / dist * maxf(dist - gap, 0.0)

	var rise: Tween = ball.hover_to((start + end_point) * 0.5, Heights.FLYING_HEIGHT, aerial_rise_time)
	await rise.finished
	var fall: Tween = ball.hover_to(end_point, Heights.GROUND_HEIGHT, aerial_fall_time)
	await fall.finished

	# Chegou no chão, nos pés do aliado: solta a bola de volta à física normal
	ball.release_hover()
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.fx_during_hover = false
	ball.register_touch(self)   # também encerra a aura
	m.pass_completed.emit(self, target)
	start_cooldown(CD_ASSAULT, assault_cooldown)
	return true


## Dive Bomb Assault: chute curvo, só com Karasu e bola no MESMO nível (suspensos ou voando).
## A curva é a bola girando a direção dela aos poucos logo depois do chute; a mira sai
## "para fora" da reta, de modo que a trajetória faça um arco em volta do ponto mirado.
func _use_dive_bomb(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter mudado de altura ou de alcance enquanto ele mirava
	if get_assault_variant() != AssaultVariant.DIVE_BOMB:
		return false
	var kind: KickType = get_kick_type(ball)
	if kind == KickType.NONE:
		return false

	var qte_ok: bool = true
	if not skips_qte():
		qte_ok = await m.run_qte(kind)   # fácil (suspensos) ou difícil (voando)

	var dir: Vector2 = aim
	if qte_ok:
		# O arco gira de -metade a +metade da curva em volta da mira
		dir = aim.rotated(-deg_to_rad(dive_bomb_curve_deg) * 0.5 * dive_bomb_bend)
		# Roda em paralelo: a curva começa quando a bola realmente sai (frame de impacto)
		_curve_ball_after_kick(ball, ball.interaction_count)

	var chance: float = minf(dive_bomb_chance + _shot_bonus(), 1.0)
	# Errou o QTE = chute fraquinho, sem aura e sem curva
	await kick_ball(ball, dir, kind, qte_ok, chance, false,
		kick_fx if qte_ok else null, &"dive_bomb_assault")
	start_cooldown(CD_ASSAULT, assault_cooldown)
	return true


## Espera o chute sair (a bola ganha um toque novo) e então gira a velocidade dela a uma taxa
## constante por dive_bomb_curve_time. A curva acaba se alguém tocar na bola, o goleiro a
## pegar, ela parar ou ficar pairando.
func _curve_ball_after_kick(ball: Ball, touches_before: int) -> void:
	var waited: float = 0.0
	while ball.interaction_count == touches_before and waited < ACTION_TIMEOUT + 1.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if ball.interaction_count == touches_before:
		return   # o chute nunca saiu (ação cancelada)

	var touches_kicked: int = ball.interaction_count
	var rate: float = deg_to_rad(dive_bomb_curve_deg) / maxf(dive_bomb_curve_time, 0.05) * dive_bomb_bend
	var elapsed: float = 0.0
	while elapsed < dive_bomb_curve_time:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		if ball.interaction_count != touches_kicked or ball.is_held() or ball.hovering \
				or ball.velocity.length() < 20.0:
			return
		ball.velocity = ball.velocity.rotated(rate * delta)


## Raven Assault: um Carrinho (a mesma mecânica do Carrinho geral, inclusive derrubar inimigos
## no caminho). Primeiro ele mira o carrinho e escolhe o aliado que vai receber; se o carrinho
## encostar na bola, ele acaba ali e Karasu faz um passe rasteiro para esse aliado. Não gasta
## o Carrinho geral do turno (slides_this_turn): é uma ação de habilidade.
func _use_raven_assault(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var dir: Vector2 = await m.aim_for_skill(self, slide_distance)
	if dir == Vector2.ZERO:
		return false   # cancelou: não gasta a ação
	var target: Player = await m.pick_ally_for_skill(self, _raven_range(m))
	if target == null:
		return false

	# A bola pode ter chegado perto (ou ficado presa) enquanto ele escolhia
	if get_assault_variant() != AssaultVariant.RAVEN:
		return false

	face_towards(dir)
	_raven_active = true
	_raven_contact = false
	start_slide(dir)
	slides_this_turn = maxi(0, slides_this_turn - 1)   # o start_slide contou um Carrinho geral
	_slide_hit_ball = true   # o carrinho comum não chuta a bola: quem trata o contato é este script
	await slide_finished
	_raven_active = false

	if _raven_contact and is_instance_valid(target):
		ball.velocity = Vector2.ZERO
		await m.run_ground_pass(self, target, ball)
	_raven_contact = false

	start_cooldown(CD_ASSAULT, assault_cooldown)
	return true


## Durante o Raven Assault, além do que o carrinho comum já faz com os jogadores, procura a
## bola: encostou -> o carrinho termina na hora (o passe sai logo depois, em _use_raven_assault)
func _check_slide_hits() -> void:
	super()
	if not _raven_active or _raven_contact:
		return
	var ball: Ball = _get_ball()
	if ball == null or ball.is_held() or ball.is_locked_for(team) \
			or ball.get_level() != Heights.Level.GROUND:
		return
	if global_position.distance_to(ball.global_position) <= slide_hit_radius:
		_raven_contact = true
		ball.velocity = Vector2.ZERO
		slide_time_left = 0.0   # o carrinho acaba aqui


# ---------- HABILIDADE 3: WINGS BLOCK / SILENT STEAL ----------

func get_wings_variant() -> WingsVariant:
	if is_down:
		return WingsVariant.NONE
	if height_level == Heights.Level.GROUND:
		return WingsVariant.BLOCK if not _wings_targets().is_empty() else WingsVariant.NONE
	if height_level == Heights.Level.SUSPENDED:
		var ball: Ball = _get_ball()
		if ball == null or ball.is_held() or ball.is_locked_for(team):
			return WingsVariant.NONE
		if ball.get_level() == Heights.Level.GROUND:
			return WingsVariant.NONE   # só alcança bola suspensa ou voando
		if global_position.distance_to(ball.global_position) <= steal_range:
			return WingsVariant.STEAL
	return WingsVariant.NONE


func _wings_skill_name() -> String:
	if height_level == Heights.Level.SUSPENDED:
		return "Silent Steal"
	return "Wings Block"


func _use_wings_skill() -> bool:
	match get_wings_variant():
		WingsVariant.BLOCK:
			return await _use_wings_block()
		WingsVariant.STEAL:
			return await _use_silent_steal()
	return false


## Os (até) wings_max_targets inimigos mais próximos que dá para agarrar agora: dentro do
## wings_range, ainda de pé e em altura que ele alcança
func _wings_targets() -> Array[Player]:
	var found: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team or p.is_down or not can_reach_level(p.height_level):
			continue
		if global_position.distance_to(p.global_position) > wings_range:
			continue
		found.append(p)
	found.sort_custom(func(a: Player, b: Player) -> bool:
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	if found.size() > wings_max_targets:
		found.resize(wings_max_targets)
	return found


## Wings Block: trava só a HABILIDADE dos inimigos agarrados (as ações gerais seguem livres),
## por wings_rounds rodadas contando a atual. O _update_grabs() solta quem ficar longe demais.
func _use_wings_block() -> bool:
	await play_action(&"wings_block")
	var targets: Array[Player] = _wings_targets()   # confere de novo depois da animação
	if targets.is_empty():
		return false
	_release_grabs()
	for e: Player in targets:
		e.apply_lock(self, wings_rounds, true)
		_grabbed.append(e)
	start_cooldown(CD_WINGS, wings_cooldown)
	queue_redraw()
	return true


## Solta quem acabou o tempo (a trava expira sozinha) ou ficou mais longe que wings_range
func _update_grabs() -> void:
	if _grabbed.is_empty():
		return
	for i in range(_grabbed.size() - 1, -1, -1):
		var e: Player = _grabbed[i]
		if not is_instance_valid(e) or e.locked_by != self or not e.is_skill_locked():
			_grabbed.remove_at(i)   # acabou o tempo, ou outro efeito assumiu a trava
		elif global_position.distance_to(e.global_position) > wings_range:
			e.clear_lock()
			_grabbed.remove_at(i)


func _release_grabs() -> void:
	for e: Player in _grabbed:
		if is_instance_valid(e) and e.locked_by == self:
			e.clear_lock()
	_grabbed.clear()


## Silent Steal: Karasu (suspenso) alcança a bola suspensa/voando, domina, e os dois descem
## juntos até o chão. A bola fica nos pés dele, sem trava: o adversário ainda pode disputar.
func _use_silent_steal() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false

	m.clear_pending_pass()   # se era um passe alto pairando, ele deixa de ser acompanhado
	face_towards(ball.global_position - global_position)
	if not await play_action(&"silent_steal"):
		return false   # ação cancelada (ex: a partida reiniciou)

	# Alcança: congela a bola no lugar (pairando) e vai até ela, subindo se ela estiver mais alta
	var gap: float = body_radius + ball.collision_radius + 2.0
	var reach_pos: Vector2 = global_position
	var to_ball: Vector2 = ball.global_position - global_position
	if to_ball.length() > gap:
		reach_pos = ball.global_position - to_ball.normalized() * gap
	ball.hover_to(ball.global_position, ball.height, steal_reach_time)
	var reach: Tween = create_tween().set_parallel(true)
	reach.tween_property(self, "global_position", reach_pos, steal_reach_time)
	reach.tween_property(self, "height", maxf(height, ball.height), steal_reach_time)
	await reach.finished

	# Domina e desce: os dois chegam ao chão juntos
	height_level = Heights.Level.GROUND
	var down: Tween = create_tween()
	down.tween_property(self, "height", Heights.GROUND_HEIGHT, steal_descend_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var ball_down: Tween = ball.hover_to(ball.global_position, Heights.GROUND_HEIGHT, steal_descend_time)
	await ball_down.finished
	if down.is_running():
		await down.finished

	ball.release_hover()
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.register_touch(self)
	start_cooldown(CD_WINGS, wings_cooldown)
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_FEINT, "name": skill_label(_feint_skill_name(), CD_FEINT)})
	list.append({"id": SKILL_ASSAULT, "name": skill_label(_assault_skill_name(), CD_ASSAULT)})
	list.append({"id": SKILL_WINGS, "name": skill_label(_wings_skill_name(), CD_WINGS)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_FEINT:
			# sem rearmar enquanto já está armado
			return not is_on_cooldown(CD_FEINT) and not _feint_armed and _can_arm_feint()
		SKILL_ASSAULT:
			return not is_on_cooldown(CD_ASSAULT) and _assault_usable()
		SKILL_WINGS:
			return not is_on_cooldown(CD_WINGS) and get_wings_variant() != WingsVariant.NONE
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_FEINT:
			return await _use_feint()
		SKILL_ASSAULT:
			return await _use_assault_skill()
		SKILL_WINGS:
			return await _use_wings_skill()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_FEINT:
			title = "Corvine Feint"
			text = ("Com a bola ao alcance (no chão ou suspenso, nunca voando), Karasu entra em pose de counter. Se um inimigo acertar um Carrinho nele, ele salta por cima, a bola fica grudada nele até o fim da rodada, e ele ganha:\n"
				+ "• +%d ação de habilidade extra;\n"
				+ "• +%.1f s no Correr e +%d%% de chance de gol (dele e dos aliados a até %d px) por %d rodadas depois da atual.\n"
				+ "Se ele for derrubado antes, o counter se desfaz. Recarga: %d rodadas.") % [
				feint_extra_skills, feint_run_bonus, _pct(feint_shot_bonus), int(feint_ally_range),
				feint_rounds, feint_cooldown]
		SKILL_ASSAULT:
			var aerial_text: String = "Aerial Pass (bola no chão e ao alcance): passe que sobe ao nível Voando e desce no chão, nos pés do aliado escolhido (precisa de um aliado ao alcance do passe alto)."
			var dive_text: String = "Dive Bomb Assault (Karasu e bola no mesmo nível, suspensos ou voando): chute curvo com %d%% de chance de gol. QTE fácil se suspensos, difícil se voando." % _pct(dive_bomb_chance)
			var raven_text: String = "Raven Assault (bola longe e Karasu no chão): um Carrinho que derruba inimigos. Você escolhe antes o aliado; se o carrinho encostar na bola, ele acaba ali e Karasu passa rasteiro para esse aliado."
			match get_assault_variant():
				AssaultVariant.AERIAL:
					title = "Aerial Pass"
					text = aerial_text
				AssaultVariant.DIVE_BOMB:
					title = "Dive Bomb Assault"
					text = dive_text
				AssaultVariant.RAVEN:
					title = "Raven Assault"
					text = raven_text
				_:
					title = "Aerial Pass / Dive Bomb / Raven Assault"
					text = aerial_text + "\n" + dive_text + "\n" + raven_text
			text += "\nRecarga: %d rodadas, compartilhada entre as três." % assault_cooldown
		SKILL_WINGS:
			var block_text: String = "Wings Block (Karasu no chão): agarra os %d inimigos mais próximos (a até %d px) e os impede de usar habilidades por %d rodadas, ou até Karasu se afastar deles. As ações gerais ficam livres." % [
				wings_max_targets, int(wings_range), wings_rounds]
			var steal_text: String = "Silent Steal (Karasu suspenso e bola suspensa ou voando a até %d px): ele alcança a bola, a domina e os dois descem até o chão." % int(steal_range)
			match get_wings_variant():
				WingsVariant.BLOCK:
					title = "Wings Block"
					text = block_text
				WingsVariant.STEAL:
					title = "Silent Steal"
					text = steal_text
				_:
					title = "Wings Block / Silent Steal"
					text = block_text + "\n" + steal_text
			text += "\nRecarga: %d rodadas, compartilhada entre as duas." % wings_cooldown
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_feint_armed = false
	_feint_until_round = -1
	_raven_active = false
	_raven_contact = false
	_release_stuck_ball()
	_release_grabs()
	run_duration = _base_run_duration
	queue_redraw()


# ---------- LOOP / VISUAL ----------

## Com as asas armadas ou alguém agarrado, o desenho precisa atualizar toda hora (asas batendo,
## a ligação com o inimigo acompanhando)
func _process(delta: float) -> void:
	super(delta)
	_update_stuck_ball()
	_update_grabs()
	if _feint_armed or not _grabbed.is_empty():
		queue_redraw()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Anel roxo fininho enquanto o bônus do Corvine Feint está valendo
	if is_feint_buff_active():
		draw_arc(center, placeholder_radius + 6.0, 0.0, TAU, 40, Color(0.7, 0.35, 1.0, 0.8), 2.0)

	# Asas roxas translúcidas = pose de counter (armado)
	if _feint_armed:
		_draw_wings(center)

	# Ligação roxa até cada inimigo agarrado pelo Wings Block
	for e: Player in _grabbed:
		if is_instance_valid(e):
			var end: Vector2 = to_local(e.global_position) + Vector2(0.0, -e.height)
			draw_line(center, end, Color(0.6, 0.25, 0.95, 0.75), 3.0)


## Duas asas de corvo (espelhadas) com "penas" na borda de baixo, batendo de leve
func _draw_wings(center: Vector2) -> void:
	var r: float = placeholder_radius
	var flap: float = 1.0 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	# Contorno da asa direita em unidades de "raio" (a esquerda é o espelho em x)
	var shape: Array[Vector2] = [
		Vector2(0.6, -0.4), Vector2(1.8, -1.9 * flap), Vector2(3.2 * flap, -2.3 * flap),
		Vector2(3.0 * flap, -1.2), Vector2(2.5, -1.35), Vector2(2.7 * flap, -0.5),
		Vector2(2.1, -0.7), Vector2(2.2 * flap, 0.2), Vector2(1.5, -0.1),
		Vector2(1.3, 0.6), Vector2(0.6, 0.1),
	]
	for i in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var pts := PackedVector2Array()
		for p: Vector2 in shape:
			pts.append(center + Vector2(p.x * side, p.y) * r)
		draw_colored_polygon(pts, Color(0.5, 0.2, 0.85, 0.35))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.8, 0.55, 1.0, 0.7), 1.5)
