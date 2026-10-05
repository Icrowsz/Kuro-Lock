class_name Ball
extends Node2D
## Bola 2.5D: visual 2D, física 3D.
## - position (Node2D)  -> posição no CHÃO (x, y do campo)
## - height             -> altura no ar (eixo Z)
## - velocity           -> velocidade no chão (x, y)
## - vel_z              -> velocidade vertical
##
## Os limites do campo, traves e gols agora são responsabilidade do Field.
##
## Estrutura da cena:
## Ball (Node2D)  <- este script
##  ├─ Shadow (Sprite2D)  -> sombra (círculo escuro achatado)
##  └─ Sprite (Sprite2D)  -> a bola

signal bounced(strength: float)
## A bola foi reposta (ex: saída de bola depois de um gol)
signal was_reset

## Chute sem disputa com o goleiro (passes, lançamentos)
const NO_SHOT: float = -1.0
## Chance padrão de um chute vencer o goleiro
const DEFAULT_SHOT_CHANCE: float = 0.30

@export_group("Física")
@export var gravity: float = 1200.0          # px/s²
@export var bounce_factor: float = 0.65      # quanto da velocidade vertical sobra no quique
@export var min_bounce_speed: float = 60.0   # abaixo disso a bola para de quicar
@export var ground_friction: float = 1.2     # atrito rolando no chão
@export var air_drag: float = 0.15           # resistência do ar
@export var stop_speed: float = 8.0          # ajuda a bola a parar de vez

@export_group("Colisão com jogadores")
@export var collide_with_players: bool = true
@export var collision_radius: float = 12.0   # raio da bola no chão (o jogador usa o body_radius dele)
@export var player_bounce: float = 0.4       # 0 = a bola "gruda" na velocidade de quem bate; 1 = quique total

@export_group("Visual")
@export var ball_radius: float = 12.0        # raio visual (px) para encostar no chão
@export var shadow_base_scale: float = 1.0
@export var shadow_min_scale: float = 0.5    # sombra encolhe com a altura
@export var max_shadow_height: float = 300.0
@export var rotate_with_speed: bool = true

var height: float = 0.0
var vel_z: float = 0.0
var velocity: Vector2 = Vector2.ZERO

## Quantos quiques ainda são permitidos neste voo (-1 = sem limite, o normal). Habilidades como o
## Bon! do Bachira põem 1: a bola quica UMA vez e na segunda queda já fica rolando. O valor
## volta sozinho para -1 quando a bola para de quicar, é chutada, segurada ou reposta.
var bounces_left: int = -1

## Bola "pairando": a física (gravidade/atrito) fica desligada e quem controla
## é o hover_to (ex: passe alto). Qualquer chute ou reset solta a bola.
var hovering: bool = false
var _hover_tween: Tween

## Desliga a colisão com jogadores temporariamente (ex: durante o voo do passe rasteiro)
var collisions_paused: bool = false
## Quem acabou de chutar a bola não colide com ela até ela se afastar
var _ignore_player: Node2D = null
## Jogador que a bola ignora por completo até ela parar (ex: Backheel Shot do Isagi,
## em que a bola atravessa o próprio chutador). Diferente do _ignore_player, não
## volta a colidir só porque a bola se afastou.
var _sticky_ignore_player: Node2D = null

## Os dois últimos jogadores DIFERENTES a interagirem com a bola (chute, passe,
## carrinho ou contato físico). Usados para saber quem fez o gol e a assistência.
var last_toucher: Player = null
var previous_toucher: Player = null

## Quantas vezes alguém interagiu com a bola (conta TODO toque, até do mesmo jogador).
## O goleiro usa isto para saber se "algo interagiu com a bola" enquanto se prepara.
var interaction_count: int = 0

## Chute em andamento: chance de vencer o goleiro (NO_SHOT = a bola não está num chute).
## O goleiro sorteia contra esta chance quando o chute entra na área e a consome.
var pending_shot_chance: float = NO_SHOT
var shot_team: int = -1   # time de quem chutou (-1 = desconhecido)

## Segurada por alguém (o goleiro): física desligada, a bola acompanha quem a segura
var held_by: Node2D = null

## Presa por um feitiço (Arresto Momentum do Ness): só o time de quem lançou consegue
## interagir com a bola. null = livre. Quem lançou é quem limpa (ou release_hover()).
var spell_owner: Player = null

