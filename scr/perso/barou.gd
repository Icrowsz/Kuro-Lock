class_name Barou
extends Player
## Shuuya Barou. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Chute (ação de habilidade; recarga de 3 rodadas, compartilhada entre as variantes):
##      - Nero: Barou no chão + bola no chão -> chute rasteiro (30%)
##      - Terror: Barou suspenso + bola suspensa -> chute com pequena curva e mais força (35%)
##      - Villain: Barou suspenso + bola voando -> chute com mais força e a curva se mantém (40%)
## 2. Chop King (ação de habilidade; recarga de 2 rodadas): duas corridas bem curtas, com uma pausa
##      entre elas. Se Barou alcançar a bola, libera o complemento Nutmeg.
##    Nutmeg (complemento, grátis, só aparece depois do Chop King): chute que atravessa jogadores
##      (aliados e inimigos saltam quando a bola passa), com 30% de chance.
## 3. Predator Eye (ação de habilidade; recarga de 3 rodadas): por 2 rodadas, +0.6 s no Correr e
##      +10% de chance em todos os chutes. Os raios vermelhos aparecem ao redor enquanto estiver ativo.
##    Tyrant (variante): aparece se houver um aliado perto da bola e a até 200 px de Barou.
##      Faz o mesmo efeito, e o aliado dá um passe rasteiro para Barou. Usa a mesma recarga.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Barou" (o nome aparece no placar de gols).
##
## Não precisa de nenhum gancho novo no match_manager.gd nem no player.gd.

const SKILL_SHOT: StringName = &"nero"            # também é o id das variantes Terror e Villain
const SKILL_CHOP: StringName = &"chop_king"
const SKILL_NUTMEG: StringName = &"nutmeg"
const SKILL_PREDATOR: StringName = &"predator_eye"  # também é o id do Tyrant (variante)

## Grupos de recarga
const CD_SHOT: StringName = &"cd_shot"            # Nero, Terror e Villain
const CD_CHOP: StringName = &"cd_chop"            # Chop King (o Nutmeg não tem recarga própria)
const CD_PREDATOR: StringName = &"cd_predator"    # Predator Eye e Tyrant

## Variante do chute que cabe na situação atual
enum ShotVariant { NONE, NERO, TERROR, VILLAIN }

@export_group("Nero / Chute")
@export_range(0.0, 1.0) var nero_chance: float = 0.4
@export var shot_cooldown: int = 3                 # recarga (rodadas), igual para as 3 variantes

@export_group("Terror / Villain")
@export_range(0.0, 1.0) var terror_chance: float = 0.45
@export var terror_force_mult: float = 1.2         # "mais força"
@export_range(0.0, 1.0) var villain_chance: float = 0.50
@export var villain_force_mult: float = 1.35
@export var curve_accel: float = 150.0             # força lateral que faz a bola curvar (px/s²)
@export var curve_side: float = 1.0                # 1 ou -1: para que lado a bola curva
@export var terror_curve_time: float = 0.5         # curva pequena: dura pouco
@export var villain_curve_time: float = 3.0        # curva se mantém até a bola parar (ou este limite)

@export_group("Chop King")
@export var chop_run_time: float = 0.7         # duração de cada corrida (muito curta)
@export var chop_delay: float = 0.4              # espera antes da segunda corrida
@export var chop_cooldown: int = 2

@export_group("Nutmeg")
@export_range(0.0, 1.0) var nutmeg_chance: float = 0.50
@export var nutmeg_max_flight: float = 3.0        # trava de segurança: tempo máximo do "atravessar"
@export var nutmeg_hop_margin: float = 14.0       # distância extra para o jogador pular

@export_group("Predator Eye")
@export var predator_rounds: int = 3              # duração em rodadas (contando a atual)
@export var predator_cooldown: int = 3
@export var predator_run_bonus: float = 0.6       # segundos a mais no Correr
@export_range(0.0, 1.0) var predator_shot_bonus: float = 0.10   # +10% em todos os chutes

