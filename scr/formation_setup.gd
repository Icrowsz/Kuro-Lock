class_name FormationSetup
extends CanvasLayer
## Tela de montagem das formações, antes da partida.
##
## Um time por vez: o time da vez arrasta os próprios jogadores (só dentro da sua metade do
## campo, que fica destacada) ou escolhe uma formação pronta, e depois confirma.
## Quando todos os times confirmaram, emite "finished" e some.
##
## O MatchManager cria este nó sozinho (use_formation_setup).

signal finished

var manager: MatchManager

var _field: Field
var _team: int = -1
var _confirmed: Array[bool] = []
var _snapshot: Dictionary = {}     # Player -> posição quando começou a editar (botão "Restaurar")
var _targets: Dictionary = {}      # Player -> destino de uma formação pronta que ainda está deslizando
var _dragging: Player = null
var _drag_offset: Vector2 = Vector2.ZERO
var _hover: Player = null
var _move_tween: Tween
var _color_tween: Tween

var _overlay: _Overlay
var _title: Label
var _title_style: StyleBoxFlat
var _preset_box: HBoxContainer
var _character_box: HBoxContainer   # um seletor de personagem por jogador do time
var _confirm_button: Button


## Destaque desenhado no campo: metade do time, espaços da formação e anel nos jogadores
class _Overlay extends Node2D:
	var rect: Rect2 = Rect2()
	var color: Color = Color.WHITE
	var slots: Array[Vector2] = []        # coordenadas locais do campo
	var players: Array[Player] = []
	var hover: Player = null
	var dragging: Player = null

	func _draw() -> void:
		draw_rect(rect, Color(color, 0.14))
		draw_rect(rect, Color(color, 0.65), false, 3.0)
		for s in slots:
			draw_arc(s, 16.0, 0.0, TAU, 24, Color(color.lightened(0.3), 0.8), 2.0)
			draw_circle(s, 3.0, Color(color.lightened(0.3), 0.8))
		for p in players:
			var strong: bool = p == hover or p == dragging
			var width: float = 4.0 if strong else 2.0
			var alpha: float = 1.0 if strong else 0.7
			draw_arc(to_local(p.global_position), 30.0, 0.0, TAU, 32, Color(1, 1, 1, alpha), width)


func _ready() -> void:
	layer = 12  # acima do placar e do menu da partida
	_field = get_tree().get_first_node_in_group("field") as Field
	if _field == null:
		push_warning("FormationSetup: nenhum Field encontrado; pulando a montagem das formações.")
		finished.emit.call_deferred()
		queue_free()
		return

	_confirmed.resize(manager.team_count)
	_confirmed.fill(false)

	_overlay = _Overlay.new()
	_overlay.z_as_relative = false
	_overlay.z_index = -4000   # acima do gramado, abaixo de jogadores e bola
	_field.add_child(_overlay)

	_build_ui()
	_begin_team(0)


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()


# ---------- CONSTRUÇÃO ----------

func _build_ui() -> void:
	# Topo: de quem é a vez de montar (a borda leva a cor do time)
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 12
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_style = UiStyle.style_panel(top)
	_title_style.set_border_width_all(3)
	add_child(top)

	var top_box := VBoxContainer.new()
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_box)
	_title = UiStyle.make_label("", 28)
	top_box.add_child(_title)
	top_box.add_child(UiStyle.make_label(
		"Arraste os jogadores dentro da sua metade (área colorida) ou escolha uma formação pronta", 16))

	# Rodapé: formações prontas + confirmar
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -16
	UiStyle.style_panel(bottom)
	add_child(bottom)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	bottom.add_child(box)

	box.add_child(UiStyle.make_label("Formações prontas", 18))

	_preset_box = HBoxContainer.new()
	_preset_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_preset_box.add_theme_constant_override("separation", 8)
	box.add_child(_preset_box)

	box.add_child(UiStyle.make_label("Personagens", 18))

	_character_box = HBoxContainer.new()
	_character_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_box.add_theme_constant_override("separation", 12)
	box.add_child(_character_box)

	_confirm_button = Button.new()
	_confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiStyle.style_button(_confirm_button, Color(0.25, 0.65, 0.35))
	_confirm_button.pressed.connect(_on_confirm_pressed)
	box.add_child(_confirm_button)


