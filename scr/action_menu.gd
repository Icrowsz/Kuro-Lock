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

## Pasta com as imagens das ações gerais (run.png, jump.png, slide.png, shoot.png, pass.png,
## stand_up.png). Imagem que não existir é só pulada: o balão aparece sem figura.
@export var general_icon_dir: String = "res://img/actions/"

const GENERAL_ICON_FILES := {
	MatchManager.GeneralAction.RUN: "run",
	MatchManager.GeneralAction.JUMP: "jump",
	MatchManager.GeneralAction.SLIDE: "slide",
	MatchManager.GeneralAction.SHOOT: "shoot",
	MatchManager.GeneralAction.PASS: "pass",
	MatchManager.GeneralAction.STAND_UP: "stand_up",
}

# Balão de descrição (aparece quando o mouse passa por cima de um botão de ação)
var _tip_panel: PanelContainer
var _tip_icon: TextureRect
var _tip_title: Label
var _tip_desc: Label
var _hover_button: Button = null
var _hover_kind: StringName = &""    # &"general" ou &"skill"
var _hover_key: Variant = null       # GeneralAction ou id da habilidade
var _tip_hash: int = 0
var _icon_cache: Dictionary = {}


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
		_hook_hover(b, &"general", action)

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

	_build_tooltip()


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
			if p.is_confused():
				status += " | CONFUSO (habilidades embaralhadas)"
			if p.is_generals_suppressed():
				status += " | AÇÕES GERAIS BLOQUEADAS (Body Core)"
			if p.is_skills_suppressed():
				status += " | HABILIDADES BLOQUEADAS (Watchtower)"
			for blocked in MatchManager.GENERAL_ACTION_NAMES:
				if p.is_general_action_blocked(blocked):
					status += " | SEM %s (Obsessive Hater)" % MatchManager.GENERAL_ACTION_NAMES[blocked]
			if p.extra_skill_left > 0:
				status += " | +%d habilidade extra (Obsessive Lover)" % p.extra_skill_left
			status += " | Correr %d/%d | Carrinho %d/%d" % [
				p.runs_this_turn, p.max_runs_per_turn, p.slides_this_turn, p.max_slides_per_turn]
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
		MatchManager.Phase.TEAM_EFFECTS:
			info_label.text = "Fim de turno: efeitos em andamento..."
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
	# Confuso (Confundo do Ness): a ordem dos botões é embaralhada e os nomes viram "???"
	var confused: bool = p != null and p.is_confused()
	if confused:
		skills = _shuffle_for_confusion(p, skills)

	var ids: Array[StringName] = []
	for s in skills:
		ids.append(s["id"])
	if ids != _skill_ids:
		_hide_tip()   # os botões vão ser recriados
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
			_hook_hover(b, &"skill", id)

	for i in skills.size():
		if confused:
			_skill_buttons[i].text = "★ ???"
			# Habilitado até quando a habilidade não pode ser usada: não entrega qual é qual.
			# Apertar uma que não dá simplesmente não faz nada (o MatchManager confere).
			_skill_buttons[i].disabled = not (manager.can_act() and manager.skill_left_for(p) > 0)
		else:
			_skill_buttons[i].text = "★ " + String(skills[i]["name"])
			_skill_buttons[i].disabled = not manager.can_use_skill(skills[i]["id"])


## Ordem embaralhada de quem está confuso (sorteada uma vez por confusão, não a cada frame)
func _shuffle_for_confusion(p: Player, skills: Array[Dictionary]) -> Array[Dictionary]:
	var order: Array[int] = p.get_confusion_order(skills.size())
	var shuffled: Array[Dictionary] = []
	for index in order:
		shuffled.append(skills[index])
	return shuffled


func _process(_delta: float) -> void:
	if manager.phase == MatchManager.Phase.CHOOSING_ACTION:
		_update_general_buttons()
		_update_skill_buttons()

	# Mostra o tempo restante enquanto alguém corre
	var p: Player = manager.active_player
	if manager.phase == MatchManager.Phase.EXECUTING and p and p.state == Player.State.RUNNING:
		info_label.text = "%s correndo (WASD)... %.1fs" % [p.get_display_name(), p.run_time_left]

	_update_tip()


# ---------- BALÃO DE DESCRIÇÃO (hover) ----------

func _build_tooltip() -> void:
	_tip_panel = PanelContainer.new()
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.visible = false
	UiStyle.style_panel(_tip_panel)
	add_child(_tip_panel)   # por último: fica por cima do resto da interface

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_tip_panel.add_child(row)

	_tip_icon = TextureRect.new()
	_tip_icon.custom_minimum_size = Vector2(72, 72)
	_tip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_tip_icon)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	_tip_title = UiStyle.make_label("", 18)
	_tip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_tip_title)

	_tip_desc = UiStyle.make_label("", 14)
	_tip_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_desc.custom_minimum_size = Vector2(300, 0)
	col.add_child(_tip_desc)


