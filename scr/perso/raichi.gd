class_name Raichi
extends Player
## Raichi. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias. Tudo é amarelo.
##
## 1. Stalker (ação de habilidade; recarga de 3 rodadas): prende um inimigo próximo com uma corrente.
##      Ele perde 5% de chance em todos os chutes. Acaba depois de 2 rodadas ou quando Raichi usa Correr.
##    Dog Trick (variante, mesmo botão, recarga própria de 2 rodadas): Raichi suspenso e bola suspensa
##      ou voando perto dele -> defletê-la na direção contrária.
## 2. Radius (ação de habilidade; recarga de 3 rodadas): um esquadro amarelo translúcido de 180 graus
##      que aponta para o inimigo mais próximo. Quem está dentro dele corre bem menos e não pode usar
##      habilidades. Dura 3 rodadas.
## 3. Sexy Mode (ação de habilidade; recarga de 3 rodadas): dura 3 rodadas e melhora tudo:
##      - Stalker: a punição sobe para 10%
##      - Dog Trick: vira um passe rasteiro (mesmos requisitos)
##      - Radius: o inimigo fica ainda mais lento e a área aumenta
##      - Correr: +0.7 s
##      - Carrinho: um pouco mais longo
##    Enquanto estiver ativo aparece um halo amarelo pulsante e o aviso "SEXY MODE" acima de Raichi.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Raichi" (o nome aparece no placar de gols).
##
## Não precisa de nenhum gancho novo no match_manager.gd nem no player.gd.
## Raichi entra no grupo "control_sources" para controlar o Radius (proíbe habilidades).

const SKILL_STALKER: StringName = &"stalker"       # também é o id do Dog Trick (variante)
const SKILL_RADIUS: StringName = &"radius"
const SKILL_SEXY: StringName = &"sexy_mode"

## Grupos de recarga (Dog Trick tem recarga própria, separada do Stalker)
const CD_STALKER: StringName = &"cd_stalker"
const CD_DOG: StringName = &"cd_dog"
const CD_RADIUS: StringName = &"cd_radius"
const CD_SEXY: StringName = &"cd_sexy"

## Abertura do esquadro do Radius (graus, fixo)
const RADIUS_ANGLE: float = PI   # 180 graus

const YELLOW := Color(1.0, 0.92, 0.1)

@export_group("Stalker")
@export var stalk_range: float = 120.0            # distância para escolher o inimigo
@export_range(0.0, 1.0) var stalk_penalty: float = 0.10        # -5% nos chutes dele
@export_range(0.0, 1.0) var stalk_penalty_sexy: float = 0.15   # -10% com Sexy Mode
@export var stalk_rounds: int = 2                 # duração (contando a atual)
@export var stalker_cooldown: int = 3

@export_group("Dog Trick")
@export var dog_cooldown: int = 2

@export_group("Radius")
@export var radius_range: float = 150.0           # raio do esquadro
@export var radius_cast_range: float = 250.0      # o inimigo mais próximo precisa estar a até isso
@export var radius_rounds: int = 3
@export var radius_cooldown: int = 3
@export var radius_slow: float = 0.9              # segundos tirados do Correr do inimigo dentro da área
@export var radius_slow_sexy: float = 1.2         # idem com Sexy Mode
@export var radius_area_mult_sexy: float = 1.3   # área maior com Sexy Mode

@export_group("Sexy Mode")
@export var sexy_rounds: int = 3
@export var sexy_cooldown: int = 3
@export var sexy_run_bonus: float = 0.7           # segundos a mais no Correr
@export var sexy_slide_mult: float = 1.3          # Carrinho mais longo

@export_group("Visual do chute")
## Aura + partículas amarelas dos chutes de habilidade. Vazio = usa o estilo padrão
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: stalker, radius, sexy_mode.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}

