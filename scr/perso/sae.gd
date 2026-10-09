class_name Sae
extends Player
## Sae. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias.
## NÃO precisa de mudanças em nenhum outro arquivo: usa só a API que já existe no Player,
## na Ball e no MatchManager.
##
## HABILIDADE 1 (botão muda conforme a situação; recarga de 2 rodadas COMPARTILHADA)
##  - Perfect Pass: Sae no chão + bola próxima (chão ou suspensa). Aparece um painel para escolher
##      em que estado a bola CHEGA (Chão / Suspensa / Voando); a trajetória se adapta. Escolhe o
##      aliado (alcance 600). A bola chega NESTA rodada. Inimigo que tentar interceptar no caminho
##      faz um QTE difícil. O receptor faz um QTE fácil: acertando, ganha +7% no próximo chute.
##  - Flawless: Sae e bola suspensos. Passe alto: escolhe o ponto exato onde a bola cai (como o
##      Rabona Cross). Inimigo que mexer na bola no meio da trajetória enfrenta uma disputa de
##      sorte (70% Sae). O receptor faz um QTE difícil; acertando, ganha +10% no próximo chute.
##  - Unbalanced: Sae no chão, SEM bola próxima. Vai até um inimigo; enquanto Sae ficar perto
##      (ou por 2 rodadas) as habilidades do inimigo ficam bloqueadas.
## HABILIDADE 2 (recarga 2, compartilhada)
##  - Royalty: bola próxima no chão. Gruda a bola e corre (menos tempo e mais rápido que o Correr)
##      sem poder perder a bola. Derruba quem encontrar e passa direto; se derrubou alguém,
##      libera o complemento Royal Heelflick.
##  - Royal Heelflick (complemento GRATUITO): toque para frente/cima; a bola fica suspensa, Sae
##      salta até ela (suspenso) e ganha +1 ação de habilidade.
##  - Ultra Vision: SEM bola próxima. Por 2 rodadas: +1 ação geral para os secundários, +50 de
##      alcance no Passe e nas habilidades, +5% nos chutes do Sae e limpa os efeitos negativos
##      que ele já tinha. A recarga só começa quando o efeito acaba.
## HABILIDADE 3 (recarga 3, compartilhada)
##  - Beautiful Shot: Sae e bola no chão (ou os dois suspensos). Chute levemente curvo e mais
##      forte, 45%. PASSIVA: a cada defesa (agarrada) do goleiro adversário, +3% de chance nos
##      chutes do Sae (máx. +30%). Zera a cada gol, de qualquer time.
##  - Lead Actor: com a bola nas laterais do gol inimigo, o chute vira esta variante: curva
##      maior, a bola sobe a "voando" no meio e cai logo depois. QTE difícil, 50%.
##
## ASSUMIÇÕES (o pedido não definia; ajuste nos @export):
##  - Os QTEs de receptor rodam AUTOMATICAMENTE quando a bola chega (e errar não tem punição):
##    ler "se quiser interagir" como opcional exigiria um gancho no MatchManager.
##  - Ultra Vision vale só para o Sae (alcance e chute); a ação geral extra vale para os secundários.
##  - Ultra Vision limpa trava, penalidades de chute e confusão. Efeitos que outros personagens
##    aplicam "consultando" o dono (ex: lentidão do Yo.. do Lorenzo) não dá para limpar daqui.
##
## Montagem: Nova Cena Herdada de player.tscn -> anexe este script no nó raiz -> nomeie "Sae".
## Registre o character_id "sae" onde você registra os outros no menu de formação.
##
## Animações opcionais (SpriteFrames): perfect_pass, flawless, unbalanced, royalty, royal_heelflick,
## ultra_vision, beautiful_shot, lead_actor. As que faltarem usam os fallbacks do Player.

const SKILL_PASS: StringName = &"sae_pass"     # Perfect Pass / Flawless / Unbalanced
const SKILL_ROYAL: StringName = &"sae_royal"   # Royalty / Ultra Vision
const SKILL_HEEL: StringName = &"sae_heel"     # Royal Heelflick (complemento gratuito)
const SKILL_SHOT: StringName = &"sae_shot"     # Beautiful Shot / Lead Actor

const CD_PASS: StringName = &"cd_sae_pass"
const CD_ROYAL: StringName = &"cd_sae_royal"
const CD_SHOT: StringName = &"cd_sae_shot"

const PINK := Color(1.0, 0.05, 0.55)
const PINK_LIGHT := Color(1.0, 0.6, 0.82)
const BLACK := Color(0.04, 0.0, 0.04)

enum PassMode { NONE, PERFECT, FLAWLESS, UNBALANCED }

@export_group("Geral")
@export var near_ball_range: float = 90.0        # "bola próxima"

@export_group("Perfect Pass")
@export var pass_range: float = 600.0
@export var pass_speed: float = 800.0
@export var pass_cooldown: int = 2
@export var pass_receive_bonus: float = 0.07     # +7% no próximo chute do receptor
@export var pass_arch_suspended: float = 22.0    # quanto a bola "sobe além" no meio do caminho
@export var pass_arch_flying: float = 36.0

@export_group("Flawless")
@export var flawless_range: float = 600.0
@export_range(0.0, 1.0) var flawless_win_chance: float = 0.70   # chance do Sae na disputa
@export var flawless_receive_bonus: float = 0.10
@export var flawless_receive_radius: float = 90.0   # aliado a esta distância do ponto = receptor

@export_group("Unbalanced")
@export var unbalanced_range: float = 300.0
@export var unbalanced_leash: float = 330.0      # se afastar além disso solta o inimigo
@export var unbalanced_rounds: int = 2
@export var unbalanced_dash_time: float = 0.25
@export var unbalanced_stop_distance: float = 40.0

@export_group("Royalty / Royal Heelflick")
@export var royal_duration_mult: float = 0.7     # fração da duração do Correr
@export var royal_speed_mult: float = 1.2
@export var royal_ball_offset: float = 30.0
@export var royal_hit_radius: float = 48.0
@export var royal_cooldown: int = 2
@export var heel_ball_range: float = 110.0
@export var heel_distance: float = 90.0
@export var heel_time: float = 0.3