@export_group("Tyrant")
@export var tyrant_range: float = 200.0          # aliado precisa estar a até isso de Barou
@export var tyrant_ball_range: float = 100.0     # e a até isso da bola

@export_group("Visual do chute")
## Aura + partículas vermelhas dos chutes. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: nero, chop_king, nutmeg, predator_eye.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}

## Predator Eye vale até o fim desta rodada (-1 = inativo)
var _predator_until_round: int = -1
## Chop King já foi usado e o complemento Nutmeg está esperando
var _nutmeg_ready: bool = false
## Chop King está correndo (as corridas dele não recebem o bônus do Predator Eye)
var _chop_running: bool = false
## O Correr está com o bônus do Predator Eye aplicado (tirado quando a corrida acaba)
var _run_bonus_pending: bool = false


func _init() -> void:
	character_id = "barou"   # o menu de formação usa isto para saber quem é quem
	display_name = "Shuuya Barou"


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	run_finished.connect(_on_run_finished)


## Vermelho e preto (cor principal do personagem); as partículas são pedaços escuros
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.775, 0.038, 0.04, 1.0)
	fx.trail_width = 16.0
	fx.particle_color = Color(0.1, 0.1, 0.1)
	fx.amount = 26
	fx.lifetime = 0.5
	fx.speed_min = 30.0
	fx.speed_max = 110.0
	fx.gravity = Vector2.ZERO
	fx.spin = 240.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 18
	fx.burst_speed = 260.0
	return fx


# ---------- PREDATOR EYE (estado) ----------

func _predator_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _predator_until_round >= 0 and m.round_number <= _predator_until_round


# ---------- AÇÕES GERAIS AFETADAS PELO PREDATOR EYE ----------

## Correr: +0.6 s enquanto o Predator Eye estiver ativo (as corridas do Chop King não entram)
func start_run() -> void:
	if not _chop_running and _predator_active():
		run_time_bonus += predator_run_bonus
		_run_bonus_pending = true
	super()


func _on_run_finished() -> void:
	if _run_bonus_pending:
		_run_bonus_pending = false
		run_time_bonus -= predator_run_bonus


## Chutar (qualquer chute, geral ou de habilidade): +10% enquanto o Predator Eye estiver ativo
func kick_ball(ball: Ball, direction: Vector2, kind: KickType, qte_success: bool = true,
		chance_override: float = -1.0, ignore_self_collision: bool = false,
		fx: KickFX = null, anim: StringName = &"") -> void:
	if _predator_active():
		var base_chance: float = chance_override if chance_override >= 0.0 else get_shot_chance(kind)
		chance_override = base_chance + predator_shot_bonus
	await super(ball, direction, kind, qte_success, chance_override, ignore_self_collision, fx, anim)


# ---------- CHUTE: NERO / TERROR / VILLAIN ----------

## Qual variante do chute cabe agora (altura de Barou x altura da bola)
func get_shot_variant() -> ShotVariant:
	var ball: Ball = _get_ball()
	if ball == null or is_down or ball.is_held() or ball.is_locked_for(team):
		return ShotVariant.NONE
	if global_position.distance_to(ball.global_position) > kick_range:
		return ShotVariant.NONE
	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND:
		return ShotVariant.NERO if ball_level == Heights.Level.GROUND else ShotVariant.NONE
	if height_level == Heights.Level.SUSPENDED:
		if ball_level == Heights.Level.SUSPENDED:
			return ShotVariant.TERROR
		if ball_level == Heights.Level.FLYING:
			return ShotVariant.VILLAIN
	return ShotVariant.NONE


func _shot_skill_name() -> String:
	match get_shot_variant():
		ShotVariant.TERROR:
			return "Terror"
		ShotVariant.VILLAIN:
			return "Villain"
	return "Nero"


