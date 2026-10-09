class_name Niko
extends Player
## Niko Ikki. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Watchtower (ação de habilidade): cria uma torre de observação verde translúcida onde o
##      Niko está (alcance 400). Dentro dela, INIMIGOS não podem usar habilidades. Dura até o
##      Niko sair do alcance ou 3 rodadas. Recarga de 3 rodadas, contada a partir do fim das 3 rodadas.
##    1.1 Body Core (variante: aparece no lugar do Watchtower enquanto a torre existe): o Niko
##      escolhe um inimigo dentro da torre, se aproxima e os dois disputam fisicamente
##      (75% Niko x 25% oponente). Se o Niko vencer, o inimigo fica proibido de usar ações
##      GERAIS por 3 rodadas, ou até o Niko se afastar dele.
## 2. Tactical (ação de habilidade): passe rasteiro curvilíneo. Vale com a bola em qualquer um
##      dos 3 níveis (chão, suspenso, voando), desde que o Niko consiga alcançá-la. Alcance 550,
##      recarga de 2 rodadas.
## 3. Metavision (ação de habilidade): +1 ação de habilidade para os Secundários, o Pular passa
##      a chegar ao nível Voando e os chutes que vieram de um passe do Niko ganham +5%.
##      Dura 3 rodadas, recarga de 3 rodadas a partir do fim do efeito.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Niko". Animações opcionais (se faltar alguma, nada quebra):
## "watchtower", "body_core", "tactical", "metavision".

const SKILL_TOWER: StringName = &"watchtower"   # o mesmo botão vira Body Core dentro da torre
const SKILL_TACTICAL: StringName = &"tactical"
const SKILL_METAVISION: StringName = &"metavision"

const CD_TOWER: StringName = &"cd_watchtower"
const CD_TACTICAL: StringName = &"cd_tactical"
const CD_METAVISION: StringName = &"cd_metavision"

const TOWER_COLOR := Color(0.3, 1.0, 0.5)

@export_group("Watchtower")
@export var tower_radius: float = 270.0
@export var tower_rounds: int = 3                 # duração total em rodadas (contando a atual)
@export var tower_cooldown: int = 3               # recarga, contada a partir do fim das rodadas da torre

@export_group("Body Core")
@export_range(0.0, 1.0) var body_core_win_chance: float = 0.75   # chance do Niko na disputa física
@export var body_core_rounds: int = 3             # quanto tempo o inimigo fica sem ações gerais (contando a atual)
@export var body_core_break_distance: float = 160.0   # o efeito acaba se o Niko ficar mais longe que isso
@export var body_core_contact_distance: float = 44.0  # distância entre os dois na hora da disputa
@export var body_core_approach_time: float = 0.45

@export_group("Tactical")
@export var tactical_range: float = 475.0
@export var tactical_cooldown: int = 2
## Quanto a bola se desvia da reta, como fração da distância do passe (0.25 = 25%)
@export_range(0.0, 0.6) var tactical_curve: float = 0.25

@export_group("Metavision")
@export var metavision_rounds: int = 3                          # rodadas depois da atual (igual ao Metavision do Isagi)
@export_range(0.0, 1.0) var metavision_pass_bonus: float = 0.05 # +5% nos chutes que vieram de um passe do Niko
@export var metavision_extra_ally_skills: int = 1               # ações de habilidade extras para os Secundários
@export var metavision_cooldown: int = 3                        # recarga, contada a partir do fim do efeito

@export_group("Visual do passe")
## Aura + partículas do Tactical. Vazio = usa o estilo padrão do Niko (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: watchtower, tactical, metavision.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}


# ---------- Torre ----------
var _tower: _TowerZone = null
var _tower_on: bool = false
var _tower_center: Vector2 = Vector2.ZERO
var _tower_until_round: int = -1

# ---------- Body Core ----------
var _core_target: Player = null
var _core_until_round: int = -1

# ---------- Metavision / passes ----------
var _metavision_until_round: int = -1
## O último toque "de passe" na bola foi do Niko (e ele não chutou depois)?
var _pass_valid: bool = false

# ---------- Texto flutuante (resultado da disputa) ----------
var _popup_text: String = ""
var _popup_color: Color = Color.WHITE
var _popup_left: float = 0.0


