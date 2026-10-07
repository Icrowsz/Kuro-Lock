class_name ScoreHud
extends CanvasLayer
## Placar no topo, aviso de gol e resumo final da partida.
## Monta tudo por código. O MatchManager cria este nó sozinho (show_score_hud).
## Visual compartilhado (cores neutras, contorno, painéis) vem do UiStyle.

## Quanto tempo o aviso de gol fica na tela
@export var banner_time: float = 3.0

var manager: MatchManager

var _score_labels: Array[Label] = []
var _last_scores: Array[int] = []
var _banner: PanelContainer
var _banner_title: Label
var _banner_detail: Label
var _banner_tween: Tween
var _event_label: Label
var _event_tween: Tween
var _summary: PanelContainer
var _summary_box: VBoxContainer
## "1º Tempo" / "2º Tempo" / "Prorrogação", exibido embaixo do placar
var _period_label: Label


func _ready() -> void:
	layer = 10  # acima do menu de ações
	_build_scoreboard()
	_build_event_label()
	_build_banner()
	_build_summary()
	manager.goal_scored.connect(_on_goal_scored)
	manager.match_ended.connect(_on_match_ended)
	manager.keeper_event.connect(_on_keeper_event)
	manager.formation_started.connect(_on_formation_started)
	manager.match_started.connect(_on_match_started)
	manager.half_started.connect(_on_half_started)
	manager.extra_time_started.connect(_on_extra_time_started)
	_refresh_scores()
	_refresh_period()


# ---------- CONSTRUÇÃO ----------

func _build_scoreboard() -> void:
	# Placar dentro de uma "pílula" translúcida, logo abaixo do "Rodada - Turno"
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 58
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style(UiStyle.PANEL_BORDER, 20.0, 4.0))
	add_child(panel)

	# Pilha vertical: linha do placar em cima, "1º Tempo / 2º Tempo / Prorrogação" embaixo
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(outer)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(box)

	for t in manager.team_count:
		if t > 0:
			box.add_child(UiStyle.make_label("×", 26))
		var label := UiStyle.make_label("", 26, _team_color(t))
		box.add_child(label)
		_score_labels.append(label)
		_last_scores.append(0)

	_period_label = UiStyle.make_label("", 15, UiStyle.MUTED_COLOR)
	_period_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_period_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_period_label)


## Linha curta embaixo do placar com o que os goleiros fazem (defesa, lançamento...)
func _build_event_label() -> void:
	_event_label = UiStyle.make_label("", 20)
	_event_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_event_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_label.offset_top = 112
	_event_label.visible = false
	add_child(_event_label)


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 160
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE  # não atrapalha cliques no jogo
	_banner.visible = false
	UiStyle.style_panel(_banner)
	add_child(_banner)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(vbox)

	_banner_title = UiStyle.make_label("", 40)
	vbox.add_child(_banner_title)
	_banner_detail = UiStyle.make_label("", 22)
	vbox.add_child(_banner_detail)


func _build_summary() -> void:
	_summary = PanelContainer.new()
	_summary.set_anchors_preset(Control.PRESET_CENTER)
	_summary.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_summary.grow_vertical = Control.GROW_DIRECTION_BOTH
	_summary.visible = false
	UiStyle.style_panel(_summary)
	add_child(_summary)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_summary.add_child(margin)

	_summary_box = VBoxContainer.new()
	_summary_box.add_theme_constant_override("separation", 14)
	margin.add_child(_summary_box)


# ---------- EVENTOS ----------

func _on_goal_scored(goal: Dictionary) -> void:
	_refresh_scores()

	var team: int = goal["team"]
	var color: Color = _team_color(team)
	_banner_title.text = "GOL! %s" % manager.get_team_name(team)
	_banner_title.add_theme_color_override("font_color", color)
	_banner_detail.text = _goal_description(goal)
	# A borda do aviso ganha a cor do time que marcou
	UiStyle.style_panel(_banner, color)
	_banner.visible = true

	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	# Entra com um "pulo" (escala + fade), fica parado e some suavemente
	_banner.pivot_offset = _banner.get_combined_minimum_size() * 0.5
	_banner.scale = Vector2.ONE * 0.7
	_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.15)
	_banner_tween.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(banner_time)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_callback(_banner.hide)


func _on_keeper_event(text: String, _team: int) -> void:
	# Mensagem neutra: a cor do time não importa, o texto já diz o que aconteceu
	_event_label.text = text
	_event_label.modulate = Color.WHITE
	_event_label.visible = true
	UiStyle.pop(_event_label, 1.2, 0.2)
	if _event_tween and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()
	_event_tween.tween_interval(2.5)
	_event_tween.tween_property(_event_label, "modulate:a", 0.0, 0.4)
	_event_tween.tween_callback(_event_label.hide)


## Durante a montagem das formações o HUD some (a tela de formação ocupa o lugar)
func _on_formation_started() -> void:
	visible = false
	for tw in [_banner_tween, _event_tween]:
		if tw and tw.is_valid():
			tw.kill()
	_banner.hide()
	_event_label.hide()
	_summary.hide()
	_refresh_scores()


func _on_match_started() -> void:
	visible = true
	_refresh_scores()   # os times podem ter mudado de nome e cor na formação
	_refresh_period()


func _on_half_started(_half: int) -> void:
	_refresh_period()


