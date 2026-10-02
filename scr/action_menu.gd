extends CanvasLayer
## Interface da partida. Monta tudo por código:
## basta adicionar um CanvasLayer com este script e apontar o "manager".
## Visual compartilhado (cores neutras, contorno, painéis, botões) vem do UiStyle.

@export var manager: MatchManager

var turn_label: Label
var info_label: Label
var general_buttons: Dictionary = {}  # MatchManager.GeneralAction -> Button
var skill_box: HBoxContainer          # botões de habilidade (mudam conforme quem está agindo)
var _skill_buttons: Array[Button] = []
var _skill_ids: Array[StringName] = []
var end_turn_button: Button
var pass_box: HBoxContainer
var pass_variant_buttons: Dictionary = {}  # MatchManager.PassVariant -> Button

var _turn_style: StyleBoxFlat   # a borda do painel do topo leva a cor do time da vez
var _last_team: int = -1
var _last_team_color: Color = Color.TRANSPARENT
var _color_tween: Tween


func _ready() -> void:
	_build_ui()
	manager.state_changed.connect(_refresh)
	_refresh()


func _build_ui() -> void:
	# Topo: rodada e time da vez. O texto é neutro; quem indica o time é a borda do painel.
	var turn_panel := PanelContainer.new()
	turn_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	turn_panel.offset_top = 8
	turn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_style = UiStyle.style_panel(turn_panel)
	_turn_style.set_border_width_all(3)
	add_child(turn_panel)

	turn_label = UiStyle.make_label("", 24)
	turn_panel.add_child(turn_label)

	# Rodapé: informações e botões
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -16
	UiStyle.style_panel(panel)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	info_label = UiStyle.make_label("", 16)
	vbox.add_child(info_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	for action in MatchManager.GENERAL_ACTION_NAMES:
		var b := Button.new()
		b.text = MatchManager.GENERAL_ACTION_NAMES[action]
		b.pressed.connect(manager.do_general_action.bind(action))
		UiStyle.style_button(b)
		hbox.add_child(b)
		general_buttons[action] = b

	skill_box = HBoxContainer.new()  # os botões dourados (ações especiais) são criados em _update_skill_buttons
	skill_box.add_theme_constant_override("separation", 8)
	hbox.add_child(skill_box)

	end_turn_button = Button.new()
	end_turn_button.text = "Encerrar turno"
	end_turn_button.pressed.connect(manager.request_end_turn)
	UiStyle.style_button(end_turn_button, Color(0.75, 0.30, 0.30))  # avermelhado: passa a vez
	hbox.add_child(end_turn_button)

	# Linha extra do Passe: variantes + cancelar (só aparece durante a escolha)
	pass_box = HBoxContainer.new()
	pass_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pass_box.add_theme_constant_override("separation", 8)
	pass_box.visible = false
	vbox.add_child(pass_box)

	for variant in MatchManager.PASS_VARIANT_NAMES:
		var vb := Button.new()
		vb.text = MatchManager.PASS_VARIANT_NAMES[variant]
		vb.pressed.connect(manager.choose_pass_variant.bind(variant))
		UiStyle.style_button(vb)
		pass_box.add_child(vb)
		pass_variant_buttons[variant] = vb

	var cancel_button := Button.new()
	cancel_button.text = "Cancelar passe"
	cancel_button.pressed.connect(manager.cancel_pass)
	UiStyle.style_button(cancel_button, Color(0.75, 0.30, 0.30))
	pass_box.add_child(cancel_button)


func _refresh() -> void:
	# Na montagem das formações a tela de formação ocupa o lugar deste menu
	visible = manager.phase != MatchManager.Phase.FORMATION
	turn_label.text = "Rodada %d — Turno: %s" % [
		manager.round_number, manager.get_team_name(manager.current_team)]
	_update_team_border()

	var p: Player = manager.active_player

	_update_general_buttons()

	var choosing_variant: bool = manager.phase == MatchManager.Phase.CHOOSING_PASS_VARIANT
	var choosing_target: bool = manager.phase == MatchManager.Phase.CHOOSING_PASS_TARGET
	pass_box.visible = choosing_variant or choosing_target
	for variant in pass_variant_buttons:
		var vb: Button = pass_variant_buttons[variant]
		vb.visible = choosing_variant
		vb.disabled = not manager.can_choose_pass_variant(variant)

	_update_skill_buttons()
	end_turn_button.disabled = manager.phase != MatchManager.Phase.CHOOSING_ACTION

	match manager.phase:
		MatchManager.Phase.CHOOSING_PROTAGONIST:
			info_label.text = "Time %s: clique em um jogador para ser o Protagonista" % \
				manager.get_team_name(manager.current_team)
		MatchManager.Phase.CHOOSING_ACTION:
			var role_text: String = "Protagonista" if p == manager.protagonist else "Secundário"
			var status: String = "Altura: %s" % Heights.level_name(p.height_level)
			if p.is_down:
				status += " | DERRUBADO (só pode Levantar)"
			if p.has_run_this_turn:
				status += " | já correu neste turno"
			info_label.text = "Agindo: %s (%s) — %s\nProtagonista — gerais: %d | habilidade: %d\nSecundários — gerais: %d | habilidade: %d\nClique em um companheiro de time para trocar quem age" % [
				p.get_display_name(), role_text, status,
				manager.protagonist_general_left, manager.protagonist_skill_left,
				manager.secondary_general_left, manager.secondary_skill_left]
		MatchManager.Phase.CHOOSING_PASS_VARIANT:
			info_label.text = "%s: escolha o tipo de passe" % p.get_display_name()
		MatchManager.Phase.CHOOSING_PASS_TARGET:
			var variant_name: String = MatchManager.PASS_VARIANT_NAMES[manager.pass_variant]
			info_label.text = "%s: clique num companheiro dentro do alcance (anel verde)\nDireito ou Esc cancela" % variant_name
			if manager.pass_hint != "":
				info_label.text += "\n" + manager.pass_hint
		MatchManager.Phase.AIMING:
			info_label.text = "Mire com o mouse — clique esquerdo confirma, direito ou Esc cancela"
		MatchManager.Phase.EXECUTING:
			info_label.text = "%s em ação..." % p.get_display_name()
		MatchManager.Phase.MATCH_OVER:
			info_label.text = "Fim de jogo!"
		MatchManager.Phase.KEEPERS_ACTING:
			info_label.text = "Os goleiros estão agindo..."
		MatchManager.Phase.FORMATION:
			info_label.text = ""


## A borda do painel do topo muda (suavemente) para a cor do time da vez
func _update_team_border() -> void:
	var team: int = manager.current_team
	var color: Color = TeamStyle.color_of(team)
	if team == _last_team and color == _last_team_color:
		return
	var first: bool = _last_team == -1
	_last_team = team
	_last_team_color = color
	if _color_tween and _color_tween.is_valid():
		_color_tween.kill()
	if first:
		_turn_style.border_color = color
		return
	_color_tween = create_tween()
	_color_tween.tween_property(_turn_style, "border_color", color, 0.25)
	UiStyle.pop(turn_label, 1.12, 0.25)


## Botões das ações gerais (Levantar só aparece para jogador derrubado).
## Também roda a cada frame na escolha de ação, porque a bola continua rolando
## e "Chutar" depende da distância até ela.
func _update_general_buttons() -> void:
	var p: Player = manager.active_player
	for action in general_buttons:
		var b: Button = general_buttons[action]
		b.disabled = not manager.can_use_general(action)
		if action == MatchManager.GeneralAction.STAND_UP:
			b.visible = p != null and p.is_down


## Um botão dourado por habilidade de quem está agindo. Reconstrói quando troca o jogador
## e atualiza nome/disponibilidade sempre (a bola rola e as alturas mudam).
func _update_skill_buttons() -> void:
	var p: Player = manager.active_player
	var skills: Array[Dictionary] = []
	if p:
		skills = p.get_skills()

	var ids: Array[StringName] = []
	for s in skills:
		ids.append(s["id"])
	if ids != _skill_ids:
		for b in _skill_buttons:
			b.queue_free()
		_skill_buttons.clear()
		_skill_ids = ids
		for id in ids:
			var b := Button.new()
			b.pressed.connect(manager.do_skill_action.bind(id))
			UiStyle.style_button(b, UiStyle.ACCENT_COLOR.darkened(0.25))  # dourado: ação especial
			skill_box.add_child(b)
			_skill_buttons.append(b)

	for i in skills.size():
		_skill_buttons[i].text = "★ " + String(skills[i]["name"])
		_skill_buttons[i].disabled = not manager.can_use_skill(skills[i]["id"])


func _process(_delta: float) -> void:
	if manager.phase == MatchManager.Phase.CHOOSING_ACTION:
		_update_general_buttons()
		_update_skill_buttons()

	# Mostra o tempo restante enquanto alguém corre
	var p: Player = manager.active_player
	if manager.phase == MatchManager.Phase.EXECUTING and p and p.state == Player.State.RUNNING:
		info_label.text = "%s correndo (WASD)... %.1fs" % [p.get_display_name(), p.run_time_left]
