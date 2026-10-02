class_name QTE
extends CanvasLayer
## Quick Time Event: aparece uma sequência de teclas e o jogador precisa
## apertar cada uma a tempo. Errar a tecla ou estourar o tempo = falha.
##
## Uso (o MatchManager já faz isso):
##   var qte := QTE.new()
##   add_child(qte)
##   qte.start(QTE.EASY_KEYS, 3, 0.9, "Voleio!")
##   var ok: bool = await qte.finished

signal finished(success: bool)

const EASY_KEYS: Array[int] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
const HARD_KEYS: Array[int] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_Z, KEY_X]

const ARROW_LABELS := {
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
}

const START_DELAY: float = 0.6      # "prepare-se" antes da primeira tecla
const RESULT_DELAY: float = 0.5     # mostra Perfeito/Errou antes de seguir

var _sequence: Array[int] = []
var _index: int = 0
var _time_per_key: float = 1.0
var _time_left: float = 0.0
var _delay_left: float = 0.0
var _running: bool = false

var _title_label: Label
var _keys_box: HBoxContainer
var _key_labels: Array[Label] = []
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _result_label: Label
var _panel: PanelContainer


func _ready() -> void:
	layer = 10  # acima do menu da partida


## key_pool: teclas possíveis | count: quantas teclas na sequência
## time_per_key: segundos para apertar cada uma
func start(key_pool: Array[int], count: int, time_per_key: float, title: String = "") -> void:
	_time_per_key = time_per_key
	_sequence = _make_sequence(key_pool, count)
	_index = 0
	_delay_left = START_DELAY
	_time_left = _time_per_key
	_build_ui(title)
	_highlight()
	_running = true


func _make_sequence(pool: Array[int], count: int) -> Array[int]:
	var seq: Array[int] = []
	for i in count:
		var k: int = pool.pick_random()
		# Evita a mesma tecla duas vezes seguidas (se houver mais de uma opção)
		while pool.size() > 1 and not seq.is_empty() and k == seq[-1]:
			k = pool.pick_random()
		seq.append(k)
	return seq


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

	_title_label = UiStyle.make_label(title, 28)
	vbox.add_child(_title_label)

	_keys_box = HBoxContainer.new()
	_keys_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_keys_box.add_theme_constant_override("separation", 18)
	vbox.add_child(_keys_box)
	for k in _sequence:
		var l := UiStyle.make_label(_key_text(k), 48)
		_keys_box.add_child(l)
		_key_labels.append(l)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(320, 18)
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	# Barra arredondada que vai de verde a vermelho conforme o tempo acaba
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.45)
	bar_bg.set_corner_radius_all(9)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = UiStyle.GOOD_COLOR
	_bar_fill.set_corner_radius_all(9)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	vbox.add_child(_bar)

	_result_label = UiStyle.make_label("Prepare-se!", 24)
	_result_label.custom_minimum_size = Vector2(0, 40)  # a caixa não "pula" quando o texto some
	vbox.add_child(_result_label)

	# Entrada com um pequeno "pulo"
	UiStyle.pop(_panel, 0.85, 0.25)


func _key_text(key: int) -> String:
	if ARROW_LABELS.has(key):
		return ARROW_LABELS[key]
	return OS.get_keycode_string(key as Key)


## Teclas já acertadas = verde, a atual = amarela, as próximas = neutras
func _highlight() -> void:
	for i in _key_labels.size():
		var c: Color = UiStyle.TEXT_COLOR
		if i < _index:
			c = UiStyle.GOOD_COLOR
		elif i == _index:
			c = Color.YELLOW
		_key_labels[i].add_theme_color_override("font_color", c)
	# A tecla da vez dá um "pulinho" para chamar atenção
	if _index < _key_labels.size():
		UiStyle.pop(_key_labels[_index], 1.25, 0.2)


func _process(delta: float) -> void:
	if not _running:
		return

	if _delay_left > 0.0:
		_delay_left -= delta
		if _delay_left <= 0.0:
			_result_label.text = ""
		return

	_time_left -= delta
	var ratio: float = clampf(_time_left / _time_per_key, 0.0, 1.0)
	_bar.value = ratio
	# verde (cheio) -> amarelo (metade) -> vermelho (acabando)
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

	get_viewport().set_input_as_handled()
	if event.keycode == _sequence[_index]:
		_index += 1
		_highlight()
		if _index >= _sequence.size():
			_finish(true)
		else:
			_time_left = _time_per_key  # cada tecla tem seu próprio tempo
	else:
		_finish(false)


func _finish(success: bool) -> void:
	if not _running:
		return
	_running = false
	_result_label.text = "Perfeito!" if success else "Errou!"
	_result_label.add_theme_color_override("font_color", UiStyle.GOOD_COLOR if success else UiStyle.BAD_COLOR)
	UiStyle.pop(_result_label, 1.5, 0.3)
	if not success:
		# Piscada avermelhada no painel
		_panel.modulate = Color(1.0, 0.6, 0.6)
		create_tween().tween_property(_panel, "modulate", Color.WHITE, 0.4)
	await get_tree().create_timer(RESULT_DELAY).timeout
	finished.emit(success)
	queue_free()
