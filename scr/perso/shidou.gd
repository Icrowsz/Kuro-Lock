class_name Shidou
extends Player
## Shidou Ryusei. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Kablamo (ação de habilidade, com 3 variantes automáticas pela altura; recarga de 3 rodadas,
##      compartilhada entre as variantes):
##      - Shidou no chão + bola no chão          -> Kablamo: chute forte com uma curva bem pequena, a bola
##                                                  ignora a colisão do próprio Shidou (30%)
##      - os dois suspensos                      -> Dragon Drive: voleio (QTE fácil); a bola sobe até
##                                                  "voando" no caminho e cai até o chão no final (35%)
##      - bola voando + Shidou suspenso          -> Big Bang Drive: voleio voador (QTE difícil), como o
##                                                  voleio voador normal, só que mais forte; a bola cai
##                                                  normalmente (45%)
## 2. Demonic Rush (ação de habilidade): um Correr com o mesmo tempo, mas bem mais veloz. Se ao
##      fim da corrida ele alcançou uma bola suspensa, o botão vira Draconic Header (complemento,
##      válido na mesma rodada e SEM gastar outra ação de habilidade): chute reto, a bola sobe até
##      "voando" e desce até o chão (40%). Recarga de 2 rodadas, compartilhada.
## 3. Obsessive Lover / Obsessive Hater (duas ações de habilidade, recarga de 2 rodadas
##      compartilhada, efeitos de 3 rodadas):
##      - Lover: escolhe um aliado (dentro de lover_pick_range). Ele ganha +1 ação de habilidade (a
##        cada turno do time enquanto durar) e os chutes do Shidou (Chutar e habilidades) ganham +5%
##        quando vêm de passe dele. O efeito acaba se o amigo passar de lover_break_distance.
##      - Hater: escolhe um inimigo (dentro de hater_pick_range), que perde UMA ação geral sorteada
##        (Correr, Pular, Carrinho, Chutar ou Passe) enquanto durar. Acaba se ele passar de
##        hater_break_distance.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Shidou". Animações opcionais (se faltar alguma, nada quebra):
## "kablamo", "dragon_drive", "big_bang_drive", "demonic_rush", "draconic_header",
## "obsessive_lover", "obsessive_hater".

const SKILL_SHOT: StringName = &"kablamo"           # o mesmo botão vira Dragon Drive / Big Bang Drive
const SKILL_RUSH: StringName = &"demonic_rush"      # e vira Draconic Header depois da corrida
const SKILL_LOVER: StringName = &"obsessive_lover"
const SKILL_HATER: StringName = &"obsessive_hater"

const CD_SHOT: StringName = &"cd_shidou_shot"
const CD_RUSH: StringName = &"cd_shidou_rush"
const CD_OBSESSIVE: StringName = &"cd_shidou_obsessive"

enum ShotVariant { NONE, KABLAMO, DRAGON, BIG_BANG }

@export_group("Kablamo / Dragon Drive / Big Bang Drive")
@export_range(0.0, 1.0) var chance_kablamo: float = 0.40
@export_range(0.0, 1.0) var chance_dragon: float = 0.45
@export_range(0.0, 1.0) var chance_big_bang: float = 0.55
@export var shot_cooldown: int = 3                       # recarga (rodadas), igual para as 3 variantes
@export var kablamo_force_mult: float = 1.6              # o Kablamo é um chute "forte": multiplica a força do chute no chão
@export var kablamo_curve_total_deg: float = 12.0        # curva "bem pouca": desvio total da bola
@export var kablamo_curve_deg_per_sec: float = 25.0      # com que rapidez a bola faz a curva
@export var big_bang_force_mult: float = 1.5             # o Big Bang Drive é um voleio voador mais forte: multiplica a força do chute
@export var big_bang_afterimages: bool = true            # rastro de "imagens fantasma" da bola
@export var big_bang_shake: float = 6.0                  # tremor da câmera no impacto (px; 0 = sem tremor)

@export_group("Demonic Rush / Draconic Header")
@export var rush_speed_mult: float = 1.4                  # quantas vezes mais veloz que o Correr normal
@export_range(0.0, 1.0) var chance_header: float = 0.50
@export var rush_cooldown: int = 2                       # recarga compartilhada com o Draconic Header