func _use_shot() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or get_shot_variant() == ShotVariant.NONE:
		return false

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação nem começa a recarga

	# A bola pode ter rolado enquanto ele mirava: confere de novo
	var ball: Ball = _get_ball()
	var variant: ShotVariant = get_shot_variant()
	if variant == ShotVariant.NONE:
		return false

	var kind: KickType = KickType.GROUND
	var chance: float = nero_chance
	var anim: StringName = &"nero"
	var force_mult: float = 1.0
	var curve_time: float = 0.0

	match variant:
		ShotVariant.TERROR:
			kind = KickType.VOLLEY
			chance = terror_chance
			anim = &"terror"
			force_mult = terror_force_mult
			curve_time = terror_curve_time
		ShotVariant.VILLAIN:
			kind = KickType.FLYING     # força de bola voando, mas SEM QTE neste personagem
			chance = villain_chance
			anim = &"villain"
			force_mult = villain_force_mult
			curve_time = villain_curve_time

	next_kick_force_mult *= force_mult
	await kick_ball(ball, aim, kind, true, chance, false, kick_fx, anim)

	# Curva: começa depois que a bola foi chutada (kick_ball já a soltou)
	if curve_time > 0.0:
		_curve_ball(ball, curve_side, curve_accel, curve_time)

	start_cooldown(CD_SHOT, shot_cooldown)
	return true


## Empurra a bola para o lado (perpendicular à direção dela) enquanto ela anda.
## Roda sozinha, sem await de quem chamou.
func _curve_ball(ball: Ball, side: float, accel: float, max_time: float) -> void:
	var t: float = 0.0
	while t < max_time:
		await get_tree().physics_frame
		if not is_instance_valid(ball) or ball.hovering or ball.is_held():
			return
		var delta: float = get_physics_process_delta_time()
		t += delta
		if ball.velocity.length() <= ball.stop_speed:
			return   # a bola parou: a curva acaba
		var perp: Vector2 = ball.velocity.normalized().orthogonal() * side
		ball.velocity += perp * accel * delta


# ---------- CHOP KING e NUTMEG ----------

## A bola está ao alcance de Barou agora (para liberar o complemento)?
func _ball_in_reach() -> bool:
	return get_kick_type(_get_ball()) != KickType.NONE


func _use_chop() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false

	_chop_running = true
	await _chop_one_run()
	if not is_inside_tree():
		_chop_running = false
		return false
	await get_tree().create_timer(chop_delay).timeout
	await _chop_one_run()
	_chop_running = false

	_nutmeg_ready = _ball_in_reach()   # alcançou a bola: libera o complemento
	start_cooldown(CD_CHOP, chop_cooldown)
	return true


## Uma corrida curta do Chop King (usa o Correr normal, mas com a duração curta)
func _chop_one_run() -> void:
	var saved_duration: float = run_duration
	run_duration = chop_run_time
	start_run()
	await run_finished
	run_duration = saved_duration
	runs_this_turn = maxi(0, runs_this_turn - 1)   # o Chop King não gasta o limite de Correr


## Complemento grátis: só depois do Chop King e enquanto a bola estiver ao alcance
func _use_nutmeg() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or not _nutmeg_ready:
		return false

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: o complemento continua disponível
	var kind: KickType = get_kick_type(ball)
	if kind == KickType.NONE:
		return false

	# Pausa a colisão com jogadores ANTES do chute: a bola atravessa todo mundo
	ball.collisions_paused = true
	await kick_ball(ball, aim, kind, true, nutmeg_chance, false, kick_fx, &"nutmeg")
	_nutmeg_ready = false
	_release_after_flight(ball)
	return true


## Espera a bola parar e então devolve a colisão. Enquanto ela passa, quem estiver perto
## da trajetória dá um pulinho (visual). Roda sozinha, sem await de quem chamou.
func _release_after_flight(ball: Ball) -> void:
	var t: float = 0.0
	while t < nutmeg_max_flight:
		await get_tree().physics_frame
		if not is_instance_valid(ball):
			return
		t += get_physics_process_delta_time()
		_hop_players_near(ball)
		if ball.hovering or (ball.is_on_ground() and ball.velocity.length() <= ball.stop_speed):
			break
	ball.collisions_paused = false