func _init() -> void:
	character_id = "niko"           # o menu de formação usa isto para saber quem é quem
	display_name = "Niko Ikki"      # aparece no placar de gols e no menu


func _ready() -> void:
	super()
	add_to_group("control_sources")  # os adversários perguntam por aqui se estão bloqueados
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_hook_manager.call_deferred()    # o MatchManager entra na árvore no mesmo frame


## Verde Blue Lock para o rastro do Tactical
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.3, 1.0, 0.5)
	fx.trail_width = 12.0
	fx.particle_color = Color(0.75, 1.0, 0.8)
	fx.amount = 18
	fx.lifetime = 0.5
	fx.speed_min = 15.0
	fx.speed_max = 60.0
	fx.scale_min = 0.15
	fx.scale_max = 0.3
	fx.burst_amount = 10
	fx.burst_speed = 180.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.pass_completed.connect(_on_pass_completed)


func _exit_tree() -> void:
	if _tower and is_instance_valid(_tower):
		_tower.queue_free()


## Qualquer passe do Niko (geral, alto ou Tactical) conta para o bônus da Metavision
func _on_pass_completed(passer: Player, _target: Player) -> void:
	if passer == self:
		_pass_valid = true


## Um chute do próprio Niko não é um passe: o bônus não vale para o que vier depois dele
func kick_ball(ball: Ball, direction: Vector2, kind: KickType, qte_success: bool = true,
		chance_override: float = -1.0, ignore_self_collision: bool = false,
		fx: KickFX = null, anim: StringName = &"", on_kick: Callable = Callable()) -> void:
	_pass_valid = false
	await super(ball, direction, kind, qte_success, chance_override, ignore_self_collision, fx, anim)


# ---------- WATCHTOWER ----------

## A torre existe agora? Confere (e encerra) sozinha: acabou o tempo ou o Niko saiu do alcance.
func is_tower_active() -> bool:
	if not _tower_on:
		return false
	var m: MatchManager = _get_manager()
	var alive: bool = m != null and m.round_number <= _tower_until_round \
		and global_position.distance_to(_tower_center) <= tower_radius
	if not alive:
		_end_tower()
	return alive


func _tower_contains(pos: Vector2) -> bool:
	return pos.distance_to(_tower_center) <= tower_radius


func _end_tower() -> void:
	_tower_on = false   # o Body Core já aplicado segue valendo: ele só acaba por rodadas ou distância
	if _tower and is_instance_valid(_tower):
		_tower.disappear()
	_tower = null
	queue_redraw()


## Chamado pelo Player de quem está sendo checado: "este adversário está proibido de usar habilidades?"
func suppresses_skills_of(p: Player) -> bool:
	return is_tower_active() and p.team != team and _tower_contains(p.global_position)


func _use_watchtower() -> bool:
	var m: MatchManager = _get_manager()
	var field := get_tree().get_first_node_in_group("field") as Field
	if m == null or field == null:
		return false
	if not await play_action(&"watchtower"):   # a torre aparece no frame de impacto
		return false

	_tower_center = global_position
	_tower_until_round = m.round_number + tower_rounds - 1   # a rodada atual conta
	start_cooldown(CD_TOWER, tower_cooldown, _tower_until_round + 1)

	_tower = _TowerZone.new()
	_tower.radius = tower_radius
	_tower.color = TOWER_COLOR
	field.add_child(_tower)
	_tower.global_position = _tower_center
	_tower.appear()
	_tower_on = true
	return true


# ---------- BODY CORE (variante do Watchtower) ----------

## Inimigos que dá para escolher: os que estão dentro da torre
func _valid_core_targets() -> Array[Player]:
	var list: Array[Player] = []
	if not is_tower_active():
		return list
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team != team and _tower_contains(other.global_position):
			list.append(other)
	return list


func is_body_core_active() -> bool:
	if _core_target == null:
		return false
	var m: MatchManager = _get_manager()
	var alive: bool = is_instance_valid(_core_target) and m != null \
		and m.round_number <= _core_until_round \
		and global_position.distance_to(_core_target.global_position) <= body_core_break_distance
	if not alive:
		_clear_body_core()
	return alive


func _clear_body_core() -> void:
	_core_target = null
	_core_until_round = -1
	queue_redraw()


