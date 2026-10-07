class_name Rin
extends Player
## Rin Itoshi. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Curve Shot (ação de habilidade, 4 variantes automáticas pela situação). Recarga de
##    2 rodadas, compartilhada entre as variantes:
##      - Rin no chão + bola no chão       -> Curve Shot: chute curvo longo; a bola sobe ao nível
##                                            Suspenso durante a trajetória e cai de novo (60%)
##      - Rin e bola Suspensos             -> Trivela Shot: chute MAIS curvo, QTE difícil (65%)
##      - Igual ao Trivela + inimigo colado -> Crash Shot: QTE fácil (70%)
##      - Destroyer Mode ativo (Curve)     -> Parabolic Curve: a bola sobe ao nível No Ar (60%)
##    A curva vai para o lado do gol que o time ataca; segurar SHIFT na hora de confirmar inverte.
## 2. Center of Gravity (recarga de 2 rodadas, compartilhada): derruba o inimigo mais próximo
##    e, se a bola estiver bem perto, ela vem até o Rin.
##      - Bola próxima e Suspensa           -> Puppets: passe curvo (alcance 500) para um companheiro
##      - Destroyer Mode ativo              -> Mangle You: além de derrubar, empurra o inimigo longe
## 3. Destroyer Mode: transformação de 3 rodadas (recarga de 3 rodadas depois do fim do efeito).
##      Libera Parabolic Curve, Mangle You e a habilidade Opposite Direction (minigame de
##      digitação; se acertar, ganha uma ação de Correr de graça).
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Rin" (o nome aparece no placar de gols).

const SKILL_CURVE: StringName = &"curve_shot"
const SKILL_GRAVITY: StringName = &"center_of_gravity"
const SKILL_DESTROYER: StringName = &"destroyer_mode"
const SKILL_OPPOSITE: StringName = &"opposite_direction"

## Grupos de recarga (cada grupo é compartilhado pelas variantes da habilidade)
const CD_CURVE: StringName = &"cd_curve"
const CD_GRAVITY: StringName = &"cd_gravity"
const CD_DESTROYER: StringName = &"cd_destroyer"

enum CurveVariant { NONE, CURVE, PARABOLIC, TRIVELA, CRASH }
enum GravityVariant { NONE, GRAVITY, PUPPETS, MANGLE }

@export_group("Curve Shot")
@export_range(0.0, 1.0) var chance_curve: float = 0.45     # Curve Shot e Parabolic Curve
@export_range(0.0, 1.0) var chance_trivela: float = 0.50
@export_range(0.0, 1.0) var chance_crash: float = 0.55
@export var curve_force: float = 60.0               # força do chute (x kick_force_to_speed = px/s)
@export var curve_aim_range: float = 200          # tamanho da seta de mira
@export var curve_turn_degrees: float = 70.0        # quanto a trajetória curva (Curve / Parabolic)
@export var trivela_turn_degrees: float = 75.0      # Trivela e Crash: bem mais curvo
@export var curve_duration: float = 1             # por quanto tempo a bola vai fazendo a curva (s)
@export var curve_preview_length: float = 600.0     # tamanho da linha tracejada da mira
@export var crash_enemy_radius: float = 90.0        # inimigo "muito próximo" do Rin
@export var curve_cooldown: int = 2

@export_group("Center of Gravity")
@export var gravity_range: float = 70.0            # alcance para achar o "inimigo mais próximo"
@export var pull_ball_radius: float = 90.0         # bola "bem próxima": ela vem até o Rin
@export var pull_ball_time: float = 0.25
@export var puppets_ball_radius: float = 110.0      # bola "próxima" para virar Puppets
@export var puppets_range: float = 500.0            # alcance do passe curvo
@export var puppets_flight_time: float = 0.9
@export var puppets_curve_amount: float = 0.35      # curvatura (fração da distância do passe)
@export var puppets_arc_height: float = 60.0        # quanto a bola sobe no meio do passe
@export var mangle_push_distance: float = 75.0     # quanto o Mangle You empurra o inimigo
@export var gravity_cooldown: int = 2