@export_group("Obsessive Lover / Hater")
@export var obsessive_rounds: int = 2                    # duração total em rodadas (contando a atual)
@export var obsessive_cooldown: int = 2                  # recarga compartilhada
@export_range(0.0, 1.0) var lover_pass_bonus: float = 0.05   # +5% nos chutes que vêm de passe do amigo
@export var lover_extra_skill_actions: int = 1           # ações de habilidade extras do amigo (por turno)
@export var lover_pick_range: float = 500.0              # alcance para ESCOLHER o aliado (px)
@export var lover_break_distance: float = 800.0          # o efeito acaba se o amigo ficar mais longe que isso (px)
@export var hater_pick_range: float = 500.0              # alcance para ESCOLHER o inimigo (px)
@export var hater_break_distance: float = 800.0          # o efeito acaba se o inimigo ficar mais longe que isso (px)

@export_group("Visual do chute")
## Aura + partículas dos chutes de habilidade. Vazio = usa o estilo padrão do Shidou (veja _make_kick_fx)
@export var kick_fx: KickFX
## Aura do Big Bang Drive (maior e mais intensa). Vazio = usa o estilo padrão (veja _make_big_bang_fx)
@export var big_bang_fx: KickFX


var _base_move_speed: float = 0.0

# Demonic Rush
var _rushing: bool = false
var _rush_round: int = -1              # rodada em que ele usou o Rush (o Header vale só nela)

# Obsessive Lover / Hater
var _lover: Player = null
var _lover_until_round: int = -1
var _friend_pass_valid: bool = false   # o último passe do amigo ainda não foi "gasto" por um chute do Shidou
var _hater_target: Player = null
var _hater_until_round: int = -1
var _hater_action: int = -1            # MatchManager.GeneralAction removida do inimigo

# Texto flutuante (o que a habilidade fez)
var _popup_text: String = ""
var _popup_color: Color = Color.WHITE
var _popup_left: float = 0.0


func _init() -> void:
	character_id = "shidou"         # o menu de formação usa isto para saber quem é quem
	display_name = "Ryusei Shidou"  # aparece no placar de gols e no menu


func _ready() -> void:
	super()
	add_to_group("control_sources")  # os adversários perguntam por aqui se uma ação deles foi removida
	_base_move_speed = move_speed
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	if big_bang_fx == null:
		big_bang_fx = _make_big_bang_fx()
	_hook_manager.call_deferred()


## Roxo/magenta (dragão); as partículas sobem como brasas
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.75, 0.2, 1.0)
	fx.trail_width = 16.0
	fx.particle_color = Color(1.0, 0.6, 0.95)
	fx.amount = 24
	fx.lifetime = 0.55
	fx.speed_min = 20.0
	fx.speed_max = 80.0
	fx.gravity = Vector2(0.0, -50.0)
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 14
	fx.burst_speed = 240.0
	return fx


## Big Bang Drive: rastro grosso, mais partículas e uma explosão forte na saída
func _make_big_bang_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.85, 0.3, 1.0)
	fx.trail_width = 26.0
	fx.particle_color = Color(1.0, 0.75, 1.0)
	fx.amount = 40
	fx.lifetime = 0.5
	fx.speed_min = 30.0
	fx.speed_max = 120.0
	fx.gravity = Vector2(0.0, -80.0)
	fx.spin = 240.0
	fx.scale_min = 0.2
	fx.scale_max = 0.5
	fx.burst_amount = 28
	fx.burst_speed = 380.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.turn_started.connect(_on_turn_started)
		m.pass_completed.connect(_on_pass_completed)


## Todo turno do time dele: o amigo recebe a ação de habilidade extra (enquanto o efeito durar)
func _on_turn_started(turn_team: int) -> void:
	if turn_team != team:
		return
	if is_lover_active():   # confere também a distância; se acabou, já se limpa sozinho
		_lover.extra_skill_left = lover_extra_skill_actions