func _hop_players_near(ball: Ball) -> void:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p == self or p.is_down or p.height_level != Heights.Level.GROUND:
			continue
		var reach: float = ball.collision_radius + p.body_radius + nutmeg_hop_margin
		if p.global_position.distance_to(ball.global_position) <= reach:
			p.hop_over()


## Complemento: deixa de ser um "turno acabou" quando ainda pode ser usado
func has_free_followup() -> bool:
	return _nutmeg_ready and can_use_skill(SKILL_NUTMEG)


func skill_is_free(skill_id: StringName) -> bool:
	return skill_id == SKILL_NUTMEG and _nutmeg_ready


## Se o turno acabar sem o Nutmeg ser usado, ele expira
func has_turn_end_effect() -> bool:
	return _nutmeg_ready


func on_turn_end() -> void:
	_nutmeg_ready = false


# ---------- PREDATOR EYE e TYRANT ----------

## Aliado perto da bola e a até tyrant_range de Barou (o mais perto da bola é o escolhido)
func _find_tyrant_ally() -> Player:
	var ball: Ball = _get_ball()
	if ball == null:
		return null
	var best: Player = null
	var best_dist: float = INF
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p == self or p.team != team or p.is_down:
			continue
		if global_position.distance_to(p.global_position) > tyrant_range:
			continue
		var d: float = p.global_position.distance_to(ball.global_position)
		if d <= tyrant_ball_range and d < best_dist:
			best = p
			best_dist = d
	return best


func _use_predator() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	if not await play_action(&"predator_eye"):
		return false
	_predator_until_round = m.round_number + predator_rounds - 1   # a rodada atual conta
	start_cooldown(CD_PREDATOR, predator_cooldown)
	queue_redraw()
	return true