## Botões de formação do time atual (dependem de quantos jogadores ele tem)
func _rebuild_presets() -> void:
	for child in _preset_box.get_children():
		_preset_box.remove_child(child)
		child.queue_free()

	var count: int = manager.get_team_players(_team).size()
	for formation in Formations.presets_for(count):
		var b := Button.new()
		b.text = formation
		b.pressed.connect(_apply_preset.bind(formation))
		UiStyle.style_button(b)
		_preset_box.add_child(b)

	var restore := Button.new()
	restore.text = "Restaurar"
	restore.pressed.connect(_restore)
	UiStyle.style_button(restore, Color(0.75, 0.30, 0.30))
	_preset_box.add_child(restore)


## Um seletor de personagem para cada jogador do time atual
func _rebuild_characters() -> void:
	for child in _character_box.get_children():
		_character_box.remove_child(child)
		child.queue_free()

	var roster: Array[Dictionary] = CharacterRoster.available()
	for p in manager.get_team_players(_team):
		var col := VBoxContainer.new()
		col.add_child(UiStyle.make_label(String(p.name), 14, UiStyle.MUTED_COLOR))

		var pick := OptionButton.new()
		UiStyle.style_button(pick)
		var selected: int = 0
		for i in roster.size():
			pick.add_item(roster[i]["name"], i)
			pick.set_item_metadata(i, roster[i]["id"])
			if roster[i]["id"] == p.character_id:
				selected = i
		pick.select(selected)
		pick.item_selected.connect(_on_character_selected.bind(p, pick))
		col.add_child(pick)
		_character_box.add_child(col)


## Troca o personagem de um jogador (o nó antigo é substituído por um novo, no mesmo lugar)
func _on_character_selected(index: int, old: Player, pick: OptionButton) -> void:
	var id: String = pick.get_item_metadata(index)
	if id == old.character_id:
		return

	_finish_move()
	_dragging = null
	_hover = null

	var fresh: Player = CharacterRoster.replace_player(old, id)
	if fresh == null:
		_rebuild_characters.call_deferred()   # não deu: o seletor volta ao personagem de antes
		return

	manager.register_player(fresh)
	if _snapshot.has(old):
		_snapshot[fresh] = _snapshot[old]   # o "Restaurar" continua valendo para o jogador novo
		_snapshot.erase(old)

	var players: Array[Player] = manager.get_team_players(_team)
	_overlay.players = players
	_overlay.hover = null
	_overlay.dragging = null
	_overlay.queue_redraw()
	_rebuild_characters.call_deferred()


# ---------- FLUXO ENTRE OS TIMES ----------

func _begin_team(team: int) -> void:
	_team = team
	_dragging = null
	_hover = null
	_targets.clear()

	_snapshot.clear()
	var players: Array[Player] = manager.get_team_players(team)
	for p in players:
		_snapshot[p] = p.global_position

	var color: Color = Player.TEAM_COLORS[team % Player.TEAM_COLORS.size()]
	_overlay.rect = Formations.team_area(team, _field)
	_overlay.color = color
	_overlay.slots.clear()
	_overlay.players = players
	_overlay.hover = null
	_overlay.dragging = null
	_overlay.queue_redraw()

	_title.text = "Formação — %s" % manager.get_team_name(team)
	if _color_tween and _color_tween.is_valid():
		_color_tween.kill()
	_color_tween = create_tween()
	_color_tween.tween_property(_title_style, "border_color", color, 0.25)
	UiStyle.pop(_title, 1.12, 0.25)

	_confirm_button.text = "Confirmar e começar a partida" if _next_team_after(team) == -1 \
		else "Confirmar formação"
	_rebuild_presets()
	_rebuild_characters()


## Próximo time que ainda não confirmou (-1 = ninguém, ou seja, este é o último)
func _next_team_after(team: int) -> int:
	for t in _confirmed.size():
		if t != team and not _confirmed[t]:
			return t
	return -1


