class_name TypingGame
extends CanvasLayer
## Minigame simples de digitação: aparece uma palavra e o jogador digita as letras em ordem
## antes de o tempo acabar. Letra errada não passa a vez e ainda tira um pedacinho do tempo.
##
## Uso (o MatchManager.run_typing_game já faz isso):
##   var game := TypingGame.new()
##   add_child(game)
##   game.start("CURVA", 5.0, "Opposite Direction!")
##   var ok: bool = await game.finished

signal finished(success: bool)

const START_DELAY: float = 0.6      # "prepare-se" antes de poder digitar
const RESULT_DELAY: float = 0.5     # mostra Perfeito/Errou antes de seguir
const WRONG_KEY_PENALTY: float = 0.4

var _word: String = ""
var _index: int = 0
var _time_limit: float = 4.0
var _time_left: float = 0.0
var _delay_left: float = 0.0
var _running: bool = false

var _letters: Array[Label] = []
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _result_label: Label
var _panel: PanelContainer


func _ready() -> void:
	layer = 10   # acima do menu da partida (igual ao QTE)


func start(word: String, time_limit: float, title: String = "") -> void:
	_word = word.to_upper()
	_time_limit = time_limit
	_time_left = time_limit
	_index = 0
	_delay_left = START_DELAY
	_build_ui(title)
	_highlight()
	_running = true


func _build_ui(title: String) -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	UiStyle.style_panel(_panel, UiStyle.ACCENT_COLOR)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	vbox.add_child(UiStyle.make_label(title, 28))

	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	vbox.add_child(box)
	for ch in _word:
		var l := UiStyle.make_label(ch, 48)
		box.add_child(l)
		_letters.append(l)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(320, 18)
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.45)
	bar_bg.set_corner_radius_all(9)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = UiStyle.GOOD_COLOR
	_bar_fill.set_corner_radius_all(9)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	vbox.add_child(_bar)

	_result_label = UiStyle.make_label("Digite a palavra!", 24)
	_result_label.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(_result_label)

	UiStyle.pop(_panel, 0.85, 0.25)


## Letras já digitadas = verde, a atual = amarela, as próximas = neutras
func _highlight() -> void:
	for i in _letters.size():
		var c: Color = UiStyle.TEXT_COLOR
		if i < _index:
			c = UiStyle.GOOD_COLOR
		elif i == _index:
			c = Color.YELLOW
		_letters[i].add_theme_color_override("font_color", c)
	if _index < _letters.size():
		UiStyle.pop(_letters[_index], 1.25, 0.2)


func _process(delta: float) -> void:
	if not _running:
		return

	if _delay_left > 0.0:
		_delay_left -= delta
		if _delay_left <= 0.0:
			_result_label.text = ""
		return

	_time_left -= delta
	var ratio: float = clampf(_time_left / _time_limit, 0.0, 1.0)
	_bar.value = ratio
	if ratio > 0.5:
		_bar_fill.bg_color = Color.YELLOW.lerp(UiStyle.GOOD_COLOR, (ratio - 0.5) * 2.0)
	else:
		_bar_fill.bg_color = UiStyle.BAD_COLOR.lerp(Color.YELLOW, ratio * 2.0)
	if _time_left <= 0.0:
		_finish(false)


func _input(event: InputEvent) -> void:
	if not _running or _delay_left > 0.0:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# Só letras/números contam (Shift, setas etc. são ignorados)
	var typed: String = ""
	if event.unicode > 32:
		typed = char(event.unicode).to_upper()
	if typed == "":
		return

	get_viewport().set_input_as_handled()
	if typed == _word[_index]:
		_index += 1
		_highlight()
		if _index >= _word.length():
			_finish(true)
	else:
		_time_left -= WRONG_KEY_PENALTY
		_panel.modulate = Color(1.0, 0.6, 0.6)
		create_tween().tween_property(_panel, "modulate", Color.WHITE, 0.2)


func _finish(success: bool) -> void:
	if not _running:
		return
	_running = false
	_result_label.text = "Perfeito!" if success else "Errou!"
	_result_label.add_theme_color_override("font_color", UiStyle.GOOD_COLOR if success else UiStyle.BAD_COLOR)
	UiStyle.pop(_result_label, 1.5, 0.3)
	if not success:
		_panel.modulate = Color(1.0, 0.6, 0.6)
		create_tween().tween_property(_panel, "modulate", Color.WHITE, 0.4)
	await get_tree().create_timer(RESULT_DELAY).timeout
	finished.emit(success)
	queue_free()