## Inimigos presos pelo Stalker: Player -> rodada até a qual a corrente vale
var _stalks: Dictionary = {}
## Última posição conhecida de cada inimigo preso (para saber o quanto ele andou)
var _stalk_last_pos: Dictionary = {}
## Radius: direção do esquadro (fixa no momento em que foi usado) e rodada final (-1 = inativo)
var _radius_dir: Vector2 = Vector2.RIGHT
var _radius_until: int = -1
## Quanto de Correr foi tirado de cada inimigo pelo Radius (Player -> valor aplicado, negativo)
var _radius_applied: Dictionary = {}
## Sexy Mode vale até o fim desta rodada (-1 = inativo)
var _sexy_until: int = -1
var _run_bonus_pending: bool = false
var _base_slide_distance: float = 0.0


func _init() -> void:
	character_id = "raichi"   # o menu de formação usa isto para saber quem é quem
	display_name = "Raichi"


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_base_slide_distance = slide_distance
	add_to_group("control_sources")   # o Radius proíbe habilidades de quem está na área
	run_finished.connect(_on_run_finished)
	slide_finished.connect(_on_slide_finished)


## Amarelo neon; as partículas são faíscas que sobem
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = YELLOW
	fx.trail_width = 14.0
	fx.particle_color = Color(1.0, 1.0, 0.6)
	fx.amount = 24
	fx.lifetime = 0.5
	fx.speed_min = 20.0
	fx.speed_max = 90.0
	fx.gravity = Vector2(0.0, -70.0)
	fx.spin = 300.0
	fx.scale_min = 0.12
	fx.scale_max = 0.3
	fx.burst_amount = 16
	fx.burst_speed = 240.0
	return fx


# ---------- ESTADO DAS HABILIDADES ----------

func _sexy_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _sexy_until >= 0 and m.round_number <= _sexy_until


func _radius_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _radius_until >= 0 and m.round_number <= _radius_until


## Raio atual do esquadro (maior com Sexy Mode)
func radius_current() -> float:
	return radius_range * (radius_area_mult_sexy if _sexy_active() else 1.0)


## Este inimigo está dentro do esquadro do Radius agora?
func _in_radius(p: Player) -> bool:
	if not _radius_active() or p.team == team:
		return false
	var offset: Vector2 = p.global_position - global_position
	if offset.length() > radius_current():
		return false
	return absf(_radius_dir.angle_to(offset)) <= RADIUS_ANGLE * 0.5


# ---------- STALKER (corrente) ----------

func _stalk_penalty() -> float:
	return stalk_penalty_sexy if _sexy_active() else stalk_penalty


## Solta todas as correntes (chamado quando Raichi usa Correr)
func _release_all_stalks() -> void:
	for key in _stalks.keys():
		var p: Player = key as Player
		if is_instance_valid(p):
			# Valor 0 com rodada -1: a penalidade deste Raichi some na próxima leitura
			p.apply_shot_debuff(0.0, -1, self)
	_stalks.clear()
	_stalk_last_pos.clear()


## Corrente grudada: quando o inimigo preso anda, Raichi anda junto a mesma distância
func _drag_stalked() -> void:
	var pull: Vector2 = Vector2.ZERO
	for key in _stalks.keys():
		var p: Player = key as Player
		if not is_instance_valid(p):
			continue
		var now: Vector2 = p.global_position
		var last: Vector2 = _stalk_last_pos.get(key, now)
		pull += now - last
		_stalk_last_pos[key] = now
	if pull != Vector2.ZERO:
		global_position += pull


## Tira as correntes que já expiraram pelo tempo
func _prune_stalks() -> void:
	var round_now: int = _get_manager().round_number if _get_manager() else 0
	for key in _stalks.keys():
		var p: Player = key as Player
		if not is_instance_valid(p) or round_now > int(_stalks[key]):
			if is_instance_valid(p):
				p.apply_shot_debuff(0.0, -1, self)
			_stalks.erase(key)
			_stalk_last_pos.erase(key)


func _not_stalked(p: Player) -> bool:
	return not _stalks.has(p)


