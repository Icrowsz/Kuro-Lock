class_name Chigiri
extends Player
## Chigiri Hyoma. Mais um personagem do time, com 3 habilidades:
##
## 1. Golden Zone / 44 Pant (ação de habilidade, com 2 variantes automáticas; recarga de 2
##      rodadas):
##      - Sem zona ativa -> Golden Zone: cria um círculo dourado na ponta externa DIREITA da
##          pequena área do goleiro (o canto da caixa mais longe da linha de gol, do lado
##          direito — ver nota de orientação abaixo), do lado de FORA da caixa, que dura 2
##          rodadas.
##      - Zona ativa, Chigiri DENTRO dela, no chão, com a bola ao alcance (no chão ou
##          suspensa) -> 44 Pant: um chute, 40% de chance. Não tem recarga própria: pode ser
##          repetido à vontade enquanto a zona durar (só a criação da zona usa CD_ZONE).
##
##      ORIENTAÇÃO DA "PONTA DIREITA": o projeto não guarda qual lado da tela é "direita", então
##      calculei como a direita de QUEM ATACA aquele gol (vire de costas para o meio-campo,
##      de frente para o gol: a mão direita aponta para esse lado). Se ficar invertido na sua
##      tela, troque golden_zone_flip_side para true (ou o sinal de _golden_zone_corner()).
##
## 2. Accelerate (ação geral Correr) / Once More (ação de habilidade; recarga de 3 rodadas):
##      - Accelerate: a corrida normal do Chigiri (ação geral "Correr"), só que 1.7x mais
##          rápida (accelerate_mult). Sem recarga, é só como ele corre. Enquanto ele corre,
##          uma pantera vermelha minimalista e translúcida aparece ao lado dele (efeito
##          visual, ver _draw_panther()).
##      - Once More: ação de HABILIDADE própria (tem botão no catálogo), só usável com
##          Chigiri suspenso. Ele avança reto em direção à bola (curto/médio:
##          once_more_dash_range). Se o avanço alcançar a bola, ele a domina (ela para, nos
##          pés dele), DESCE para o chão (height_level vira Chão) e ganha +1 ação de
##          habilidade — já podendo usar o 44 Pant na sequência, por exemplo. Se não
##          alcançar, continua Suspenso. Recarga de 3 rodadas, mesmo se não alcançar a bola.
##
## 3. Miau! / Red Princess (ação de habilidade, com 2 variantes automáticas pela distância da
##      bola; recarga de 3 rodadas — NÃO informada no pedido original, usei 3 por padrão,
##      ajuste em miau_cooldown se quiser outra):
##      - Bola longe (fora do kick_range) -> Miau!: um Carrinho mais longo que o normal
##          (miau_slide_distance), na direção mirada. Não gasta o Carrinho geral do turno.
##      - Bola perto (no chão ou suspensa, ao alcance) -> Red Princess: cruzamento alto e
##          longo (red_princess_range = 550) para um aliado a pelo menos
##          red_princess_min_range (350) de distância; a bola sobe e desce NO CHÃO, nos pés
##          do aliado escolhido.
##
## Como montar a cena: igual aos outros — Nova Cena Herdada de player.tscn -> anexe este
## script ao nó raiz -> renomeie o nó raiz para "Chigiri".
##
## Animações opcionais (se faltar alguma, o jogo só pula): golden_zone, pant_44, once_more,
## miau, red_princess.
##
## PEÇAS NO RESTO DO PROJETO (já aplicadas nos arquivos devolvidos nas rodadas anteriores):
## - field.gd: get_goal_area_rect(team), irmã do get_penalty_area_rect() que já existia —
##   usada para achar o canto da pequena área do gol inimigo.
## - player.gd: o gancho can_run() (não é mais usado pelo Chigiri agora que o Once More virou
##   habilidade própria, mas continua lá, inofensivo, para outros personagens que queiram).

