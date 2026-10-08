class_name Kaiser
extends Player
## Michael Kaiser. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Magnus (ação de habilidade, 3 variantes automáticas pela altura; recarga de 2 rodadas,
##      compartilhada entre as variantes):
##      - Bola no chão + Kaiser no chão ou suspenso -> Magnus: chute curvo; a bola sobe
##        suavemente até o nível Suspenso durante a trajetória
##      - Kaiser suspenso + bola Voando             -> Beinschuss: bicicleta com QTE difícil
##      - Kaiser suspenso + bola Suspensa           -> Kaiser Impact: chute reto e rápido, a
##        bola vai Suspensa durante todo o trajeto
## 2. Empire (ação de habilidade): marca aliados no alcance como servos, pela partida inteira.
##      A 1ª escolha vira o Servo Garçom (flor dourada): chutes do Kaiser com passe/assistência
##      dele ganham +% de chance. A 2ª vira o Servo Palhaço (flor azul-escura): libera o
##      Auf die Knee. Cancelar a 2ª escolha marca só o Garçom. Cada GOL do Kaiser dá +1 uso.
##    Auf die Knee (botão próprio, recarga de 3 rodadas): se a bola está perto de um Palhaço
##      e o Kaiser está ao alcance do passe dele, o Palhaço passa rasteiro para o Kaiser.
##      Gasta a ação de habilidade do Kaiser E uma ação geral do Palhaço (a pool dele).
## 3. Blue Rose (2 botões, uma variante por vez; dura 3 rodadas contando a atual; recarga de
##      2 rodadas a partir do fim do efeito; a mesma variante no máximo 2 vezes seguidas):
##      - Predator: Chutar mais forte, Carrinho mais longo e +% em qualquer chute do Kaiser
##      - Meta: +1 ação de habilidade para os Secundários nas próximas 2 rodadas, nenhum QTE
##        para o Kaiser e mais segundos no Correr
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Kaiser".
##
## Animações opcionais (SpriteFrames; hit_frames diz o frame de impacto de cada uma):
## "magnus", "beinschuss", "kaiser_impact", "empire", "blue_rose". Sem elas, nada quebra.
##
## REQUISITO: o kick_ball() do player.gd precisa do parâmetro on_kick (veja a conversa).

const SKILL_SHOT: StringName = &"magnus"
const SKILL_EMPIRE: StringName = &"empire"
const SKILL_KNEE: StringName = &"auf_die_knee"
const SKILL_PREDATOR: StringName = &"predator"
const SKILL_META: StringName = &"meta"

## Grupos de recarga (as 3 variantes do chute compartilham o mesmo)
const CD_SHOT: StringName = &"cd_shot"
const CD_KNEE: StringName = &"cd_knee"
const CD_ROSE: StringName = &"cd_blue_rose"

enum ShotVariant { NONE, MAGNUS, BEINSCHUSS, IMPACT }
enum ServantType { WAITER, CLOWN }

@export_group("Magnus / Beinschuss / Kaiser Impact")
@export_range(0.0, 1.0) var chance_magnus: float = 0.40
@export_range(0.0, 1.0) var chance_beinschuss: float = 0.55
@export_range(0.0, 1.0) var chance_impact: float = 0.45
@export var shot_cooldown: int = 2                  # recarga (rodadas), igual para as 3 variantes
## Magnus: a bola sai desviada deste ângulo e vai curvando de volta, cruzando a linha da mira
@export var magnus_bend_deg: float = 28.0
## +1 / -1 escolhe para que lado a bola faz a curva
@export var magnus_bend_sign: float = 1.0
## Quanto tempo a bola é conduzida (curva + subida até o nível Suspenso); depois cai normal
@export var magnus_flight_time: float = 0.9
## Kaiser Impact: multiplicador de força (rápido) e por quanto tempo a bola fica Suspensa
@export var impact_force_mult: float = 1.6
@export var impact_flight_time: float = 1.2