func _on_confirm_pressed() -> void:
	_finish_move()
	_dragging = null
	_confirmed[_team] = true
	var next: int = _next_team_after(_team)
	if next == -1:
		finished.emit()
		queue_free()
	else:
		_begin_team(next)


# ---------- FORMAÇÕES PRONTAS ----------

func _apply_preset(formation: String) -> void:
	_finish_move()
	var players: Array[Player] = manager.get_team_players(_team)
	var slot_positions: Array[Vector2] = Formations.slots(formation, _team, _field)
	_targets = Formations.assign(players, slot_positions)

	_overlay.slots.clear()
	for s in slot_positions:
		_overlay.slots.append(_field.to_local(s))
	_start_move()


func _restore() -> void:
	_finish_move()
	_targets = _snapshot.duplicate()
	_overlay.slots.clear()
	_start_move()


func _start_move() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween().set_parallel(true)
	for key in _targets:
		var p: Player = key
		_move_tween.tween_property(p, "global_position", _targets[key], 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.finished.connect(_targets.clear, CONNECT_ONE_SHOT)


## Se uma formação ainda está deslizando, termina na hora (evita brigar com o arrastar/confirmar)
func _finish_move() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	for key in _targets:
		var p: Player = key
		p.global_position = _targets[key]
	_targets.clear()


# ---------- ARRASTAR ----------

func _mouse_world() -> Vector2:
	return _field.get_global_mouse_position()


## Jogador do time atual debaixo do mouse (o mais próximo)
func _player_at(pos: Vector2) -> Player:
	var best: Player = null
	var best_dist: float = INF
	for p in manager.get_team_players(_team):
		var d: float = p.global_position.distance_to(pos)
		if d <= p.body_radius + 12.0 and d < best_dist:
			best = p
			best_dist = d
	return best


func _unhandled_input(event: InputEvent) -> void:
	if _team < 0:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p: Player = _player_at(_mouse_world())
			if p != null:
				_finish_move()
				_dragging = p
				_drag_offset = p.global_position - _mouse_world()
				_overlay.slots.clear()   # o guia some quando você começa a mexer na mão
				get_viewport().set_input_as_handled()
		elif _dragging != null:
			_dragging = null
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging != null:
		_dragging.global_position = _constrain(_mouse_world() + _drag_offset, _dragging)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _field == null or _team < 0:
		return
	if _dragging == null:
		_hover = _player_at(_mouse_world())
	Input.set_default_cursor_shape(
		Input.CURSOR_DRAG if _dragging != null
		else (Input.CURSOR_POINTING_HAND if _hover != null else Input.CURSOR_ARROW))
	_overlay.hover = _hover
	_overlay.dragging = _dragging
	_overlay.queue_redraw()


## Mantém o jogador dentro da metade do time e fora de cima de outros jogadores e goleiros
func _constrain(target_global: Vector2, who: Player) -> Vector2:
	var pos: Vector2 = _clamp_to_area(target_global)
	for i in 3:
		for other: Player in get_tree().get_nodes_in_group("players"):
			if other != who:
				pos = _push_away(pos, who.body_radius, other.global_position, other.body_radius)
		for keeper: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
			pos = _push_away(pos, who.body_radius, keeper.global_position, keeper.body_radius)
		pos = _clamp_to_area(pos)
	return pos


func _clamp_to_area(global_pos: Vector2) -> Vector2:
	var area: Rect2 = Formations.team_area(_team, _field)
	var local: Vector2 = _field.to_local(global_pos)
	local.x = clampf(local.x, area.position.x, area.end.x)
	local.y = clampf(local.y, area.position.y, area.end.y)
	return _field.to_global(local)


func _push_away(pos: Vector2, radius: float, other_pos: Vector2, other_radius: float) -> Vector2:
	var need: float = radius + other_radius + 6.0
	var away: Vector2 = pos - other_pos
	if away.length() >= need:
		return pos
	if away.length() < 0.01:
		away = Vector2.RIGHT
	return other_pos + away.normalized() * need