const SKILL_ZONE: StringName = &"golden_zone"
const SKILL_ONCE_MORE: StringName = &"once_more"
const SKILL_MIAU: StringName = &"miau"

## Grupos de recarga (as variantes de cada habilidade compartilham o mesmo)
const CD_ZONE: StringName = &"cd_zone"
const CD_ONCE_MORE: StringName = &"cd_once_more"
const CD_MIAU: StringName = &"cd_miau"

## Variante da habilidade 1, por ter zona ativa (e Chigiri estar dentro, com a bola)
enum ZoneVariant { NONE, CREATE, SHOT }
## Variante da habilidade 3, pela distância da bola
enum MiauVariant { NONE, MIAU, RED_PRINCESS }

@export_group("Golden Zone / 44 Pant")
@export var golden_zone_rounds: int = 2
@export var golden_zone_cooldown: int = 0
@export var golden_zone_radius: float = 70.0
## O quanto o centro do círculo fica empurrado para FORA da caixa, a partir do canto externo
## (quanto maior, mais longe do canto — "mais à esquerda e mais embaixo" ao mesmo tempo, já
## que essa é a direção diagonal pra fora do canto). PRECISA ser maior que golden_zone_radius,
## senão o círculo volta a sobrepor a caixa. Dá pra ajustar aqui OU direto no Inspector da
## cena (o valor salvo na cena tem prioridade sobre este padrão do script).
@export var golden_zone_outside_margin: float = 180.0
@export_range(0.0, 1.0) var chance_44_pant: float = 0.40
## Inverte o lado da zona, se "direita" saiu do lado errado na sua tela (ver nota no topo)
@export var golden_zone_flip_side: bool = false

@export_group("Accelerate / Once More")
@export var accelerate_mult: float = 1.3
@export var once_more_dash_range: float = 260.0     # avanço curto/médio
@export var once_more_dash_time: float = 0.3
@export var once_more_cooldown: int = 3
@export var once_more_extra_skills: int = 1

@export_group("Miau! / Red Princess")
@export var miau_slide_distance: float = 230.0      # o Carrinho comum (slide_distance) é mais curto
@export var miau_slide_duration: float = 0.5
@export var red_princess_range: float = 550.0       # alcance máximo do cruzamento
@export var red_princess_min_range: float = 300.0   # o aliado tem que estar pelo menos este tanto longe
@export var red_princess_rise_time: float = 0.5
@export var red_princess_fall_time: float = 0.55
@export var miau_cooldown: int = 3                  # não informado no pedido; ajuste se quiser outro valor

@export_group("Visual do chute")
## Aura + partículas dos chutes/passes de habilidade. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

## Golden Zone ativa até esta rodada (-1 = inativa) e onde ela está (posição global)
var _zone_until_round: int = -1
var _zone_center: Vector2 = Vector2.ZERO

## Carrinho mais longo (Miau!) em andamento: não usa o Carrinho geral do turno
var _miau_active: bool = false


func _init() -> void:
	character_id = "chigiri"   # o menu de formação usa isto para saber quem é quem
	display_name = "Chigiri"


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_hook_manager.call_deferred()

func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(1.0, 0.242, 0.216, 1.0)
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(1.0, 0.401, 0.569, 1.0)
	fx.amount = 20
	fx.lifetime = 0.45
	fx.speed_min = 40.0
	fx.speed_max = 140.0
	fx.gravity = Vector2.ZERO
	fx.spin = 0.0
	fx.scale_min = 0.12
	fx.scale_max = 0.26
	fx.burst_amount = 16
	fx.burst_speed = 260.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)


func _on_round_started(new_round: int) -> void:
	if _zone_until_round >= 0 and new_round > _zone_until_round:
		_zone_until_round = -1   # a zona expirou
	queue_redraw()


# ---------- HABILIDADE 1: GOLDEN ZONE / 44 PANT ----------

func is_zone_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _zone_until_round >= 0 and m.round_number <= _zone_until_round


