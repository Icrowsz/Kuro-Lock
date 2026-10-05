class_name Ness
extends Player
## Alexis Ness. Herda tudo do Player (ações gerais) e adiciona 3 famílias de habilidades
## (cada família tem recarga compartilhada entre as variantes):
##
## 1. Alohomora (recarga 2) - passe mágico rosa em zigue-zague curvo, alcance 500. A bola sobe ao
##    nível Suspenso no MEIO do trajeto e fica assim até o fim (pairando no aliado, como o passe alto).
##    O botão muda sozinho conforme a situação:
##      - bola SUSPENSA ao alcance  -> Depulso: Ness pula até ela e a repele na direção contrária
##                                     à que ela vinha
##      - bola ao alcance do pé     -> Alohomora (precisa de um aliado a até 500)
##      - sem a bola por perto      -> Expelliarmus: vai até um inimigo próximo e tira 10% da chance
##                                     de gol dos chutes dele por 2 rodadas (ou até Ness se afastar)
## 2. Confundo (recarga 3) - embaralha as habilidades de um inimigo próximo (botões viram "???" e
##    trocam de ordem). Variante Reparo (aparece quando algum aliado tem habilidade em recarga):
##    tira 1 rodada da recarga de até 2 habilidades dele. Confundo e Reparo dividem a recarga.
## 3. Leviosa (recarga 3) - sobe a bola um nível de altura. Descendo (bola Suspensa/Voando) desce um
##    nível. Arresto Momentum (bola Voando) prende a bola ali por 3 rodadas, ou até um aliado
##    interagir com ela; depois ela cai direto para o chão. Leviosa/Descendo/Arresto dividem a recarga.
##    Bola levantada/baixada pelos feitiços (sem Arresto) fica pairando até o fim do turno do time.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Ness". Depois registre o personagem na tela de formação
## (ela usa o character_id "ness" para saber quem é quem).
##
## Animações opcionais (a SpriteFrames pode ter; as que faltarem são puladas):
## "alohomora" (cai em "pass"), "depulso" (cai em "kick"), "expelliarmus", "confundo",
## "reparo", "leviosa", "descendo", "arresto".

const SKILL_ALOHOMORA: StringName = &"alohomora"   # também vira Depulso / Expelliarmus
const SKILL_CONFUNDO: StringName = &"confundo"
const SKILL_REPARO: StringName = &"reparo"
const SKILL_LEVIOSA: StringName = &"leviosa"
const SKILL_DESCENDO: StringName = &"descendo"
const SKILL_ARRESTO: StringName = &"arresto_momentum"

## Grupos de recarga (as variantes de cada família compartilham o mesmo)
const CD_ALOHOMORA: StringName = &"cd_alohomora"
const CD_CONFUNDO: StringName = &"cd_confundo"    # Confundo + Reparo
const CD_LEVIOSA: StringName = &"cd_leviosa"      # Leviosa + Descendo + Arresto Momentum

## Variante da habilidade 1 que cabe na situação atual
enum SpellVariant { NONE, ALOHOMORA, DEPULSO, EXPELLIARMUS }

@export_group("Alohomora")
@export var alohomora_range: float = 500.0           # alcance do passe
@export var alohomora_cooldown: int = 2              # recarga (rodadas), das 3 variantes
@export var alohomora_speed: float = 650.0           # velocidade da bola (px/s) ao longo do trajeto
@export var alohomora_amplitude: float = 70.0        # quanto o zigue-zague balança para os lados (px)
@export var alohomora_waves: float = 2.5             # quantas "ondas" tem o zigue-zague
## Inimigo no MESMO nível da bola e perto do trajeto intercepta (como no passe rasteiro)
@export var alohomora_interceptable: bool = true

@export_group("Depulso")
@export var depulso_range: float = 140.0             # distância máxima até a bola suspensa
@export var depulso_jump_time: float = 0.3           # tempo do pulo até a bola
@export var depulso_power: float = 180.0             # velocidade da bola repelida (px/s)
@export var depulso_arc: float = 40.0                # quanto a bola sobe a mais ao ser repelida

