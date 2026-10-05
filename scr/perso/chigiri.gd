class_name Chigiri
extends Player
## Chigiri Hyoma. Mais um personagem do time, com 3 habilidades:
##
## 1. Golden Zone / 44 Pant (ação de habilidade, com 2 variantes automáticas; recarga de 2
##      rodadas):
##      - Sem zona ativa -> Golden Zone: cria um círculo dourado na ponta DIREITA da pequena
##          área do gol inimigo (ver golden_zone_corner() — veja a nota de orientação logo
##          abaixo), que dura 2 rodadas.
##      - Zona ativa, Chigiri DENTRO dela, no chão, com a bola ao alcance (no chão ou
##          suspensa) -> 44 Pant: um chute, 40% de chance. Não tem recarga própria: pode ser
##          repetido à vontade enquanto a zona durar (só a criação da zona usa CD_ZONE).
##
##      ORIENTAÇÃO DA "PONTA DIREITA": o projeto não guarda qual lado da tela é "direita", então
##      calculei como a direita de QUEM ATACA aquele gol (vire de costas para o meio-campo,
##      de frente para o gol: a mão direita aponta para esse lado). Se ficar invertido na sua
##      tela, troque golden_zone_flip_side para true (ou o sinal de golden_zone_corner()).
##
## 2. Accelerate / Once More (ação geral Correr, com variante automática pela altura):
##      - Chigiri no chão -> Accelerate: Correr normal, mas 1.7x mais rápido (accelerate_mult).
##          Sem recarga (é só a corrida dele).
##      - Chigiri suspenso -> Once More: em vez de mover livre, ele avança reto em direção à
##          bola (curto/médio: once_more_dash_range). Se o avanço alcançar a bola, ele a
##          domina (ela para, nos pés dele) e ganha +1 ação de habilidade. Recarga de 3
##          rodadas, mesmo se não alcançar a bola.
##      Importante: o botão "Correr" do menu continua com o mesmo texto para todo mundo (o
##      menu não troca o nome dos botões gerais, só os de habilidade) — só o comportamento
##      muda conforme a altura do Chigiri.
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
## PEÇAS NO RESTO DO PROJETO (já aplicadas nos arquivos devolvidos junto com este):
## - field.gd: get_goal_area_rect(team), irmã do get_penalty_area_rect() que já existia —
##   usada para achar o canto da pequena área do gol inimigo.
## - player.gd: o gancho can_run() (Correr, por padrão só no chão; o Chigiri sobrescreve para
##   também valer suspenso).
## - match_manager.gd: can_use_general() chama p.can_run() em vez de checar GROUND na mão.

const SKILL_ZONE: StringName = &"golden_zone"
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
@export var golden_zone_cooldown: int = 2
@export var golden_zone_radius: float = 70.0
@export_range(0.0, 1.0) var chance_44_pant: float = 0.40
## Inverte o lado da zona, se "direita" saiu do lado errado na sua tela (ver nota no topo)
@export var golden_zone_flip_side: bool = false

@export_group("Accelerate / Once More")
@export var accelerate_mult: float = 1.7
@export var once_more_dash_range: float = 260.0     # avanço curto/médio
@export var once_more_dash_time: float = 0.3
@export var once_more_cooldown: int = 3
@export var once_more_extra_skills: int = 1

@export_group("Miau! / Red Princess")
@export var miau_slide_distance: float = 340.0      # o Carrinho comum (slide_distance) é mais curto
@export var miau_slide_duration: float = 0.5
@export var red_princess_range: float = 550.0       # alcance máximo do cruzamento
@export var red_princess_min_range: float = 350.0   # o aliado tem que estar pelo menos este tanto longe
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


## Dourado vivo; as partículas são "faíscas" rápidas, à altura da velocidade dele
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(1.0, 0.8, 0.1)
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(1.0, 0.92, 0.5)
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


## Canto direito da pequena área do gol que o time ADVERSÁRIO defende (= o gol que Chigiri
## ataca). "Direita" = a direita de quem está atacando aquele gol (ver nota no topo do arquivo).
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

	# x: a borda da área mais perto da linha de gol; y: o lado (direita) dela, um pouco
	# recuado para o círculo caber inteiro dentro da pequena área
	var inset: float = golden_zone_radius * 0.6
	var goal_line_x: float = rect.position.x if team == 1 else rect.end.x   # a borda voltada para o gol
	var x: float = goal_line_x + (inset if team == 1 else -inset)
	var y: float = (rect.position.y + inset) if right.y < 0.0 else (rect.end.y - inset)

	return field.to_global(Vector2(x, y))


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

## Suspenso -> Once More (se não estiver em recarga); no chão (ou suspenso com Once More em
## recarga) -> Accelerate normal. can_run() no player.gd já libera Correr estando suspenso.
func start_run() -> void:
	if height_level == Heights.Level.SUSPENDED and not is_on_cooldown(CD_ONCE_MORE):
		_start_once_more()
	else:
		_start_accelerate()


func _start_accelerate() -> void:
	runs_this_turn += 1
	var previous_speed: float = move_speed
	move_speed = previous_speed * accelerate_mult
	run_finished.connect(func() -> void: move_speed = previous_speed, CONNECT_ONE_SHOT)
	run_time_left = run_duration + run_time_bonus
	state = State.RUNNING


## Avanço reto em direção à bola. Não usa o WASD livre do Correr comum: anda até
## once_more_dash_range OU até chegar perto da bola (o que vier primeiro).
func _start_once_more() -> void:
	runs_this_turn += 1
	start_cooldown(CD_ONCE_MORE, once_more_cooldown)   # entra em recarga mesmo se não alcançar a bola
	_run_once_more_dash()


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
		ball.release_hover()
		ball.velocity = Vector2.ZERO
		ball.vel_z = 0.0
		ball.height = Heights.to_height(height_level)   # a bola vem para o nível dele, sob controle
		ball.register_touch(self)
		extra_skill_left += once_more_extra_skills

	state = State.IDLE
	run_finished.emit()


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
		SKILL_MIAU:
			return not is_on_cooldown(CD_MIAU) and get_miau_variant() != MiauVariant.NONE
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_ZONE:
			return await _use_zone_skill()
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
	if not is_zone_active():
		return
	# Círculo dourado translúcido no canto da área do gol inimigo, com uma varredura girando
	var local_center: Vector2 = to_local(_zone_center) + Vector2(0.0, -height)
	var sweep: float = Time.get_ticks_msec() / 1000.0 * 2.2
	draw_arc(local_center, golden_zone_radius, 0.0, TAU, 32, Color(1.0, 0.85, 0.1, 0.22), golden_zone_radius)
	draw_arc(local_center, golden_zone_radius, 0.0, TAU, 32, Color(1.0, 0.9, 0.3, 0.85), 2.0)
	draw_line(local_center, local_center + Vector2(cos(sweep), sin(sweep)) * golden_zone_radius,
		Color(1.0, 0.95, 0.5, 0.7), 2.0)