## Chigiri está DENTRO da zona ativa agora?
func _in_golden_zone() -> bool:
	return is_zone_active() and global_position.distance_to(_zone_center) <= golden_zone_radius


func get_zone_variant() -> ZoneVariant:
	if is_zone_active():
		if is_down or height_level != Heights.Level.GROUND or not _in_golden_zone():
			return ZoneVariant.NONE
		var ball: Ball = _get_ball()
		if ball != null and get_kick_type(ball) != KickType.NONE:
			return ZoneVariant.SHOT
		return ZoneVariant.NONE
	return ZoneVariant.CREATE


func _zone_skill_name() -> String:
	return "44 Pant" if get_zone_variant() == ZoneVariant.SHOT else "Golden Zone"


func _use_zone_skill() -> bool:
	match get_zone_variant():
		ZoneVariant.CREATE:
			return await _create_golden_zone()
		ZoneVariant.SHOT:
			return await _use_44_pant()
	return false


## Canto EXTERNO (o mais longe da linha de gol) do lado direito da pequena área do gol que o
## time ADVERSÁRIO defende (= o gol que Chigiri ataca), empurrado para fora da caixa.
## "Direita" = a direita de quem está atacando aquele gol (ver nota no topo do arquivo).
func _golden_zone_corner() -> Vector2:
	var field := get_tree().get_first_node_in_group("field") as Field
	if field == null:
		return global_position   # sem campo (cena de teste?): não quebra, só não acerta o canto
	var enemy_team: int = 1 - team
	var rect: Rect2 = field.get_goal_area_rect(enemy_team)

	var forward: Vector2 = Vector2(1.0, 0.0) * (1.0 if team == 0 else -1.0)   # para onde Chigiri ataca
	var right: Vector2 = forward.rotated(deg_to_rad(90.0))                     # "direita" de quem ataca
	if golden_zone_flip_side:
		right = -right

	# external_x: a borda da área MAIS LONGE da linha de gol (o "fundo" da caixa, para o
	# lado do campo); corner_y: o lado direito dela
	var external_x: float = rect.end.x if enemy_team == 0 else rect.position.x
	var corner_y: float = rect.end.y if right.y > 0.0 else rect.position.y
	var corner := Vector2(external_x, corner_y)

	# Empurra o centro do círculo para FORA da caixa, a partir desse canto: no eixo x, no
	# sentido contrário ao ataque (= se afastando do gol); no eixo y, continuando no mesmo
	# sentido do lado direito (= se afastando do centro da caixa)
	# safe_margin: nunca menor que o raio (+ uma folga), senão o círculo volta a cobrir
	# parte da caixa e visualmente parece estar "por dentro" dela.
	var safe_margin: float = maxf(golden_zone_outside_margin, golden_zone_radius + 20.0)
	var push: Vector2 = Vector2(-forward.x, signf(corner_y - rect.get_center().y)) * safe_margin
	return field.to_global(corner + push)


func _create_golden_zone() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	await play_action(&"golden_zone")
	_zone_center = _golden_zone_corner()
	_zone_until_round = m.round_number + golden_zone_rounds
	start_cooldown(CD_ZONE, golden_zone_cooldown)
	queue_redraw()
	return true


## 44 Pant: chute dado de DENTRO da Golden Zone. O tipo (chão/bola alta) é o mesmo que o
## get_kick_type() já resolveria normalmente (Chigiri sempre no chão aqui).
func _use_44_pant() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação
	if get_zone_variant() != ZoneVariant.SHOT:
		return false   # saiu da zona, a bola fugiu, ou a zona expirou enquanto ele mirava
	var kind: KickType = get_kick_type(ball)

	var qte_ok: bool = true
	if kind != KickType.GROUND and not skips_qte():
		qte_ok = await m.run_qte(kind)

	await kick_ball(ball, aim, kind, qte_ok, chance_44_pant, false,
		kick_fx if qte_ok else null, &"pant_44")
	# Sem recarga própria: só a criação da zona (CD_ZONE) entrou em recarga, lá atrás
	return true


