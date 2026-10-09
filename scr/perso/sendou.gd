class_name Sendou
extends Player
## Shuto Sendou. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias.
## NÃO precisa de nenhuma edição em outros arquivos.
##
## 1. Ace / Star / Sniper (ação de habilidade, 3 variantes automáticas pela altura; recarga de
##      2 rodadas, compartilhada entre as variantes):
##      - Bola no chão (Sendou no chão ou suspenso) -> Ace: chute reto, um pouco mais forte (40%)
##      - Bola e Sendou suspensos                   -> Star: mais forte, QTE fácil (45%)
##      - Sendou suspenso + bola voando             -> Sniper: bicicleta com QTE difícil (50%);
##        cada inimigo na trajetória tem 35% de chance de ser atravessado pela bola
## 2. Second Striker (ação de habilidade, recarga de 2 rodadas): com a bola ao alcance, marca um
##      aliado (alcance 500) e faz um passe rasteiro para ele; logo depois o Sendou dá um
##      avanço (dash) em direção ao gol inimigo.
## 3. Star Talent / Semi Predator (ação de habilidade, recarga de 2 rodadas, compartilhada;
##      a variante muda sozinha pelo setor do campo onde o Sendou está). Os dois são um avanço
##      (dash) mirável, feito com o Sendou no chão:
##      - Setor DEFENSIVO -> Star Talent: se encontrar a bola (no chão ou suspensa), para e a
##        arremessa na direção CONTRÁRIA ao avanço (QTE fácil)
##      - Setor OFENSIVO  -> Semi Predator: se encontrar a bola (no chão ou suspensa), domina
##        ela (fica colada nele) e ativa o efeito: +1 ação de habilidade para ele, +5% de chance
##        nos próximos 3 chutes e um pouco mais de força em qualquer chute
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Sendou".
##
## Animações opcionais (SpriteFrames; hit_frames diz o frame de impacto de cada uma):
## "ace", "star", "sniper", "second_striker", "star_talent", "semi_predator" e "dash" (o avanço,
## em loop; sem ela usa "run"). Sem elas, nada quebra.

const SKILL_SHOT: StringName = &"ace"
const SKILL_STRIKER: StringName = &"second_striker"
const SKILL_TALENT: StringName = &"star_talent"

## Grupos de recarga (as 3 variantes do chute compartilham o mesmo; Star Talent e Semi Predator também)
const CD_SHOT: StringName = &"cd_shot"
const CD_STRIKER: StringName = &"cd_striker"
const CD_TALENT: StringName = &"cd_talent"

enum ShotVariant { NONE, ACE, STAR, SNIPER }

@export_group("Ace / Star / Sniper")
@export_range(0.0, 1.0) var chance_ace: float = 0.40
@export_range(0.0, 1.0) var chance_star: float = 0.45
@export_range(0.0, 1.0) var chance_sniper: float = 0.50
@export var shot_cooldown: int = 2                   # recarga (rodadas), igual para as 3 variantes
@export var ace_force_mult: float = 1.25             # "um pouco mais forte que o normal"
@export var star_force_mult: float = 1.4             # "mais forte"
@export var sniper_force_mult: float = 1.0
@export_range(0.0, 1.0) var sniper_pierce_chance: float = 0.35   # chance de atravessar CADA inimigo na trajetória
@export var sniper_watch_time: float = 2.5           # por quanto tempo a bola do Sniper "procura" inimigos

@export_group("Second Striker")
@export var striker_range: float = 500.0             # alcance do passe
@export var striker_dash_distance: float = 350.0     # avanço depois do passe
@export var striker_cooldown: int = 2