@export_group("Destroyer Mode")
@export var destroyer_rounds: int = 3               # duração total em rodadas (contando a atual)
@export var destroyer_cooldown: int = 2             # recarga, contada a partir do fim do efeito
@export var typing_time: float = 3.0                # Opposite Direction: tempo para digitar
@export var typing_words: Array[String] = ["DEVORAR", "DESTRUIR", "ANIRAP", "DESTROÇAR", "MATAR", "EGOISTA"]

@export_group("Visual do chute")
## Aura + partículas do Curve Shot. Vazio = usa o estilo padrão do Rin (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: curve_shot, center_of_gravity, destroyer_mode, opposite_direction.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}

## Destroyer Mode vale até o fim desta rodada (-1 = inativo)
var _destroyer_until_round: int = -1
## Mirando um chute curvo: o desenho mostra a trajetória aproximada
var _aiming_curve: bool = false
## Pulso visual do Center of Gravity (1 -> 0) e o ponto do inimigo atingido
var _pulse: float = 0.0
var _pulse_target: Vector2 = Vector2.ZERO


func _init() -> void:
	character_id = "rin"             # o menu de formação usa isto para saber quem é quem
	display_name = "Itoshi Rin"      # aparece no placar de gols e no menu


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_hook_manager.call_deferred()


## Verde-azulado do Rin; as partículas giram em espiral (a curva / "gravidade")
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.176, 0.661, 0.569)
	fx.additive = false   # o campo é verde: mistura normal mantém a cor visível
	fx.trail_width = 16.0
	fx.trail_points = 20
	fx.shape = KickFX.Shape.DOT
	fx.particle_color = Color(0.314, 0.909, 0.625)
	fx.amount = 26
	fx.lifetime = 0.6
	fx.speed_min = 10.0
	fx.speed_max = 50.0
	fx.swirl = 140.0
	fx.damping = 20.0
	fx.scale_min = 0.2
	fx.scale_max = 0.45
	fx.burst_amount = 14
	fx.burst_speed = 200.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m and not m.round_started.is_connected(_on_round_started):
		m.round_started.connect(_on_round_started)


func _on_round_started(_round_number: int) -> void:
	queue_redraw()   # a aura do Destroyer Mode some quando as rodadas acabam


# ---------- DESTROYER MODE ----------

## Exemplo de animação por situação: com o Destroyer Mode ligado, o Rin parado usa
## "idle_destroyer" (se existir na SpriteFrames; senão segue com "idle")
func _desired_anim() -> StringName:
	var a: StringName = super()
	if a == ANIM_IDLE and is_destroyer_active() and animated_sprite \
			and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(&"idle_destroyer"):
		return &"idle_destroyer"
	return a


func is_destroyer_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _destroyer_until_round >= 0 and m.round_number <= _destroyer_until_round


func _use_destroyer() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	_destroyer_until_round = m.round_number + destroyer_rounds - 1
	# A recarga começa a contar na rodada seguinte ao fim do efeito
	start_cooldown(CD_DESTROYER, destroyer_cooldown, _destroyer_until_round + 1)
	_play_pulse(global_position)
	queue_redraw()
	return true


## Opposite Direction: minigame de digitação; acertou = Correr de graça (na hora)
func _use_opposite_direction() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or not is_destroyer_active():
		return false
	var ok: bool = await m.run_typing_game("Opposite Direction!", typing_words, typing_time)
	if ok:
		start_run()
		runs_this_turn = maxi(0, runs_this_turn - 1)   # de graça: não conta no limite de Correr
		await run_finished
	return true   # tentar já gasta a ação (igual a errar um QTE)


# ---------- SITUAÇÕES (variantes automáticas) ----------

func _ball_near_suspended(ball: Ball) -> bool:
	return ball != null and not ball.is_held() \
		and ball.get_level() == Heights.Level.SUSPENDED \
		and global_position.distance_to(ball.global_position) <= puppets_ball_radius


func _ball_close(ball: Ball) -> bool:
	return ball != null and not ball.is_held() \
		and global_position.distance_to(ball.global_position) <= pull_ball_radius


func _enemy_close() -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down:
			continue
		if global_position.distance_to(other.global_position) <= crash_enemy_radius:
			return true
	return false


func _nearest_enemy(max_dist: float) -> Player:
	var best: Player = null
	var best_d: float = max_dist
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d <= best_d:
			best = other
			best_d = d
	return best


func _has_ally_in_range(range_px: float) -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other != self and other.team == team \
				and global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