func _hook_hover(b: Button, kind: StringName, key: Variant) -> void:
	b.mouse_entered.connect(_show_tip.bind(b, kind, key))
	b.mouse_exited.connect(_hide_tip)
	b.pressed.connect(_hide_tip)


func _show_tip(b: Button, kind: StringName, key: Variant) -> void:
	_hover_button = b
	_hover_kind = kind
	_hover_key = key
	_tip_hash = 0
	_update_tip()


func _hide_tip() -> void:
	_hover_button = null
	if _tip_panel:
		_tip_panel.visible = false


## Mantém o balão atualizado enquanto o mouse está no botão (a variante de uma habilidade
## pode mudar com a situação) e posicionado acima dele.
func _update_tip() -> void:
	if _tip_panel == null or _hover_button == null:
		return
	if not is_instance_valid(_hover_button) or not _hover_button.is_visible_in_tree():
		_hide_tip()
		return
	var data: Dictionary = _tip_data()
	if data.is_empty() or String(data.get("description", "")) == "":
		_tip_panel.visible = false
		return

	var h: int = hash(data)
	if h != _tip_hash:
		_tip_hash = h
		_tip_title.text = String(data.get("title", ""))
		_tip_desc.text = String(data["description"])
		var icon: Texture2D = data.get("icon") as Texture2D
		_tip_icon.texture = icon
		_tip_icon.visible = icon != null

	_tip_panel.visible = true
	_tip_panel.reset_size()
	var r: Rect2 = _hover_button.get_global_rect()
	var view_w: float = get_viewport().get_visible_rect().size.x
	var x: float = clampf(r.position.x + r.size.x * 0.5 - _tip_panel.size.x * 0.5,
		8.0, maxf(8.0, view_w - _tip_panel.size.x - 8.0))
	_tip_panel.position = Vector2(x, r.position.y - _tip_panel.size.y - 10.0)


## {"title", "description", "icon"} do botão em foco. Vazio = sem balão.
func _tip_data() -> Dictionary:
	var p: Player = manager.active_player
	if _hover_kind == &"general":
		return _general_tip(int(_hover_key), p)
	# Habilidade: quem descreve é o próprio personagem (get_skill_info). Quem não tiver essa
	# função fica sem balão. Confuso (Confundo): não entrega qual botão é qual.
	if p == null or p.is_confused() or not p.has_method("get_skill_info"):
		return {}
	return p.get_skill_info(_hover_key)


func _general_icon(action: int) -> Texture2D:
	if _icon_cache.has(action):
		return _icon_cache[action]
	var tex: Texture2D = null
	var path: String = "%s/%s.png" % [general_icon_dir, GENERAL_ICON_FILES.get(action, "")]
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_icon_cache[action] = tex
	return tex


## Descrição das ações gerais (usa os números de quem está agindo, quando há alguém)
func _general_tip(action: int, p: Player) -> Dictionary:
	var text: String = ""
	match action:
		MatchManager.GeneralAction.RUN:
			var secs: float = (p.run_duration + p.run_time_bonus) if p else 1.5
			var uses: int = p.max_runs_per_turn if p else 2
			text = "Corre livremente com WASD por %.1f s. Só no chão, até %d vezes por turno." % [secs, uses]
		MatchManager.GeneralAction.JUMP:
			text = "Sobe ao nível Suspenso (só a partir do chão) e fica no ar até o turno do seu time voltar. Quem está suspenso passa por baixo de carrinhos e alcança a bola voando."
		MatchManager.GeneralAction.SLIDE:
			var dist: int = int(p.slide_distance) if p else 220
			var uses_s: int = p.max_slides_per_turn if p else 1
			text = "Mire e deslize até %d px. Derruba inimigos no chão e empurra a bola rasteira na direção do carrinho. Quem está suspenso desvia. Só no chão, %d vez por turno." % [dist, uses_s]
		MatchManager.GeneralAction.SHOOT:
			var reach: int = int(p.kick_range) if p else 70
			text = "Chuta a bola se ela estiver a até %d px e num nível alcançável. Chute no chão não tem QTE; bola alta, voleio e bola voando têm. Errar o QTE enfraquece o chute e derruba." % reach
		MatchManager.GeneralAction.PASS:
			text = "Passa para um companheiro, com a bola ao alcance. Rasteiro: alcance %d px, e inimigo no chão no caminho intercepta. Alto: alcance %d px, a bola paira e chega no seu próximo turno." % [
				int(manager.ground_pass_range), int(manager.high_pass_range)]
		MatchManager.GeneralAction.STAND_UP:
			text = "Levanta o jogador derrubado. Se ninguém levantar, ele se levanta sozinho depois de %d rodadas." % manager.auto_stand_up_rounds
	return {
		"title": MatchManager.GENERAL_ACTION_NAMES.get(action, ""),
		"description": text,
		"icon": _general_icon(action),
	}
