class_name Kunigami
extends Player
## Rensuke Kunigami. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Lefty Shot (ação de habilidade; recarga de 3 rodadas, chance de 35%):
##      chute forte em direção ao gol adversário. Funciona com o Kunigami no chão ou suspenso
##      e a bola no chão ou suspensa. Não usa QTE.
## 2. Heroic Clash (ação de habilidade; recarga de 3 rodadas, compartilhada com o Justice Header):
##      disputa física com um inimigo (70% para o Kunigami). Se ganhar, joga o inimigo longe,
##      derruba e o deixa travado (stun). Se perder, só os dois se chocam e nada mais acontece.
##    Justice Header (variante do mesmo botão): Kunigami suspenso com a bola suspensa ou voando
##      perto dele -> cabeceio com mira. Usa a mesma recarga do Heroic Clash.
## 3. Bulk Up (ação de habilidade; recarga de 3 rodadas): prepara o Kunigami por 2 rodadas.
##      Ele só é afetado nas próximas 2 ações (o que vier primeiro: 2 ações ou o fim das rodadas):
##      - Lefty Shot: mais força e +5% de chance
##      - Heroic Clash: +10% de chance de ganhar a disputa
##      - Justice Header: mais força no cabeceio
##      - Correr: 0.7 s a mais
##      - Pular: sobe até o nível Voando
##      - Carrinho: desliza mais longe
##      - Chutar (geral): +5% de chance
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Kunigami" (o nome aparece no placar de gols).
##
## Não precisa de nenhum gancho novo no match_manager.gd nem no player.gd.

const SKILL_LEFTY: StringName = &"lefty_shot"
const SKILL_CLASH: StringName = &"heroic_clash"   # também é o id do Justice Header (variante)
const SKILL_BULK: StringName = &"bulk_up"

## Grupos de recarga (o Heroic Clash e o Justice Header compartilham o mesmo)
const CD_LEFTY: StringName = &"cd_lefty"
const CD_CLASH: StringName = &"cd_clash"
const CD_BULK: StringName = &"cd_bulk"

@export_group("Lefty Shot")
@export_range(0.0, 1.0) var lefty_shot_chance: float = 0.35
@export var lefty_force_mult: float = 1.2          # "forte": multiplica a força do chute
@export var lefty_cooldown: int = 3

@export_group("Heroic Clash")
@export_range(0.0, 1.0) var clash_win_chance: float = 0.70
@export var clash_range: float = 90.0              # distância para escolher o inimigo
@export var clash_bump: float = 18.0               # px que os dois avançam um no outro (visual)
@export var clash_push_distance: float = 160.0     # quanto o inimigo voa para longe se o Kunigami ganhar
@export var clash_push_time: float = 0.35
@export var stun_rounds: int = 2                   # rodadas (contando a atual) em que o inimigo não age
@export var clash_cooldown: int = 3                # recarga compartilhada com o Justice Header

@export_group("Justice Header")
@export_range(0.0, 1.0) var header_shot_chance: float = 0.35   # chance base do cabeceio (ajuste à vontade)

@export_group("Bulk Up")
@export var bulk_actions: int = 2                  # quantas ações são afetadas
@export var bulk_rounds: int = 2                   # duração em rodadas (contando a atual)
@export var bulk_cooldown: int = 3
@export var bulk_lefty_force_mult: float = 1.25    # força extra do Lefty Shot
@export var bulk_header_force_mult: float = 1.3    # força extra do Justice Header
@export_range(0.0, 1.0) var bulk_shot_bonus: float = 0.05    # +5% em Lefty Shot e no Chutar geral
@export_range(0.0, 1.0) var bulk_clash_bonus: float = 0.10   # +10% na disputa do Heroic Clash
@export var bulk_run_bonus: float = 0.7            # segundos a mais no Correr
@export var bulk_slide_mult: float = 1.4           # o Carrinho vai 40% mais longe

@export_group("Visual do chute")
## Aura + partículas laranjas dos chutes de habilidade. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

