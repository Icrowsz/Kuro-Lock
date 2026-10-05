class_name Aiku
extends Player
## Aiku. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Snake Lunge (ação de habilidade, 2 variantes automáticas pela altura do
##      PRÓPRIO Aiku; recarga de 3 rodadas, compartilhada entre as variantes,
##      contada a partir do FIM do efeito):
##      - Aiku no chão: Snake Lunge -> escolhe um inimigo "no chão" ao alcance, vai até
##        ele (bote) e o TRAVA por 3 rodadas (nenhuma ação geral nem habilidade), ou até
##        o Aiku se afastar demais dele (o que vier primeiro).
##      - Aiku suspenso ou voando: Bloom -> mesma ideia com um inimigo "suspenso" ou
##        "voando" ao alcance: derruba ele (como um carrinho) e trava só a HABILIDADE
##        dele por 2 rodadas (as ações gerais ficam livres assim que ele levantar).
## 2. Viper Tackle (ação de habilidade): um carrinho bem mais longo que o normal e que
##      também pode ser feito com o Aiku SUSPENSO (o Carrinho comum só funciona no chão).
##      Derruba os inimigos no caminho (no mesmo nível do Aiku) normalmente. Se encontrar
##      a bola pelo caminho:
##      - Bola no chão -> dá a ação Passe normal (escolhe um companheiro clicando nele),
##        só que com alcance reduzido (sem gastar a ação geral de Passe); sem ninguém
##        por perto, ou se cancelar, a bola só fica solta ali.
##      - Bola suspensa -> QTE fácil; acertando, pode mirar um chute fraco na bola.
## 3. Serpent Wall (ação de habilidade): se a bola estiver ao alcance e "suspensa" ou
##      "voando", o Aiku salta até ela e faz um QTE difícil; acertando, dá um chute
##      fraco nela (mira a direção).
##
## Observação: o pedido original não deu recarga para o Viper Tackle nem para o Serpent
## Wall, então usei um valor padrão razoável (2 rodadas pros dois) — ajuste à vontade
## nos @export abaixo.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Aiku" (o nome aparece no placar de gols).

const SKILL_LUNGE: StringName = &"snake_lunge"
const SKILL_VIPER: StringName = &"viper_tackle"
const SKILL_WALL: StringName = &"serpent_wall"

## Grupos de recarga (as variantes do Snake Lunge/Bloom compartilham o mesmo)
const CD_LUNGE: StringName = &"cd_lunge"
const CD_VIPER: StringName = &"cd_viper"
const CD_WALL: StringName = &"cd_wall"

@export_group("Snake Lunge / Bloom")
@export var lunge_range: float = 230.0          # alcance para escolher o inimigo
@export var lunge_dash_time: float = 0.25       # duração do "bote" até perto do inimigo
@export var lunge_stop_distance: float = 40.0   # até onde o Aiku chega perto do inimigo
@export var lunge_leash_range: float = 160.0    # Aiku se afastar além disso solta o inimigo antes da hora
@export var lunge_rounds: int = 3               # Snake Lunge (chão): rodadas totalmente travado
@export var bloom_rounds: int = 2               # Bloom (suspenso/voando): rodadas com a habilidade travada
@export var lunge_cooldown: int = 3             # recarga, contada a partir do FIM do efeito (as 2 variantes compartilham)

@export_group("Viper Tackle")
@export var viper_aim_range: float = 90.0        # tamanho da seta de mira (direção do bote)
@export var viper_distance: float = 250.0        # bem mais longe que o Carrinho normal
@export var viper_duration: float = 0.65
@export var viper_hit_radius: float = 60.0       # alcance para derrubar inimigos e "encontrar" a bola
@export var viper_ball_pass_range: float = 300.0 # alcance do passe (igual à ação Passe, só que menor)
@export var viper_weak_kick_speed: float = 600.0 # força do "chute fraco" (bola suspensa, pós-QTE)
@export_range(0.0, 1.0) var viper_weak_kick_chance: float = 0.20
@export var viper_cooldown: int = 2              # não especificado no pedido original; ajuste à vontade