@export_group("Empire")
@export var empire_range: float = 450.0             # alcance para marcar os servos
@export var empire_starting_uses: int = 1           # usos no começo da partida (+1 a cada gol dele)
@export_range(0.0, 1.0) var waiter_bonus: float = 0.07   # +7% no chute com passe/assistência do Garçom
@export var knee_cooldown: int = 3                  # recarga do Auf die Knee

@export_group("Blue Rose")
@export var rose_rounds: int = 3                    # duração total em rodadas (contando a atual)
@export var rose_cooldown: int = 2                  # recarga, contada a partir do fim do efeito
@export var rose_max_repeat: int = 2                # a mesma variante no máximo X vezes seguidas
@export_range(0.0, 1.0) var predator_shot_bonus: float = 0.08   # +8% em qualquer chute
@export var predator_force_mult: float = 1.3        # força do Chutar comum
@export_range(0.0, 1.0) var predator_slide_bonus: float = 0.2   # +20% na distância do Carrinho
@export var meta_ally_rounds: int = 2               # rodadas (depois da atual) com a ação extra
@export var meta_extra_ally_skills: int = 1         # ações de habilidade extras para os Secundários
@export var meta_run_bonus: float = 0.7             # segundos a mais no Correr

@export_group("Visual do chute")
## Aura + partículas dos chutes de habilidade. Vazio = usa o estilo padrão do Kaiser (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: magnus, empire, auf_die_knee, predator, meta.
@export var skill_icons: Dictionary = {}

## Servos marcados pelo Empire (valem até o fim da partida)
var _waiters: Array[Player] = []
var _clowns: Array[Player] = []
var _marks: Dictionary = {}          # Player -> FlowerMark
var _empire_uses_left: int = 1

## Blue Rose: variante ativa, até que rodada vale, e histórico para o limite de repetição
var _rose_variant: StringName = &""
var _rose_until_round: int = -1
var _rose_last: StringName = &""
var _rose_streak: int = 0

## Meta: rodadas em que os Secundários ganham a ação extra (e a última rodada já concedida)
var _meta_ally_from: int = -1
var _meta_ally_until: int = -1
var _meta_granted_round: int = -1

var _base_run_duration: float = 0.0
var _base_slide_distance: float = 0.0
## Mirando o Magnus: o desenho mostra também a curva que a bola vai fazer
var _aiming_magnus: bool = false


func _init() -> void:
	character_id = "kaiser"          # o menu de formação usa isto para saber quem é quem
	display_name = "Michael Kaiser"  # aparece no placar de gols e no menu


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_base_run_duration = run_duration
	_base_slide_distance = slide_distance
	_empire_uses_left = empire_starting_uses
	_hook_manager.call_deferred()   # o MatchManager entra na árvore no mesmo frame


## Azul-escuro com partículas douradas
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.08, 0.15, 0.7)
	fx.trail_width = 14.0
	fx.particle_color = Color(1.0, 0.82, 0.25)
	fx.amount = 22
	fx.lifetime = 0.55
	fx.speed_min = 15.0
	fx.speed_max = 70.0
	fx.gravity = Vector2(0.0, -40.0)
	fx.spin = 240.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 14
	fx.burst_speed = 220.0
	return fx


func _exit_tree() -> void:
	_clear_servants()


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m == null:
		return
	m.round_started.connect(_on_round_started)
	m.goal_scored.connect(_on_goal_scored)
	m.state_changed.connect(_on_state_changed)


func _on_round_started(_round_number: int) -> void:
	_apply_rose_stats()   # o Predator acabou? o Carrinho volta ao normal
	queue_redraw()        # a aura da Blue Rose some quando as rodadas acabam


## Cada gol DO KAISER dá mais um uso do Empire
func _on_goal_scored(goal: Dictionary) -> void:
	if goal.get("own_goal", false) or goal.get("team", -1) != team:
		return
	if goal.get("scorer", "") == get_display_name():
		_empire_uses_left += 1