## Um passe do amigo (rasteiro, alto ou habilidade) vale o bônus no PRÓXIMO chute do Shidou
func _on_pass_completed(passer: Player, _target: Player) -> void:
	if passer == _lover and is_lover_active():
		_friend_pass_valid = true


# ---------- BÔNUS DE CHUTE (Obsessive Lover) ----------

## O efeito vale agora? Confere (e encerra) sozinho: acabaram as rodadas ou o amigo se afastou demais.
## Depois de encerrado por distância, não volta se ele se aproximar de novo.
func is_lover_active() -> bool:
	if _lover == null:
		return false
	var m: MatchManager = _get_manager()
	var alive: bool = is_instance_valid(_lover) and m != null \
		and m.round_number <= _lover_until_round \
		and global_position.distance_to(_lover.global_position) <= lover_break_distance
	if not alive:
		_end_lover()
	return alive


func _end_lover() -> void:
	if _lover != null and is_instance_valid(_lover):
		_lover.extra_skill_left = 0
	_lover = null
	_lover_until_round = -1
	_friend_pass_valid = false
	queue_redraw()


## +5% se a bola veio de um passe do amigo (ela ainda é dele, ou o Shidou já tocou nela depois do passe)
func _shot_bonus() -> float:
	if not is_lover_active() or not _friend_pass_valid:
		return 0.0
	var ball: Ball = _get_ball()
	if ball == null:
		return 0.0
	if ball.last_toucher == _lover or (ball.last_toucher == self and ball.previous_toucher == _lover):
		return lover_pass_bonus
	return 0.0


## Vale também para o Chutar geral: base do tipo de chute + bônus
func get_shot_chance(kind: KickType) -> float:
	return minf(super(kind) + _shot_bonus(), 1.0)


## Depois de qualquer chute dele o bônus do passe foi usado (a chance já foi calculada lá dentro)
func kick_ball(ball: Ball, direction: Vector2, kind: KickType, qte_success: bool = true,
		chance_override: float = -1.0, ignore_self_collision: bool = false,
		fx: KickFX = null, anim: StringName = &"") -> void:
	await super(ball, direction, kind, qte_success, chance_override, ignore_self_collision, fx, anim)
	_friend_pass_valid = false


# ---------- KABLAMO / DRAGON DRIVE / BIG BANG DRIVE ----------

func get_shot_variant() -> ShotVariant:
	var ball: Ball = _get_ball()
	# get_kick_type já confere: derrubado, bola na mão do goleiro, longe demais, altura inalcançável
	if get_kick_type(ball) == KickType.NONE:
		return ShotVariant.NONE
	var ball_level: Heights.Level = ball.get_level()
	match height_level:
		Heights.Level.GROUND:
			if ball_level == Heights.Level.GROUND:
				return ShotVariant.KABLAMO
		Heights.Level.SUSPENDED:
			if ball_level == Heights.Level.SUSPENDED:
				return ShotVariant.DRAGON
			if ball_level == Heights.Level.FLYING:
				return ShotVariant.BIG_BANG
	return ShotVariant.NONE