# ---------- HABILIDADE 2 (AÇÃO GERAL CORRER): ACCELERATE / ONCE MORE ----------

## A corrida do Chigiri é sempre acelerada (1.7x). O Once More agora é uma habilidade à
## parte (ver _use_once_more()), não uma variante do Correr.
func start_run() -> void:
	_start_accelerate()


func _start_accelerate() -> void:
	runs_this_turn += 1
	var previous_speed: float = move_speed
	move_speed = previous_speed * accelerate_mult
	run_finished.connect(func() -> void: move_speed = previous_speed, CONNECT_ONE_SHOT)
	run_time_left = run_duration + run_time_bonus
	state = State.RUNNING


## Once More: ação de habilidade própria, só com Chigiri suspenso. Avanço reto em direção à
## bola (não usa o WASD livre do Correr comum): anda até once_more_dash_range OU até chegar
## perto da bola (o que vier primeiro).
func _use_once_more() -> bool:
	if is_down or height_level != Heights.Level.SUSPENDED:
		return false
	if not await play_action(&"once_more"):
		return false   # ação cancelada (ex: a partida reiniciou)
	await _run_once_more_dash()
	start_cooldown(CD_ONCE_MORE, once_more_cooldown)   # entra em recarga mesmo se não alcançar a bola
	return true


func _run_once_more_dash() -> void:
	var ball: Ball = _get_ball()
	var gap: float = body_radius + (ball.collision_radius if ball else 0.0) + 2.0
	var dest: Vector2 = global_position
	var reached: bool = false

	if ball != null:
		var to_ball: Vector2 = ball.global_position - global_position
		var dist: float = to_ball.length()
		if dist > 0.001:
			var dir: Vector2 = to_ball / dist
			if dist - gap <= once_more_dash_range:
				dest = ball.global_position - dir * gap   # alcança: para encostando na bola
				reached = true
			else:
				dest = global_position + dir * once_more_dash_range   # avanço parcial: não chega

	face_towards(dest - global_position)
	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", dest, once_more_dash_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished

	if reached and is_instance_valid(ball):
		land()   # dominou a bola: desce para o chão de propósito (libera, por ex., o 44 Pant na hora)
		ball.release_hover()
		ball.velocity = Vector2.ZERO
		ball.vel_z = 0.0
		ball.height = Heights.to_height(height_level)   # a bola vem para o nível dele (agora Chão), sob controle
		ball.register_touch(self)
		extra_skill_left += once_more_extra_skills


# ---------- HABILIDADE 3: MIAU! / RED PRINCESS ----------

func get_miau_variant() -> MiauVariant:
	if is_down or height_level != Heights.Level.GROUND:
		return MiauVariant.NONE
	var ball: Ball = _get_ball()
	if ball == null:
		return MiauVariant.NONE
	var near: bool = global_position.distance_to(ball.global_position) <= kick_range \
		and not ball.is_held() and not ball.is_locked_for(team) \
		and ball.get_level() != Heights.Level.FLYING
	return MiauVariant.RED_PRINCESS if near else MiauVariant.MIAU


func _miau_skill_name() -> String:
	return "Red Princess" if get_miau_variant() == MiauVariant.RED_PRINCESS else "Miau!"


func _use_miau_skill() -> bool:
	match get_miau_variant():
		MiauVariant.MIAU:
			return await _use_miau()
		MiauVariant.RED_PRINCESS:
			return await _use_red_princess()
	return false