@export_group("Star Talent / Semi Predator")
@export var talent_dash_distance: float = 320.0      # avanço mirável
@export var talent_cooldown: int = 2                 # recarga, igual para as duas variantes
@export var dash_duration: float = 0.45              # tempo do avanço (começa rápido e desacelera)
@export var dash_ball_radius: float = 55.0           # "encontrar a bola": distância que conta
## Onde acaba o setor defensivo, como fração da metade do campo a partir do meio:
## 0 = linha do meio-campo; 0.33 = defensivo só até 1/3 da metade; -0.33 = vai além do meio-campo
@export var sector_split: float = 0.0
@export var throw_speed: float = 1100.0              # Star Talent: velocidade da bola arremessada (px/s)
@export var semi_shots: int = 3                      # Semi Predator: quantos chutes recebem o bônus
@export_range(0.0, 1.0) var semi_shot_bonus: float = 0.05   # +5% de chance
@export var semi_force_mult: float = 1.15            # "um pouco mais de força" em qualquer chute
@export var semi_extra_skills: int = 1               # ações de habilidade extras para o Sendou

@export_group("Visual do chute")
## Aura + partículas dos chutes e passes de habilidade. Vazio = salmão claro (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: ace, second_striker, star_talent.
@export var skill_icons: Dictionary = {}

## Cor do personagem: rosa bem claro, pouco saturado (salmão)
const SALMON := Color(0.96, 0.72, 0.68)
const SALMON_LIGHT := Color(1.0, 0.87, 0.84)

## Semi Predator: quantos chutes ainda têm o bônus
var _semi_shots_left: int = 0
## Avanço em andamento (a direção serve para desenhar o rastro)
var _dashing: bool = false
var _dash_dir: Vector2 = Vector2.RIGHT
## Muda a cada partida nova: um avanço antigo percebe e para
var _dash_token: int = 0


func _init() -> void:
	character_id = "sendou"          # o menu de formação usa isto para saber quem é quem
	display_name = "Shuto Sendou"    # aparece no placar de gols e no menu (troque aqui se quiser)


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()


## Salmão claro com partículas mais claras ainda
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = SALMON
	fx.trail_width = 14.0
	fx.particle_color = SALMON_LIGHT
	fx.amount = 22
	fx.lifetime = 0.55
	fx.speed_min = 15.0
	fx.speed_max = 70.0
	fx.gravity = Vector2(0.0, -50.0)
	fx.spin = 240.0
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 14
	fx.burst_speed = 220.0
	return fx


# ---------- SETOR DO CAMPO ----------

func _field() -> Field:
	return get_tree().get_first_node_in_group("field") as Field


## O time 0 ataca para a direita (+x) e o time 1 para a esquerda
func _attack_dir() -> float:
	return 1.0 if team == 0 else -1.0


## Está na metade (ou no pedaço, veja sector_split) do campo do próprio gol?
func is_in_defensive_sector() -> bool:
	var field: Field = _field()
	if field == null:
		return false
	var local_x: float = field.to_local(global_position).x * _attack_dir()
	return local_x < sector_split * field.pitch_size.x * 0.5


## Direção do Sendou até o gol que o time dele ataca
func _enemy_goal_dir() -> Vector2:
	var field: Field = _field()
	if field == null:
		return Vector2(_attack_dir(), 0.0)
	var goal: Vector2 = field.to_global(Vector2(_attack_dir() * field.pitch_size.x * 0.5, 0.0))
	var dir: Vector2 = goal - global_position
	return dir.normalized() if dir.length() > 1.0 else Vector2(_attack_dir(), 0.0)


# ---------- ACE / STAR / SNIPER ----------

func get_shot_variant() -> ShotVariant:
	var ball: Ball = _get_ball()
	# get_kick_type já confere: derrubado, bola na mão do goleiro, longe demais, altura inalcançável
	if get_kick_type(ball) == KickType.NONE:
		return ShotVariant.NONE

	match ball.get_level():
		Heights.Level.GROUND:
			return ShotVariant.ACE            # Sendou no chão ou suspenso
		Heights.Level.SUSPENDED:
			if height_level == Heights.Level.SUSPENDED:
				return ShotVariant.STAR
		Heights.Level.FLYING:
			if height_level == Heights.Level.SUSPENDED:
				return ShotVariant.SNIPER
	return ShotVariant.NONE