## Mantém a aura/partículas da habilidade mesmo com a bola pairando (ex: Alohomora do Ness,
## que leva a bola pelo ar sem usar a física)
var fx_during_hover: bool = false

## Rastro suave atrás da bola (ligado durante os passes)
@export_group("Rastro")
@export var trail_length: int = 12
var trail_enabled: bool = false
var _trail: Array[Vector2] = []
var _hover_time: float = 0.0
var _prev_global: Vector2 = Vector2.ZERO

## FX de habilidade (aura + partículas). Os 3 nós são criados UMA vez, na primeira
## habilidade usada, e reaproveitados em todos os chutes seguintes.
@export_group("FX de habilidade")
@export var fx_stop_speed: float = 40.0   # rolando abaixo dessa velocidade, o efeito acaba
var _fx_active: bool = false
var _fx_touches: int = 0
var _fx_step_sq: float = 16.0
var _fx_max_points: int = 16
var _styled_fx: KickFX = null
var _fx_trail: Line2D
var _fx_stream: CPUParticles2D
var _fx_burst: CPUParticles2D

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	add_to_group("ball")  # o carrinho (e outras ações) encontram a bola por este grupo
	_prev_global = global_position


func _physics_process(delta: float) -> void:
	if not hovering:
		_apply_vertical(delta)
		_apply_ground_motion(delta)
		_collide_with_players()
		_expire_shot()
	_update_visuals(delta)


# ---------- FÍSICA ----------

func _apply_vertical(delta: float) -> void:
	# Só aplica gravidade se estiver no ar ou subindo
	if height > 0.0 or vel_z > 0.0:
		vel_z -= gravity * delta
		height += vel_z * delta

		if height <= 0.0:
			height = 0.0
			var impact: float = absf(vel_z)
			if impact > min_bounce_speed and bounces_left != 0:
				vel_z = -vel_z * bounce_factor
				velocity *= 0.9  # perde um pouco de velocidade horizontal ao quicar
				if bounces_left > 0:
					bounces_left -= 1
				bounced.emit(impact)
			else:
				vel_z = 0.0
				bounces_left = -1   # acabou o voo: o limite não vale para o próximo


## Rastro: guarda onde a bola esteve nos últimos frames; desligado, ele vai sumindo
func _update_trail() -> void:
	if trail_enabled:
		_trail.append(sprite.global_position)
		if _trail.size() > trail_length:
			_trail.pop_front()
		queue_redraw()
	elif not _trail.is_empty():
		_trail.pop_front()
		queue_redraw()


func _draw() -> void:
	var n: int = _trail.size()
	for i in range(1, n):
		var t: float = float(i) / float(n)
		draw_line(to_local(_trail[i - 1]), to_local(_trail[i]),
			Color(1.0, 1.0, 1.0, 0.45 * t), 1.0 + 4.0 * t)


## Colisão círculo x círculo com os jogadores que estão no MESMO nível de altura
## (quem pulou passa por baixo de uma bola rasteira, e vice-versa). Empurra a bola
## para fora do jogador e reflete a velocidade relativa, então um jogador correndo
## empurra a bola e uma bola rolando bate e volta em quem está parado.
func _collide_with_players() -> void:
	if not collide_with_players or collisions_paused:
		return
	var level: Heights.Level = get_level()
	for p in get_tree().get_nodes_in_group("players"):
		if p.height_level != level or _is_ignored(p):
			continue
		var min_dist: float = collision_radius + p.body_radius
		var offset: Vector2 = global_position - p.global_position
		var dist: float = offset.length()
		if dist >= min_dist:
			continue
		register_touch(p as Player)
		var normal: Vector2 = offset / dist if dist > 0.001 else Vector2.RIGHT
		global_position = p.global_position + normal * min_dist
		var approach: float = (velocity - p.velocity).dot(normal)
		if approach < 0.0:
			velocity -= normal * approach * (1.0 + player_bounce)


func _is_ignored(p: Node2D) -> bool:
	if p == _sticky_ignore_player:
		if velocity.length() <= stop_speed + 1.0:
			_sticky_ignore_player = null   # a bola parou: volta a colidir normalmente
			return false
		return true
	if p != _ignore_player:
		return false
	if global_position.distance_to(p.global_position) > collision_radius + p.body_radius + 6.0:
		_ignore_player = null  # a bola já se afastou: volta a colidir normalmente
		return false
	return true