func _shot_skill_name() -> String:
	match get_shot_variant():
		ShotVariant.DRAGON:
			return "Dragon Drive"
		ShotVariant.BIG_BANG:
			return "Big Bang Drive"
	return "Kablamo"


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

	var base_chance: float = chance_kablamo
	var needs_qte: bool = false
	var qte_kind: KickType = KickType.VOLLEY
	match variant:
		ShotVariant.DRAGON:
			base_chance = chance_dragon
			needs_qte = true
			qte_kind = KickType.VOLLEY    # QTE fácil
		ShotVariant.BIG_BANG:
			base_chance = chance_big_bang
			needs_qte = true
			qte_kind = KickType.FLYING    # QTE difícil

	var qte_ok: bool = true
	if needs_qte and not skips_qte():
		qte_ok = await m.run_qte(qte_kind)

	var chance: float = minf(base_chance + _shot_bonus(), 1.0)
	# Errou o QTE = chute fraquinho, sem aura
	var fx: KickFX = kick_fx if qte_ok else null

	match variant:
		ShotVariant.KABLAMO:
			next_kick_force_mult = kablamo_force_mult
			var bend: float = _curve_side(aim)
			# ignore_self_collision = true: a bola passa direto pelo próprio Shidou
			await kick_ball(ball, aim, KickType.GROUND, qte_ok, chance, true, fx, &"kablamo")
			_curve_ball(ball, bend)   # sem await: a curva acontece enquanto a bola rola
		ShotVariant.DRAGON:
			# A bola sobe até "voando" no meio do caminho e cai até o chão
			var saved_peak: Heights.Level = volley_peak_level
			volley_peak_level = Heights.Level.FLYING
			await kick_ball(ball, aim, KickType.VOLLEY, qte_ok, chance, false, fx, &"dragon_drive")
			volley_peak_level = saved_peak
		ShotVariant.BIG_BANG:
			# Voleio voador normal (a bola cai sozinha, com a gravidade), só que mais forte
			var touches: int = ball.interaction_count
			var origin: Vector2 = ball.global_position
			var origin_height: float = ball.height
			next_kick_force_mult = big_bang_force_mult
			var big_fx: KickFX = big_bang_fx if qte_ok else null
			await kick_ball(ball, aim, KickType.FLYING, qte_ok, chance, false, big_fx, &"big_bang_drive")
			if ball.interaction_count == touches:   # o chute não saiu (ação cancelada)
				return false
			if qte_ok:   # chute de verdade (não o fraquinho): onda de choque, tremor e imagens fantasma
				_spawn_shockwave(origin, origin_height, 95.0, 0.4)
				_shake_camera(big_bang_shake)
				if big_bang_afterimages:
					_ghost_trail(ball)   # sem await: acontece enquanto a bola voa

	start_cooldown(CD_SHOT, shot_cooldown)
	return true


## Para que lado a curva do Kablamo vai: para o lado do gol que o time dele ataca
func _curve_side(aim: Vector2) -> float:
	var field := get_tree().get_first_node_in_group("field") as Field
	if field == null:
		return 1.0
	var attack_dir: float = 1.0 if team == 0 else -1.0
	var goal: Vector2 = field.to_global(Vector2(attack_dir * field.pitch_size.x * 0.5, 0.0))
	var side: float = signf(aim.cross(goal - global_position))
	return side if side != 0.0 else 1.0


## A bola rolando vai entortando um pouquinho (kablamo_curve_total_deg no total). A curva para
## se alguém tocar na bola, o goleiro pegar, ou ela quase parar.
func _curve_ball(ball: Ball, bend_sign: float) -> void:
	var touches: int = ball.interaction_count
	var left: float = kablamo_curve_total_deg
	var time_left: float = 2.0   # trava de segurança
	while left > 0.0 and time_left > 0.0:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		time_left -= delta
		if ball.interaction_count != touches or ball.is_held() or ball.hovering \
				or ball.velocity.length() < 80.0:
			return
		var step: float = minf(kablamo_curve_deg_per_sec * delta, left)
		ball.velocity = ball.velocity.rotated(deg_to_rad(step) * bend_sign)
		left -= step


## Imagens fantasma atrás da bola enquanto ela voa. Para quando alguém toca na bola, o goleiro
## pega, ela fica pairando ou perde a velocidade.
func _ghost_trail(ball: Ball) -> void:
	var touches: int = ball.interaction_count
	var time_left: float = 1.2   # trava de segurança
	while time_left > 0.0:
		_spawn_ghost(ball)
		await get_tree().create_timer(0.03).timeout
		time_left -= 0.03
		if ball.interaction_count != touches or ball.is_held() or ball.hovering \
				or (ball.is_on_ground() and ball.velocity.length() < 120.0):
			return


## Imagem fantasma da bola (some em instantes)
func _spawn_ghost(ball: Ball) -> void:
	var g := _Ghost.new()
	g.radius = ball.ball_radius * 1.3
	g.color = Color(0.85, 0.35, 1.0)
	ball.get_parent().add_child(g)
	g.global_position = ball.global_position + Vector2(0.0, -ball.height)
	g.z_as_relative = false
	g.z_index = int(ball.global_position.y) - 1