func get_curve_variant() -> CurveVariant:
	var ball: Ball = _get_ball()
	# get_kick_type já confere: derrubado, bola na mão do goleiro, longe demais, altura inalcançável
	if get_kick_type(ball) == KickType.NONE:
		return CurveVariant.NONE
	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND and ball_level == Heights.Level.GROUND:
		return CurveVariant.PARABOLIC if is_destroyer_active() else CurveVariant.CURVE
	if height_level == Heights.Level.SUSPENDED and ball_level == Heights.Level.SUSPENDED:
		return CurveVariant.CRASH if _enemy_close() else CurveVariant.TRIVELA
	return CurveVariant.NONE


func get_gravity_variant() -> GravityVariant:
	var ball: Ball = _get_ball()
	if _ball_near_suspended(ball) and _has_ally_in_range(puppets_range):
		return GravityVariant.PUPPETS
	if _nearest_enemy(gravity_range) != null:
		return GravityVariant.MANGLE if is_destroyer_active() else GravityVariant.GRAVITY
	return GravityVariant.NONE


func _curve_skill_name() -> String:
	match get_curve_variant():
		CurveVariant.PARABOLIC:
			return "Parabolic Curve"
		CurveVariant.TRIVELA:
			return "Trivela Shot"
		CurveVariant.CRASH:
			return "Crash Shot"
		CurveVariant.NONE:
			return "Parabolic Curve" if is_destroyer_active() else "Curve Shot"
	return "Curve Shot"


func _gravity_skill_name() -> String:
	match get_gravity_variant():
		GravityVariant.PUPPETS:
			return "Puppets"
		GravityVariant.MANGLE:
			return "Mangle You"
		GravityVariant.NONE:
			return "Mangle You" if is_destroyer_active() else "Center of Gravity"
	return "Center of Gravity"


# ---------- CURVE SHOT (e variantes) ----------

## Para que lado a bola curva: para o gol que o time ataca. SHIFT inverte.
func _curve_side(from_pos: Vector2, aim: Vector2) -> float:
	var field := get_tree().get_first_node_in_group("field") as Field
	var target: Vector2 = from_pos + Vector2(1.0 if team == 0 else -1.0, 0.0)
	if field:
		target = field.get_attack_goal_center(team)
	var side: float = 1.0 if aim.cross(target - from_pos) >= 0.0 else -1.0
	if Input.is_key_pressed(KEY_SHIFT):
		side = -side
	return side


func _use_curve_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or get_curve_variant() == CurveVariant.NONE:
		return false

	_aiming_curve = true
	queue_redraw()
	var aim: Vector2 = await m.aim_for_skill(self, curve_aim_range)
	_aiming_curve = false
	queue_redraw()
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter mudado enquanto ele mirava: confere de novo
	var ball: Ball = _get_ball()
	var variant: CurveVariant = get_curve_variant()
	if variant == CurveVariant.NONE:
		return false

	var chance: float = chance_curve
	var anim: StringName = &"curve_shot"
	var turn: float = curve_turn_degrees
	var peak: Heights.Level = Heights.Level.SUSPENDED
	var needs_qte: bool = false
	var qte_kind: KickType = KickType.VOLLEY

	match variant:
		CurveVariant.PARABOLIC:
			anim = &"parabolic_curve"
			peak = Heights.Level.FLYING        # sobe ao nível No Ar antes de cair
		CurveVariant.TRIVELA:
			anim = &"trivela_shot"
			chance = chance_trivela
			turn = trivela_turn_degrees
			needs_qte = true
			qte_kind = KickType.FLYING         # QTE difícil
		CurveVariant.CRASH:
			anim = &"crash_shot"
			chance = chance_crash
			turn = trivela_turn_degrees
			needs_qte = true
			qte_kind = KickType.VOLLEY         # QTE fácil

	var qte_ok: bool = true
	if needs_qte and not skips_qte():
		qte_ok = await m.run_qte(qte_kind)

	var side: float = _curve_side(ball.global_position, aim)
	await _curve_kick(ball, aim, side, turn, peak, chance, qte_ok, anim)
	start_cooldown(CD_CURVE, curve_cooldown)
	return true