## Meta: nas próximas rodadas, a pool dos Secundários ganha a ação extra. O MatchManager zera as
## pools em select_protagonist(), então a extra é somada logo depois, quando a fase vira
## CHOOSING_ACTION (uma vez por rodada).
func _on_state_changed() -> void:
	if _meta_ally_until < 0:
		return
	var m: MatchManager = _get_manager()
	if m == null or m.phase != MatchManager.Phase.CHOOSING_ACTION or m.current_team != team:
		return
	var r: int = m.round_number
	if r < _meta_ally_from or r > _meta_ally_until or _meta_granted_round == r:
		return
	_meta_granted_round = r
	m.secondary_skill_left += meta_extra_ally_skills


# ---------- SERVOS (EMPIRE) ----------

func _is_servant(p: Player) -> bool:
	return p in _waiters or p in _clowns


## Quem pode ser marcado: companheiro (não ele mesmo) que ainda não é servo
func _is_markable(p: Player) -> bool:
	return is_instance_valid(p) and p != self and p.team == team and not _is_servant(p)


func _is_markable_except(p: Player, skip: Player) -> bool:
	return p != skip and _is_markable(p)


## Companheiros que dá para marcar agora (ao alcance do Empire)
func _empire_candidates(skip: Player = null) -> Array[Player]:
	var result: Array[Player] = []
	var m: MatchManager = _get_manager()
	if m == null:
		return result
	for p: Player in m.get_team_players(team):
		if p != skip and _is_markable(p) \
				and global_position.distance_to(p.global_position) <= empire_range:
			result.append(p)
	return result


func _add_servant(p: Player, type: ServantType) -> void:
	var mark := FlowerMark.new()
	if type == ServantType.WAITER:
		_waiters.append(p)
		mark.petal_color = Color(1.0, 0.82, 0.22)    # flor dourada
		mark.core_color = Color(0.08, 0.15, 0.6)
	else:
		_clowns.append(p)
		mark.petal_color = Color(0.08, 0.15, 0.6)    # flor azul-escura
		mark.core_color = Color(1.0, 0.82, 0.22)
	p.add_child(mark)
	_marks[p] = mark


func _clear_servants() -> void:
	for mark in _marks.values():
		if is_instance_valid(mark):
			mark.queue_free()
	_marks.clear()
	_waiters.clear()
	_clowns.clear()


## Habilidade Empire: escolhe o Servo Garçom e depois o Servo Palhaço
func _use_empire() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false

	m.announce_keeper("Empire: escolha o Servo Garçom (flor dourada)", team)
	var first: Player = await m.pick_ally_for_skill(self, empire_range, false, _is_markable)
	if first == null or m.match_over:
		return false   # cancelou: não gasta a ação nem o uso

	var second: Player = null
	if not _empire_candidates(first).is_empty():
		m.announce_keeper("Empire: escolha o Servo Palhaço (flor azul) ou cancele para marcar só um", team)
		second = await m.pick_ally_for_skill(self, empire_range, false, _is_markable_except.bind(first))
		if second == null:
			# O manager trata "cancelou a última escolha" como habilidade cancelada (devolve a ação).
			# Aqui cancelar a 2ª escolha é só "não quero um Palhaço": a habilidade FOI usada.
			m._skill_pick_cancelled = false
		if m.match_over:
			return false

	if not await play_action(&"empire"):
		return false   # ação cancelada (ex: a partida reiniciou)
	_empire_uses_left = maxi(0, _empire_uses_left - 1)
	_add_servant(first, ServantType.WAITER)
	if second != null:
		_add_servant(second, ServantType.CLOWN)
	return true


## Garçom: o último toque na bola foi dele (o Kaiser está para tocar) ou o toque anterior foi dele
## (o Kaiser já encostou). Em qualquer caso, é ele quem seria o autor da assistência.
func _waiter_bonus(ball: Ball) -> float:
	if ball == null or _waiters.is_empty():
		return 0.0
	var assister: Player = ball.last_toucher
	if assister == self:
		assister = ball.previous_toucher
	if assister != null and assister in _waiters:
		return waiter_bonus
	return 0.0