## Miau!: Carrinho maior que o comum, na direção mirada. Ação de habilidade: não consome o
## Carrinho geral do turno (slides_this_turn).
func _use_miau() -> bool:
	var dir: Vector2 = await _aim_for_skill(miau_slide_distance)
	if dir == Vector2.ZERO:
		return false   # cancelou: não gasta a ação
	if get_miau_variant() != MiauVariant.MIAU:
		return false   # a bola chegou perto enquanto ele mirava: virou Red Princess, cancela

	face_towards(dir)
	_miau_active = true
	var previous_distance: float = slide_distance
	var previous_duration: float = slide_duration
	slide_distance = miau_slide_distance
	slide_duration = miau_slide_duration
	start_slide(dir)
	slides_this_turn = maxi(0, slides_this_turn - 1)   # o start_slide contou um Carrinho geral; devolve
	await slide_finished
	slide_distance = previous_distance
	slide_duration = previous_duration
	_miau_active = false

	start_cooldown(CD_MIAU, miau_cooldown)
	return true


func _aim_for_skill(range_px: float) -> Vector2:
	var m: MatchManager = _get_manager()
	return await m.aim_for_skill(self, range_px) if m else Vector2.ZERO


## Red Princess: cruzamento alto e longo para um aliado a pelo menos red_princess_min_range
## de distância (e até red_princess_range). A bola sobe ao nível Voando no meio do caminho e
## desce NO CHÃO, nos pés do aliado — mesma ideia do Aerial Pass do Karasu.
func _use_red_princess() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false

	var far_enough := func(other: Player) -> bool:
		return global_position.distance_to(other.global_position) >= red_princess_min_range
	var target: Player = await m.pick_ally_for_skill(self, red_princess_range, false, far_enough)
	if target == null:
		return false   # cancelou: não gasta a ação

	if get_miau_variant() != MiauVariant.RED_PRINCESS:
		return false   # a bola fugiu do alcance enquanto ele escolhia o alvo

	face_towards(target.global_position - global_position)
	if not await play_action(&"red_princess", ANIM_PASS_HIGH):
		return false   # ação cancelada (ex: a partida reiniciou)

	ball.register_touch(self)   # o cruzamento não usa kick(), então registra o toque aqui
	if kick_fx:
		ball.fx_during_hover = true
		ball.play_fx(kick_fx)

	var start: Vector2 = ball.global_position
	var to_target: Vector2 = target.global_position - start
	var dist: float = to_target.length()
	var gap: float = ball.collision_radius + target.body_radius + 2.0
	var end_point: Vector2 = start
	if dist > 0.001:
		end_point = start + to_target / dist * maxf(dist - gap, 0.0)

	var rise: Tween = ball.hover_to((start + end_point) * 0.5, Heights.FLYING_HEIGHT, red_princess_rise_time)
	await rise.finished
	var fall: Tween = ball.hover_to(end_point, Heights.GROUND_HEIGHT, red_princess_fall_time)
	await fall.finished

	ball.release_hover()
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.fx_during_hover = false
	ball.register_touch(self)
	m.pass_completed.emit(self, target)
	start_cooldown(CD_MIAU, miau_cooldown)
	return true