@export_group("Expelliarmus")
@export var expelliarmus_range: float = 200.0        # distância máxima até o inimigo escolhido
@export var expelliarmus_move_time: float = 0.35     # tempo da corrida até ele
@export_range(0.0, 1.0) var expelliarmus_shot_penalty: float = 0.10   # -10% (pontos percentuais)
@export var expelliarmus_rounds: int = 2             # a partir do próximo turno do inimigo
## Se a distância entre Ness e o inimigo passar disso, o efeito acaba (para sempre)
@export var expelliarmus_break_distance: float = 160.0

@export_group("Confundo / Reparo")
@export var confundo_range: float = 250.0            # distância máxima até o inimigo
@export var confundo_rounds: int = 1                 # turnos do inimigo confusos (a partir do próximo)
@export var confundo_cooldown: int = 3               # recarga de Confundo e Reparo
@export var reparo_range: float = 250.0              # distância máxima até o aliado
@export var reparo_skills: int = 2                   # quantas habilidades em recarga ele conserta
@export var reparo_rounds: int = 1                   # quantas rodadas cada uma perde de recarga

@export_group("Leviosa / Descendo / Arresto Momentum")
@export var spell_cooldown: int = 3                  # recarga das 3 (compartilhada)
## Distância máxima de Ness até a bola para lançar estes feitiços. 0 = sem limite
@export var ball_spell_range: float = 400.0
@export var spell_time: float = 0.35                 # tempo da bola subindo/descendo de nível
@export var arresto_rounds: int = 3                  # duração (contando a rodada em que foi usado)
@export var arresto_drop_time: float = 0.35          # tempo da queda até o chão quando o feitiço acaba

@export_group("Visual dos feitiços")
## Aura + partículas rosa. Vazio = usa o estilo padrão do Ness (veja _make_kick_fx)
@export var kick_fx: KickFX

## Arresto Momentum: até esta rodada (inclusive) a bola fica presa. -1 = nenhum feitiço ativo
var _arresto_until_round: int = -1
var _arresto_interactions: int = 0
## Última direção em que a bola andou de verdade (o Depulso repele para o lado contrário)
var _ball_dir: Vector2 = Vector2.ZERO
var _last_ball_pos: Vector2 = Vector2.ZERO
var _ball_pos_known: bool = false


func _init() -> void:
	character_id = "ness"            # o menu de formação usa isto para saber quem é quem
	display_name = "Alexis Ness"     # aparece no placar de gols e no menu


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_hook_manager.call_deferred()   # o MatchManager entra na árvore no mesmo frame


## Rosa mágico: faíscas que giram e sobem
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(1.0, 0.4, 0.8)
	fx.trail_width = 12.0
	fx.particle_color = Color(1.0, 0.8, 0.95)
	fx.amount = 28
	fx.lifetime = 0.6
	fx.speed_min = 10.0
	fx.speed_max = 60.0
	fx.gravity = Vector2(0.0, -50.0)
	fx.spin = 300.0
	fx.swirl = 40.0
	fx.scale_min = 0.12
	fx.scale_max = 0.3
	fx.burst_amount = 16
	fx.burst_speed = 200.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)


func _on_round_started(round_number: int) -> void:
	# Arresto Momentum acabou: a bola cai direto para o chão
	if _arresto_until_round >= 0 and round_number > _arresto_until_round:
		_end_arresto(true)


# ---------- UTILIDADES ----------

## Até que rodada vale um efeito que dura "rounds" TURNOS do alvo, contando a partir do próximo
## turno dele (se o turno dele ainda não passou nesta rodada, é o desta; senão, o da seguinte).
## Assim "2 rodadas" são sempre 2 turnos do inimigo, jogue o time do Ness primeiro ou depois.
func _effect_until_round(target: Player, rounds: int) -> int:
	var m: MatchManager = _get_manager()
	if m == null:
		return rounds
	var n: int = maxi(m.team_count, 1)
	var target_idx: int = posmod(target.team - m.starting_team, n)
	var current_idx: int = posmod(m.current_team - m.starting_team, n)
	var first_round: int = m.round_number if target_idx > current_idx else m.round_number + 1
	return first_round + rounds - 1


## Tem algum jogador (aliado ou inimigo) dentro do alcance que passe no filtro?
func _has_player_in_range(range_px: float, enemies: bool, filter: Callable = Callable()) -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self or (other.team != team) != enemies:
			continue
		if filter.is_valid() and not filter.call(other):
			continue
		if global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