## Onda de choque no chão (anel + raios), na altura "lift"
func _spawn_shockwave(at: Vector2, lift: float, radius: float, life: float) -> void:
	var ball: Ball = _get_ball()
	if ball == null:
		return
	var w := _Shockwave.new()
	w.max_radius = radius
	w.life = life
	w.lift = lift
	ball.get_parent().add_child(w)
	w.global_position = at
	w.z_as_relative = false
	w.z_index = int(at.y) + 1


var _shaking: bool = false

## Tremor curto da câmera (se houver uma Camera2D ativa)
func _shake_camera(strength: float) -> void:
	if strength <= 0.0 or _shaking:
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return
	_shaking = true
	var base: Vector2 = cam.offset
	var tw := create_tween()
	for i in 6:
		var amount: float = strength * (1.0 - float(i) / 6.0)
		tw.tween_property(cam, "offset",
			base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount, 0.035)
	tw.tween_property(cam, "offset", base, 0.04)
	tw.finished.connect(func() -> void: _shaking = false)


# ---------- DEMONIC RUSH / DRACONIC HEADER ----------

## O complemento está liberado? Usou o Rush NESTA rodada e agora está ao alcance de uma bola suspensa
func _header_available() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or _rush_round != m.round_number:
		return false
	return get_kick_type(_get_ball()) == KickType.HIGH_BALL   # no chão + bola suspensa ao alcance


## O Draconic Header já foi "pago" pelo Demonic Rush: não gasta outra ação de habilidade
func skill_is_free(skill_id: StringName) -> bool:
	return skill_id == SKILL_RUSH and _header_available()


## Com o Header esperando, o turno não acaba sozinho mesmo sem ações sobrando
func has_free_followup() -> bool:
	return _header_available()


func _use_rush() -> bool:
	if _header_available():
		return await _use_header()
	var m: MatchManager = _get_manager()
	if m == null or height_level != Heights.Level.GROUND:
		return false
	if not await play_action(&"demonic_rush"):
		return false

	# Um Correr (mesmo tempo) mais veloz. Não conta no limite de Correr do turno: é uma habilidade.
	_rushing = true
	queue_redraw()
	move_speed = _base_move_speed * rush_speed_mult
	start_run()
	await run_finished
	move_speed = _base_move_speed
	runs_this_turn = maxi(0, runs_this_turn - 1)
	_rushing = false
	queue_redraw()

	if m.match_over:
		return false
	_rush_round = m.round_number   # libera o Draconic Header até o fim desta rodada
	start_cooldown(CD_RUSH, rush_cooldown)
	return true


## Draconic Header: chute reto, a bola sobe até "voando" e desce até o chão
func _use_header() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: o Header continua liberado e não gasta nada
	if not _header_available():   # a bola pode ter saído do alcance enquanto ele mirava
		return false

	var ball: Ball = _get_ball()
	var chance: float = minf(chance_header + _shot_bonus(), 1.0)
	var saved_peak: Heights.Level = volley_peak_level
	volley_peak_level = Heights.Level.FLYING
	await kick_ball(ball, aim, KickType.VOLLEY, true, chance, false, kick_fx, &"draconic_header")
	volley_peak_level = saved_peak

	_rush_round = -1   # o complemento foi usado
	start_cooldown(CD_RUSH, rush_cooldown)
	return true


# ---------- OBSESSIVE LOVER / HATER ----------

## Mesma ideia do Lover: acaba pelas rodadas ou se o inimigo ficar longe demais (e não volta)
func is_hater_active() -> bool:
	if _hater_target == null:
		return false
	var m: MatchManager = _get_manager()
	var alive: bool = is_instance_valid(_hater_target) and m != null \
		and m.round_number <= _hater_until_round \
		and global_position.distance_to(_hater_target.global_position) <= hater_break_distance
	if not alive:
		_end_hater()
	return alive


func _end_hater() -> void:
	_hater_target = null
	_hater_until_round = -1
	_hater_action = -1
	queue_redraw()


## Chamado pelo Player do inimigo: "esta ação geral foi removida de mim?"
func blocks_general_action(p: Player, action: int) -> bool:
	return is_hater_active() and p == _hater_target and action == _hater_action