func _shot_skill_name() -> String:
	match get_shot_variant():
		ShotVariant.STAR:
			return "Star"
		ShotVariant.SNIPER:
			return "Sniper"
	return "Ace"


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

	var kind: KickType = KickType.GROUND
	var anim: StringName = &"ace"
	var base_chance: float = chance_ace
	var force_mult: float = ace_force_mult
	var needs_qte: bool = false
	var qte_kind: KickType = KickType.VOLLEY

	match variant:
		ShotVariant.STAR:
			kind = KickType.VOLLEY
			anim = &"star"
			base_chance = chance_star
			force_mult = star_force_mult
			needs_qte = true
			qte_kind = KickType.VOLLEY    # QTE fácil
		ShotVariant.SNIPER:
			kind = KickType.FLYING
			anim = &"sniper"
			base_chance = chance_sniper
			force_mult = sniper_force_mult
			needs_qte = true
			qte_kind = KickType.FLYING    # QTE difícil

	var qte_ok: bool = true
	if needs_qte:
		qte_ok = await m.run_qte(qte_kind)

	next_kick_force_mult *= force_mult   # gasto dentro do kick_ball (soma com o do Semi Predator)
	var chance: float = minf(base_chance + _shot_bonus(), 1.0)

	# Sniper: a bola "procura" inimigos na trajetória (roda junto com o chute, sem esperar).
	# Só vale se acertou o QTE: errar = chute fraquinho.
	if variant == ShotVariant.SNIPER and qte_ok:
		_sniper_watch(ball)

	# Errou o QTE = chute fraquinho, sem aura
	await kick_ball(ball, aim, kind, qte_ok, chance, false, kick_fx if qte_ok else null, anim)
	start_cooldown(CD_SHOT, shot_cooldown)
	return true


## Sniper: espera o chute sair e, a cada inimigo que a bola está prestes a atingir, sorteia
## sniper_pierce_chance: se der certo, a bola ignora esse inimigo (atravessa). Para quando alguém
## toca na bola, ela é segurada/reposta ou para de rolar.
func _sniper_watch(ball: Ball) -> void:
	var m: MatchManager = _get_manager()
	var start_touches: int = ball.interaction_count

	# 1) espera o chute sair: a bola passa a ter um chute pendente DO SENDOU
	var waited: float = 0.0
	while not (ball.interaction_count != start_touches and ball.last_toucher == self \
			and ball.has_pending_shot()):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if waited > ACTION_TIMEOUT + 2.0 or not is_instance_valid(ball) \
				or (m != null and m.match_over):
			return

	# 2) acompanha o voo
	var state: Dictionary = {"abort": false}
	var on_reset: Callable = func() -> void: state["abort"] = true
	ball.was_reset.connect(on_reset, CONNECT_ONE_SHOT)
	var touches: int = ball.interaction_count
	var rolled: Dictionary = {}   # inimigo -> true se a bola vai atravessar
	var elapsed: float = 0.0
	while elapsed < sniper_watch_time:
		await get_tree().physics_frame
		if not is_instance_valid(ball) or state["abort"] or ball.interaction_count != touches \
				or ball.hovering or (m != null and m.match_over):
			break
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		if ball.is_on_ground() and ball.velocity.length() < 60.0:
			break   # a bola parou
		var reach_extra: float = ball.velocity.length() * delta * 1.5
		for other: Player in get_tree().get_nodes_in_group("players"):
			# A bola só colide com quem está no mesmo nível dela
			if other.team == team or rolled.has(other) or other.height_level != ball.get_level():
				continue
			if ball.global_position.distance_to(other.global_position) \
					> ball.collision_radius + other.body_radius + reach_extra:
				continue
			var pierce: bool = randf() < sniper_pierce_chance
			rolled[other] = pierce
			if pierce:
				ball.ignore_player_until_stopped(other)   # a bola passa direto por ele
				_spawn_pierce_ring(other)

	if is_instance_valid(ball) and ball.was_reset.is_connected(on_reset):
		ball.was_reset.disconnect(on_reset)