func _apply_ground_motion(delta: float) -> void:
	if is_on_ground():
		velocity = velocity.move_toward(
			Vector2.ZERO,
			velocity.length() * ground_friction * delta + stop_speed * delta
		)
	else:
		velocity *= maxf(0.0, 1.0 - air_drag * delta)

	position += velocity * delta


# ---------- VISUAL ----------

func _update_visuals(delta: float) -> void:
	# A bola sobe na tela conforme a altura; a sombra fica no chão
	# Pairando (sem tween): balança de leve para cima e para baixo
	var bob: float = 0.0
	if hovering and not (_hover_tween and _hover_tween.is_valid()):
		_hover_time += delta
		bob = sin(_hover_time * 3.0) * 3.0
	sprite.position = Vector2(0, -height - ball_radius + bob)
	shadow.position = Vector2.ZERO

	var t: float = clampf(height / max_shadow_height, 0.0, 1.0)
	var s: float = lerpf(shadow_base_scale, shadow_min_scale, t)
	shadow.scale = Vector2(s, s * 0.5)  # achatada
	shadow.modulate.a = lerpf(0.6, 0.25, t)

	# Rotação proporcional à velocidade (rolando)
	if rotate_with_speed:
		var vx: float = velocity.x
		if hovering and delta > 0.0:
			vx = (global_position.x - _prev_global.x) / delta  # gira também quando voa pelo tween
		sprite.rotation += vx * delta * 0.05
	_prev_global = global_position

	# Profundidade: quem está mais embaixo na tela fica na frente
	z_index = int(global_position.y)

	_update_trail()
	_update_fx()


# ---------- FX DE HABILIDADE (aura + partículas) ----------

## Liga a aura + partículas do `fx`. Chame logo DEPOIS do kick()/kick_ground().
## Termina sozinho: alguém toca na bola, ela é segurada ou para de rolar.
func play_fx(fx: KickFX) -> void:
	if fx == null:
		return
	_ensure_fx_nodes()
	_fx_active = true
	_fx_touches = interaction_count
	_fx_step_sq = fx.trail_min_step * fx.trail_min_step
	_fx_max_points = fx.trail_points

	# Só reconfigura quando o estilo muda (ex: outro personagem chutou)
	if fx != _styled_fx:
		_styled_fx = fx
		_fx_trail.width = fx.trail_width
		_fx_trail.width_curve = fx.get_width_curve()
		_fx_trail.gradient = fx.get_trail_gradient()
		_fx_trail.material = fx.get_blend_material()
		_style_particles(_fx_stream, fx, false)
		_style_particles(_fx_burst, fx, true)

	_fx_trail.clear_points()
	_fx_trail.visible = true
	_fx_stream.position = sprite.position
	_fx_burst.position = sprite.position
	_fx_stream.emitting = true
	_fx_burst.restart()
	_fx_burst.emitting = true


## Para de gerar aura/partículas novas (o que já saiu some sozinho)
func stop_fx() -> void:
	_fx_active = false
	if _fx_stream:
		_fx_stream.emitting = false


## Apaga tudo na hora (ex: bola reposta depois de um gol)
func _clear_fx() -> void:
	_fx_active = false
	if _fx_trail == null:
		return
	_fx_trail.clear_points()
	_fx_trail.visible = false
	_fx_stream.emitting = false
	_fx_burst.emitting = false


func _ensure_fx_nodes() -> void:
	if _fx_trail != null:
		return
	_fx_trail = Line2D.new()
	_fx_trail.top_level = true   # pontos em coordenadas globais: o rastro fica no lugar por onde a bola passou
	_fx_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_fx_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_fx_trail.round_precision = 4
	_fx_trail.visible = false
	_fx_stream = CPUParticles2D.new()
	_fx_burst = CPUParticles2D.new()
	_fx_stream.emitting = false   # o padrão do CPUParticles2D é ligado
	_fx_burst.emitting = false
	for n: Node2D in [_fx_trail, _fx_stream, _fx_burst]:
		add_child(n)
		move_child(n, sprite.get_index())   # desenha ATRÁS do sprite da bola