func _use_obsessive(hater: bool) -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false

	# Mostra o círculo de alcance e só deixa escolher quem está dentro dele
	var pick_range: float = hater_pick_range if hater else lover_pick_range
	var target: Player = await m.pick_ally_for_skill(self, pick_range, hater)
	if target == null:
		return false   # cancelou: não gasta a ação

	if not await play_action(&"obsessive_hater" if hater else &"obsessive_lover"):
		return false

	var until_round: int = m.round_number + obsessive_rounds - 1   # a rodada atual conta
	if hater:
		# Sorteia UMA ação geral para tirar do inimigo (o Levantar não entra: só existe para quem caiu)
		var options: Array[int] = [
			MatchManager.GeneralAction.RUN, MatchManager.GeneralAction.JUMP,
			MatchManager.GeneralAction.SLIDE, MatchManager.GeneralAction.SHOOT,
			MatchManager.GeneralAction.PASS]
		_hater_target = target
		_hater_until_round = until_round
		_hater_action = options.pick_random()
		_show_popup("%s: sem %s" % [target.get_display_name(),
			MatchManager.GENERAL_ACTION_NAMES[_hater_action]], Color(1.0, 0.45, 0.4))
	else:
		_lover = target
		_lover_until_round = until_round
		_friend_pass_valid = false
		_lover.extra_skill_left = lover_extra_skill_actions   # já vale neste turno
		_show_popup("%s é o amigo!" % target.get_display_name(), Color(1.0, 0.6, 0.85))

	start_cooldown(CD_OBSESSIVE, obsessive_cooldown)
	queue_redraw()
	await get_tree().create_timer(0.5).timeout   # tempo de ler o resultado
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_SHOT, "name": skill_label(_shot_skill_name(), CD_SHOT)})
	var rush_name: String = "Draconic Header" if _header_available() \
		else skill_label("Demonic Rush", CD_RUSH)
	list.append({"id": SKILL_RUSH, "name": rush_name})
	var lover_name: String = "Obsessive Lover (ativo)" if is_lover_active() \
		else skill_label("Obsessive Lover", CD_OBSESSIVE)
	list.append({"id": SKILL_LOVER, "name": lover_name})
	var hater_name: String = "Obsessive Hater (ativo)" if is_hater_active() \
		else skill_label("Obsessive Hater", CD_OBSESSIVE)
	list.append({"id": SKILL_HATER, "name": hater_name})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_SHOT:
			return not is_on_cooldown(CD_SHOT) and get_shot_variant() != ShotVariant.NONE
		SKILL_RUSH:
			if _header_available():   # o complemento ignora a recarga que o próprio Rush começou
				return true
			return not is_on_cooldown(CD_RUSH) and height_level == Heights.Level.GROUND
		SKILL_LOVER:
			# sem reativar enquanto está valendo nem durante a recarga
			return not is_lover_active() and not is_on_cooldown(CD_OBSESSIVE) \
				and _has_other(true, lover_pick_range)
		SKILL_HATER:
			return not is_hater_active() and not is_on_cooldown(CD_OBSESSIVE) \
				and _has_other(false, hater_pick_range)
	return false


## Existe algum companheiro (same_team) ou inimigo dentro do alcance de escolha?
func _has_other(same_team: bool, range_px: float) -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other != self and (other.team == team) == same_team \
				and global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_SHOT:
			return await _use_shot_skill()
		SKILL_RUSH:
			return await _use_rush()
		SKILL_LOVER:
			return await _use_obsessive(false)
		SKILL_HATER:
			return await _use_obsessive(true)
	return false


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	move_speed = _base_move_speed
	_rushing = false
	_rush_round = -1
	_end_lover()
	_end_hater()
	_popup_left = 0.0
	queue_redraw()


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	if _popup_left > 0.0:
		_popup_left -= delta
	# Confere TODO frame (para o efeito acabar no instante em que o alvo passa da distância máxima)
	var lover_on: bool = is_lover_active()
	var hater_on: bool = is_hater_active()
	# Redesenha enquanto há algo animado (linhas do Lover/Hater, aura do Rush, texto)
	if _popup_left > 0.0 or _rushing or lover_on or hater_on:
		queue_redraw()