## Anel salmão que se abre em cima do inimigo atravessado
func _spawn_pierce_ring(other: Player) -> void:
	var ring := PierceRing.new()
	ring.ring_color = SALMON
	other.add_child(ring)


# ---------- AVANÇO (DASH) ----------

## Desliza "distance" px em dash_duration s (começa rápido e desacelera, como o Carrinho).
## look_for_ball: para assim que encontrar a bola (no chão ou suspensa) NA FRENTE dele e devolve
## true. Quem está suspenso não bloqueia o avanço (igual ao Carrinho).
func _dash(dir: Vector2, distance: float, look_for_ball: bool) -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	var token: int = _dash_token
	face_towards(dir)
	_dash_dir = dir
	_dashing = true
	queue_redraw()

	var met: bool = false
	var elapsed: float = 0.0
	while elapsed < dash_duration:
		await get_tree().physics_frame
		if token != _dash_token or (m != null and m.match_over):
			break
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		var frac: float = clampf(1.0 - elapsed / dash_duration, 0.0, 1.0)
		velocity = dir * (2.0 * distance / dash_duration) * frac
		_update_dash_collision_exceptions()
		move_and_slide()
		queue_redraw()
		if look_for_ball and _ball_in_dash_reach(ball, dir):
			met = true
			break

	_dashing = false
	velocity = Vector2.ZERO
	_clear_slide_collision_exceptions()   # solta as exceções de colisão (a mesma do Carrinho)
	queue_redraw()
	return met


func _update_dash_collision_exceptions() -> void:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		if other.height_level != Heights.Level.GROUND:
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)
		else:
			remove_collision_exception_with(other)
			other.remove_collision_exception_with(self)


func _ball_in_dash_reach(ball: Ball, dir: Vector2) -> bool:
	if ball == null or ball.is_held() or ball.is_locked_for(team):
		return false
	if not can_reach_level(ball.get_level()):   # no chão: alcança chão e suspensa
		return false
	var to_ball: Vector2 = ball.global_position - global_position
	return to_ball.length() <= dash_ball_radius and to_ball.dot(dir) > 0.0   # só se está na frente


# ---------- STAR TALENT / SEMI PREDATOR ----------

func _talent_skill_name() -> String:
	return "Star Talent" if is_in_defensive_sector() else "Semi Predator"


func _use_talent() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var defensive: bool = is_in_defensive_sector()   # a variante é a do setor onde ele está agora

	var aim: Vector2 = await m.aim_for_skill(self, talent_dash_distance)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	var ball: Ball = _get_ball()
	var met: bool = await _dash(aim, talent_dash_distance, true)
	if met and is_instance_valid(ball) and not m.match_over:
		if defensive:
			await _star_talent_throw(ball, aim)
		else:
			await _semi_predator_control(ball, aim)
	start_cooldown(CD_TALENT, talent_cooldown)
	return true


## Star Talent: arremessa a bola na direção CONTRÁRIA ao avanço (QTE fácil)
func _star_talent_throw(ball: Ball, dash_dir: Vector2) -> void:
	var m: MatchManager = _get_manager()
	var qte_ok: bool = await m.run_qte(KickType.VOLLEY)   # QTE fácil
	if not await play_action(&"star_talent"):
		return
	if not is_instance_valid(ball) or ball.is_held() or ball.is_locked_for(team):
		return

	var dir: Vector2 = -dash_dir
	var speed: float = throw_speed
	if not qte_ok:   # errou o QTE: sai fraco e torto
		speed *= qte_fail_power_mult
		dir = dir.rotated(deg_to_rad(randf_range(-qte_fail_max_angle, qte_fail_max_angle)))

	# Não é chute a gol (NO_SHOT). A bola sai sempre RASTEIRA, sem subir: se estava suspensa,
	# ela é "abaixada" até o chão (como no Semi Predator) e rola reto na direção contrária.
	ball.height = 0.0
	ball.kick_ground(dir, speed, self, Ball.NO_SHOT)
	if qte_ok:
		ball.play_fx(kick_fx)