func _style_particles(p: CPUParticles2D, fx: KickFX, burst: bool) -> void:
	p.texture = fx.get_texture()
	p.material = fx.get_blend_material()
	p.local_coords = false          # as partículas ficam no mundo, não andam com a bola
	p.fixed_fps = 30                # metade das atualizações: visualmente igual, bem mais barato
	p.lifetime = fx.lifetime
	p.one_shot = burst
	p.explosiveness = 1.0 if burst else 0.0
	p.randomness = 0.5
	p.amount = fx.burst_amount if burst else fx.amount
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = fx.emit_radius
	p.direction = Vector2.UP
	p.spread = 180.0                # para todos os lados
	p.gravity = fx.gravity
	if burst:
		p.initial_velocity_min = fx.burst_speed * 0.4
		p.initial_velocity_max = fx.burst_speed
		p.damping_min = fx.burst_speed * 1.2   # a explosão freia rápido
		p.damping_max = fx.burst_speed * 1.2
	else:
		p.initial_velocity_min = fx.speed_min
		p.initial_velocity_max = fx.speed_max
		p.damping_min = fx.damping
		p.damping_max = fx.damping
	p.tangential_accel_min = fx.swirl
	p.tangential_accel_max = fx.swirl
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -fx.spin
	p.angular_velocity_max = fx.spin
	p.scale_amount_min = fx.scale_min
	p.scale_amount_max = fx.scale_max
	p.scale_amount_curve = fx.get_shrink_curve()
	p.color_ramp = fx.get_particle_gradient()


func _update_fx() -> void:
	if _fx_trail == null:
		return   # nenhuma habilidade foi usada ainda: custo zero
	if _fx_active:
		var keep_hover: bool = hovering and fx_during_hover
		var stopped: bool = not keep_hover and is_on_ground() \
				and velocity.length_squared() < fx_stop_speed * fx_stop_speed
		if interaction_count != _fx_touches or (hovering and not fx_during_hover) or stopped:
			stop_fx()
		else:
			_fx_stream.position = sprite.position
			_push_trail_point(sprite.global_position)
	elif _fx_trail.visible:
		# Depois que o efeito acaba, a cauda vai sendo "comida" até sumir
		if _fx_trail.get_point_count() > 0:
			_fx_trail.remove_point(0)
		else:
			_fx_trail.visible = false


func _push_trail_point(p: Vector2) -> void:
	var n: int = _fx_trail.get_point_count()
	if n > 0 and _fx_trail.get_point_position(n - 1).distance_squared_to(p) < _fx_step_sq:
		return   # quase não andou: não polui o rastro com pontos colados
	_fx_trail.add_point(p)
	if n + 1 > _fx_max_points:
		_fx_trail.remove_point(0)


# ---------- API ----------

func is_on_ground() -> bool:
	return height <= 0.0 and vel_z == 0.0


## Coloca a bola parada em uma posição global (ex: saída de bola)
func reset(global_pos: Vector2) -> void:
	release_hover()
	_ignore_player = null
	_sticky_ignore_player = null
	clear_touches()
	pending_shot_chance = NO_SHOT
	_clear_fx()
	global_position = global_pos
	velocity = Vector2.ZERO
	height = 0.0
	vel_z = 0.0
	was_reset.emit()


## Registra que um jogador interagiu com a bola (repetir o mesmo jogador não muda nada)
func register_touch(p: Player) -> void:
	interaction_count += 1
	if p != _sticky_ignore_player:
		_sticky_ignore_player = null   # outro jogador tocou na bola: acabou a exceção
	if p == null or p == last_toucher:
		return
	previous_toucher = last_toucher
	last_toucher = p


func clear_touches() -> void:
	last_toucher = null
	previous_toucher = null


## Bola parada no chão = o chute acabou (não carrega a chance para um toque futuro)
func _expire_shot() -> void:
	if pending_shot_chance >= 0.0 and is_on_ground() and velocity.length() < 20.0:
		pending_shot_chance = NO_SHOT


func has_pending_shot() -> bool:
	return pending_shot_chance >= 0.0


func is_held() -> bool:
	return held_by != null


## A bola está presa por um feitiço de OUTRO time? (aí este time não consegue tocar nela)
func is_locked_for(team: int) -> bool:
	return spell_owner != null and is_instance_valid(spell_owner) and spell_owner.team != team