func _show_popup(text: String, color: Color) -> void:
	_popup_text = text
	_popup_color = color
	_popup_left = 1.6
	queue_redraw()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Rush: aura vermelha enquanto ele corre veloz
	if _rushing:
		draw_arc(center, placeholder_radius + 6.0, 0.0, TAU, 40, Color(1.0, 0.25, 0.2, 0.9), 3.0)

	# Lover: linha e anel rosa no amigo (+ círculo fino da distância máxima)
	if is_lover_active():
		_draw_link(_lover, Color(1.0, 0.45, 0.8), lover_break_distance)

	# Hater: linha e anel vermelho escuro no inimigo (+ círculo fino da distância máxima)
	if is_hater_active():
		_draw_link(_hater_target, Color(0.9, 0.15, 0.2), hater_break_distance)

	# Resultado da habilidade, flutuando em cima do Shidou
	if _popup_left > 0.0:
		var alpha: float = clampf(_popup_left / 0.4, 0.0, 1.0)
		var y: float = -placeholder_radius - 46.0 - height - (1.6 - _popup_left) * 10.0
		draw_string(ThemeDB.fallback_font, Vector2(-130.0, y), _popup_text,
			HORIZONTAL_ALIGNMENT_CENTER, 260.0, 18, Color(_popup_color, alpha))


## Linha fina até o alvo + anel tracejado nele + círculo da distância máxima. Quando o alvo
## chega perto do limite, a linha esquenta para amarelo (aviso de que o efeito está acabando).
func _draw_link(other: Player, color: Color, limit: float) -> void:
	if other == null or not is_instance_valid(other):
		return
	var from := Vector2(0.0, -height)
	var to: Vector2 = to_local(other.global_position) + Vector2(0.0, -other.height)
	var ratio: float = global_position.distance_to(other.global_position) / limit
	var line_color: Color = color.lerp(Color(1.0, 0.9, 0.2), clampf((ratio - 0.7) / 0.3, 0.0, 1.0))
	draw_arc(Vector2.ZERO, limit, 0.0, TAU, 96, Color(color, 0.18), 2.0)
	draw_line(from, to, Color(line_color, 0.55), 2.0)
	var segments: int = 12
	for i in segments:
		if i % 2 == 0:
			var a0: float = TAU * float(i) / float(segments)
			var a1: float = TAU * float(i + 1) / float(segments)
			draw_arc(to, other.placeholder_radius + 12.0, a0, a1, 6, Color(line_color, 0.95), 3.0)


# ====================================================================
# Efeitos visuais do Big Bang Drive
# ====================================================================

## Imagem fantasma: círculo que encolhe e some
class _Ghost extends Node2D:
	var life: float = 0.28
	var radius: float = 14.0
	var color: Color = Color(0.85, 0.35, 1.0)
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = _t / life
		draw_circle(Vector2.ZERO, radius * (1.0 - 0.5 * k), Color(color, 0.5 * (1.0 - k)))


## Onda de choque: anel achatado (visão de cima inclinada) que se expande + raios
class _Shockwave extends Node2D:
	var life: float = 0.4
	var max_radius: float = 90.0
	var lift: float = 0.0
	var color: Color = Color(0.85, 0.35, 1.0)
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = _t / life
		var e: float = 1.0 - pow(1.0 - k, 3.0)   # abre rápido e desacelera
		var r: float = max_radius * e
		var a: float = 1.0 - k
		var c := Vector2(0.0, -lift)
		draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(color, a), 6.0 * (1.0 - k) + 1.0)
		draw_arc(Vector2.ZERO, r * 0.6, 0.0, TAU, 48, Color(1.0, 0.85, 1.0, a * 0.7), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 10:
			var ang: float = TAU * float(i) / 10.0 + 0.3
			var d := Vector2(cos(ang), sin(ang) * 0.55)
			draw_line(c + d * r * 0.55, c + d * r * 1.05, Color(color, a), 2.0)