## Inimigo próximo que ainda não está preso
func _stalk_target_in_range() -> bool:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team != team and not _stalks.has(p) \
				and global_position.distance_to(p.global_position) <= stalk_range:
			return true
	return false


func _use_stalker() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	# Escolha do inimigo (cancelou = não gasta nem começa a recarga)
	var target: Player = await m.pick_ally_for_skill(self, stalk_range, true, Callable(self, "_not_stalked"))
	if target == null:
		return false
	if not await play_action(&"stalker"):
		return false
	var until: int = m.round_number + stalk_rounds - 1   # a rodada atual conta
	_stalks[target] = until
	_stalk_last_pos[target] = target.global_position
	target.apply_shot_debuff(_stalk_penalty(), until, self)
	start_cooldown(CD_STALKER, stalker_cooldown)
	queue_redraw()
	return true


# ---------- DOG TRICK (defletir, ou passe rasteiro no Sexy Mode) ----------

## Raichi suspenso e bola suspensa ou voando perto dele
func _dog_ok() -> bool:
	var ball: Ball = _get_ball()
	if ball == null or is_down or ball.is_held() or ball.is_locked_for(team):
		return false
	if height_level != Heights.Level.SUSPENDED:
		return false
	var ball_level: Heights.Level = ball.get_level()
	if ball_level != Heights.Level.SUSPENDED and ball_level != Heights.Level.FLYING:
		return false
	return global_position.distance_to(ball.global_position) <= kick_range


func _use_dog_trick() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or not _dog_ok():
		return false

	# Sexy Mode: passe rasteiro para um aliado no alcance do passe
	if _sexy_active():
		var ally: Player = await m.pick_ally_for_skill(self, m.ground_pass_range, false)
		if ally == null:
			return false   # cancelou
		if not _dog_ok():
			return false
		start_cooldown(CD_DOG, dog_cooldown)
		await m.run_ground_pass(self, ally, ball)
		return true

	# Defletir: manda a bola de volta, na direção contrária ao movimento dela
	var dir: Vector2 = -ball.velocity
	if dir.length() < 1.0:
		dir = ball.global_position - global_position
	await kick_ball(ball, dir, KickType.VOLLEY, true, -1.0, false, kick_fx, &"dog_trick")
	start_cooldown(CD_DOG, dog_cooldown)
	return true


# ---------- RADIUS (esquadro de 180 graus) ----------

## Inimigo mais próximo dentro de max_dist (null = nenhum)
func _nearest_enemy(max_dist: float) -> Player:
	var best: Player = null
	var best_dist: float = max_dist
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team:
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d <= best_dist:
			best = p
			best_dist = d
	return best


func _use_radius() -> bool:
	var m: MatchManager = _get_manager()
	var target: Player = _nearest_enemy(radius_cast_range)
	if m == null or target == null:
		return false
	if not await play_action(&"radius"):
		return false
	_radius_dir = (target.global_position - global_position).normalized()
	_radius_until = m.round_number + radius_rounds - 1   # a rodada atual conta
	start_cooldown(CD_RADIUS, radius_cooldown)
	queue_redraw()
	return true


## Mantém o Correr de quem está dentro do esquadro menor, e devolve tudo ao sair ou acabar.
## Também proíbe as habilidades de quem está lá (ver suppresses_skills_of).
func _sync_radius() -> void:
	var active: bool = _radius_active()
	if not active:
		_clear_radius()
		return
	var slow: float = radius_slow_sexy if _sexy_active() else radius_slow
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team:
			continue
		var target: float = -slow if _in_radius(p) else 0.0
		var applied: float = float(_radius_applied.get(p, 0.0))
		if is_equal_approx(target, applied):
			continue
		p.run_time_bonus += target - applied
		if target == 0.0:
			_radius_applied.erase(p)
		else:
			_radius_applied[p] = target