@export_group("Ultra Vision")
@export var uv_rounds: int = 2
@export var uv_range_bonus: float = 50.0         # Passe e habilidades do Sae
@export var uv_shot_bonus: float = 0.05
@export var uv_extra_general: int = 1            # ação geral extra dos secundários

@export_group("Beautiful Shot / Lead Actor")
@export_range(0.0, 1.0) var beautiful_chance: float = 0.45
@export var beautiful_force_mult: float = 1.3
@export var beautiful_curve_total_deg: float = 18.0
@export var beautiful_curve_deg_per_sec: float = 45.0
@export_range(0.0, 1.0) var lead_chance: float = 0.50
@export var lead_curve_total_deg: float = 45.0
@export var lead_curve_deg_per_sec: float = 100.0
@export var lead_range: float = 520.0            # distância horizontal do chute voador
@export var lead_zone_depth: float = 450.0       # até onde da linha de fundo vale "lateral"
@export var lead_zone_min_y: float = 130.0       # |y| mínimo (fora das traves = lateral)
@export var shot_cooldown: int = 3
@export var save_bonus_step: float = 0.03        # passiva: +3% por defesa do goleiro
@export var save_bonus_max: float = 0.30

@export_group("Visual do chute")
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Chaves: sae_pass, sae_royal, sae_heel, sae_shot
@export var skill_icons: Dictionary = {}

signal _level_chosen(level: int)

var _epoch: int = 0                 # muda a cada partida nova (corrotinas antigas desistem)
var _base_move_speed: float = 0.0
var _base_run_duration: float = 0.0

# --- Perfect Pass: painel de escolha ---
var _choosing_level: bool = false
var _level_layer: CanvasLayer = null

# --- Flawless (acompanhamento) ---
var _flaw_active: bool = false
var _flaw_point: Vector2 = Vector2.ZERO
var _flaw_touches: int = 0
var _flaw_last: Player = null
var _flaw_prev: Player = null
var _flaw_snap_pos: Vector2 = Vector2.ZERO
var _flaw_snap_h: float = 0.0
var _flaw_stage: int = 0
var _flaw_landed: bool = false

# --- Unbalanced ---
var _unbal_target: Player = null

# --- Royalty ---
var _royal_active: bool = false
var _royal_ball: Ball = null
var _royal_prev_owner: Player = null
var _royal_hits: Array[Player] = []
var _royal_hit_any: bool = false
var _royal_ready: bool = false      # Royal Heelflick liberado neste turno

# --- Ultra Vision ---
var _uv_until: int = -1
var _uv_pass_applied: float = 0.0
var _uv_turn_key: int = -1

# --- Passiva do Beautiful Shot ---
var _saves: int = 0
var _prev_held: bool = false

# --- Visual ---
var _pulse: float = 0.0
var _pulse_target: Vector2 = Vector2.ZERO
var _popup_text: String = ""
var _popup_left: float = 0.0


func _init() -> void:
	character_id = "sae"
	display_name = "Sae"


func _ready() -> void:
	super()
	_base_move_speed = move_speed
	_base_run_duration = run_duration
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_connect_manager.call_deferred()


func _connect_manager() -> void:
	var m: MatchManager = _get_manager()
	if m == null:
		return
	if not m.turn_ended.is_connected(_on_turn_ended):
		m.turn_ended.connect(_on_turn_ended)
	if not m.goal_scored.is_connected(_on_goal_scored):
		m.goal_scored.connect(_on_goal_scored)
	if not m.state_changed.is_connected(_on_state_changed):
		m.state_changed.connect(_on_state_changed)


func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = PINK
	fx.additive = false
	fx.trail_width = 16.0
	fx.particle_color = PINK_LIGHT
	fx.amount = 24
	fx.lifetime = 0.5
	fx.speed_min = 20.0
	fx.speed_max = 80.0
	fx.gravity = Vector2(0.0, -40.0)
	fx.scale_min = 0.15
	fx.scale_max = 0.35
	fx.burst_amount = 14
	fx.burst_speed = 220.0
	return fx


# ---------- SINAIS DO MANAGER ----------

func _on_turn_ended(turn_team: int) -> void:
	if turn_team == team and _royal_ready:
		_royal_ready = false   # o complemento só vale no turno em que foi liberado
		queue_redraw()


## Gol (de qualquer time): a passiva do Beautiful Shot zera
func _on_goal_scored(_goal: Dictionary) -> void:
	_saves = 0
	queue_redraw()


## Ultra Vision: no começo do turno do time (já com o Protagonista escolhido) cada secundário
## ganha a ação geral extra. Uma vez por turno.
func _on_state_changed() -> void:
	if not _uv_active():
		return
	var m: MatchManager = _get_manager()
	if m == null or m.current_team != team or m.phase != MatchManager.Phase.CHOOSING_ACTION:
		return
	var key: int = _turn_key(m)
	if key == _uv_turn_key:
		return
	_uv_turn_key = key
	m.secondary_general_left += uv_extra_general


func _turn_key(m: MatchManager) -> int:
	return m.round_number * 8 + m.current_team


# ---------- UTILIDADES ----------

func _uv_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _uv_until >= 0 and m.round_number <= _uv_until


## Alcance com o bônus da Ultra Vision
func _range(base: float) -> float:
	return base + (uv_range_bonus if _uv_active() else 0.0)


func _save_bonus() -> float:
	return minf(float(_saves) * save_bonus_step, save_bonus_max)


## Bônus total nos chutes do Sae (passiva + Ultra Vision)
func _shot_bonus() -> float:
	return _save_bonus() + (uv_shot_bonus if _uv_active() else 0.0)


## Vale também para o Chutar geral
func get_shot_chance(kind: KickType) -> float:
	return minf(super(kind) + _shot_bonus(), 1.0)


func _ball_free(ball: Ball) -> bool:
	return ball != null and not ball.is_held() and not ball.is_locked_for(team)


## Bola livre, ao alcance da mão e numa altura que o Sae alcança
func _ball_near() -> bool:
	var ball: Ball = _get_ball()
	return _ball_free(ball) and can_reach_level(ball.get_level()) \
		and global_position.distance_to(ball.global_position) <= near_ball_range


func _ball_near_ground() -> bool:
	return _ball_near() and _get_ball().get_level() == Heights.Level.GROUND


func _can_receive(other: Player) -> bool:
	return not other.is_pass_blocked()


func _has_ally_in(range_px: float) -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other != self and other.team == team and _can_receive(other) \
				and global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