## Anota para que lado a bola andou por último (o Depulso repele no sentido oposto)
func _track_ball_direction() -> void:
	var ball: Ball = _get_ball()
	if ball == null:
		return
	var pos: Vector2 = ball.global_position
	if _ball_pos_known:
		var step: Vector2 = pos - _last_ball_pos
		var length: float = step.length()
		# Ignora pulinhos de bola parada e teletransporte (bola reposta no centro)
		if length > 1.5 and length < 250.0:
			_ball_dir = step / length
	_last_ball_pos = pos
	_ball_pos_known = true


func _ball_spell_ok(ball: Ball) -> bool:
	if ball == null or ball.is_held() or ball.is_locked_for(team):
		return false
	if ball_spell_range > 0.0 and global_position.distance_to(ball.global_position) > ball_spell_range:
		return false
	return true


# ---------- 1. ALOHOMORA / DEPULSO / EXPELLIARMUS ----------

func _depulso_possible(ball: Ball) -> bool:
	return ball != null and not ball.is_held() and not ball.is_locked_for(team) \
		and ball.get_level() == Heights.Level.SUSPENDED \
		and global_position.distance_to(ball.global_position) <= depulso_range


## Qual variante o botão da habilidade 1 é agora (por situação da bola)
func get_spell_variant() -> SpellVariant:
	var ball: Ball = _get_ball()
	if ball == null:
		return SpellVariant.NONE
	if _depulso_possible(ball):
		return SpellVariant.DEPULSO
	# get_kick_type já confere: derrubado, bola na mão do goleiro, longe, nível inalcançável, presa
	if get_kick_type(ball) != KickType.NONE:
		return SpellVariant.ALOHOMORA
	return SpellVariant.EXPELLIARMUS


func _spell_name() -> String:
	match get_spell_variant():
		SpellVariant.DEPULSO:
			return "Depulso"
		SpellVariant.EXPELLIARMUS:
			return "Expelliarmus"
	return "Alohomora"


## A variante atual tem como ser usada? (ex: Alohomora precisa de um aliado ao alcance)
func _spell_usable(variant: SpellVariant) -> bool:
	match variant:
		SpellVariant.ALOHOMORA:
			return _has_player_in_range(alohomora_range, false)
		SpellVariant.DEPULSO:
			return true
		SpellVariant.EXPELLIARMUS:
			return _has_player_in_range(expelliarmus_range, true)
	return false


func _use_spell_one() -> bool:
	match get_spell_variant():
		SpellVariant.ALOHOMORA:
			return await _use_alohomora()
		SpellVariant.DEPULSO:
			return await _use_depulso()
		SpellVariant.EXPELLIARMUS:
			return await _use_expelliarmus()
	return false


func _use_alohomora() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var target: Player = await m.pick_ally_for_skill(self, alohomora_range)
	if target == null:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele mirava: confere de novo
	var ball: Ball = _get_ball()
	if get_spell_variant() != SpellVariant.ALOHOMORA:
		return false

	face_towards(target.global_position - global_position)
	if not await play_action(&"alohomora", ANIM_PASS):
		return false   # ação cancelada (ex: a partida reiniciou)

	await _fly_alohomora(m, ball, target)
	start_cooldown(CD_ALOHOMORA, alohomora_cooldown)
	return true