@export_group("Serpent Wall")
@export var wall_range: float = 220.0            # alcance para alcançar a bola suspensa/voando
@export var wall_jump_time: float = 0.2          # duração do salto até a bola
@export var wall_weak_kick_speed: float = 300.0
@export_range(0.0, 1.0) var wall_weak_kick_chance: float = 0.3
@export var wall_cooldown: int = 2               

@export_group("Visual do chute")
## Aura + partículas do Viper Tackle / Serpent Wall. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

## Inimigo atualmente travado pelo Snake Lunge/Bloom deste Aiku (null = nenhum)
var _lunge_target: Player = null
## Pulso visual do bote (1 -> 0) e o ponto do inimigo atingido
var _pulse: float = 0.0
var _pulse_target: Vector2 = Vector2.ZERO


func _init() -> void:
	character_id = "aiku"    # o menu de formação usa isto para saber quem é quem
	display_name = "Aiku"    # aparece no placar de gols e no menu (troque aqui se quiser o nome completo)


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()


## Verde-veneno; as partículas "escorregam" para os lados, feito escamas
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.45, 0.65, 0.1)
	fx.additive = false   # o campo é verde: mistura normal mantém a cor visível
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.DOT
	fx.particle_color = Color(0.8, 0.95, 0.4)
	fx.amount = 20
	fx.lifetime = 0.5
	fx.speed_min = 15.0
	fx.speed_max = 65.0
	fx.swirl = 90.0
	fx.damping = 18.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 12
	fx.burst_speed = 190.0
	return fx


# ---------- SNAKE LUNGE / BLOOM ----------

## 0 = "no chão", 1 = "suspenso ou voando" — a variante depende do nível do PRÓPRIO Aiku
func _lunge_bucket(level: Heights.Level) -> int:
	return 0 if level == Heights.Level.GROUND else 1


func _lunge_skill_name() -> String:
	return "Bloom" if _lunge_bucket(height_level) == 1 else "Snake Lunge"


## O inimigo está no mesmo "nível" do Aiku (os dois no chão, ou os dois suspensos/voando)
## e não está derrubado (já incapacitado, não faz sentido travar de novo)
func _is_valid_lunge_target(enemy: Player) -> bool:
	return not enemy.is_down and _lunge_bucket(height_level) == _lunge_bucket(enemy.height_level)


func _has_lunge_target() -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team:
			continue
		if global_position.distance_to(other.global_position) > lunge_range:
			continue
		if _is_valid_lunge_target(other):
			return true
	return false


func _use_lunge_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or not _has_lunge_target():
		return false

	var is_bloom: bool = _lunge_bucket(height_level) == 1
	var target: Player = await m.pick_ally_for_skill(
		self, lunge_range, true, Callable(self, "_is_valid_lunge_target"))
	if target == null:
		return false   # cancelou: não gasta a ação

	# O inimigo pode ter mudado de altura enquanto o Aiku escolhia: confere de novo
	if not _is_valid_lunge_target(target):
		return false

	face_towards(target.global_position - global_position)
	await play_action(&"bloom" if is_bloom else &"snake_lunge", ANIM_SLIDE)
	await _dash_to(target)
	_play_pulse(target.global_position)

	if is_bloom:
		target.knock_down()
		target.apply_lock(self, bloom_rounds, true)    # só a habilidade fica travada
	else:
		target.apply_lock(self, lunge_rounds, false)   # trava tudo

	_lunge_target = target
	return true


## O "bote": o Aiku vai até ficar bem perto do alvo (sem entrar por cima dele)
func _dash_to(target: Player) -> void:
	var offset: Vector2 = global_position - target.global_position
	var dist: float = offset.length()
	if dist < 1.0:
		return
	var dir: Vector2 = offset / dist
	var dest: Vector2 = target.global_position + dir * lunge_stop_distance
	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", dest, lunge_dash_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