# ---------- AUF DIE KNEE ----------

## Palhaço que tem a bola ao alcance do pé, consegue passar rasteiro para o Kaiser e ainda tem
## uma ação geral sobrando (o Auf die Knee gasta uma ação geral DELE)
func _find_knee_clown() -> Player:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return null
	var best: Player = null
	var best_dist: float = INF
	for c in _clowns:
		if not is_instance_valid(c) or c.is_down:
			continue
		# Gasta uma ação geral (Passe) do Palhaço: ele precisa ter uma e poder agir
		if c.is_locked() or c.is_generals_suppressed() \
				or c.is_general_action_blocked(MatchManager.GeneralAction.PASS) \
				or m.general_left_for(c, MatchManager.GeneralAction.PASS) <= 0:
			continue
		if c.get_kick_type(ball) == KickType.NONE:   # longe da bola, derrubado, bola presa...
			continue
		if not m.can_pass_to(c, self, MatchManager.PassVariant.GROUND):   # alcance do passe
			continue
		var d: float = c.global_position.distance_to(ball.global_position)
		if d < best_dist:
			best = c
			best_dist = d
	return best


## O Palhaço passa rasteiro para o Kaiser. Gasta uma ação geral do PALHAÇO (da pool dele) e,
## como em qualquer habilidade, a ação de habilidade do Kaiser (paga pelo MatchManager).
func _use_knee() -> bool:
	var m: MatchManager = _get_manager()
	var clown: Player = _find_knee_clown()
	if m == null or clown == null:
		return false
	var ball: Ball = _get_ball()
	_pay_general_action_of(m, clown)   # sem await antes: a conferência de cima ainda vale
	start_cooldown(CD_KNEE, knee_cooldown)
	# Passe curvilíneo com curva 0 = passe rasteiro reto, mas aceita a aura (fx) da habilidade
	await m.run_curved_ground_pass(clown, self, ball, 0.0, 1.0, &"", kick_fx)
	return true


## Gasta uma ação geral (Passe) de OUTRO jogador, na mesma ordem do MatchManager._consume_general():
## primeiro a extra "sem Correr", depois a extra só dele, depois a pool do papel dele
## (Protagonista ou Secundários). O _consume_general do manager só gasta de quem está agindo
## (o Kaiser), por isso a conta é refeita aqui.
func _pay_general_action_of(m: MatchManager, p: Player) -> void:
	if p.extra_general_no_run_left > 0:
		p.extra_general_no_run_left -= 1
	elif p.extra_general_left > 0:
		p.extra_general_left -= 1
	elif p == m.protagonist:
		m.protagonist_general_left = maxi(0, m.protagonist_general_left - 1)
	else:
		m.secondary_general_left = maxi(0, m.secondary_general_left - 1)
	m.state_changed.emit()   # os contadores do HUD atualizam


# ---------- BLUE ROSE ----------

func is_rose_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _rose_until_round >= 0 and m.round_number <= _rose_until_round


func is_predator_active() -> bool:
	return is_rose_active() and _rose_variant == SKILL_PREDATOR


func is_meta_active() -> bool:
	return is_rose_active() and _rose_variant == SKILL_META


## Pode ativar esta variante? Nada ativo, fora de recarga e sem repetir a mesma mais que o limite
func _can_use_rose(variant: StringName) -> bool:
	if is_rose_active() or is_on_cooldown(CD_ROSE):
		return false
	return not (_rose_last == variant and _rose_streak >= rose_max_repeat)


func _use_rose(variant: StringName) -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	if not await play_action(&"blue_rose"):
		return false

	var start_round: int = m.round_number
	_rose_variant = variant
	_rose_until_round = start_round + rose_rounds - 1   # a rodada atual conta
	if _rose_last == variant:
		_rose_streak += 1
	else:
		_rose_last = variant
		_rose_streak = 1
	start_cooldown(CD_ROSE, rose_cooldown, _rose_until_round + 1)

	if variant == SKILL_META:
		_meta_ally_from = start_round + 1
		_meta_ally_until = start_round + meta_ally_rounds
		_meta_granted_round = -1

	_apply_rose_stats()
	queue_redraw()
	return true