## Chamado pelo Player de quem está sendo checado: "este adversário está proibido de usar ações gerais?"
func suppresses_generals_of(p: Player) -> bool:
	return is_body_core_active() and p == _core_target


func _use_body_core() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false

	# O círculo de seleção seria de 2x o raio da torre (para alcançar qualquer inimigo dentro
	# dela) e atrapalharia a leitura: some logo depois de ser desenhado. A torre já mostra o alcance.
	_hide_own_range_preview.call_deferred()
	var in_tower := func(other: Player) -> bool:
		return _tower_contains(other.global_position)
	var target: Player = await m.pick_ally_for_skill(self, tower_radius * 2.0, true, in_tower)
	if target == null:
		return false   # cancelou: não gasta a ação

	# Aproxima do inimigo (parando ao lado dele; o caminho fica sempre dentro da torre)
	face_towards(target.global_position - global_position)
	var away: Vector2 = global_position - target.global_position
	var dist: float = away.length()
	if dist > body_core_contact_distance:
		var contact_point: Vector2 = target.global_position + away / dist * body_core_contact_distance
		var tw := create_tween()
		tw.tween_property(self, "global_position", contact_point, body_core_approach_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tw.finished

	face_towards(target.global_position - global_position)
	if not await play_action(&"body_core"):
		return false

	# Disputa física: 75% Niko x 25% oponente
	if randf() < body_core_win_chance:
		_core_target = target
		_core_until_round = m.round_number + body_core_rounds - 1   # a rodada atual conta
		_show_popup("BODY CORE!", Color(0.5, 1.0, 0.6))
	else:
		_show_popup("Perdeu a disputa", Color(1.0, 0.6, 0.5))
	queue_redraw()
	await get_tree().create_timer(0.6).timeout   # tempo de ler o resultado
	return true


func _hide_own_range_preview() -> void:
	range_preview = 0.0


# ---------- TACTICAL ----------

## Alcance do passe: 550 + bônus de alcance de passe vindo de outros jogadores (ex: Orbital Orbital)
func _tactical_range() -> float:
	return tactical_range + pass_range_bonus


func _has_ally_in_tactical_range() -> bool:
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other != self and other.team == team \
				and global_position.distance_to(other.global_position) <= _tactical_range():
			return true
	return false


func _use_tactical() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false

	var target: Player = await m.pick_ally_for_skill(self, _tactical_range())
	if target == null:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele escolhia o alvo
	if get_kick_type(ball) == KickType.NONE:
		return false

	var bend: float = _best_curve_side(ball.global_position, target.global_position)
	await m.run_curved_ground_pass(self, target, ball, tactical_curve, bend, &"tactical", kick_fx)
	start_cooldown(CD_TACTICAL, tactical_cooldown)
	return true


## Escolhe para que lado a bola faz a curva: o lado em que ela passa mais longe dos adversários no chão
func _best_curve_side(from: Vector2, to: Vector2) -> float:
	var best_side: float = 1.0
	var best_clearance: float = -1.0
	for side: float in [1.0, -1.0]:
		var control: Vector2 = MatchManager.curve_control_point(from, to, tactical_curve, side)
		var clearance: float = INF
		for i in range(1, 20):
			var pt: Vector2 = MatchManager.curve_point(from, control, to, float(i) / 20.0)
			for other: Player in get_tree().get_nodes_in_group("players"):
				if other.team == team or other.is_down or other.height_level != Heights.Level.GROUND:
					continue
				clearance = minf(clearance, pt.distance_to(other.global_position))
		if clearance > best_clearance:
			best_clearance = clearance
			best_side = side
	return best_side


# ---------- METAVISION ----------

func is_metavision_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _metavision_until_round >= 0 and m.round_number <= _metavision_until_round


func _use_metavision() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	_metavision_until_round = m.round_number + metavision_rounds
	start_cooldown(CD_METAVISION, metavision_cooldown, _metavision_until_round + 1)
	m.secondary_skill_left += metavision_extra_ally_skills
	queue_redraw()
	return true


## Com a Metavision ativa, o Pular chega ao nível Voando
func jump() -> void:
	if not is_metavision_active():
		await super()
		return
	height_level = Heights.Level.FLYING
	var tw := create_tween()
	tw.tween_property(self, "height", Heights.FLYING_HEIGHT, jump_rise_time * 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


## +5% nos chutes de companheiros que vieram de um passe do Niko: a bola ainda é "dele"
## (último toque) ou só passou pelo chutador (que a recebeu direto do Niko)
func shot_bonus_for_ally(shooter: Player, ball: Ball) -> float:
	if not is_metavision_active() or not _pass_valid or shooter == self or ball == null:
		return 0.0
	if ball.last_toucher == self \
			or (ball.last_toucher == shooter and ball.previous_toucher == self):
		return metavision_pass_bonus
	return 0.0


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var tower_name: String
	if is_tower_active():
		tower_name = "Body Core (ativo)" if is_body_core_active() else "Body Core"
	else:
		tower_name = skill_label("Watchtower", CD_TOWER)
	list.append({"id": SKILL_TOWER, "name": tower_name})
	list.append({"id": SKILL_TACTICAL, "name": skill_label("Tactical", CD_TACTICAL)})
	var meta_name: String = "Metavision (ativa)" if is_metavision_active() \
		else skill_label("Metavision", CD_METAVISION)
	list.append({"id": SKILL_METAVISION, "name": meta_name})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_TOWER:
			if is_tower_active():   # variante Body Core
				return not is_body_core_active() and not _valid_core_targets().is_empty()
			return not is_on_cooldown(CD_TOWER)
		SKILL_TACTICAL:
			return not is_on_cooldown(CD_TACTICAL) \
				and get_kick_type(_get_ball()) != KickType.NONE \
				and _has_ally_in_tactical_range()
		SKILL_METAVISION:
			return not is_metavision_active() and not is_on_cooldown(CD_METAVISION)
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_TOWER:
			if is_tower_active():
				return await _use_body_core()
			return await _use_watchtower()
		SKILL_TACTICAL:
			return await _use_tactical()
		SKILL_METAVISION:
			if not await play_action(&"metavision"):
				return false
			return _use_metavision()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_TOWER:
			title = "Body Core" if is_tower_active() else "Watchtower"
			text = ("Watchtower: cria uma torre de observação onde Niko está. Dentro do círculo verde (raio de %d px), INIMIGOS não podem usar habilidades. Dura %d rodadas ou até Niko sair do círculo. Recarga: %d rodadas, contadas a partir do fim da torre.\n"
				+ "Body Core (aparece no lugar do Watchtower enquanto a torre existe): Niko escolhe um inimigo dentro da torre, vai até ele e os dois disputam fisicamente (%d%% Niko x %d%% oponente). Se Niko vencer, o inimigo fica sem ações gerais por %d rodadas, ou até Niko se afastar mais de %d px dele. O Body Core não tem recarga própria.") % [
				int(tower_radius), tower_rounds, tower_cooldown, _pct(body_core_win_chance),
				_pct(1.0 - body_core_win_chance), body_core_rounds, int(body_core_break_distance)]
		SKILL_TACTICAL:
			title = "Tactical"
			text = ("Passe rasteiro curvo para um aliado a até %d px. Vale com a bola em qualquer altura (chão, suspensa ou voando), desde que Niko consiga alcançá-la.\n"
				+ "Recarga: %d rodadas.") % [
				int(tactical_range), tactical_cooldown]
		SKILL_METAVISION:
			title = "Metavision"
			text = ("Por %d rodadas depois da atual: +%d ação(ões) de habilidade extra para os aliados, o Pular de Niko chega ao nível voando e os chutes que vieram de um passe dele ganham +%d%%.\n"
				+ "Recarga: %d rodadas, contadas a partir do fim do efeito.") % [
				metavision_rounds, metavision_extra_ally_skills, _pct(metavision_pass_bonus),
				metavision_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_end_tower()
	_tower_until_round = -1
	_clear_body_core()
	_metavision_until_round = -1
	_pass_valid = false
	_popup_left = 0.0
	queue_redraw()


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	# Confere a cada frame: a torre acaba no instante em que o Niko sai do alcance, e o
	# Body Core no instante em que ele se afasta do alvo (e não voltam se ele retornar)
	is_tower_active()
	var core: bool = is_body_core_active()
	if _popup_left > 0.0:
		_popup_left -= delta
	if core or _popup_left > 0.0:
		queue_redraw()


func _show_popup(text: String, color: Color) -> void:
	_popup_text = text
	_popup_color = color
	_popup_left = 1.4
	queue_redraw()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Aura verde enquanto a Metavision está valendo
	if is_metavision_active():
		draw_arc(center, placeholder_radius + 6.0, 0.0, TAU, 40, Color(0.35, 1.0, 0.6, 0.9), 2.0)

	# Body Core ativo: linha até o alvo + anel tracejado verde nele
	if _core_target != null and is_instance_valid(_core_target):
		var t: Vector2 = to_local(_core_target.global_position) + Vector2(0.0, -_core_target.height)
		draw_line(center, t, Color(0.4, 1.0, 0.6, 0.5), 2.0)
		var segments: int = 12
		for i in segments:
			if i % 2 == 0:
				var a0: float = TAU * float(i) / float(segments)
				var a1: float = TAU * float(i + 1) / float(segments)
				draw_arc(t, _core_target.placeholder_radius + 12.0, a0, a1, 6, Color(0.4, 1.0, 0.6, 0.95), 3.0)

	# Resultado da disputa, flutuando em cima do Niko
	if _popup_left > 0.0:
		var alpha: float = clampf(_popup_left / 0.4, 0.0, 1.0)
		var y: float = -placeholder_radius - 46.0 - height - (1.4 - _popup_left) * 10.0
		draw_string(ThemeDB.fallback_font, Vector2(-100.0, y), _popup_text,
			HORIZONTAL_ALIGNMENT_CENTER, 200.0, 20, Color(_popup_color, alpha))


# ====================================================================
# Torre de observação (círculo de alcance + desenho da torre)
# ====================================================================

## Círculo verde translúcido no chão (acima da grama, abaixo de jogadores e bola)
class _TowerZone extends Node2D:
	var radius: float = 400.0
	var color: Color = Color(0.3, 1.0, 0.5)
	var _time: float = 0.0
	var _body: _TowerBody
	var _fade: Tween

	func _ready() -> void:
		z_as_relative = false
		z_index = -4000   # o campo fica em -4096
		modulate.a = 0.0
		_body = _TowerBody.new()
		_body.color = color
		add_child(_body)
		_body.z_as_relative = false

	func appear() -> void:
		_body.z_index = int(global_position.y)   # mesma regra de profundidade dos jogadores (a posição já foi definida)
		_kill_fade()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, 0.4)

	func disappear() -> void:
		_kill_fade()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 0.0, 0.4)
		_fade.tween_callback(queue_free)

	func _kill_fade() -> void:
		if _fade and _fade.is_valid():
			_fade.kill()

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(color, 0.12))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 128, Color(color, 0.7), 3.0)
		# Anel interno que pulsa devagar (a torre "vigiando")
		var pulse: float = fmod(_time * 0.35, 1.0)
		draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 96, Color(color, 0.35 * (1.0 - pulse)), 2.0)