## Leva a bola por um zigue-zague curvo até o aliado. Ela sobe ao nível Suspenso no meio do
## trajeto e termina pairando em cima dele (igual ao passe alto: fica até alguém tocar ou o
## turno do time acabar).
func _fly_alohomora(m: MatchManager, ball: Ball, target: Player) -> void:
	m.clear_pending_pass()
	_end_arresto(false)

	var start: Vector2 = ball.global_position
	var end: Vector2 = target.global_position
	var start_height: float = ball.height
	var dist: float = maxf(start.distance_to(end), 1.0)
	var dir: Vector2 = (end - start) / dist
	var amplitude: float = minf(alohomora_amplitude, dist * 0.35)
	var duration: float = maxf(dist / alohomora_speed, 0.35)

	# Toca na bola (registra o toque, para) e passa a conduzir a bola quadro a quadro
	ball.kick_ground(Vector2.ZERO, 0.0, self, Ball.NO_SHOT)   # passe não é chute
	ball.hovering = true
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.fx_during_hover = true
	ball.play_fx(kick_fx)

	var elapsed: float = 0.0
	var intercepted: bool = false
	while elapsed < duration:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var t: float = clampf(elapsed / duration, 0.0, 1.0)
		ball.global_position = _alohomora_point(start, end, dir.orthogonal(), amplitude, t)
		# Sobe ao nível Suspenso no meio do trajeto (entre 40% e 60%)
		ball.height = lerpf(start_height, Heights.SUSPENDED_HEIGHT, smoothstep(0.4, 0.6, t))
		if alohomora_interceptable and t < 1.0 and _alohomora_intercepted(m, ball):
			intercepted = true
			break

	ball.fx_during_hover = false
	if intercepted:
		ball.release_hover()   # a bola solta onde foi cortada
		return
	ball.global_position = end
	ball.height = Heights.SUSPENDED_HEIGHT
	m.register_skill_pass(team, target)   # pairando Suspensa no aliado até tocarem ou o turno acabar


## Ponto do trajeto em t (0..1): reta + ondulação lateral que some nas pontas (sai e chega certinho)
func _alohomora_point(start: Vector2, end: Vector2, perp: Vector2, amplitude: float, t: float) -> Vector2:
	var envelope: float = sin(t * PI)
	var wave: float = sin(t * TAU * alohomora_waves) \
		+ 0.35 * sin(t * TAU * alohomora_waves * 2.3 + 1.0)   # 2ª onda: o "louco"
	return start.lerp(end, t) + perp * wave * envelope * amplitude


func _alohomora_intercepted(m: MatchManager, ball: Ball) -> bool:
	var level: Heights.Level = ball.get_level()
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down or other.height_level != level:
			continue
		if other.global_position.distance_to(ball.global_position) <= m.ground_pass_intercept_radius:
			return true
	return false


## Depulso: pula até a bola suspensa e a repele para o lado contrário ao que ela vinha
func _use_depulso() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or not _depulso_possible(ball):
		return false
	m.clear_pending_pass()
	_end_arresto(false)

	var repel: Vector2 = _repel_direction(ball)
	face_towards(repel)

	# Pula até a bola, ficando do lado de onde ela vinha (no caminho dela)
	var stand_off: float = body_radius + ball.collision_radius + 4.0
	var dest: Vector2 = ball.global_position - repel * stand_off
	height_level = Heights.Level.SUSPENDED
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", dest, depulso_jump_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "height", Heights.SUSPENDED_HEIGHT, depulso_jump_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished

	if not await play_action(&"depulso", ANIM_KICK):
		return false

	ball = _get_ball()
	if not ball.is_held():   # (o goleiro pode ter pegado a bola nesse meio tempo)
		# Repelir não é chute: sem disputa com o goleiro (NO_SHOT)
		ball.kick(repel, depulso_power, Heights.lift_for_peak(depulso_arc, ball.gravity),
			self, Ball.NO_SHOT)
		ball.play_fx(kick_fx)
	start_cooldown(CD_ALOHOMORA, alohomora_cooldown)
	return true


func _repel_direction(ball: Ball) -> Vector2:
	if _ball_dir != Vector2.ZERO:
		return -_ball_dir
	# Sem histórico da bola: empurra para longe do Ness
	var away: Vector2 = ball.global_position - global_position
	return away.normalized() if away.length() > 1.0 else Vector2(facing, 0.0)