## Predator: Carrinho mais longo (o slide_distance é lido na hora da mira e do Carrinho)
func _apply_rose_stats() -> void:
	slide_distance = _base_slide_distance * (1.0 + predator_slide_bonus) \
		if is_predator_active() else _base_slide_distance


## Predator: o Chutar comum (sem animação de habilidade) sai mais forte e com aura
func kick_ball(ball: Ball, direction: Vector2, kind: KickType, qte_success: bool = true,
		chance_override: float = -1.0, ignore_self_collision: bool = false,
		fx: KickFX = null, anim: StringName = &"", on_kick: Callable = Callable()) -> void:
	if is_predator_active() and anim == &"":
		next_kick_force_mult *= predator_force_mult
		if fx == null and qte_success:
			fx = kick_fx
	await super(ball, direction, kind, qte_success, chance_override, ignore_self_collision,
		fx, anim, on_kick)


## Meta: mais tempo no Correr (checado na hora em que a corrida começa)
func start_run() -> void:
	run_duration = _base_run_duration + (meta_run_bonus if is_meta_active() else 0.0)
	super()


## Meta: nenhum QTE nos chutes do Kaiser
func skips_qte() -> bool:
	return is_meta_active()


# ---------- BÔNUS DE CHUTE (Predator + Garçom) ----------

func _shot_bonus() -> float:
	var bonus: float = 0.0
	if is_predator_active():
		bonus += predator_shot_bonus
	bonus += _waiter_bonus(_get_ball())
	return bonus


## Vale também para o Chutar geral: base do tipo de chute + bônus
func get_shot_chance(kind: KickType) -> float:
	return minf(super(kind) + _shot_bonus(), 1.0)


# ---------- MAGNUS / BEINSCHUSS / KAISER IMPACT ----------

func get_shot_variant() -> ShotVariant:
	var ball: Ball = _get_ball()
	# get_kick_type já confere: derrubado, bola na mão do goleiro, longe demais, altura inalcançável
	if get_kick_type(ball) == KickType.NONE:
		return ShotVariant.NONE

	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND:
		if ball_level == Heights.Level.GROUND:
			return ShotVariant.MAGNUS
	elif height_level == Heights.Level.SUSPENDED:
		match ball_level:
			Heights.Level.GROUND:
				return ShotVariant.MAGNUS
			Heights.Level.SUSPENDED:
				return ShotVariant.IMPACT
			Heights.Level.FLYING:
				return ShotVariant.BEINSCHUSS
	return ShotVariant.NONE


func _shot_skill_name() -> String:
	match get_shot_variant():
		ShotVariant.BEINSCHUSS:
			return "Beinschuss"
		ShotVariant.IMPACT:
			return "Kaiser Impact"
	return "Magnus"


func _use_shot_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or get_shot_variant() == ShotVariant.NONE:
		return false

	# Mira. No Magnus o desenho mostra também a curva que a bola vai fazer.
	_aiming_magnus = get_shot_variant() == ShotVariant.MAGNUS
	queue_redraw()
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	_aiming_magnus = false
	queue_redraw()
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele mirava: confere de novo
	var ball: Ball = _get_ball()
	var variant: ShotVariant = get_shot_variant()
	if variant == ShotVariant.NONE:
		return false

	var kind: KickType = KickType.GROUND
	var anim: StringName = &"magnus"
	var base_chance: float = chance_magnus
	var dir: Vector2 = aim
	var needs_qte: bool = false
	var on_kick: Callable = Callable()

	match variant:
		ShotVariant.MAGNUS:
			# Sai desviado e vai curvando de volta; a bola é conduzida logo depois do chute
			dir = _magnus_heading(aim.angle(), 0.0)
			on_kick = _launch_magnus.bind(aim)
		ShotVariant.BEINSCHUSS:
			kind = KickType.FLYING
			anim = &"beinschuss"
			base_chance = chance_beinschuss
			needs_qte = true   # QTE difícil
		ShotVariant.IMPACT:
			kind = KickType.VOLLEY
			anim = &"kaiser_impact"
			base_chance = chance_impact
			on_kick = _launch_impact

	var qte_ok: bool = true
	if needs_qte and not skips_qte():
		qte_ok = await m.run_qte(KickType.FLYING)

	if variant == ShotVariant.IMPACT:
		next_kick_force_mult *= impact_force_mult   # rápido (gasto dentro do kick_ball)

	var chance: float = minf(base_chance + _shot_bonus(), 1.0)
	# Errou o QTE = chute fraquinho, sem aura
	await kick_ball(ball, dir, kind, qte_ok, chance, false,
		kick_fx if qte_ok else null, anim, on_kick)
	start_cooldown(CD_SHOT, shot_cooldown)
	return true