## Fica de olho no inimigo travado: se o efeito acabar sozinho (rodadas esgotaram) ou
## se o Aiku se afastar demais (solta antes da hora), inicia a recarga.
func _process(delta: float) -> void:
	super(delta)
	if _lunge_target == null:
		return
	if not is_instance_valid(_lunge_target) or _lunge_target.locked_by != self:
		_lunge_target = null
		return
	if not _lunge_target.is_skill_locked():
		_finish_lunge_effect(false)   # expirou sozinho: a recarga já pode valer esta rodada
		return
	if global_position.distance_to(_lunge_target.global_position) > lunge_leash_range:
		_lunge_target.clear_lock()
		_finish_lunge_effect(true)    # Aiku se afastou: a recarga só começa na rodada seguinte


func _finish_lunge_effect(early: bool) -> void:
	var m: MatchManager = _get_manager()
	var round_now: int = m.round_number if m else 0
	start_cooldown(CD_LUNGE, lunge_cooldown, round_now + 1 if early else round_now)
	_lunge_target = null


# ---------- VIPER TACKLE ----------

func _use_viper_tackle() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false

	# Primeiro mira a direção do bote; só gasta a ação se o jogador confirmar
	var dir: Vector2 = await m.aim_for_skill(self, viper_aim_range)
	if dir == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	face_towards(dir)
	await play_action(&"viper_tackle", ANIM_SLIDE)
	await _run_viper_tackle(dir)
	start_cooldown(CD_VIPER, viper_cooldown)
	return true


## Corre bem mais longe que o Carrinho normal, derrubando inimigos no mesmo nível pelo
## caminho; se encontrar a bola, para ali e resolve o encontro (passe curto ou QTE + chute).
func _run_viper_tackle(direction: Vector2) -> void:
	var level: Heights.Level = height_level
	var dir: Vector2 = direction.normalized()
	var hit_enemies: Array[Player] = []
	var ball: Ball = _get_ball()
	var ball_hit: bool = false
	var elapsed: float = 0.0

	while elapsed < viper_duration:
		await get_tree().physics_frame
		var dt: float = get_physics_process_delta_time()
		elapsed += dt
		var frac: float = clampf(1.0 - elapsed / viper_duration, 0.0, 1.0)
		velocity = dir * (2.0 * viper_distance / viper_duration) * frac
		move_and_slide()
		queue_redraw()

		for other: Player in get_tree().get_nodes_in_group("players"):
			if other.team == team or other.is_down or other in hit_enemies:
				continue
			if other.height_level != level:
				continue
			if global_position.distance_to(other.global_position) <= viper_hit_radius:
				hit_enemies.append(other)
				other.knock_down()

		if not ball_hit and ball != null and not ball.is_held() \
				and global_position.distance_to(ball.global_position) <= viper_hit_radius:
			ball_hit = true
			break

	velocity = Vector2.ZERO

	if ball_hit:
		await _resolve_viper_ball(ball, dir)


## Existe algum companheiro dentro do alcance reduzido do passe do Viper Tackle?
func _has_ally_in_pass_range(range_px: float) -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self or other.team != team:
			continue
		if global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


## A bola foi encontrada no meio do bote: resolve conforme a altura dela
func _resolve_viper_ball(ball: Ball, fallback_dir: Vector2) -> void:
	var m: MatchManager = _get_manager()
	var level: Heights.Level = ball.get_level()

	if level == Heights.Level.GROUND:
		if m == null or not _has_ally_in_pass_range(viper_ball_pass_range):
			return   # ninguém por perto para receber: a bola fica solta ali mesmo
		var target: Player = await m.pick_ally_for_skill(self, viper_ball_pass_range)
		if target == null:
			return   # não quis passar: a bola fica solta ali mesmo
		await m.run_ground_pass(self, target, ball)   # igual à ação Passe, só que com alcance menor
		return

	if level == Heights.Level.SUSPENDED:
		var qte_ok: bool = true
		if m and not skips_qte():
			qte_ok = await m.run_qte(KickType.VOLLEY)   # QTE fácil
		var aim: Vector2 = fallback_dir
		if qte_ok and m:
			var picked: Vector2 = await m.aim_for_skill(self, viper_aim_range)
			if picked != Vector2.ZERO:
				aim = picked
		var dir: Vector2 = aim.normalized() if aim.length() > 0.01 else fallback_dir
		var speed: float = viper_weak_kick_speed
		if not qte_ok:
			speed *= qte_fail_power_mult
			dir = dir.rotated(deg_to_rad(randf_range(-qte_fail_max_angle, qte_fail_max_angle)))
		ball.kick_ground(dir, speed, self, viper_weak_kick_chance)
		if qte_ok:
			ball.play_fx(kick_fx)
		else:
			knock_down()   # errou o QTE: se desequilibra, igual a um chute normal