## Expelliarmus: corre até um inimigo próximo e enfraquece os chutes dele
func _use_expelliarmus() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var target: Player = await m.pick_ally_for_skill(self, expelliarmus_range, true)
	if target == null:
		return false
	if get_spell_variant() != SpellVariant.EXPELLIARMUS:   # a bola chegou perto enquanto mirava
		return false

	# Vai até ele (para encostando, não por dentro)
	var to_target: Vector2 = target.global_position - global_position
	var stop_dist: float = body_radius + target.body_radius + 6.0
	face_towards(to_target)
	if to_target.length() > stop_dist:
		var dest: Vector2 = target.global_position - to_target.normalized() * stop_dist
		var tw := create_tween()
		tw.tween_property(self, "global_position", dest, expelliarmus_move_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished

	if not await play_action(&"expelliarmus"):
		return false

	target.apply_shot_debuff(expelliarmus_shot_penalty,
		_effect_until_round(target, expelliarmus_rounds), self, expelliarmus_break_distance)
	start_cooldown(CD_ALOHOMORA, alohomora_cooldown)
	return true


# ---------- 2. CONFUNDO / REPARO ----------

func _use_confundo() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var target: Player = await m.pick_ally_for_skill(self, confundo_range, true, _not_confused)
	if target == null:
		return false
	face_towards(target.global_position - global_position)
	if not await play_action(&"confundo"):
		return false
	target.apply_confusion(_effect_until_round(target, confundo_rounds))
	start_cooldown(CD_CONFUNDO, confundo_cooldown)
	return true


func _not_confused(other: Player) -> bool:
	return not other.is_confused()


func _has_cooldown(other: Player) -> bool:
	return other.has_cooldown_active()


func _use_reparo() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var target: Player = await m.pick_ally_for_skill(self, reparo_range, false, _has_cooldown)
	if target == null:
		return false
	face_towards(target.global_position - global_position)
	if not await play_action(&"reparo"):
		return false
	target.reduce_cooldowns(reparo_skills, reparo_rounds)
	start_cooldown(CD_CONFUNDO, confundo_cooldown)   # Reparo divide a recarga com o Confundo
	return true


# ---------- 3. LEVIOSA / DESCENDO / ARRESTO MOMENTUM ----------

## step = +1 (Leviosa, sobe) ou -1 (Descendo, desce): dá para mover a bola para esse nível?
func _level_spell_ok(ball: Ball, step: int) -> bool:
	if not _ball_spell_ok(ball):
		return false
	var new_level: int = int(ball.get_level()) + step
	return new_level >= 0 and new_level <= int(Heights.Level.FLYING)


func _use_level_spell(step: int) -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or not _level_spell_ok(ball, step):
		return false

	var anim: StringName = &"leviosa" if step > 0 else &"descendo"
	if not await play_action(anim):
		return false
	if not _level_spell_ok(ball, step):   # a bola pode ter mudado durante a animação
		return false

	_end_arresto(false)
	m.clear_pending_pass()
	var new_level: Heights.Level = (int(ball.get_level()) + step) as Heights.Level
	ball.play_fx(kick_fx)
	var tw: Tween = ball.hover_to(ball.global_position, Heights.to_height(new_level), spell_time)
	await tw.finished

	if new_level == Heights.Level.GROUND:
		ball.release_hover()   # chegou ao chão: volta à física normal
	else:
		# Fica pairando no novo nível até alguém tocar ou o turno do time acabar (aí ela cai)
		m.register_skill_pass(team, null)
	start_cooldown(CD_LEVIOSA, spell_cooldown)
	return true


func _arresto_active() -> bool:
	return _arresto_until_round >= 0


func _use_arresto() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or not _ball_spell_ok(ball) or ball.get_level() != Heights.Level.FLYING:
		return false
	if not await play_action(&"arresto"):
		return false
	if not _ball_spell_ok(ball) or ball.get_level() != Heights.Level.FLYING:
		return false

	m.clear_pending_pass()   # se era um passe alto pairando, o feitiço assume a bola
	# Congela a bola onde está, no nível Voando
	ball.hover_to(ball.global_position, Heights.FLYING_HEIGHT, 0.2)
	ball.spell_owner = self                          # o time adversário não consegue tocar nela
	ball.play_fx(kick_fx)
	_arresto_until_round = m.round_number + arresto_rounds - 1   # a rodada atual conta
	_arresto_interactions = ball.interaction_count
	start_cooldown(CD_LEVIOSA, spell_cooldown)
	queue_redraw()
	return true


## Acaba o Arresto Momentum. drop = true: a bola cai direto para o chão.
## drop = false: a bola já foi tocada/solta por outra coisa, só libera o bloqueio.
func _end_arresto(drop: bool) -> void:
	_arresto_until_round = -1
	queue_redraw()
	var ball: Ball = _get_ball()
	if ball == null or ball.spell_owner != self:
		return
	ball.spell_owner = null
	if drop and ball.hovering and not ball.is_held():
		_drop_ball(ball)


## Desce a bola direto até o chão (sem quicar de volta ao nível Suspenso)
func _drop_ball(ball: Ball) -> void:
	var tw: Tween = ball.hover_to(ball.global_position, Heights.GROUND_HEIGHT, arresto_drop_time)
	await tw.finished
	if is_instance_valid(ball) and ball.hovering and not ball.is_held() and ball.spell_owner == null:
		ball.release_hover()


## Um aliado interagiu com a bola (ou ela foi reposta/segurada): o Arresto Momentum acaba
func _watch_arresto() -> void:
	var ball: Ball = _get_ball()
	if ball == null or ball.spell_owner != self or not ball.hovering or ball.is_held() \
			or ball.interaction_count != _arresto_interactions:
		_end_arresto(false)


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var ball: Ball = _get_ball()

	list.append({"id": SKILL_ALOHOMORA, "name": skill_label(_spell_name(), CD_ALOHOMORA)})
	list.append({"id": SKILL_CONFUNDO, "name": skill_label("Confundo", CD_CONFUNDO)})
	# Reparo só aparece quando algum aliado tem habilidade em recarga
	if _has_player_in_range(INF, false, _has_cooldown):
		list.append({"id": SKILL_REPARO, "name": skill_label("Reparo", CD_CONFUNDO)})

	list.append({"id": SKILL_LEVIOSA, "name": skill_label("Leviosa", CD_LEVIOSA)})
	if ball != null and ball.get_level() != Heights.Level.GROUND:
		list.append({"id": SKILL_DESCENDO, "name": skill_label("Descendo", CD_LEVIOSA)})
	if ball != null and ball.get_level() == Heights.Level.FLYING:
		var arresto_name: String = "Arresto Momentum (ativo)" if _arresto_active() \
			else skill_label("Arresto Momentum", CD_LEVIOSA)
		list.append({"id": SKILL_ARRESTO, "name": arresto_name})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	var ball: Ball = _get_ball()
	match skill_id:
		SKILL_ALOHOMORA:
			return not is_on_cooldown(CD_ALOHOMORA) and _spell_usable(get_spell_variant())
		SKILL_CONFUNDO:
			return not is_on_cooldown(CD_CONFUNDO) \
				and _has_player_in_range(confundo_range, true, _not_confused)
		SKILL_REPARO:
			return not is_on_cooldown(CD_CONFUNDO) \
				and _has_player_in_range(reparo_range, false, _has_cooldown)
		SKILL_LEVIOSA:
			return not is_on_cooldown(CD_LEVIOSA) and _level_spell_ok(ball, 1)
		SKILL_DESCENDO:
			return not is_on_cooldown(CD_LEVIOSA) and _level_spell_ok(ball, -1)
		SKILL_ARRESTO:
			return not is_on_cooldown(CD_LEVIOSA) and not _arresto_active() \
				and _ball_spell_ok(ball) and ball.get_level() == Heights.Level.FLYING
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_ALOHOMORA:
			return await _use_spell_one()
		SKILL_CONFUNDO:
			return await _use_confundo()
		SKILL_REPARO:
			return await _use_reparo()
		SKILL_LEVIOSA:
			return await _use_level_spell(1)
		SKILL_DESCENDO:
			return await _use_level_spell(-1)
		SKILL_ARRESTO:
			return await _use_arresto()
	return false


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_arresto_until_round = -1
	_ball_dir = Vector2.ZERO
	_ball_pos_known = false


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	_track_ball_direction()
	if _arresto_active():
		_watch_arresto()
		queue_redraw()   # os anéis em volta da bola giram


func _draw() -> void:
	super()
	# Arresto Momentum: dois anéis rosa girando em volta da bola presa
	if _arresto_active():
		var ball: Ball = _get_ball()
		if ball != null and ball.spell_owner == self:
			var c: Vector2 = to_local(ball.sprite.global_position)
			var t: float = Time.get_ticks_msec() / 1000.0
			draw_arc(c, 24.0, t * 2.0, t * 2.0 + PI * 1.5, 24, Color(1.0, 0.4, 0.8, 0.9), 3.0)
			draw_arc(c, 18.0, -t * 3.0, -t * 3.0 + PI, 20, Color(1.0, 0.8, 0.95, 0.9), 2.0)