## Direção da bola no ponto u (0 = chute, 1 = fim da condução) do Magnus. Começa desviada para
## um lado e termina desviada para o outro: o desvio total é zero, então ela cruza a linha da mira.
func _magnus_heading(aim_angle: float, u: float) -> Vector2:
	var bend: float = deg_to_rad(magnus_bend_deg) * magnus_bend_sign
	return Vector2.from_angle(aim_angle + bend * (1.0 - 2.0 * u))


## Chamado pelo kick_ball() logo depois que a bola sai (on_kick)
func _launch_magnus(ball: Ball, _dir: Vector2, speed: float, aim: Vector2) -> void:
	_drive_ball(ball, magnus_flight_time, _magnus_step.bind(aim.angle(), speed))


func _launch_impact(ball: Ball, _dir: Vector2, _speed: float) -> void:
	_drive_ball(ball, impact_flight_time, _impact_step)


## Um passo da condução do Magnus: curva a velocidade e sobe suavemente até o nível Suspenso
func _magnus_step(b: Ball, u: float, delta: float, aim_angle: float, speed: float) -> void:
	b.velocity = _magnus_heading(aim_angle, u) * speed * lerpf(1.0, 0.85, u)
	b.height = Heights.SUSPENDED_HEIGHT * smoothstep(0.0, 1.0, u)
	b.vel_z = b.gravity * delta   # cancela a gravidade deste frame: a altura é conduzida aqui


## Um passo do Kaiser Impact: segura a bola no nível Suspenso (a velocidade fica como saiu do chute)
func _impact_step(b: Ball, _u: float, delta: float) -> void:
	b.height = move_toward(b.height, Heights.SUSPENDED_HEIGHT, 300.0 * delta)
	b.vel_z = b.gravity * delta


## Conduz a bola por "duration" segundos chamando step(bola, u 0..1, delta) a cada frame de física.
## Para sozinho se alguém tocar na bola, ela for segurada, reposta ou a partida acabar. Se chegou
## ao fim, solta a bola e a gravidade volta. Quem chama NÃO precisa esperar (roda em segundo plano).
func _drive_ball(ball: Ball, duration: float, step: Callable) -> void:
	var m: MatchManager = _get_manager()
	var touches: int = ball.interaction_count   # o chute do Kaiser já foi contado
	var state: Dictionary = {"abort": false}
	var on_reset: Callable = func() -> void: state["abort"] = true
	ball.was_reset.connect(on_reset, CONNECT_ONE_SHOT)

	var elapsed: float = 0.0
	var completed: bool = false
	while true:
		await get_tree().physics_frame
		if not is_instance_valid(ball) or state["abort"] or ball.interaction_count != touches \
				or ball.hovering or (m != null and m.match_over):
			break
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		step.call(ball, clampf(elapsed / duration, 0.0, 1.0), delta)
		if elapsed >= duration:
			completed = true
			break

	if not is_instance_valid(ball):
		return
	if ball.was_reset.is_connected(on_reset):
		ball.was_reset.disconnect(on_reset)
	if completed:
		ball.vel_z = 0.0   # solta: a gravidade assume e a bola cai


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_SHOT, "name": skill_label(_shot_skill_name(), CD_SHOT)})
	list.append({"id": SKILL_EMPIRE, "name": "Empire (%d)" % _empire_uses_left})
	list.append({"id": SKILL_KNEE, "name": skill_label("Auf die Knee", CD_KNEE)})
	list.append({"id": SKILL_PREDATOR, "name": _rose_label("Predator", SKILL_PREDATOR)})
	list.append({"id": SKILL_META, "name": _rose_label("Meta", SKILL_META)})
	return list