## A torre em si, "em pé" (sobe na tela, igual às traves do campo)
class _TowerBody extends Node2D:
	var color: Color = Color(0.3, 1.0, 0.5)

	func _draw() -> void:
		var fill := Color(color, 0.5)
		var edge := Color(color, 0.95)
		var h: float = 90.0
		# Sombra no chão
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 28.0, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Pernas e travessas em X
		draw_line(Vector2(-22, 0), Vector2(-14, -h), edge, 3.0)
		draw_line(Vector2(22, 0), Vector2(14, -h), edge, 3.0)
		draw_line(Vector2(-22, 0), Vector2(14, -h), Color(edge, 0.5), 2.0)
		draw_line(Vector2(22, 0), Vector2(-14, -h), Color(edge, 0.5), 2.0)
		# Plataforma, cabine, telhado e a "janela"
		draw_rect(Rect2(-20, -h - 4, 40, 6), fill)
		draw_rect(Rect2(-16, -h - 30, 32, 26), fill)
		draw_rect(Rect2(-16, -h - 30, 32, 26), edge, false, 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-22, -h - 30), Vector2(22, -h - 30), Vector2(0, -h - 50)]), Color(edge, 0.7))
		draw_circle(Vector2(0, -h - 17), 5.0, Color(1, 1, 1, 0.75))