func _use_tyrant() -> bool:
	var m: MatchManager = _get_manager()
	var ally: Player = _find_tyrant_ally()
	if m == null or ally == null:
		return false
	if not await play_action(&"predator_eye"):
		return false
	_predator_until_round = m.round_number + predator_rounds - 1
	start_cooldown(CD_PREDATOR, predator_cooldown)
	queue_redraw()
	# O aliado dá um passe rasteiro para Barou
	await m.run_ground_pass(ally, self, _get_ball())
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_SHOT, "name": skill_label(_shot_skill_name(), CD_SHOT)})
	list.append({"id": SKILL_CHOP, "name": skill_label("Chop King", CD_CHOP)})
	if _nutmeg_ready:
		list.append({"id": SKILL_NUTMEG, "name": "Nutmeg (complemento)"})
	var pred_name: String
	if _predator_active():
		pred_name = "Predator Eye (ativo)"
	elif _find_tyrant_ally() != null:
		pred_name = skill_label("Tyrant", CD_PREDATOR)
	else:
		pred_name = skill_label("Predator Eye", CD_PREDATOR)
	list.append({"id": SKILL_PREDATOR, "name": pred_name})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_SHOT:
			return not is_on_cooldown(CD_SHOT) and get_shot_variant() != ShotVariant.NONE
		SKILL_CHOP:
			return not is_on_cooldown(CD_CHOP) and not _chop_running
		SKILL_NUTMEG:
			return _nutmeg_ready and _ball_in_reach()
		SKILL_PREDATOR:
			# Sem reativar enquanto está valendo nem durante a recarga
			return not _predator_active() and not is_on_cooldown(CD_PREDATOR)
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_SHOT:
			return await _use_shot()
		SKILL_CHOP:
			return await _use_chop()
		SKILL_NUTMEG:
			return await _use_nutmeg()
		SKILL_PREDATOR:
			if _find_tyrant_ally() != null:
				return await _use_tyrant()
			return await _use_predator()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_SHOT:
			var nero_text: String = "Nero (Barou e bola no chão): chute rasteiro, %d%% de chance de gol." % _pct(nero_chance)
			var terror_text: String = "Terror (os dois suspensos): chute com pequena curva e %d%% mais força. %d%% de chance de gol." % [
				_pct(terror_force_mult - 1.0), _pct(terror_chance)]
			var villain_text: String = "Villain (Barou suspenso e bola voando): chute com %d%% mais força e a curva se mantém. %d%% de chance de gol, sem QTE." % [
				_pct(villain_force_mult - 1.0), _pct(villain_chance)]
			match get_shot_variant():
				ShotVariant.TERROR:
					title = "Terror"
					text = terror_text
				ShotVariant.VILLAIN:
					title = "Villain"
					text = villain_text
				ShotVariant.NERO:
					title = "Nero"
					text = nero_text
				_:
					title = "Nero / Terror / Villain"
					text = nero_text + "\n" + terror_text + "\n" + villain_text
			text += "\nRecarga: %d rodadas, compartilhada entre as três." % shot_cooldown
		SKILL_CHOP:
			title = "Chop King"
			text = ("Duas corridas bem curtas (%.1f s cada), com uma pausa de %.1f s entre elas. Não gasta o limite de Correr. Se ao fim Barou alcançar a bola, libera o Nutmeg.\n"
				+ "Recarga: %d rodadas.") % [chop_run_time, chop_delay, chop_cooldown]
		SKILL_NUTMEG:
			title = "Nutmeg"
			text = "Complemento grátis do Chop King (não gasta ação de habilidade), com a bola ao alcance. Mire o chute: a bola atravessa todos os jogadores, aliados e inimigos (eles saltam). %d%% de chance de gol. Expira se o turno acabar sem usar." % _pct(nutmeg_chance)
		SKILL_PREDATOR:
			var effect_text: String = "Por %d rodadas (contando a atual): +%.1f s no Correr e +%d%% de chance de gol em todos os chutes." % [
				predator_rounds, predator_run_bonus, _pct(predator_shot_bonus)]
			if _find_tyrant_ally() != null:
				title = "Tyrant"
				text = "Tyrant (há um aliado perto da bola): " + effect_text + " Além disso, esse aliado dá um passe rasteiro para Barou."
			else:
				title = "Predator Eye"
				text = effect_text + "\nSe houver um aliado a até %d px dele e perto da bola, vira Tyrant: o aliado ainda passa a bola para o Barou." % int(tyrant_range)
			text += "\nRecarga: %d rodadas, compartilhada entre as duas." % predator_cooldown
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_predator_until_round = -1
	_nutmeg_ready = false
	_chop_running = false
	_run_bonus_pending = false
	queue_redraw()


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	if _predator_active():
		queue_redraw()   # os raios piscam todo frame


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Sem arte: o corpo fica vermelho com contorno preto (com sprite, pinte a arte na SpriteFrames)
	if draw_placeholder and not is_down and state != State.SLIDING:
		draw_circle(center, placeholder_radius, Color(0.8, 0.05, 0.05))
		draw_arc(center, placeholder_radius, 0.0, TAU, 32, Color.BLACK, 3.0)

	# Raios vermelhos em volta enquanto o Predator Eye estiver ativo
	if _predator_active():
		_draw_lightning(center)


func _draw_lightning(center: Vector2) -> void:
	var rays: int = 5
	for i in rays:
		var a: float = TAU * float(i) / float(rays) + randf() * 0.5
		var r0: float = placeholder_radius + 4.0
		var r1: float = placeholder_radius + 24.0 + randf() * 12.0
		var steps: int = 4
		var pts := PackedVector2Array()
		for s in range(steps + 1):
			var r: float = lerpf(r0, r1, float(s) / float(steps))
			var ang: float = a + (randf() - 0.5) * 0.35   # zig-zag do raio
			pts.append(center + Vector2(cos(ang), sin(ang)) * r)
		draw_polyline(pts, Color(0.9, 0.05, 0.05, 0.95), 3.0)
		draw_polyline(pts, Color(0.0, 0.0, 0.0, 0.7), 1.0)