func _has_enemy_in(range_px: float) -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team != team and global_position.distance_to(other.global_position) <= range_px:
			return true
	return false


## QTE com título próprio (mesma regra do MatchManager: fácil = voleio, difícil = bola voando)
func _run_sae_qte(hard: bool, title: String) -> bool:
	var m: MatchManager = _get_manager()
	if m == null or m.match_over:
		return false
	var qte := QTE.new()
	m.add_child(qte)
	if hard:
		qte.start(QTE.HARD_KEYS, m.flying_qte_keys, m.flying_qte_time_per_key, title)
	else:
		qte.start(QTE.EASY_KEYS, m.volley_qte_keys, m.volley_qte_time_per_key, title)
	var ok: bool = await qte.finished
	return ok


func _dash_to(target: Player, time: float, stop_distance: float) -> void:
	var offset: Vector2 = global_position - target.global_position
	var dist: float = offset.length()
	if dist < 1.0:
		return
	var dest: Vector2 = target.global_position + offset / dist * stop_distance
	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", dest, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


func _set_pass_through(on: bool) -> void:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		if on:
			add_collision_exception_with(other)
			other.add_collision_exception_with(self)
		else:
			remove_collision_exception_with(other)
			other.remove_collision_exception_with(self)


func _nudge_out_of_players(dir: Vector2) -> void:
	for _i in 8:
		var overlapping: bool = false
		for other: Player in get_tree().get_nodes_in_group("players"):
			if other != self and other.height_level == height_level \
					and global_position.distance_to(other.global_position) < body_radius + other.body_radius:
				overlapping = true
				break
		if not overlapping:
			return
		global_position += dir * 10.0


# ---------- HABILIDADE 1: QUAL VARIANTE? ----------

func _pass_mode() -> PassMode:
	var ball: Ball = _get_ball()
	var near: bool = _ball_near()
	if height_level == Heights.Level.GROUND:
		if near:
			return PassMode.PERFECT   # bola próxima no chão ou suspensa (o que o Sae alcança)
		return PassMode.UNBALANCED
	if height_level == Heights.Level.SUSPENDED and near and ball.get_level() == Heights.Level.SUSPENDED:
		return PassMode.FLAWLESS
	return PassMode.NONE


func _pass_skill_name() -> String:
	match _pass_mode():
		PassMode.FLAWLESS:
			return "Flawless"
		PassMode.UNBALANCED:
			return "Unbalanced"
		PassMode.PERFECT:
			return "Perfect Pass"
	return "Flawless" if height_level != Heights.Level.GROUND else "Perfect Pass"


func _use_pass() -> bool:
	match _pass_mode():
		PassMode.PERFECT:
			return await _use_perfect_pass()
		PassMode.FLAWLESS:
			return await _use_flawless()
		PassMode.UNBALANCED:
			return await _use_unbalanced()
	return false


# ---------- PERFECT PASS ----------

func _use_perfect_pass() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false
	var epoch: int = _epoch

	var level: int = await _choose_pass_level()
	if level < 0 or epoch != _epoch:
		return false

	var target: Player = await m.pick_ally_for_skill(self, _range(pass_range), false, Callable(self, "_can_receive"))
	if target == null or epoch != _epoch:
		return false
	if not _ball_near():
		return false

	var done: bool = await _run_perfect_pass(target, ball, level)
	if epoch != _epoch:
		return false
	if not done:
		return false
	start_cooldown(CD_PASS, pass_cooldown)
	return true


## Painel com as 3 opções de chegada. Devolve o nível (Heights.Level) ou -1 se cancelou.
func _choose_pass_level() -> int:
	_choosing_level = true
	_level_layer = CanvasLayer.new()
	_level_layer.layer = 60
	add_child(_level_layer)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_layer.add_child(vb)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _box(Color(BLACK, 0.92), PINK, 3, 10, 12))
	vb.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	var title := Label.new()
	title.text = "Perfect Pass: em que estado a bola chega?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", PINK_LIGHT)
	inner.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(row)
	var options: Array = [["Chão", Heights.Level.GROUND], ["Suspensa", Heights.Level.SUSPENDED],
		["Voando", Heights.Level.FLYING]]
	for entry in options:
		var lvl: int = int(entry[1])
		var b: Button = _make_button(String(entry[0]), PINK)
		b.pressed.connect(func() -> void: _level_chosen.emit(lvl))
		row.add_child(b)

	var cancel: Button = _make_button("Cancelar", Color(0.75, 0.75, 0.75))
	cancel.pressed.connect(func() -> void: _level_chosen.emit(-1))
	inner.add_child(cancel)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 150.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer)

	var chosen: int = await _level_chosen
	_choosing_level = false
	if _level_layer != null and is_instance_valid(_level_layer):
		_level_layer.queue_free()
	_level_layer = null
	return chosen


func _make_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110.0, 38.0)
	b.add_theme_stylebox_override("normal", _box(color, BLACK, 2, 6, 6))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.25), BLACK, 3, 6, 6))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.25), BLACK, 3, 6, 6))
	b.add_theme_stylebox_override("focus", _box(color, BLACK, 2, 6, 6))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, BLACK)
	return b