## Alguém (o goleiro) pega a bola: ela para e passa a acompanhar quem a segura
func hold(by: Node2D) -> void:
	release_hover()
	held_by = by
	hovering = true
	velocity = Vector2.ZERO
	vel_z = 0.0
	pending_shot_chance = NO_SHOT


func _set_shot(by: Node2D, chance: float) -> void:
	pending_shot_chance = chance
	shot_team = (by as Player).team if by is Player else -1


## A bola atravessa este jogador (sem colidir) até parar ou outro jogador tocar nela.
## Chame DEPOIS do kick()/kick_ground(), que limpam essa exceção.
func ignore_player_until_stopped(p: Node2D) -> void:
	_sticky_ignore_player = p


## Passe/chute rasteiro (by = quem chutou: não colide com a bola até ela se afastar).
## shot_chance = chance de o chute vencer o goleiro (padrão 30%). Passes devem usar NO_SHOT.
func kick_ground(direction: Vector2, power: float, by: Node2D = null,
		shot_chance: float = DEFAULT_SHOT_CHANCE) -> void:
	release_hover()
	_ignore_player = by
	_sticky_ignore_player = null
	register_touch(by as Player)
	_set_shot(by, shot_chance)
	velocity = direction.normalized() * power
	vel_z = 0.0


## Chute com elevação (lift = velocidade vertical inicial). Habilidades que chutam
## podem passar o shot_chance próprio; o padrão é 30%.
func kick(direction: Vector2, power: float, lift: float, by: Node2D = null,
		shot_chance: float = DEFAULT_SHOT_CHANCE) -> void:
	release_hover()
	_ignore_player = by
	_sticky_ignore_player = null
	register_touch(by as Player)
	_set_shot(by, shot_chance)
	velocity = direction.normalized() * power
	vel_z = lift


## Leva a bola (movimento horizontal linear + subida suave) até uma posição e
## altura e a deixa PAIRANDO lá, sem gravidade, até alguém chutar ou release_hover().
## Devolve o Tween (use "await tween.finished" se quiser esperar chegar).
func hover_to(global_pos: Vector2, target_height: float, duration: float) -> Tween:
	_kill_hover_tween()
	pending_shot_chance = NO_SHOT  # passe alto não é chute
	hovering = true
	velocity = Vector2.ZERO
	vel_z = 0.0
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(self, "global_position", global_pos, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "height", target_height, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	trail_enabled = true
	_hover_tween.finished.connect(_on_hover_tween_finished)
	return _hover_tween


func _on_hover_tween_finished() -> void:
	trail_enabled = false


## Solta a bola pairando: a gravidade volta e ela cai (e quica) até o chão
func release_hover() -> void:
	hovering = false
	bounces_left = -1   # todo chute/solta começa sem limite de quiques (quem quiser limita DEPOIS)
	held_by = null
	spell_owner = null
	_kill_hover_tween()


func _kill_hover_tween() -> void:
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	trail_enabled = false


## Nível de altura atual da bola (Chão / Suspenso / Voando)
func get_level() -> Heights.Level:
	return Heights.from_height(height)


## Chute que faz a bola atingir o pico do nível escolhido
## (SUSPENDED = chute normal, FLYING = situações específicas)
func kick_to_level(direction: Vector2, power: float, level: Heights.Level) -> void:
	velocity = direction.normalized() * power
	vel_z = Heights.lift_for_peak(Heights.to_height(level), gravity)


## Cobertura / chapéu
func chip(direction: Vector2, power: float) -> void:
	kick(direction, power * 0.6, power * 0.9)


## Posição 3D (x, y do campo, z altura) — útil para IA e colisões
func get_position_3d() -> Vector3:
	return Vector3(position.x, position.y, height)


## Verifica se a bola está numa altura alcançável (ex: pé 0–60, cabeceio até 120)
func is_in_reach(min_h: float, max_h: float) -> bool:
	return height >= min_h and height <= max_h


## Distância 3D até um ponto (ex: o pé do jogador na altura 0)
func distance_to_3d(ground_pos: Vector2, z: float = 0.0) -> float:
	return get_position_3d().distance_to(Vector3(ground_pos.x, ground_pos.y, z))