## Chuta a bola e vai girando a velocidade dela durante a trajetória (a curva)
func _curve_kick(ball: Ball, dir: Vector2, side: float, turn_deg: float,
		peak: Heights.Level, chance: float, qte_ok: bool, anim: StringName = &"curve_shot") -> void:
	# A bola só sai no frame de impacto da animação (hit_frames); sem arte, sai direto
	if not await play_action(anim, ANIM_KICK):
		return
	var speed: float = curve_force * kick_force_to_speed
	var d: Vector2 = dir.normalized()
	if not qte_ok:
		speed *= qte_fail_power_mult
		d = d.rotated(deg_to_rad(randf_range(-qte_fail_max_angle, qte_fail_max_angle)))

	# Sobe só o que falta até o pico do nível (se a bola já está mais alta, só cai)
	var rise: float = maxf(0.0, Heights.to_height(peak) - ball.height)
	ball.kick(d, speed, Heights.lift_for_peak(rise, ball.gravity), self, chance)
	if qte_ok:
		ball.play_fx(kick_fx)   # errou o QTE = chute fraquinho, sem aura

	var touches: int = ball.interaction_count
	var elapsed: float = 0.0
	while elapsed < curve_duration:
		await get_tree().physics_frame
		var dt: float = get_physics_process_delta_time()
		elapsed += dt
		# Alguém tocou na bola, o goleiro já decidiu o chute ou a bola foi segurada: acabou a curva
		if ball.interaction_count != touches or ball.hovering or not ball.has_pending_shot():
			break
		ball.velocity = ball.velocity.rotated(side * deg_to_rad(turn_deg) / curve_duration * dt)

	# Errou o QTE: o jogador se desequilibra e cai (igual ao chute geral)
	if not qte_ok:
		knock_down()


# ---------- CENTER OF GRAVITY (e variantes) ----------

func _use_gravity() -> bool:
	var variant: GravityVariant = get_gravity_variant()
	if variant == GravityVariant.NONE:
		return false

	var ok: bool = true
	if variant == GravityVariant.PUPPETS:
		ok = await _do_puppets()
	else:
		await _do_gravity(variant == GravityVariant.MANGLE)

	if ok:
		start_cooldown(CD_GRAVITY, gravity_cooldown)
	return ok


## Derruba o inimigo mais próximo (Mangle You também empurra) e puxa a bola se estiver bem perto
func _do_gravity(push: bool) -> void:
	await play_action(&"mangle_you" if push else &"center_of_gravity", &"center_of_gravity")
	var enemy: Player = _nearest_enemy(gravity_range)
	var ball: Ball = _get_ball()
	_play_pulse(enemy.global_position if enemy else global_position)

	var push_tween: Tween = null
	if enemy:
		enemy.knock_down()
		if push:
			push_tween = _push_enemy(enemy)

	if _ball_close(ball):
		await _pull_ball_to_self(ball)
	if push_tween and push_tween.is_valid():
		await push_tween.finished
	await get_tree().create_timer(0.15).timeout


