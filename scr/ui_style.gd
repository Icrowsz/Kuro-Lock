class_name UiStyle
extends RefCounted
## Estilo visual compartilhado da interface (placar, menu de ações, QTE).
## Tudo é estático: basta chamar UiStyle.make_label(...), UiStyle.panel_style() etc.

const TEXT_COLOR := Color(0.93, 0.93, 0.93)          # texto neutro
const MUTED_COLOR := Color(0.93, 0.93, 0.93, 0.65)   # texto secundário
const OUTLINE_COLOR := Color(0.05, 0.05, 0.05)       # contorno das letras
const PANEL_COLOR := Color(0.06, 0.07, 0.10, 0.78)   # fundo dos painéis
const PANEL_BORDER := Color(1, 1, 1, 0.14)
const ACCENT_COLOR := Color(1.0, 0.82, 0.25)         # destaque (habilidade, aviso)
const GOOD_COLOR := Color.LIME_GREEN
const BAD_COLOR := Color.TOMATO


## Contorno proporcional ao tamanho da fonte (26 pt ≈ 5, 48 pt ≈ 10)
static func outline(control: Control, font_size: int = 16) -> void:
	var size: int = clampi(roundi(font_size * 0.2), 3, 10)
	control.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	control.add_theme_constant_override("outline_size", size)


## Label já com cor neutra, contorno e centralizado. Quem quiser cor de time sobrescreve depois.
static func make_label(text: String, font_size: int, color: Color = TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	outline(label, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Painel arredondado, translúcido, com borda fina e sombra leve
static func panel_style(border: Color = PANEL_BORDER, h_margin: float = 16.0, v_margin: float = 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = h_margin
	sb.content_margin_right = h_margin
	sb.content_margin_top = v_margin
	sb.content_margin_bottom = v_margin
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	return sb


## Aplica o painel a um PanelContainer
static func style_panel(panel: PanelContainer, border: Color = PANEL_BORDER) -> StyleBoxFlat:
	var sb := panel_style(border)
	panel.add_theme_stylebox_override("panel", sb)
	return sb


## Botão com visual próprio (normal / hover / pressionado / desativado) e "pulinho" ao passar o mouse
static func style_button(b: Button, accent: Color = Color(0.30, 0.34, 0.45)) -> void:
	b.add_theme_stylebox_override("normal", _button_box(accent.darkened(0.35), accent))
	b.add_theme_stylebox_override("hover", _button_box(accent.darkened(0.1), accent.lightened(0.35)))
	b.add_theme_stylebox_override("pressed", _button_box(accent.darkened(0.55), accent))
	b.add_theme_stylebox_override("focus", _button_box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.5)))
	b.add_theme_stylebox_override("disabled", _button_box(Color(0.15, 0.15, 0.18, 0.7), Color(1, 1, 1, 0.08)))
	b.add_theme_color_override("font_color", TEXT_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED_COLOR.darkened(0.2))
	b.add_theme_font_size_override("font_size", 18)
	outline(b, 18)
	b.mouse_entered.connect(_button_pop.bind(b, 1.06))
	b.mouse_exited.connect(_button_pop.bind(b, 1.0))


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func _button_pop(b: Button, target: float) -> void:
	if b.disabled:
		target = 1.0
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE * target, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## "Pulinho" de escala (usa o tamanho mínimo como pivô, serve para Labels e painéis centralizados)
static func pop(control: Control, from_scale: float = 1.35, time: float = 0.25) -> void:
	control.pivot_offset = control.get_combined_minimum_size() * 0.5
	control.scale = Vector2.ONE * from_scale
	var tw := control.create_tween()
	tw.tween_property(control, "scale", Vector2.ONE, time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