func _rose_label(title: String, variant: StringName) -> String:
	var full: String = "Blue Rose: " + title
	if is_rose_active() and _rose_variant == variant:
		return "%s (ativo)" % full
	if not is_rose_active() and not is_on_cooldown(CD_ROSE) \
			and _rose_last == variant and _rose_streak >= rose_max_repeat:
		return "%s (alterne)" % full
	return skill_label(full, CD_ROSE)


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_SHOT:
			return not is_on_cooldown(CD_SHOT) and get_shot_variant() != ShotVariant.NONE
		SKILL_EMPIRE:
			return _empire_uses_left > 0 and not _empire_candidates().is_empty()
		SKILL_KNEE:
			return not is_on_cooldown(CD_KNEE) and _find_knee_clown() != null
		SKILL_PREDATOR, SKILL_META:
			return _can_use_rose(skill_id)
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_SHOT:
			return await _use_shot_skill()
		SKILL_EMPIRE:
			return await _use_empire()
		SKILL_KNEE:
			return await _use_knee()
		SKILL_PREDATOR:
			return await _use_rose(SKILL_PREDATOR)
		SKILL_META:
			return await _use_rose(SKILL_META)
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_SHOT:
			title = _shot_skill_name()
			text = ("Chute de habilidade. A variante muda sozinha com a altura dele e da bola:\n"
				+ "• Magnus (bola no chão; ele no chão ou suspenso): chute curvo; a bola sobe ao nível Suspenso durante a trajetória. %d%% de chance de gol.\n"
				+ "• Beinschuss (ele suspenso e bola voando): bicicleta com QTE difícil. %d%%.\n"
				+ "• Kaiser Impact (ele suspenso e bola suspensa): chute reto e rápido, a bola vai suspensa o trajeto todo. %d%%.\n"
				+ "Recarga: %d rodadas, compartilhada entre as três.") % [
				_pct(chance_magnus), _pct(chance_beinschuss), _pct(chance_impact), shot_cooldown]
		SKILL_EMPIRE:
			title = "Empire"
			text = ("Marca aliados no alcance como servos, pela partida inteira:\n"
				+ "• 1ª escolha - Servo Garçom (flor dourada): chutes do Kaiser com passe/assistência dele ganham +%d%%.\n"
				+ "• 2ª escolha - Servo Palhaço (flor azul-escura): libera o Auf die Knee. Cancele a 2ª escolha para marcar só um.\n"
				+ "Cada gol do Kaiser dá +1 uso. Usos agora: %d.") % [_pct(waiter_bonus), _empire_uses_left]
		SKILL_KNEE:
			title = "Auf die Knee"
			text = ("Se a bola está perto de um Servo Palhaço e o Kaiser está ao alcance do passe dele, "
				+ "o Palhaço é obrigado a passar rasteiro para o Kaiser. Gasta uma ação geral do Palhaço "
				+ "(ele precisa ter uma sobrando) e a ação de habilidade do Kaiser.\nRecarga: %d rodadas.") % knee_cooldown
		SKILL_PREDATOR:
			title = "Blue Rose: Predator"
			text = ("Por %d rodadas: o Chutar fica mais forte (x%.2f), o Carrinho vai +%d%% mais longe "
				+ "e qualquer chute do Kaiser ganha +%d%% de chance.\n"
				+ "Recarga: %d rodadas depois do fim. Não dá para usar a mesma variante mais de %d vezes seguidas.") % [
				rose_rounds, predator_force_mult, _pct(predator_slide_bonus), _pct(predator_shot_bonus),
				rose_cooldown, rose_max_repeat]
		SKILL_META:
			title = "Blue Rose: Meta"
			text = ("Por %d rodadas: nenhum QTE nos chutes do Kaiser e +%.1f s no Correr. "
				+ "Nas próximas %d rodadas, os Secundários ganham +%d ação(ões) de habilidade.\n"
				+ "Recarga: %d rodadas depois do fim. Não dá para usar a mesma variante mais de %d vezes seguidas.") % [
				rose_rounds, meta_run_bonus, meta_ally_rounds, meta_extra_ally_skills,
				rose_cooldown, rose_max_repeat]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_clear_servants()
	_empire_uses_left = empire_starting_uses
	_rose_variant = &""
	_rose_until_round = -1
	_rose_last = &""
	_rose_streak = 0
	_meta_ally_from = -1
	_meta_ally_until = -1
	_meta_granted_round = -1
	_aiming_magnus = false
	run_duration = _base_run_duration
	slide_distance = _base_slide_distance
	queue_redraw()