func _push_enemy(enemy: Player) -> Tween:
	var dir: Vector2 = enemy.global_position - global_position
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	var dest: Vector2 = enemy.global_position + dir * mangle_push_distance
	var field := get_tree().get_first_node_in_group("field") as Field
	if field:
		var half: Vector2 = field.pitch_size * 0.5
		var l: Vector2 = field.to_local(dest)
		dest = field.to_global(Vector2(clampf(l.x, -half.x, half.x), clampf(l.y, -half.y, half.y)))
	var tw: Tween = create_tween()
	tw.tween_property(enemy, "global_position", dest, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


## A bola desliza até encostar no Rin (se estava no ar, cai ali)
func _pull_ball_to_self(ball: Ball) -> void:
	var dir: Vector2 = ball.global_position - global_position
	dir = dir.normalized() if dir.length() > 1.0 else Vector2(1.0 if team == 0 else -1.0, 0.0)
	var dest: Vector2 = global_position + dir * (ball.collision_radius + body_radius + 6.0)
	ball.register_touch(self)
	var tw: Tween = ball.hover_to(dest, ball.height, pull_ball_time)
	await tw.finished
	ball.release_hover()


## Puppets: passe curvo até um companheiro (clique nele), alcance 500
func _do_puppets() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false
	var target: Player = await m.pick_ally_for_skill(self, puppets_range)
	if target == null or not _ball_near_suspended(ball):
		return false   # cancelou: não gasta a ação
	face_towards(target.global_position - global_position)
	await play_action(&"puppets")
	await _curved_pass(ball, target)
	m.register_skill_pass(team, target)   # a bola fica Suspensa no alvo até alguém tocar ou o turno acabar
	return true


func _curved_pass(ball: Ball, target: Player) -> void:
	var start: Vector2 = ball.global_position
	var end: Vector2 = target.global_position
	var seg: Vector2 = end - start
	var normal: Vector2 = seg.orthogonal().normalized() if seg.length() > 1.0 else Vector2.UP
	var control: Vector2 = (start + end) * 0.5 \
		+ normal * _pass_curve_side(start, end) * seg.length() * puppets_curve_amount

	ball.register_touch(self)   # o passe conta como toque (autor do gol / assistência)
	# Põe a bola no modo "pairando" (sem física) para o tween conduzir
	var settle_tween: Tween = ball.hover_to(start, ball.height, 0.02)
	await settle_tween.finished
	ball.trail_enabled = true

	var tw: Tween = create_tween()
	tw.tween_method(_move_ball_on_curve.bind(ball, start, control, end, ball.height),
		0.0, 1.0, puppets_flight_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	ball.trail_enabled = false


func _move_ball_on_curve(t: float, ball: Ball, a: Vector2, c: Vector2, b: Vector2,
		start_height: float) -> void:
	var u: float = 1.0 - t
	ball.global_position = u * u * a + 2.0 * u * t * c + t * t * b
	ball.height = lerpf(start_height, Heights.SUSPENDED_HEIGHT, t) + sin(t * PI) * puppets_arc_height


## A curva do passe desvia do inimigo mais perto da linha reta (vai para o lado oposto)
func _pass_curve_side(a: Vector2, b: Vector2) -> float:
	var seg: Vector2 = b - a
	if seg.length() < 1.0:
		return 1.0
	var normal: Vector2 = seg.orthogonal().normalized()
	var best_dist: float = INF
	var side: float = 1.0
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team:
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(other.global_position, a, b)
		var d: float = other.global_position.distance_to(closest)
		if d < best_dist:
			best_dist = d
			side = -signf((other.global_position - closest).dot(normal))
	return side if side != 0.0 else 1.0


# ---------- VISUAL: PULSO ----------

func _play_pulse(target_global: Vector2) -> void:
	_pulse_target = target_global
	_pulse = 1.0
	var tw: Tween = create_tween()
	tw.tween_method(_set_pulse, 1.0, 0.0, 0.5)


func _set_pulse(value: float) -> void:
	_pulse = value
	queue_redraw()


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_CURVE, "name": skill_label(_curve_skill_name(), CD_CURVE)})
	list.append({"id": SKILL_GRAVITY, "name": skill_label(_gravity_skill_name(), CD_GRAVITY)})
	var destroyer_name: String = "Destroyer Mode (ativo)" if is_destroyer_active() \
		else skill_label("Destroyer Mode", CD_DESTROYER)
	list.append({"id": SKILL_DESTROYER, "name": destroyer_name})
	if is_destroyer_active():
		list.append({"id": SKILL_OPPOSITE, "name": "Opposite Direction"})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_CURVE:
			return not is_on_cooldown(CD_CURVE) and get_curve_variant() != CurveVariant.NONE
		SKILL_GRAVITY:
			return not is_on_cooldown(CD_GRAVITY) and get_gravity_variant() != GravityVariant.NONE
		SKILL_DESTROYER:
			return not is_destroyer_active() and not is_on_cooldown(CD_DESTROYER)
		SKILL_OPPOSITE:
			return is_destroyer_active()
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_CURVE:
			return await _use_curve_skill()
		SKILL_GRAVITY:
			return await _use_gravity()
		SKILL_DESTROYER:
			await play_action(&"destroyer_mode")
			return _use_destroyer()
		SKILL_OPPOSITE:
			return await _use_opposite_direction()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_CURVE:
			title = _curve_skill_name()
			text = ("Chute de habilidade. A variante muda sozinha com a situação:\n"
				+ "• Curve Shot (Rin e bola no chão): chute curvo longo; a bola sobe ao nível suspenso no trajeto e cai de novo. %d%% de chance de gol.\n"
				+ "• Trivela Shot (Rin e bola suspensos): chute ainda mais curvo, com QTE difícil. %d%%.\n"
				+ "• Crash Shot (como a Trivela, com um inimigo colado em Rin): QTE fácil. %d%%.\n"
				+ "• Parabolic Curve (Curve Shot com o Destroyer Mode ativo): a bola sobe ao nível voando. %d%%.\n"
				+ "A curva vai para o lado do gol que o time ataca; segure SHIFT ao confirmar para inverter. Recarga: %d rodadas, compartilhada.") % [
				_pct(chance_curve), _pct(chance_trivela), _pct(chance_crash), _pct(chance_curve), curve_cooldown]
		SKILL_GRAVITY:
			title = _gravity_skill_name()
			text = ("Derruba o inimigo mais próximo (a até %d px) e, se a bola estiver bem perto (até %d px), ela vem até Rin.\n"
				+ "• Puppets (bola suspensa perto de Rin e um aliado a até %d px): em vez de derrubar, faz um passe curvo para o aliado.\n"
				+ "• Mangle You (com o Destroyer Mode ativo): além de derrubar, empurra o inimigo para longe.\n"
				+ "Recarga: %d rodadas, compartilhada.") % [
				int(gravity_range), int(pull_ball_radius), int(puppets_range), gravity_cooldown]
		SKILL_DESTROYER:
			title = "Destroyer Mode"
			text = ("Transformação de %d rodadas. Libera Parabolic Curve, Mangle You e a habilidade Opposite Direction.\n"
				+ "Recarga: %d rodadas, contadas a partir do fim do efeito.") % [
				destroyer_rounds, destroyer_cooldown]
		SKILL_OPPOSITE:
			title = "Opposite Direction"
			text = ("Só aparece com o Destroyer Mode ativo. Minigame de digitação: digite a palavra em até %.1f segundos. Se acertar, Rin ganha uma ação de Correr de graça (não conta no limite de Correr). Tentar já usa a habilidade, mesmo errando. Não tem recarga própria.") % [
				typing_time]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()   # também zera as recargas
	_destroyer_until_round = -1
	_aiming_curve = false
	_pulse = 0.0
	queue_redraw()


