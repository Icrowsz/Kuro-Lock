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

## Rastro suave atrás da bola (ligado durante os passes)
@export_group("Rastro")
@export var trail_length: int = 12
var trail_enabled: bool = false
var _trail: Array[Vector2] = []
var _hover_time: float = 0.0
var _prev_global: Vector2 = Vector2.ZERO

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
			if impact > min_bounce_speed:
				vel_z = -vel_z * bounce_factor
				velocity *= 0.9  # perde um pouco de velocidade horizontal ao quicar
				bounced.emit(impact)
			else:
				vel_z = 0.0


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
	held_by = null
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