## Semi Predator: domina a bola (deixa colada nele) e ativa o efeito
func _semi_predator_control(ball: Ball, dash_dir: Vector2) -> void:
	if not await play_action(&"semi_predator"):
		return
	if not is_instance_valid(ball) or ball.is_held() or ball.is_locked_for(team):
		return

	ball.release_hover()
	ball.pending_shot_chance = Ball.NO_SHOT
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.global_position = global_position + dash_dir * (body_radius + ball.collision_radius + 4.0)
	ball.register_touch(self)   # agora ele é o último a tocar na bola

	_semi_shots_left = semi_shots
	next_kick_force_mult = maxf(next_kick_force_mult, semi_force_mult)   # "um pouco mais de força"
	extra_skill_left += semi_extra_skills
	queue_redraw()


## Semi Predator: +% de chance nos próximos chutes
func _shot_bonus() -> float:
	return semi_shot_bonus if _semi_shots_left > 0 else 0.0


## Vale também para o Chutar geral: base do tipo de chute + bônus
func get_shot_chance(kind: KickType) -> float:
	return minf(super(kind) + _shot_bonus(), 1.0)


## O Player chama isto em TODO chute com chance de gol. Cada chute gasta 1 do Semi Predator e,
## se ainda sobrar, a força extra é preparada de novo (o kick_ball zera o multiplicador a cada
## chute; assim o "um pouco mais de força" vale também para o Chutar geral sem mexer no player.gd).
func on_shot_attempt() -> void:
	super()
	if _semi_shots_left > 0:
		_semi_shots_left -= 1
		if _semi_shots_left > 0:
			next_kick_force_mult = maxf(next_kick_force_mult, semi_force_mult)
		queue_redraw()


# ---------- SECOND STRIKER ----------

## Quem pode receber o passe: companheiro (não ele mesmo) que não está com o passe bloqueado
func _can_receive(p: Player) -> bool:
	return is_instance_valid(p) and p != self and not p.is_pass_blocked()


func _striker_candidates() -> Array[Player]:
	var result: Array[Player] = []
	var m: MatchManager = _get_manager()
	if m == null:
		return result
	for p: Player in m.get_team_players(team):
		if _can_receive(p) and global_position.distance_to(p.global_position) <= striker_range:
			result.append(p)
	return result