## Bulk Up: ações que ainda serão afetadas e rodada até a qual vale (-1 = inativo)
var _bulk_charges: int = 0
var _bulk_until_round: int = -1
## O Correr está com o bônus de tempo do Bulk Up aplicado (tirado quando a corrida acaba)
var _run_bonus_pending: bool = false
var _base_slide_distance: float = 0.0
## Flash do choque do Heroic Clash (segundos restantes)
var _clash_flash: float = 0.0
## true enquanto uma habilidade está executando: os chutes dela não gastam o Bulk Up
var _in_skill: bool = false


func _init() -> void:
	character_id = "kunigami"   # o menu de formação usa isto para saber quem é quem
	display_name = "Rensuke Kunigami"   # aparece no placar de gols e no menu


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_base_slide_distance = slide_distance
	run_finished.connect(_on_run_finished)
	slide_finished.connect(_on_slide_finished)


## Laranja (cor principal do personagem); as partículas são brasas que sobem
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(1.0, 0.5, 0.1)
	fx.trail_width = 14.0
	fx.particle_color = Color(1.0, 0.85, 0.4)
	fx.amount = 24
	fx.lifetime = 0.5
	fx.speed_min = 20.0
	fx.speed_max = 80.0
	fx.gravity = Vector2(0.0, -80.0)   # as brasas sobem
	fx.spin = 180.0
	fx.scale_min = 0.12
	fx.scale_max = 0.3
	fx.burst_amount = 16
	fx.burst_speed = 240.0
	return fx


# ---------- BULK UP (estado e consumo das próximas ações) ----------

## O Bulk Up ainda vale agora? (tem ações sobrando e a rodada não passou)
func _bulk_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _bulk_charges > 0 and m.round_number <= _bulk_until_round


## Gasta uma das ações afetadas pelo Bulk Up. Devolve true se ela estava valendo.
func _spend_bulk_charge() -> bool:
	if not _bulk_active():
		return false
	_bulk_charges -= 1
	queue_redraw()
	return true


func _use_bulk() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	if not await play_action(&"bulk_up"):
		return false
	_bulk_charges = bulk_actions
	_bulk_until_round = m.round_number + bulk_rounds - 1   # a rodada atual conta
	start_cooldown(CD_BULK, bulk_cooldown)
	queue_redraw()
	return true


# ---------- AÇÕES GERAIS AFETADAS PELO BULK UP ----------

## Correr: +0.7 s enquanto o bônus estiver valendo (tirado quando a corrida acaba)
func start_run() -> void:
	if _spend_bulk_charge():
		run_time_bonus += bulk_run_bonus
		_run_bonus_pending = true
	super()


func _on_run_finished() -> void:
	if _run_bonus_pending:
		_run_bonus_pending = false
		run_time_bonus -= bulk_run_bonus