## Durante o Miau!, procura a bola como o Raven Assault do Karasu: se o carrinho encostar
## nela sem querer, ele ainda pode empurrá-la (mesma regra do Carrinho comum)
func _check_slide_hits() -> void:
	super()


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_ZONE, "name": skill_label(_zone_skill_name(), CD_ZONE)})
	list.append({"id": SKILL_ONCE_MORE, "name": skill_label("Once More", CD_ONCE_MORE)})
	list.append({"id": SKILL_MIAU, "name": skill_label(_miau_skill_name(), CD_MIAU)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_ZONE:
			match get_zone_variant():
				ZoneVariant.CREATE:
					return not is_on_cooldown(CD_ZONE)
				ZoneVariant.SHOT:
					return true   # sem recarga própria
			return false
		SKILL_ONCE_MORE:
			return not is_on_cooldown(CD_ONCE_MORE) and not is_down and height_level == Heights.Level.SUSPENDED
		SKILL_MIAU:
			return not is_on_cooldown(CD_MIAU) and get_miau_variant() != MiauVariant.NONE
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_ZONE:
			return await _use_zone_skill()
		SKILL_ONCE_MORE:
			return await _use_once_more()
		SKILL_MIAU:
			return await _use_miau_skill()
	return false


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_zone_until_round = -1
	_miau_active = false
	queue_redraw()


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	if is_zone_active():
		queue_redraw()   # a varredura do círculo dourado gira o tempo todo


func _draw() -> void:
	super()

	if is_zone_active():
		# Círculo dourado translúcido no canto da área do gol inimigo, com uma varredura girando
		var local_center: Vector2 = to_local(_zone_center) + Vector2(0.0, -height)
		var sweep: float = Time.get_ticks_msec() / 1000.0 * 2.2
		draw_arc(local_center, golden_zone_radius, 0.0, TAU, 32, Color(1.0, 0.85, 0.1, 0.22), golden_zone_radius)
		draw_arc(local_center, golden_zone_radius, 0.0, TAU, 32, Color(1.0, 0.9, 0.3, 0.85), 2.0)
		draw_line(local_center, local_center + Vector2(cos(sweep), sin(sweep)) * golden_zone_radius,
			Color(1.0, 0.95, 0.5, 0.7), 2.0)

	if state == State.RUNNING:
		_draw_panther(Vector2(0.0, -height))


## Pantera vermelha minimalista e translúcida correndo ao lado do Chigiri (silhueta de
## perfil, só o contorno): aparece enquanto o Accelerate (ação geral Correr) está em
## andamento. Fica do lado de trás, na direção oposta ao movimento, com um leve balanço.
func _draw_panther(center: Vector2) -> void:
	var dir: float = facing
	if velocity.length() > 1.0:
		dir = signf(velocity.x) if absf(velocity.x) > 1.0 else dir
	var t: float = Time.get_ticks_msec() / 1000.0
	var bob: float = sin(t * 10.0) * 3.0
	var side_offset := Vector2(-dir * (placeholder_radius + 26.0), -4.0 + bob)
	var p: Vector2 = center + side_offset
	var r: float = placeholder_radius * 0.85

	# Contorno de perfil (olhando para -dir, ou seja, correndo "atrás" do Chigiri), em
	# unidades de raio: cabeça pequena, lombo arqueado, cauda longa curva, pernas simples
	var shape: Array[Vector2] = [
		Vector2(1.6, -0.5), Vector2(1.9, -0.75), Vector2(1.7, -0.95),   # orelha
		Vector2(1.95, -0.6), Vector2(2.1, -0.35), Vector2(1.9, -0.05),  # cabeça/focinho
		Vector2(1.5, 0.05), Vector2(0.8, -0.35), Vector2(0.1, -0.5),    # lombo arqueado
		Vector2(-0.6, -0.35), Vector2(-1.1, 0.0), Vector2(-1.6, -0.1),
		Vector2(-2.2, -0.55), Vector2(-1.9, -0.75), Vector2(-1.5, -0.4), # cauda curva
		Vector2(-1.0, 0.3), Vector2(-1.1, 0.75), Vector2(-0.85, 0.8),   # pata trás
		Vector2(-0.65, 0.35), Vector2(-0.1, 0.35), Vector2(-0.05, 0.8),
		Vector2(0.2, 0.85), Vector2(0.3, 0.4), Vector2(0.8, 0.3),       # pata frente
		Vector2(1.0, 0.8), Vector2(1.25, 0.85), Vector2(1.3, 0.35),
		Vector2(1.6, 0.1),
	]
	var pts := PackedVector2Array()
	for sp: Vector2 in shape:
		pts.append(p + Vector2(sp.x * dir, sp.y) * r)
	draw_colored_polygon(pts, Color(0.85, 0.1, 0.12, 0.3))
	pts.append(pts[0])
	draw_polyline(pts, Color(1.0, 0.25, 0.25, 0.65), 1.5)