# ---------- SERPENT WALL ----------

func _has_wall_target() -> bool:
	if is_down:
		return false
	var ball: Ball = _get_ball()
	if ball == null or ball.is_held():
		return false
	var level: Heights.Level = ball.get_level()
	if level != Heights.Level.SUSPENDED and level != Heights.Level.FLYING:
		return false
	return global_position.distance_to(ball.global_position) <= wall_range


func _use_serpent_wall() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or not _has_wall_target():
		return false

	face_towards(ball.global_position - global_position)
	await play_action(&"serpent_wall", ANIM_JUMP)

	# Salto até a bola: sobe ao nível dela e se aproxima
	var target_level: Heights.Level = ball.get_level()
	height_level = target_level
	var approach: Vector2 = ball.global_position
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "height", Heights.to_height(target_level), wall_jump_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", approach, wall_jump_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished

	var qte_ok: bool = true
	if not skips_qte():
		qte_ok = await m.run_qte(KickType.FLYING)   # QTE difícil

	if qte_ok:
		var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
		if aim == Vector2.ZERO:
			aim = Vector2(_default_facing(), 0.0)   # não mirou: segue atacando para a frente
		ball.register_touch(self)
		ball.kick_ground(aim, wall_weak_kick_speed, self, wall_weak_kick_chance)
		ball.play_fx(kick_fx)
	else:
		knock_down()   # errou o QTE difícil: cai, igual a um chute normal

	land()
	start_cooldown(CD_WALL, wall_cooldown)
	return true


# ---------- VISUAL: PULSO (bote do Snake Lunge/Bloom) ----------

func _play_pulse(target_global: Vector2) -> void:
	_pulse_target = target_global
	_pulse = 1.0
	var tw: Tween = create_tween()
	tw.tween_method(_set_pulse, 1.0, 0.0, 0.4)


func _set_pulse(value: float) -> void:
	_pulse = value
	queue_redraw()


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_LUNGE, "name": skill_label(_lunge_skill_name(), CD_LUNGE)})
	list.append({"id": SKILL_VIPER, "name": skill_label("Viper Tackle", CD_VIPER)})
	list.append({"id": SKILL_WALL, "name": skill_label("Serpent Wall", CD_WALL)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_LUNGE:
			return not is_on_cooldown(CD_LUNGE) and _has_lunge_target()
		SKILL_VIPER:
			return not is_on_cooldown(CD_VIPER) \
				and (height_level == Heights.Level.GROUND or height_level == Heights.Level.SUSPENDED)
		SKILL_WALL:
			return not is_on_cooldown(CD_WALL) and _has_wall_target()
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_LUNGE:
			return await _use_lunge_skill()
		SKILL_VIPER:
			return await _use_viper_tackle()
		SKILL_WALL:
			return await _use_serpent_wall()
	return false


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()   # também solta a trava que o Aiku sofreu, se houver (clear_lock)
	if _lunge_target != null and is_instance_valid(_lunge_target):
		_lunge_target.clear_lock()
	_lunge_target = null
	_pulse = 0.0
	queue_redraw()


# ---------- VISUAL ----------

func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Pulso do bote (Snake Lunge/Bloom): anel que se expande e um raio até o inimigo
	if _pulse > 0.0:
		var ring: float = lerpf(placeholder_radius + 60.0, placeholder_radius, _pulse)
		draw_arc(center, ring, 0.0, TAU, 40, Color(0.55, 0.78, 0.2, _pulse), 3.0)
		draw_line(center, to_local(_pulse_target), Color(0.55, 0.78, 0.2, _pulse * 0.8), 2.0)