func _use_second_striker() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or get_kick_type(ball) == KickType.NONE:
		return false

	var target: Player = await m.pick_ally_for_skill(self, striker_range, false, _can_receive)
	if target == null or m.match_over:
		return false   # cancelou: não gasta a ação

	# Passe rasteiro (curva 0 = reta), com a aura do personagem. Quem passa é o Sendou.
	var goal_dir: Vector2 = _enemy_goal_dir()
	await m.run_curved_ground_pass(self, target, ball, 0.0, 1.0, &"second_striker", kick_fx)
	start_cooldown(CD_STRIKER, striker_cooldown)

	# Logo depois do passe, o avanço em direção ao gol inimigo
	if not m.match_over:
		await _dash(goal_dir, striker_dash_distance, false)
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_SHOT, "name": skill_label(_shot_skill_name(), CD_SHOT)})
	list.append({"id": SKILL_STRIKER, "name": skill_label("Second Striker", CD_STRIKER)})
	list.append({"id": SKILL_TALENT, "name": skill_label(_talent_skill_name(), CD_TALENT)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_SHOT:
			return not is_on_cooldown(CD_SHOT) and get_shot_variant() != ShotVariant.NONE
		SKILL_STRIKER:
			return not is_on_cooldown(CD_STRIKER) and get_kick_type(_get_ball()) != KickType.NONE \
				and not _striker_candidates().is_empty()
		SKILL_TALENT:
			# O avanço é no chão e precisa de um setor do campo para escolher a variante
			return not is_on_cooldown(CD_TALENT) and height_level == Heights.Level.GROUND \
				and _field() != null
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_SHOT:
			return await _use_shot_skill()
		SKILL_STRIKER:
			return await _use_second_striker()
		SKILL_TALENT:
			return await _use_talent()
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
				+ "• Ace (bola no chão): chute reto, um pouco mais forte que o normal. %d%% de chance de gol.\n"
				+ "• Star (ele e a bola suspensos): mais forte, QTE fácil. %d%%.\n"
				+ "• Sniper (ele suspenso e bola voando): bicicleta com QTE difícil. %d%%. Cada inimigo na trajetória tem %d%% de chance de ser atravessado pela bola.\n"
				+ "Recarga: %d rodadas, compartilhada entre as três.") % [
				_pct(chance_ace), _pct(chance_star), _pct(chance_sniper),
				_pct(sniper_pierce_chance), shot_cooldown]
		SKILL_STRIKER:
			title = "Second Striker"
			text = ("Com a bola ao alcance, marque um aliado (alcance %d): o Sendou faz um passe "
				+ "rasteiro para ele e, logo depois, dá um avanço em direção ao gol inimigo.\n"
				+ "Recarga: %d rodadas.") % [int(striker_range), striker_cooldown]
		SKILL_TALENT:
			title = _talent_skill_name()
			text = ("Avanço (dash) mirável, feito no chão. A variante muda sozinha pelo setor do campo:\n"
				+ "• Star Talent (setor defensivo): se encontrar a bola (no chão ou suspensa), arremessa ela na direção CONTRÁRIA ao avanço. QTE fácil.\n"
				+ "• Semi Predator (setor ofensivo): se encontrar a bola (no chão ou suspensa), domina ela e ganha +%d ação de habilidade, +%d%% de chance nos próximos %d chutes e um pouco mais de força em qualquer chute.\n"
				+ "Recarga: %d rodadas, compartilhada entre as duas.") % [
				semi_extra_skills, _pct(semi_shot_bonus), semi_shots, talent_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_dash_token += 1   # um avanço em andamento percebe e para
	_dashing = false
	_semi_shots_left = 0
	_clear_slide_collision_exceptions()
	queue_redraw()


# ---------- VISUAL ----------

## Troca a animação do estado enquanto avança: "dash" (se existir) ou "run"
func _desired_anim() -> StringName:
	if _dashing and not is_down:
		if _has_art and animated_sprite.sprite_frames.has_animation(&"dash"):
			return &"dash"
		return ANIM_RUN
	return super()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Semi Predator ativo: anel salmão e uma bolinha para cada chute que ainda tem o bônus
	if _semi_shots_left > 0:
		draw_arc(center, placeholder_radius + 8.0, 0.0, TAU, 40, Color(SALMON, 0.95), 2.5)
		for i in _semi_shots_left:
			var x: float = (float(i) - float(_semi_shots_left - 1) * 0.5) * 12.0
			draw_circle(center + Vector2(x, -(placeholder_radius + 22.0)), 3.5, SALMON)

	# Avanço: riscos de velocidade atrás dele
	if _dashing:
		var back: Vector2 = -_dash_dir
		var side: Vector2 = _dash_dir.orthogonal()
		for i in 3:
			var off: Vector2 = side * float(i - 1) * 9.0
			var length: float = 34.0 - absf(float(i - 1)) * 10.0
			draw_line(center + off + back * (placeholder_radius + 4.0),
				center + off + back * (placeholder_radius + 4.0 + length), Color(SALMON, 0.85), 3.0)


## Anel salmão que se abre e some em cima de um inimigo atravessado pela bola do Sniper
class PierceRing extends Node2D:
	var ring_color: Color = Color(0.96, 0.72, 0.68)
	var _time: float = 0.0
	const LIFE: float = 0.5

	func _ready() -> void:
		z_index = 10

	func _process(delta: float) -> void:
		_time += delta
		if _time >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_time / LIFE, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 18.0 + 30.0 * k, 0.0, TAU, 32, Color(ring_color, 1.0 - k), 3.0)