# ---------- VISUAL ----------

func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)
	var ring: float = placeholder_radius + 26.0
	var gold := Color(1.0, 0.82, 0.25, 0.95)
	var blue := Color(0.1, 0.2, 0.75, 0.95)

	# Predator: anel dourado com "espinhos"
	if is_predator_active():
		draw_arc(center, ring, 0.0, TAU, 40, gold, 3.0)
		for i in 8:
			var d := Vector2.from_angle(TAU * float(i) / 8.0)
			draw_line(center + d * ring, center + d * (ring + 7.0), gold, 3.0)

	# Meta: anel azul-escuro tracejado com um fio dourado por dentro
	elif is_meta_active():
		var segments: int = 12
		for i in segments:
			if i % 2 == 0:
				var a0: float = TAU * float(i) / float(segments)
				var a1: float = TAU * float(i + 1) / float(segments)
				draw_arc(center, ring, a0, a1, 6, blue, 3.0)
		draw_arc(center, ring - 5.0, 0.0, TAU, 40, Color(gold, 0.6), 1.5)

	# Magnus: curva dourada = o caminho real da bola (a seta laranja do Player é a linha da mira)
	if is_aiming and _aiming_magnus:
		var steps: int = 24
		var step_len: float = (placeholder_radius + aim_range * 2.0) / float(steps)
		var a: float = aim_direction.angle()
		var pos := Vector2.ZERO
		var pts := PackedVector2Array([pos])
		for i in steps:
			pos += _magnus_heading(a, float(i) / float(steps)) * step_len
			pts.append(pos)
		draw_polyline(pts, gold, 3.0)
		draw_circle(pos, 5.0, gold)


## Flor que fica em cima de um servo (dourada = Garçom, azul-escura = Palhaço).
## É filha do jogador marcado, então acompanha ele (e sobe quando ele pula).
class FlowerMark extends Node2D:
	var petal_color: Color = Color(1.0, 0.82, 0.22)
	var core_color: Color = Color(0.08, 0.15, 0.6)
	var offset: Vector2 = Vector2(20.0, -40.0)
	var _target: Player = null

	func _ready() -> void:
		_target = get_parent() as Player
		z_index = 10
		_follow()

	func _process(_delta: float) -> void:
		_follow()

	func _follow() -> void:
		var h: float = _target.height if _target != null else 0.0
		position = offset + Vector2(0.0, -h)

	func _draw() -> void:
		var outline := Color(0.0, 0.0, 0.0, 0.75)
		var petals: int = 6
		for i in petals:
			draw_circle(Vector2.from_angle(TAU * float(i) / float(petals)) * 6.0, 5.0, outline)
		draw_circle(Vector2.ZERO, 4.0, outline)
		for i in petals:
			draw_circle(Vector2.from_angle(TAU * float(i) / float(petals)) * 6.0, 4.0, petal_color)
		draw_circle(Vector2.ZERO, 3.2, core_color)