## Pular: sobe até o nível Voando (se o Bulk Up estiver valendo)
func jump() -> void:
	if not _spend_bulk_charge():
		await super()
		return
	height_level = Heights.Level.FLYING
	var tw := create_tween()
	tw.tween_property(self, "height", Heights.FLYING_HEIGHT, jump_rise_time * 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


## Carrinho: desliza mais longe (o alcance volta ao normal quando ele termina)
func start_slide(direction: Vector2) -> void:
	slide_distance = _base_slide_distance
	if _spend_bulk_charge():
		slide_distance *= bulk_slide_mult
	super(direction)


func _on_slide_finished() -> void:
	slide_distance = _base_slide_distance


## Chutar (geral): +5% de chance. Os chutes das habilidades não entram aqui (_in_skill).
func kick_ball(ball: Ball, direction: Vector2, kind: KickType, qte_success: bool = true,
		chance_override: float = -1.0, ignore_self_collision: bool = false,
		fx: KickFX = null, anim: StringName = &"") -> void:
	if not _in_skill and _spend_bulk_charge():
		var base_chance: float = chance_override if chance_override >= 0.0 else get_shot_chance(kind)
		chance_override = base_chance + bulk_shot_bonus
	await super(ball, direction, kind, qte_success, chance_override, ignore_self_collision, fx, anim)


# ---------- LEFTY SHOT ----------

## O Kunigami está no chão ou suspenso e a bola no chão ou suspensa (sem QTE, sem voando)?
func _lefty_possible(ball: Ball) -> bool:
	if ball == null or height_level == Heights.Level.FLYING:
		return false
	var kind: KickType = get_kick_type(ball)   # já confere alcance, bola na mão do goleiro, etc.
	return kind == KickType.GROUND or kind == KickType.HIGH_BALL or kind == KickType.VOLLEY


## Direção do gol adversário a partir da bola (o Lefty Shot não usa mira)
func _goal_direction(ball: Ball) -> Vector2:
	var field := get_tree().get_first_node_in_group("field") as Field
	if field:
		return field.get_attack_goal_center(team) - ball.global_position
	return Vector2.RIGHT if team == 0 else Vector2.LEFT


func _use_lefty() -> bool:
	var ball: Ball = _get_ball()
	if not _lefty_possible(ball):
		return false

	var kind: KickType = get_kick_type(ball)
	var boosted: bool = _spend_bulk_charge()   # Bulk Up: gasta a ação afetada antes do chute
	var chance: float = lefty_shot_chance + (bulk_shot_bonus if boosted else 0.0)
	# O multiplicador vale só para este chute (kick_ball consome next_kick_force_mult)
	next_kick_force_mult *= lefty_force_mult * (bulk_lefty_force_mult if boosted else 1.0)

	await kick_ball(ball, _goal_direction(ball), kind, true, chance, false, kick_fx, &"lefty_shot")
	start_cooldown(CD_LEFTY, lefty_cooldown)
	return true


# ---------- HEROIC CLASH e JUSTICE HEADER (mesmo botão, mesma recarga) ----------

## Bola suspensa ou voando perto do Kunigami suspenso -> o botão vira Justice Header
func _header_variant_ok() -> bool:
	var ball: Ball = _get_ball()
	if ball == null or is_down or ball.is_held() or ball.is_locked_for(team):
		return false
	if height_level != Heights.Level.SUSPENDED:
		return false
	var ball_level: Heights.Level = ball.get_level()
	if ball_level != Heights.Level.SUSPENDED and ball_level != Heights.Level.FLYING:
		return false
	return global_position.distance_to(ball.global_position) <= kick_range


## Filtro do alvo: só inimigos de pé podem ser escolhidos para a disputa
func _is_standing(p: Player) -> bool:
	return not p.is_down


## Tem algum inimigo de pé perto o bastante para a disputa?
func _has_clash_target() -> bool:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team != team and not p.is_down and global_position.distance_to(p.global_position) <= clash_range:
			return true
	return false


func _use_clash_skill() -> bool:
	if _header_variant_ok():
		return await _use_header()
	return await _use_clash()


func _use_clash() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	# Escolha do inimigo (clique direito / Esc = cancelou, e aí não gasta nem entra em recarga)
	var enemy: Player = await m.pick_ally_for_skill(self, clash_range, true, Callable(self, "_is_standing"))
	if enemy == null:
		return false
	if not await play_action(&"heroic_clash"):
		return false

	var dir: Vector2 = enemy.global_position - global_position
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT

	var boosted: bool = _spend_bulk_charge()
	var win_chance: float = clash_win_chance + (bulk_clash_bonus if boosted else 0.0)

	await _clash_bump(enemy, dir)
	_clash_flash = 0.4
	var won: bool = randf() < win_chance
	start_cooldown(CD_CLASH, clash_cooldown)
	if won:
		await _push_away(enemy, dir)
	return true


## Os dois avançam um no outro e voltam (o choque visual)
func _clash_bump(enemy: Player, dir: Vector2) -> void:
	var my_start: Vector2 = global_position
	var his_start: Vector2 = enemy.global_position
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", my_start + dir * clash_bump, 0.12)
	tw.tween_property(enemy, "global_position", his_start - dir * clash_bump, 0.12)
	await tw.finished
	var back := create_tween().set_parallel(true)
	back.tween_property(self, "global_position", my_start, 0.2)
	back.tween_property(enemy, "global_position", his_start, 0.2)
	await back.finished


## Vitória: o inimigo voa para longe, cai e fica travado (stun)
func _push_away(enemy: Player, dir: Vector2) -> void:
	enemy.knock_down()
	var target: Vector2 = _clamped_to_pitch(enemy.global_position + dir * clash_push_distance)
	var tw := create_tween()
	tw.tween_property(enemy, "global_position", target, clash_push_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	# Stun: trava total (ações gerais e habilidades) pelas rodadas definidas
	enemy.apply_lock(self, stun_rounds)


## Mantém um ponto global dentro das linhas do campo (o inimigo não voa para fora)
func _clamped_to_pitch(global_pos: Vector2) -> Vector2:
	var field := get_tree().get_first_node_in_group("field") as Field
	if field == null:
		return global_pos
	var local: Vector2 = field.to_local(global_pos)
	var half: Vector2 = field.pitch_size * 0.5
	local = Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return field.to_global(local)


func _use_header() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação
	# A bola pode ter caído enquanto ele mirava: confere de novo
	if not _header_variant_ok():
		return false

	var ball: Ball = _get_ball()
	var boosted: bool = _spend_bulk_charge()
	if boosted:
		next_kick_force_mult *= bulk_header_force_mult
	# VOLLEY = força de voleio e sem QTE (o cabeceio não tem QTE neste personagem)
	await kick_ball(ball, aim, KickType.VOLLEY, true, header_shot_chance, false, kick_fx, &"justice_header")
	start_cooldown(CD_CLASH, clash_cooldown)
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_LEFTY, "name": skill_label("Lefty Shot", CD_LEFTY)})
	var clash_name: String = "Justice Header" if _header_variant_ok() else "Heroic Clash"
	list.append({"id": SKILL_CLASH, "name": skill_label(clash_name, CD_CLASH)})
	var bulk_name: String = "Bulk Up (ativo)" if _bulk_active() else skill_label("Bulk Up", CD_BULK)
	list.append({"id": SKILL_BULK, "name": bulk_name})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_LEFTY:
			return not is_on_cooldown(CD_LEFTY) and _lefty_possible(_get_ball())
		SKILL_CLASH:
			if is_on_cooldown(CD_CLASH):
				return false
			return _header_variant_ok() or _has_clash_target()
		SKILL_BULK:
			# Não reativa enquanto está valendo nem durante a recarga
			return not _bulk_active() and not is_on_cooldown(CD_BULK)
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	_in_skill = true
	var used: bool = false
	match skill_id:
		SKILL_LEFTY:
			used = await _use_lefty()
		SKILL_CLASH:
			used = await _use_clash_skill()
		SKILL_BULK:
			used = await _use_bulk()
	_in_skill = false
	return used


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	if _clash_flash > 0.0:
		_clash_flash = maxf(0.0, _clash_flash - delta)
		queue_redraw()
	if _bulk_active():
		queue_redraw()   # a aura de fogo tremula todo frame


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Aura de fogo translúcida enquanto o Bulk Up está valendo
	if _bulk_active():
		_draw_fire_aura(center)

	# Anel laranja que se expande no choque do Heroic Clash
	if _clash_flash > 0.0:
		var k: float = _clash_flash / 0.4
		var r: float = placeholder_radius + 14.0 + (1.0 - k) * 60.0
		draw_arc(center, r, 0.0, TAU, 40, Color(1.0, 0.55, 0.15, k), 4.0)


func _draw_fire_aura(center: Vector2) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var flicker: float = 0.5 + 0.5 * sin(t * 9.0)
	var ring: float = placeholder_radius + 12.0
	# Halo translúcido (só um anel grosso, para não cobrir o corpo)
	draw_arc(center, ring + 5.0 * flicker, 0.0, TAU, 40, Color(1.0, 0.4, 0.05, 0.25), 8.0)
	# Línguas de fogo saindo para fora, girando devagar
	for i in 6:
		var a: float = TAU * float(i) / 6.0 + t * 1.5
		var out_dir := Vector2(cos(a), sin(a))
		var base_p: Vector2 = center + out_dir * ring
		var tip: Vector2 = base_p + out_dir * (10.0 + 8.0 * flicker)
		var side: Vector2 = out_dir.orthogonal() * 5.0
		draw_colored_polygon(
			PackedVector2Array([base_p + side, base_p - side, tip]),
			Color(1.0, 0.5, 0.1, 0.45)
		)


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_bulk_charges = 0
	_bulk_until_round = -1
	_run_bonus_pending = false
	_clash_flash = 0.0
	slide_distance = _base_slide_distance
	queue_redraw()