# ---------- VISUAL ----------

func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Aura vermelha/roxa enquanto o Destroyer Mode está valendo
	if is_destroyer_active():
		draw_arc(center, placeholder_radius + 7.0, 0.0, TAU, 40, Color(0.176, 0.661, 0.569, 0.9), 2.5)
		draw_arc(center, placeholder_radius + 11.0, 0.0, TAU, 40, Color(0.293, 0.513, 0.595, 0.5), 1.5)

	# Pulso do Center of Gravity: anel que se expande e um raio até o inimigo
	if _pulse > 0.0:
		var ring: float = lerpf(placeholder_radius + 70.0, placeholder_radius, _pulse)
		draw_arc(center, ring, 0.0, TAU, 48, Color(0.7, 0.3, 1.0, _pulse), 3.0)
		draw_line(center, to_local(_pulse_target), Color(0.7, 0.3, 1.0, _pulse * 0.8), 2.0)

	# Mira do chute curvo: linha tracejada com a trajetória aproximada
	if is_aiming and _aiming_curve:
		_draw_curve_preview()


func _draw_curve_preview() -> void:
	var ball: Ball = _get_ball()
	var from_pos: Vector2 = ball.global_position if ball else global_position
	var side: float = _curve_side(from_pos, aim_direction)
	var variant: CurveVariant = get_curve_variant()
	var turn: float = curve_turn_degrees
	if variant == CurveVariant.TRIVELA or variant == CurveVariant.CRASH:
		turn = trivela_turn_degrees

	var steps: int = 24
	var step_len: float = curve_preview_length / float(steps)
	var per_step: float = side * deg_to_rad(turn) / float(steps)
	var pos: Vector2 = Vector2.ZERO
	var dir: Vector2 = aim_direction
	for i in steps:
		var next: Vector2 = pos + dir * step_len
		if i % 2 == 0:
			draw_line(pos, next, Color(0.314, 0.909, 0.625, 0.961), 3.0)
		pos = next
		dir = dir.rotated(per_step)