func _box(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## Esc / clique direito fecha o painel
func _unhandled_input(event: InputEvent) -> void:
	if _choosing_level:
		var cancel: bool = event.is_action_pressed("ui_cancel")
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			cancel = true
		if cancel:
			get_viewport().set_input_as_handled()
			_level_chosen.emit(-1)
			return
	super(event)


func _watch_level_choice() -> void:
	var m: MatchManager = _get_manager()
	if m != null and m.match_over:
		_level_chosen.emit(-1)


## A bola sai da mão do Sae e chega ao aliado NESTA rodada, no estado escolhido.
## Devolve true se o passe foi executado (mesmo que interceptado).
func _run_perfect_pass(target: Player, ball: Ball, level: int) -> bool:
	var m: MatchManager = _get_manager()
	var epoch: int = _epoch
	face_towards(target.global_position - global_position)
	if not await play_action(&"perfect_pass", ANIM_PASS):
		return false
	if epoch != _epoch:
		return false

	var start: Vector2 = ball.global_position
	var start_h: float = ball.height
	var to_target: Vector2 = target.global_position - start
	var dist: float = to_target.length()
	var travel: float = dist - (ball.collision_radius + target.body_radius + 2.0)
	if travel < 1.0:
		return false
	var dir: Vector2 = to_target / dist
	var end_h: float = Heights.to_height(level)
	var arch: float = 0.0
	if level == Heights.Level.SUSPENDED:
		arch = pass_arch_suspended
	elif level == Heights.Level.FLYING:
		arch = pass_arch_flying

	# A bola passa a ser conduzida por este script (sem física, sem colidir)
	m.clear_pending_pass()
	ball.register_touch(self)
	ball.hovering = true
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.pending_shot_chance = Ball.NO_SHOT   # passe não é chute
	ball.collisions_paused = true
	ball.trail_enabled = true
	ball.fx_during_hover = true
	if kick_fx:
		ball.play_fx(kick_fx)

	var duration: float = maxf(travel / pass_speed, 0.18)
	var elapsed: float = 0.0
	var tried: Array[Player] = []
	var stolen_by: Player = null

	while elapsed < duration:
		await get_tree().physics_frame
		if epoch != _epoch or m.match_over:
			break
		elapsed += get_physics_process_delta_time()
		var f: float = clampf(elapsed / duration, 0.0, 1.0)
		var pos_f: float = 1.0 - pow(1.0 - f, 1.5)   # vai amortecendo no fim
		ball.global_position = start + dir * travel * pos_f
		ball.height = maxf(lerpf(start_h, end_h, pos_f) + arch * sin(PI * pos_f), 0.0)

		# Tentativa de interceptação: QTE difícil para o inimigo que alcança a bola
		var ball_level: Heights.Level = ball.get_level()
		for other: Player in get_tree().get_nodes_in_group("players"):
			if other.team == team or other.is_down or other in tried:
				continue
			var reaches: bool = (other.height_level == ball_level) if ball_level == Heights.Level.GROUND \
				else other.can_reach_level(ball_level)
			if not reaches:
				continue
			if other.global_position.distance_to(ball.global_position) > m.ground_pass_intercept_radius:
				continue
			tried.append(other)
			var ok: bool = other.skips_qte()
			if not ok:
				ok = await _run_sae_qte(true, "Intercepte o passe do Sae!")
			if epoch != _epoch or m.match_over:
				break
			if ok:
				stolen_by = other
				break
		if stolen_by != null:
			break

	ball.collisions_paused = false
	ball.trail_enabled = false
	ball.fx_during_hover = false
	if epoch != _epoch:
		return false

	if stolen_by != null:
		# O inimigo ficou com a bola: ela solta onde está e cai
		ball.release_hover()
		ball.velocity = Vector2.ZERO
		ball.register_touch(stolen_by)
		_show_popup("Interceptado!", Color.WHITE)
		return true

	ball.global_position = start + dir * travel
	ball.height = end_h
	if level == Heights.Level.GROUND:
		ball.release_hover()
		ball.velocity = Vector2.ZERO
		ball.vel_z = 0.0
		ball.height = 0.0
	else:
		# Fica pairando no estado escolhido, igual a um passe alto recebido (cai no fim do turno)
		m.register_skill_pass(team, target)
	m.pass_completed.emit(self, target)
	await _receive_qte(target, pass_receive_bonus, false)
	return true


## O receptor faz o QTE; acertando, ganha bônus no próximo chute dele
func _receive_qte(receiver: Player, bonus: float, hard: bool) -> void:
	var m: MatchManager = _get_manager()
	if m == null or m.match_over or not is_instance_valid(receiver):
		return
	var epoch: int = _epoch
	var ok: bool = receiver.skips_qte()
	if not ok:
		ok = await _run_sae_qte(hard, "Domine o passe do Sae!")
	if epoch != _epoch or not is_instance_valid(receiver):
		return
	if ok:
		receiver.next_shot_bonus += bonus
		_show_popup("+%d%% no próximo chute" % int(round(bonus * 100.0)), PINK_LIGHT)
	else:
		_show_popup("Errou o controle", Color.WHITE)


# ---------- FLAWLESS ----------

func _use_flawless() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false
	var epoch: int = _epoch
	var point: Vector2 = await m.pick_point_for_skill(self, _range(flawless_range))
	if point == Vector2.INF or epoch != _epoch:
		return false
	if _pass_mode() != PassMode.FLAWLESS:
		return false

	face_towards(point - global_position)
	if not await play_action(&"flawless", ANIM_PASS_HIGH):
		return false
	if epoch != _epoch:
		return false

	# Passe alto até um PONTO: sobe a "voando" no meio e pousa (suspensa) quando o turno do time volta
	m.clear_pending_pass()
	ball.register_touch(self)
	var mid: Vector2 = (ball.global_position + point) * 0.5
	var tween: Tween = ball.hover_to(mid, Heights.FLYING_HEIGHT, m.high_pass_flight_time)
	m.begin_point_pass(team, point)
	m._spawn_pass_marker(team, point, ball)
	if kick_fx:
		ball.play_fx(kick_fx)
	_flaw_begin(ball, point)
	await tween.finished
	start_cooldown(CD_PASS, pass_cooldown)
	return true


func _flaw_begin(ball: Ball, point: Vector2) -> void:
	_flaw_active = true
	_flaw_landed = false
	_flaw_point = point
	_flaw_touches = ball.interaction_count
	_flaw_last = ball.last_toucher
	_flaw_prev = ball.previous_toucher
	_flaw_snap_pos = ball.global_position
	_flaw_snap_h = ball.height
	_flaw_stage = MatchManager.PassStage.FLYING


## Todo frame: guarda a última posição boa da bola e vigia se alguém mexeu nela
func _watch_flawless() -> void:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or m.match_over:
		_flaw_active = false
		return

	if ball.interaction_count != _flaw_touches:
		var toucher: Player = ball.last_toucher
		if toucher != null and toucher.team != team:
			_resolve_dispute(ball, toucher, m)
		else:
			_flaw_active = false   # um companheiro tocou: o passe cumpriu o papel
		return

	if not ball.hovering:   # bola reposta ou solta sem ninguém tocar
		_flaw_active = false
		return

	_flaw_snap_pos = ball.global_position
	_flaw_snap_h = ball.height
	_flaw_stage = m._pass_stage

	# A bola pousou no ponto: o receptor (aliado perto) faz o QTE difícil
	if not _flaw_landed and m._pass_stage == MatchManager.PassStage.RECEIVED \
			and ball.global_position.distance_to(_flaw_point) < 6.0 \
			and absf(ball.height - Heights.SUSPENDED_HEIGHT) < 3.0:
		_flaw_landed = true
		_flaw_receive()


func _flaw_receive() -> void:
	var receiver: Player = null
	var best: float = INF
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p == self or p.team != team or p.is_down:
			continue
		var d: float = p.global_position.distance_to(_flaw_point)
		if d <= flawless_receive_radius and d < best:
			best = d
			receiver = p
	if receiver == null:
		return
	await _receive_qte(receiver, flawless_receive_bonus, true)


## Um inimigo tocou na bola no meio da trajetória: disputa de sorte (70% Sae)
func _resolve_dispute(ball: Ball, enemy: Player, m: MatchManager) -> void:
	if randf() >= flawless_win_chance:
		_flaw_active = false
		_show_popup("%s ganhou a disputa" % enemy.get_display_name(), Color.WHITE)
		return
	# Sae vence: desfaz o toque do inimigo e devolve a bola para onde ela estava
	ball.stop_fx()
	ball.pending_shot_chance = Ball.NO_SHOT
	ball.last_toucher = _flaw_last
	ball.previous_toucher = _flaw_prev
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.global_position = _flaw_snap_pos
	ball.height = _flaw_snap_h
	ball.hover_to(_flaw_snap_pos, _flaw_snap_h, 0.05)
	if _flaw_stage == MatchManager.PassStage.RECEIVED:
		m.register_skill_pass(team, null)
	else:
		m.begin_point_pass(team, _flaw_point)
		m._spawn_pass_marker(team, _flaw_point, ball)
	_flaw_touches = ball.interaction_count   # continua valendo para novas tentativas
	_show_popup("Disputa vencida!", PINK_LIGHT)
	_play_pulse(ball.global_position)


# ---------- UNBALANCED ----------

func _use_unbalanced() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or not _has_enemy_in(_range(unbalanced_range)):
		return false
	var epoch: int = _epoch
	var target: Player = await m.pick_ally_for_skill(self, _range(unbalanced_range), true)
	if target == null or epoch != _epoch:
		return false

	face_towards(target.global_position - global_position)
	if not await play_action(&"unbalanced", ANIM_SLIDE):
		return false
	await _dash_to(target, unbalanced_dash_time, unbalanced_stop_distance)
	if epoch != _epoch:
		return false
	_play_pulse(target.global_position)

	# Habilidades do inimigo bloqueadas (as gerais continuam liberadas)
	target.apply_lock(self, unbalanced_rounds, true)
	_unbal_target = target
	start_cooldown(CD_PASS, pass_cooldown)
	queue_redraw()
	return true


## Se o Sae se afasta demais, solta o inimigo; também some quando a trava expira
func _watch_unbalanced() -> void:
	var t: Player = _unbal_target
	if not is_instance_valid(t) or t.locked_by != self or not t.is_skill_locked():
		_unbal_target = null
		queue_redraw()
		return
	if global_position.distance_to(t.global_position) > unbalanced_leash:
		t.clear_lock()
		_unbal_target = null
		queue_redraw()


# ---------- HABILIDADE 2: QUAL VARIANTE? ----------

func _royal_skill_name() -> String:
	return "Royalty" if _ball_near() else "Ultra Vision"


func _use_royal() -> bool:
	if _ball_near():
		return await _use_royalty()
	return await _use_ultra_vision()


# ---------- ROYALTY ----------

func _use_royalty() -> bool:
	var ball: Ball = _get_ball()
	if ball == null or height_level != Heights.Level.GROUND or not _ball_near_ground():
		return false
	var epoch: int = _epoch

	face_towards(ball.global_position - global_position)
	if not await play_action(&"royalty", ANIM_RUN):
		return false
	if epoch != _epoch:
		return false
	_begin_royal(ball)

	# Um Correr "especial": mais curto e mais rápido, sem gastar o limite de Correr do turno
	var runs_before: int = runs_this_turn
	move_speed = _base_move_speed * royal_speed_mult
	run_duration = _base_run_duration * royal_duration_mult
	_set_pass_through(true)
	start_run()
	runs_this_turn = runs_before
	await run_finished

	move_speed = _base_move_speed
	run_duration = _base_run_duration
	_set_pass_through(false)
	_end_royal()
	if epoch != _epoch:
		return false
	_nudge_out_of_players(Vector2(facing, 0.0))

	_royal_ready = _royal_hit_any   # derrubou alguém: libera o Royal Heelflick
	start_cooldown(CD_ROYAL, royal_cooldown)
	if _royal_hit_any:
		_show_popup("Royal Heelflick liberado!", PINK_LIGHT)
	queue_redraw()
	return true


## A bola gruda no pé, sem colidir e travada para o time adversário
func _begin_royal(ball: Ball) -> void:
	_royal_active = true
	_royal_ball = ball
	_royal_hits.clear()
	_royal_hit_any = false
	_royal_prev_owner = ball.spell_owner
	ball.register_touch(self)
	ball.collisions_paused = true
	ball.spell_owner = self
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	if not ball.was_reset.is_connected(_end_royal):
		ball.was_reset.connect(_end_royal)   # gol / reinício: solta tudo


func _end_royal() -> void:
	if _royal_ball != null and is_instance_valid(_royal_ball):
		_royal_ball.collisions_paused = false
		_royal_ball.spell_owner = _royal_prev_owner if is_instance_valid(_royal_prev_owner) else null
		_royal_ball.velocity = Vector2.ZERO
		if _royal_ball.was_reset.is_connected(_end_royal):
			_royal_ball.was_reset.disconnect(_end_royal)
	_royal_active = false
	_royal_ball = null
	_royal_prev_owner = null


func _physics_process(delta: float) -> void:
	super(delta)
	if _royal_active:
		_glue_ball(delta)
		_royal_check_hits()


func _glue_ball(delta: float) -> void:
	if _royal_ball == null or not is_instance_valid(_royal_ball):
		_royal_active = false
		_royal_ball = null
		return
	var dir := Vector2(facing, 0.0)
	if velocity.length() > 20.0:
		dir = velocity.normalized()
	var wanted: Vector2 = global_position + dir * royal_ball_offset
	_royal_ball.global_position = _royal_ball.global_position.lerp(wanted, clampf(delta * 20.0, 0.0, 1.0))
	_royal_ball.velocity = Vector2.ZERO
	_royal_ball.vel_z = 0.0
	_royal_ball.height = 0.0


## Quem o Sae encontra no caminho cai; ele passa direto
func _royal_check_hits() -> void:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down or other in _royal_hits:
			continue
		if other.height_level != Heights.Level.GROUND:
			continue
		if global_position.distance_to(other.global_position) <= royal_hit_radius:
			_royal_hits.append(other)
			_royal_hit_any = true
			other.knock_down()
			_play_pulse(other.global_position)


# ---------- ROYAL HEELFLICK (complemento gratuito) ----------

func _heel_available() -> bool:
	if not _royal_ready or is_down or height_level != Heights.Level.GROUND:
		return false
	var ball: Ball = _get_ball()
	return _ball_free(ball) and ball.get_level() == Heights.Level.GROUND \
		and global_position.distance_to(ball.global_position) <= heel_ball_range


func _use_heelflick() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or not _heel_available():
		return false
	var epoch: int = _epoch

	var fwd := Vector2(facing, 0.0)
	var point: Vector2 = ball.global_position + fwd * heel_distance
	if not await play_action(&"royal_heelflick", ANIM_KICK):
		return false
	if epoch != _epoch:
		return false

	# Toque para frente/cima: a bola fica pairando SUSPENSA e o Sae salta até ela
	m.clear_pending_pass()
	ball.register_touch(self)
	var ball_tween: Tween = ball.hover_to(point, Heights.SUSPENDED_HEIGHT, heel_time)
	if kick_fx:
		ball.play_fx(kick_fx)
	jump()   # sobe ao nível Suspenso (sem await: acontece junto com o movimento)
	var move_tween: Tween = create_tween()
	move_tween.tween_property(self, "global_position", point - fwd * 24.0, heel_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await ball_tween.finished
	if epoch != _epoch:
		return false

	# Igual a um passe alto recebido: se ninguém tocar, ela cai no fim do turno
	m.register_skill_pass(team, self)
	_royal_ready = false
	extra_skill_left += 1   # mais uma ação de habilidade
	_show_popup("+1 ação de habilidade", PINK_LIGHT)
	_play_pulse(ball.global_position)
	return true


# ---------- ULTRA VISION ----------

func _use_ultra_vision() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or _ball_near() or _uv_active():
		return false
	var epoch: int = _epoch
	if not await play_action(&"ultra_vision"):
		return false
	if epoch != _epoch:
		return false

	_cleanse()
	_uv_until = m.round_number + uv_rounds - 1
	_uv_pass_applied = uv_range_bonus
	pass_range_bonus += _uv_pass_applied
	_uv_turn_key = _turn_key(m)
	m.secondary_general_left += uv_extra_general   # já vale neste turno
	# A recarga só começa depois que o efeito acaba
	start_cooldown(CD_ROYAL, royal_cooldown, _uv_until + 1)
	_play_pulse(global_position)
	_show_popup("ULTRA VISION", PINK_LIGHT)
	queue_redraw()
	return true


## Livra o Sae do que ele JÁ tinha recebido (trava, penalidades de chute, confusão)
func _cleanse() -> void:
	clear_lock()
	_shot_debuffs.clear()
	confused_until_round = -1
	_confusion_order.clear()
	_status_drawn = -1   # força o redesenho dos status


func _watch_uv() -> void:
	var m: MatchManager = _get_manager()
	if m != null and m.round_number > _uv_until:
		_end_uv()


func _end_uv() -> void:
	pass_range_bonus -= _uv_pass_applied
	_uv_pass_applied = 0.0
	_uv_until = -1
	_uv_turn_key = -1
	queue_redraw()


# ---------- HABILIDADE 3: BEAUTIFUL SHOT / LEAD ACTOR ----------

## Sae e bola no mesmo nível (chão ou suspensos) e ao alcance do chute
func _shot_possible() -> bool:
	var ball: Ball = _get_ball()
	if ball == null or is_down or not _ball_free(ball):
		return false
	if get_kick_type(ball) == KickType.NONE:
		return false
	var ball_level: Heights.Level = ball.get_level()
	return ball_level == height_level and ball_level != Heights.Level.FLYING


## A bola está nas partes laterais do gol inimigo?
func _in_lead_zone() -> bool:
	var field := get_tree().get_first_node_in_group("field") as Field
	var ball: Ball = _get_ball()
	if field == null or ball == null:
		return false
	var p: Vector2 = field.to_local(ball.global_position)
	var attack_dir: float = 1.0 if team == 0 else -1.0
	var from_goal_line: float = field.pitch_size.x * 0.5 - p.x * attack_dir
	return from_goal_line >= 0.0 and from_goal_line <= lead_zone_depth and absf(p.y) >= lead_zone_min_y


func _shot_skill_name() -> String:
	return "Lead Actor" if _shot_possible() and _in_lead_zone() else "Beautiful Shot"


func _use_shot() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or not _shot_possible():
		return false
	var epoch: int = _epoch

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO or epoch != _epoch:
		return false
	if not _shot_possible():   # a bola pode ter rolado enquanto ele mirava
		return false

	var lead: bool = _in_lead_zone()
	var qte_ok: bool = true
	if lead and not skips_qte():
		qte_ok = await _run_sae_qte(true, "Lead Actor!")
		if epoch != _epoch:
			return false

	var base: float = lead_chance if lead else beautiful_chance
	var chance: float = minf(base + _shot_bonus(), 1.0)
	var fx: KickFX = kick_fx if qte_ok else null   # errou o QTE: chute fraco, sem aura
	var touches: int = ball.interaction_count
	var bend: float = _curve_side(aim)

	if lead:
		await _kick_lead_actor(ball, aim, qte_ok, chance, fx)
		if ball.interaction_count == touches:
			return false
		_curve_ball(ball, bend, lead_curve_total_deg, lead_curve_deg_per_sec)
	else:
		next_kick_force_mult = beautiful_force_mult
		var kind: KickType = KickType.GROUND if height_level == Heights.Level.GROUND else KickType.VOLLEY
		await kick_ball(ball, aim, kind, qte_ok, chance, false, fx, &"beautiful_shot")
		if ball.interaction_count == touches:
			return false
		_curve_ball(ball, bend, beautiful_curve_total_deg, beautiful_curve_deg_per_sec)

	start_cooldown(CD_SHOT, shot_cooldown)
	return true


## Lead Actor: a bola sobe até "voando" no meio da trajetória e cai logo depois.
## A força é calculada para a bola percorrer ~lead_range na horizontal antes de cair.
func _kick_lead_actor(ball: Ball, aim: Vector2, qte_ok: bool, chance: float, fx: KickFX) -> void:
	var saved_peak: Heights.Level = volley_peak_level
	volley_peak_level = Heights.Level.FLYING
	var rise: float = maxf(0.0, Heights.to_height(Heights.Level.FLYING) - ball.height)
	var vz: float = Heights.lift_for_peak(rise, ball.gravity)
	var flight_time: float = maxf(2.0 * vz / ball.gravity, 0.2)
	var wanted_speed: float = lead_range / flight_time
	next_kick_force_mult = wanted_speed / (kick_force_volley * kick_force_to_speed)
	await kick_ball(ball, aim, KickType.VOLLEY, qte_ok, chance, false, fx, &"lead_actor")
	volley_peak_level = saved_peak


## Para que lado a curva vai: para o lado do gol que o time dele ataca
func _curve_side(aim: Vector2) -> float:
	var field := get_tree().get_first_node_in_group("field") as Field
	if field == null:
		return 1.0
	var attack_dir: float = 1.0 if team == 0 else -1.0
	var goal: Vector2 = field.to_global(Vector2(attack_dir * field.pitch_size.x * 0.5, 0.0))
	var side: float = signf(aim.cross(goal - global_position))
	return side if side != 0.0 else 1.0


## A bola vai entortando enquanto voa/rola. Para se alguém tocar nela, o goleiro pegar, ela
## ficar pairando ou perder a velocidade.
func _curve_ball(ball: Ball, bend_sign: float, total_deg: float, deg_per_sec: float) -> void:
	var touches: int = ball.interaction_count
	var left: float = total_deg
	var time_left: float = 2.5   # trava de segurança
	while left > 0.0 and time_left > 0.0:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		time_left -= delta
		if ball.interaction_count != touches or ball.is_held() or ball.hovering \
				or ball.velocity.length() < 80.0:
			return
		var step: float = minf(deg_per_sec * delta, left)
		ball.velocity = ball.velocity.rotated(deg_to_rad(step) * bend_sign)
		left -= step


## PASSIVA: cada vez que o goleiro ADVERSÁRIO agarra a bola, +3% (máx. +30%) nos chutes do Sae
func _track_saves() -> void:
	var ball: Ball = _get_ball()
	if ball == null:
		return
	var held: bool = ball.is_held() and ball.held_by is Goalkeeper
	if held and not _prev_held:
		var keeper: Goalkeeper = ball.held_by as Goalkeeper
		if keeper.team != team and _save_bonus() < save_bonus_max:
			_saves += 1
			_show_popup("Defesa! +%d%% nos chutes" % int(round(_save_bonus() * 100.0)), PINK_LIGHT)
	_prev_held = held


# ---------- LOOP ----------

func _process(delta: float) -> void:
	super(delta)
	_track_saves()
	if _flaw_active:
		_watch_flawless()
	if _unbal_target != null:
		_watch_unbalanced()
	if _uv_until >= 0:
		_watch_uv()
	if _choosing_level:
		_watch_level_choice()
	if _popup_left > 0.0:
		_popup_left -= delta
	if _uv_until >= 0 or _royal_active or _popup_left > 0.0 or _unbal_target != null:
		queue_redraw()


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_PASS, "name": skill_label(_pass_skill_name(), CD_PASS)})
	list.append({"id": SKILL_ROYAL, "name": skill_label(_royal_skill_name(), CD_ROYAL)})
	if _heel_available():
		list.append({"id": SKILL_HEEL, "name": "Royal Heelflick"})
	list.append({"id": SKILL_SHOT, "name": skill_label(_shot_skill_name(), CD_SHOT)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_PASS:
			if is_on_cooldown(CD_PASS):
				return false
			match _pass_mode():
				PassMode.PERFECT:
					return _has_ally_in(_range(pass_range))
				PassMode.FLAWLESS:
					return true
				PassMode.UNBALANCED:
					return _has_enemy_in(_range(unbalanced_range))
			return false
		SKILL_ROYAL:
			if is_on_cooldown(CD_ROYAL):
				return false
			if _ball_near():
				return height_level == Heights.Level.GROUND and _ball_near_ground()
			return not _uv_active()
		SKILL_HEEL:
			return _heel_available()
		SKILL_SHOT:
			return not is_on_cooldown(CD_SHOT) and _shot_possible()
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_PASS:
			return await _use_pass()
		SKILL_ROYAL:
			return await _use_royal()
		SKILL_HEEL:
			return await _use_heelflick()
		SKILL_SHOT:
			return await _use_shot()
	return false


## O Royal Heelflick já foi "pago" pelo Royalty: não gasta ação de habilidade
func skill_is_free(skill_id: StringName) -> bool:
	return skill_id == SKILL_HEEL


## Com o Heelflick esperando, o turno não acaba sozinho mesmo sem ações sobrando
func has_free_followup() -> bool:
	return _heel_available()


# ---------- DESCRIÇÃO (balão do menu) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_PASS:
			match _pass_mode():
				PassMode.FLAWLESS:
					title = "Flawless"
					text = "Sae e bola suspensos: passe alto para o PONTO exato que você escolher (alcance %d px). Inimigo que mexer na bola no meio do caminho disputa na sorte (%d%% Sae). O receptor faz um QTE difícil e, acertando, ganha +%d%% no próximo chute." % [
						int(_range(flawless_range)), _pct(flawless_win_chance), _pct(flawless_receive_bonus)]
				PassMode.UNBALANCED:
					title = "Unbalanced"
					text = "Sem bola próxima: vai até um inimigo a até %d px e o marca. Enquanto Sae ficar perto (ou por %d rodadas) as habilidades dele ficam bloqueadas." % [
						int(_range(unbalanced_range)), unbalanced_rounds]
				_:
					title = "Perfect Pass"
					text = "Bola próxima (chão ou suspensa): escolha em que estado ela chega (Chão, Suspensa ou Voando) e o aliado (alcance %d px). A bola chega NESTA rodada. Interceptar exige um QTE difícil; o receptor faz um QTE fácil e, acertando, ganha +%d%% no próximo chute." % [
						int(_range(pass_range)), _pct(pass_receive_bonus)]
			text += "\nRecarga: %d rodadas (compartilhada entre as 3 versões)." % pass_cooldown
		SKILL_ROYAL:
			if _ball_near():
				title = "Royalty"
				text = "Com a bola nos pés, domina e corre com ela (mais curto e mais rápido que o Correr). Não perde a bola, derruba quem encontrar e passa direto. Se derrubar alguém, libera o Royal Heelflick."
			else:
				title = "Ultra Vision"
				text = "Sem bola próxima, por %d rodadas: +%d ação geral para os secundários, +%d de alcance no Passe e nas habilidades, +%d%% nos chutes do Sae e limpa os efeitos negativos que ele já tinha. A recarga só começa quando o efeito acaba." % [
					uv_rounds, uv_extra_general, int(uv_range_bonus), _pct(uv_shot_bonus)]
			text += "\nRecarga: %d rodadas (compartilhada)." % royal_cooldown
		SKILL_HEEL:
			title = "Royal Heelflick"
			text = "Complemento gratuito: toque para frente/cima, a bola fica suspensa e o Sae salta até ela, ganhando mais uma ação de habilidade."
		SKILL_SHOT:
			if _shot_possible() and _in_lead_zone():
				title = "Lead Actor"
				text = "Bola nas laterais do gol inimigo: chute com curva maior; a bola sobe a voando no meio e cai logo depois. QTE difícil. %d%% de chance." % _pct(minf(lead_chance + _shot_bonus(), 1.0))
			else:
				title = "Beautiful Shot"
				text = "Sae e bola no chão (ou os dois suspensos): chute levemente curvo e mais forte. %d%% de chance." % _pct(minf(beautiful_chance + _shot_bonus(), 1.0))
			text += "\nPASSIVA: cada defesa do goleiro adversário dá +%d%% nos chutes do Sae (máx. +%d%%), zera a cada gol. Agora: +%d%%." % [
				_pct(save_bonus_step), _pct(save_bonus_max), _pct(_save_bonus())]
			text += "\nRecarga: %d rodadas (compartilhada com o Lead Actor)." % shot_cooldown
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_epoch += 1
	if _choosing_level:
		_level_chosen.emit(-1)
	_end_royal()
	_royal_ready = false
	move_speed = _base_move_speed
	run_duration = _base_run_duration
	_unbal_target = null
	_flaw_active = false
	_uv_until = -1
	_uv_pass_applied = 0.0
	_uv_turn_key = -1
	_saves = 0
	_prev_held = false
	_popup_left = 0.0
	_pulse = 0.0
	queue_redraw()


# ---------- VISUAL (rosa choque com contorno preto) ----------

func _show_popup(text: String, _color: Color) -> void:
	_popup_text = text
	_popup_left = 1.8
	queue_redraw()


func _play_pulse(target_global: Vector2) -> void:
	_pulse_target = target_global
	_pulse = 1.0
	var tw: Tween = create_tween()
	tw.tween_method(_set_pulse, 1.0, 0.0, 0.45)


func _set_pulse(value: float) -> void:
	_pulse = value
	queue_redraw()


func _outlined_arc(center: Vector2, radius: float, color: Color, width: float) -> void:
	draw_arc(center, radius, 0.0, TAU, 40, BLACK, width + 3.0)
	draw_arc(center, radius, 0.0, TAU, 40, color, width)


func _outlined_text(pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string_outline(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, 5, BLACK)
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, color)


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Pulso: anel que se fecha e um raio até o alvo
	if _pulse > 0.0:
		var ring: float = lerpf(placeholder_radius + 60.0, placeholder_radius, _pulse)
		_outlined_arc(center, ring, Color(PINK, _pulse), 3.0)
		draw_line(center, to_local(_pulse_target), Color(BLACK, _pulse * 0.8), 5.0)
		draw_line(center, to_local(_pulse_target), Color(PINK_LIGHT, _pulse * 0.9), 2.0)

	# Royalty: aura rosa em volta da bola colada
	if _royal_active and _royal_ball != null and is_instance_valid(_royal_ball):
		var bp: Vector2 = to_local(_royal_ball.global_position)
		var beat: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
		_outlined_arc(bp, 17.0 + beat * 3.0, PINK, 2.5)

	# Unbalanced: fio tracejado até o inimigo marcado
	if _unbal_target != null and is_instance_valid(_unbal_target):
		var tp: Vector2 = to_local(_unbal_target.global_position) + Vector2(0.0, -_unbal_target.height)
		draw_dashed_line(center, tp, BLACK, 5.0, 9.0)
		draw_dashed_line(center, tp, PINK, 2.5, 9.0)
		_outlined_arc(tp, _unbal_target.placeholder_radius + 14.0, PINK, 2.0)

	# Ultra Vision: aura de números rosa choque girando em volta do Sae
	if _uv_until >= 0:
		var t: float = Time.get_ticks_msec() / 1000.0
		var steps: int = 14
		for i in steps:
			var ang: float = t * 1.4 + TAU * float(i) / float(steps)
			var rad: float = placeholder_radius + 26.0 + 6.0 * sin(t * 3.0 + float(i))
			var pos: Vector2 = center + Vector2(cos(ang) * rad, sin(ang) * rad * 0.7)
			var digit: String = str(int(abs(sin(float(i) * 12.9898 + floor(t * 5.0)) * 9.99)) % 10)
			draw_string_outline(ThemeDB.fallback_font, pos, digit, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, 5, BLACK)
			draw_string(ThemeDB.fallback_font, pos, digit, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, PINK)

	# Passiva: bônus de chute acumulado dos chutes do Sae
	if _saves > 0:
		_outlined_text(Vector2(-100.0, placeholder_radius + 26.0), "+%d%%" % _pct(_save_bonus()), 13, PINK_LIGHT)

	# Aviso flutuante em cima do Sae
	if _popup_left > 0.0:
		_outlined_text(Vector2(-100.0, -placeholder_radius - 46.0 - height), _popup_text, 14, PINK)