func _on_extra_time_started() -> void:
	_refresh_period()
	# Aviso rápido avisando que entrou no gol de ouro
	_event_label.text = "Prorrogação! Gol de ouro decide a partida."
	_event_label.modulate = Color.WHITE
	_event_label.visible = true
	UiStyle.pop(_event_label, 1.2, 0.2)
	if _event_tween and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()
	_event_tween.tween_interval(3.0)
	_event_tween.tween_property(_event_label, "modulate:a", 0.0, 0.4)
	_event_tween.tween_callback(_event_label.hide)


func _refresh_period() -> void:
	_period_label.text = manager.time_label()


func _on_back_pressed(button: Button) -> void:
	button.disabled = true  # evita clique duplo
	manager.return_to_formation()


func _on_match_ended(winner: int) -> void:
	_refresh_scores()
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.hide()

	for child in _summary_box.get_children():
		_summary_box.remove_child(child)
		child.queue_free()

	# Título e placar final (winner = -1 quando a prorrogação acaba empatada)
	var is_draw: bool = winner < 0
	var title_text: String = "FIM DE JOGO — Empate!" if is_draw \
		else "FIM DE JOGO — %s venceu!" % manager.get_team_name(winner)
	var title := UiStyle.make_label(title_text, 34)
	if not is_draw:
		title.add_theme_color_override("font_color", _team_color(winner))
	_summary_box.add_child(title)

	var parts: PackedStringArray = []
	for t in manager.team_count:
		parts.append("%s %d" % [manager.get_team_name(t), manager.scores[t]])
	_summary_box.add_child(UiStyle.make_label("  ×  ".join(parts), 26))

	_summary_box.add_child(HSeparator.new())

	# Uma coluna por time, com os gols na ordem em que aconteceram (#1, #2...)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_summary_box.add_child(columns)

	for t in manager.team_count:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		columns.add_child(col)

		var header := UiStyle.make_label("%s (%d)" % [manager.get_team_name(t), manager.scores[t]], 22, _team_color(t))
		col.add_child(header)

		var any_goal: bool = false
		for goal: Dictionary in manager.goal_log:
			if goal["team"] != t:
				continue
			any_goal = true
			var line := UiStyle.make_label(_goal_line(goal), 16)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			col.add_child(line)
		if not any_goal:
			var none := UiStyle.make_label("Nenhum gol", 16, UiStyle.MUTED_COLOR)
			none.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			col.add_child(none)

	_add_mvp_section()

	# Botão para voltar à montagem das formações e começar de novo
	_summary_box.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Voltar às formações"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiStyle.style_button(back, UiStyle.ACCENT_COLOR.darkened(0.25))
	back.pressed.connect(_on_back_pressed.bind(back))
	_summary_box.add_child(back)

	_summary.visible = true
	_summary.modulate.a = 0.0
	UiStyle.pop(_summary, 0.85, 0.35)
	create_tween().tween_property(_summary, "modulate:a", 1.0, 0.25)


## Bloco do MVP no resumo final: nome, imagem/animação embaixo e a conta dos pontos
func _add_mvp_section() -> void:
	var mvp: Dictionary = manager.mvp
	if mvp.is_empty():
		return
	var color: Color = _team_color(mvp["team"])

	_summary_box.add_child(HSeparator.new())
	_summary_box.add_child(UiStyle.make_label("MVP", 18, UiStyle.MUTED_COLOR))
	_summary_box.add_child(UiStyle.make_label(String(mvp["name"]), 32, color))

	var portrait := MvpPortrait.new()
	portrait.setup(mvp["image"] as Texture2D, color, String(mvp["name"]))
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_summary_box.add_child(portrait)

	_summary_box.add_child(UiStyle.make_label(_mvp_breakdown(mvp), 16, UiStyle.MUTED_COLOR))


## "5 pts — 2 gols · 1 assist. · vitória"
func _mvp_breakdown(mvp: Dictionary) -> String:
	var parts: PackedStringArray = []
	if mvp["goals"] > 0:
		var goal_word: String = "gol de ouro" if mvp["golden"] else ("gol" if mvp["goals"] == 1 else "gols")
		parts.append("%d %s" % [mvp["goals"], goal_word])
	if mvp["assists"] > 0:
		parts.append("%d assist." % mvp["assists"])
	if mvp["win"] > 0:
		parts.append("vitória")
	return "%d pts — %s" % [mvp["points"], " · ".join(parts)]


# ---------- TEXTOS ----------

## Linha do resumo final: "#2  Fulano — assist.: Ciclano"
func _goal_line(goal: Dictionary) -> String:
	var text: String = "#%d  %s" % [goal["order"], goal["scorer"]]
	if goal["own_goal"]:
		text += " (gol contra)"
	elif goal["assist"] != "":
		text += " — assist.: %s" % goal["assist"]
	return text


## Detalhe do aviso de gol
func _goal_description(goal: Dictionary) -> String:
	var text: String = goal["scorer"]
	if goal["own_goal"]:
		text += " (gol contra)"
	elif goal["assist"] != "":
		text += "\nAssistência: %s" % goal["assist"]
	return text


func _refresh_scores() -> void:
	for t in _score_labels.size():
		_score_labels[t].text = "%s %d" % [manager.get_team_name(t), manager.scores[t]]
		_score_labels[t].add_theme_color_override("font_color", _team_color(t))   # o time pode ter mudado a cor
		# Quando o time marca, o número dele dá um "pulinho"
		if manager.scores[t] != _last_scores[t]:
			_last_scores[t] = manager.scores[t]
			UiStyle.pop(_score_labels[t], 1.4, 0.3)


# ---------- UTIL ----------

func _team_color(team: int) -> Color:
	return TeamStyle.color_of(team)