func _clear_radius() -> void:
	for key in _radius_applied.keys():
		var p: Player = key as Player
		if is_instance_valid(p):
			p.run_time_bonus -= float(_radius_applied[key])
	_radius_applied.clear()


## Controle: quem está dentro do esquadro não usa habilidades (Player consulta isto)
func suppresses_skills_of(p: Player) -> bool:
	return _in_radius(p)


# ---------- SEXY MODE ----------

func _use_sexy() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	if not await play_action(&"sexy_mode"):
		return false
	_sexy_until = m.round_number + sexy_rounds - 1   # a rodada atual conta
	start_cooldown(CD_SEXY, sexy_cooldown)
	queue_redraw()
	return true


# ---------- AÇÕES GERAIS AFETADAS PELO RAICHI ----------

## Correr: solta as correntes do Stalker e ganha +0.7 s no Sexy Mode
func start_run() -> void:
	_release_all_stalks()
	if _sexy_active():
		run_time_bonus += sexy_run_bonus
		_run_bonus_pending = true
	super()


func _on_run_finished() -> void:
	if _run_bonus_pending:
		_run_bonus_pending = false
		run_time_bonus -= sexy_run_bonus


## Carrinho: um pouco mais longo no Sexy Mode
func start_slide(direction: Vector2) -> void:
	slide_distance = _base_slide_distance * (sexy_slide_mult if _sexy_active() else 1.0)
	super(direction)


func _on_slide_finished() -> void:
	slide_distance = _base_slide_distance


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if _dog_ok():
		list.append({"id": SKILL_STALKER, "name": skill_label("Dog Trick", CD_DOG)})
	else:
		list.append({"id": SKILL_STALKER, "name": skill_label("Stalker", CD_STALKER)})
	var radius_name: String = "Radius (ativo)" if _radius_active() else skill_label("Radius", CD_RADIUS)
	list.append({"id": SKILL_RADIUS, "name": radius_name})
	var sexy_name: String = "Sexy Mode (ativo)" if _sexy_active() else skill_label("Sexy Mode", CD_SEXY)
	list.append({"id": SKILL_SEXY, "name": sexy_name})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_STALKER:
			if _dog_ok():
				return not is_on_cooldown(CD_DOG)
			return not is_on_cooldown(CD_STALKER) and _stalk_target_in_range()
		SKILL_RADIUS:
			# Sem reativar enquanto está valendo; precisa de um inimigo perto para apontar
			return not _radius_active() and not is_on_cooldown(CD_RADIUS) \
				and _nearest_enemy(radius_cast_range) != null
		SKILL_SEXY:
			return not _sexy_active() and not is_on_cooldown(CD_SEXY)
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_STALKER:
			if _dog_ok():
				return await _use_dog_trick()
			return await _use_stalker()
		SKILL_RADIUS:
			return await _use_radius()
		SKILL_SEXY:
			return await _use_sexy()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_STALKER:
			title = "Dog Trick" if _dog_ok() else "Stalker"
			text = ("Stalker: prende com uma corrente um inimigo a até %d px. Ele perde %d%% de chance de gol em todos os chutes por %d rodadas (%d%% com Sexy Mode). Acaba antes se Raichi usar Correr; enquanto durar, se o inimigo andar, Raichi é puxado junto. Recarga: %d rodadas.\n"
				+ "Dog Trick (aparece no lugar quando Raichi está suspenso e a bola está suspensa ou voando perto dele): defleta a bola na direção contrária à que ela vinha; com Sexy Mode vira um passe rasteiro para um aliado. Recarga própria: %d rodadas.") % [
				int(stalk_range), _pct(stalk_penalty), stalk_rounds, _pct(stalk_penalty_sexy), stalker_cooldown,
				dog_cooldown]
		SKILL_RADIUS:
			title = "Radius"
			text = ("Cria um esquadro amarelo de %d° (raio de %d px) apontando para o inimigo mais próximo, que precisa estar a até %d px. A direção fica fixa. Inimigos dentro dele correm %.1f s a menos e não podem usar habilidades. Dura %d rodadas. Com Sexy Mode: raio %d%% maior e %.1f s a menos.\n"
				+ "Recarga: %d rodadas.") % [
				int(rad_to_deg(RADIUS_ANGLE)), int(radius_range), int(radius_cast_range), radius_slow,
				radius_rounds, _pct(radius_area_mult_sexy - 1.0), radius_slow_sexy, radius_cooldown]
		SKILL_SEXY:
			title = "Sexy Mode"
			text = ("Dura %d rodadas e melhora tudo:\n"
				+ "• Stalker: a punição sobe para %d%%.\n"
				+ "• Dog Trick: vira um passe rasteiro (mesmos requisitos).\n"
				+ "• Radius: inimigos ficam ainda mais lentos e a área aumenta.\n"
				+ "• Correr dura +%.1f s e o Carrinho fica %d%% mais longo.\n"
				+ "Recarga: %d rodadas.") % [
				sexy_rounds, _pct(stalk_penalty_sexy), sexy_run_bonus, _pct(sexy_slide_mult - 1.0),
				sexy_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_stalks.clear()             # as penalidades dos inimigos somem com o reset deles
	_stalk_last_pos.clear()
	_radius_applied.clear()     # idem para o Correr deles
	_radius_until = -1
	_sexy_until = -1
	_run_bonus_pending = false
	slide_distance = _base_slide_distance
	queue_redraw()


# ---------- LOOP ----------

func _physics_process(delta: float) -> void:
	super(delta)
	_drag_stalked()
	_sync_radius()
	_prune_stalks()


func _process(delta: float) -> void:
	super(delta)
	# Efeitos animados (correntes, esquadro, halo) redesenham todo frame enquanto existirem
	if _radius_active() or _sexy_active() or not _stalks.is_empty():
		queue_redraw()


# ---------- VISUAL ----------

func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Corrente amarela ligando Raichi a cada inimigo preso
	for key in _stalks.keys():
		var p: Player = key as Player
		if is_instance_valid(p):
			_draw_chain(center, to_local(p.global_position) + Vector2(0.0, -p.height))

	# Esquadro de 180 graus amarelo translúcido
	if _radius_active():
		_draw_radius()

	# Sexy Mode: halo pulsante e aviso acima da cabeça
	if _sexy_active():
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		draw_arc(center, placeholder_radius + 14.0 + 3.0 * pulse, 0.0, TAU, 40,
			Color(1.0, 0.92, 0.1, 0.6 + 0.4 * pulse), 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(-40.0, -placeholder_radius - height - 26.0),
			"SEXY MODE", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, YELLOW)


## Corrente em zigue-zague (pequena, presa aos dois)
func _draw_chain(a: Vector2, b: Vector2) -> void:
	var steps: int = 6
	var pts := PackedVector2Array()
	var perp: Vector2 = (b - a).normalized().orthogonal()
	for i in range(steps + 1):
		var f: float = float(i) / float(steps)
		var offset: float = 3.5 if i % 2 == 0 else -3.5
		if i == 0 or i == steps:
			offset = 0.0
		pts.append(a.lerp(b, f) + perp * offset)
	draw_polyline(pts, Color(1.0, 0.92, 0.1, 0.95), 2.5)


func _draw_radius() -> void:
	var r: float = radius_current()
	var base_ang: float = _radius_dir.angle()
	var segs: int = 28
	var outline := PackedVector2Array([Vector2.ZERO])
	for i in range(segs + 1):
		var a: float = base_ang - RADIUS_ANGLE * 0.5 + RADIUS_ANGLE * float(i) / float(segs)
		outline.append(Vector2.from_angle(a) * r)
	draw_colored_polygon(outline, Color(1.0, 0.95, 0.2, 0.22))
	var closed := outline.duplicate()
	closed.append(Vector2.ZERO)
	draw_polyline(closed, Color(1.0, 0.95, 0.2, 0.9), 2.0)
