class_name GoalNet
extends Node2D
## Rede do gol: uma malha de pontos ligados por molas.
##
## - A borda da linha de fundo e as duas laterais ficam presas às traves (não se mexem).
## - O resto da rede reage: estufa quando a bola entra forte, acompanha a bola enquanto ela
##   se arrasta lá dentro, ondula quando a bola bate no fundo/lateral e treme quando a bola
##   bate na trave ou no travessão.
## - Os pontos deslocados "sobem" um pouco na tela (igual à altura da bola), então o estufar
##   lê como a rede se inflando. Linhas muito esticadas ficam mais brilhantes.
## - Quando a rede para de se mexer, ela "dorme" e não gasta processamento.
##
## O Field cria uma GoalNet por gol. Dá para chamar de fora (ex: o goleiro):
##   field.poke_net(global_pos, velocidade, forca)

@export var rect: Rect2 = Rect2(0.0, -110.0, 70.0, 220.0)   # área da rede (coordenadas do Field)
@export var front_is_min_x: bool = true     # a linha de fundo (boca do gol) é o lado de menor x?
@export var cell_size: float = 12.0         # tamanho de cada quadradinho da malha
@export var stiffness: float = 90.0         # força que devolve a rede ao repouso
@export var damping: float = 4.5            # quanto ela demora para parar de balançar
@export var coupling: float = 55.0          # quanto cada ponto puxa os vizinhos (rede "unida")
@export var bulge: float = 1.0              # multiplicador geral do estufar
@export var max_offset: float = 60.0        # deslocamento máximo de um ponto (px)
@export var drag_gain: float = 0.5          # quanto a bola em movimento arrasta a rede
@export var fill_color: Color = Color(0.0, 0.0, 0.0, 0.35)
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.25)
@export var stretched_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var frame_color: Color = Color(1.0, 1.0, 1.0, 0.6)

var _cols: int = 2
var _rows: int = 2
var _rest: PackedVector2Array = PackedVector2Array()
var _off: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _awake: bool = false


func _ready() -> void:
	_cols = maxi(2, roundi(rect.size.x / cell_size) + 1)
	_rows = maxi(2, roundi(rect.size.y / cell_size) + 1)
	var n: int = _cols * _rows
	_rest.resize(n)
	_off.resize(n)
	_vel.resize(n)
	for c in _cols:
		for r in _rows:
			_rest[_idx(c, r)] = Vector2(
				rect.position.x + rect.size.x * float(c) / float(_cols - 1),
				rect.position.y + rect.size.y * float(r) / float(_rows - 1))
	queue_redraw()


func _idx(c: int, r: int) -> int:
	return c * _rows + r


func _front_col() -> int:
	return 0 if front_is_min_x else _cols - 1


## Linha de fundo e laterais ficam presas às traves
func _is_fixed(c: int, r: int) -> bool:
	return c == _front_col() or r == 0 or r == _rows - 1


# ---------- API ----------

## Impacto: a bola bateu/entrou na rede em global_pos com essa velocidade.
## strength ~1 = chute normal; 2 = chute muito forte.
func hit(global_pos: Vector2, velocity: Vector2, strength: float = 1.0) -> void:
	var p: Vector2 = to_local(global_pos)
	var dir: Vector2 = velocity.normalized() if velocity.length() > 1.0 else Vector2.ZERO
	var s: float = strength * bulge
	var radius: float = lerpf(45.0, 110.0, clampf(s / 2.0, 0.0, 1.0))
	for c in _cols:
		for r in _rows:
			if _is_fixed(c, r):
				continue
			var i: int = _idx(c, r)
			var d: float = _rest[i].distance_to(p)
			var f: float = exp(-(d * d) / (radius * radius))
			if f < 0.02:
				continue
			if dir == Vector2.ZERO:
				# Sem direção (uma cutucada): empurra para fora do ponto
				_vel[i] += (_rest[i] - p).normalized() * f * s * 120.0
			else:
				_vel[i] += dir * f * s * 260.0
	_wake()


## Bola em movimento dentro da rede: arrasta os pontos perto dela (chame todo frame)
func drag(global_pos: Vector2, velocity: Vector2, delta: float) -> void:
	var p: Vector2 = to_local(global_pos)
	for c in _cols:
		for r in _rows:
			if _is_fixed(c, r):
				continue
			var i: int = _idx(c, r)
			var d: float = _rest[i].distance_to(p)
			var f: float = exp(-(d * d) / (40.0 * 40.0))
			if f < 0.02:
				continue
			_vel[i] += velocity * f * drag_gain * bulge * delta
	_wake()


## Vibração leve (bola bateu na trave/travessão, onde a rede está presa)
func shake(global_pos: Vector2, amount: float = 1.0) -> void:
	var p: Vector2 = to_local(global_pos)
	for c in _cols:
		for r in _rows:
			if _is_fixed(c, r):
				continue
			var i: int = _idx(c, r)
			var d: float = _rest[i].distance_to(p)
			var f: float = exp(-(d * d) / (140.0 * 140.0))
			if f < 0.02:
				continue
			_vel[i] += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 90.0 * f * amount
	_wake()


## Para a rede na hora (ex: partida recomeçando)
func settle() -> void:
	for i in _off.size():
		_off[i] = Vector2.ZERO
		_vel[i] = Vector2.ZERO
	_awake = false
	queue_redraw()


func _wake() -> void:
	_awake = true


# ---------- SIMULAÇÃO ----------

func _physics_process(delta: float) -> void:
	if not _awake:
		return
	var dt: float = minf(delta, 1.0 / 30.0)

	# 1) forças: mola até o repouso + amortecimento + puxão dos vizinhos
	for c in _cols:
		for r in _rows:
			if _is_fixed(c, r):
				continue
			var i: int = _idx(c, r)
			var acc: Vector2 = -stiffness * _off[i] - damping * _vel[i]
			var n_sum: Vector2 = Vector2.ZERO
			var n_cnt: int = 0
			if c > 0:
				n_sum += _off[_idx(c - 1, r)]
				n_cnt += 1
			if c < _cols - 1:
				n_sum += _off[_idx(c + 1, r)]
				n_cnt += 1
			if r > 0:
				n_sum += _off[_idx(c, r - 1)]
				n_cnt += 1
			if r < _rows - 1:
				n_sum += _off[_idx(c, r + 1)]
				n_cnt += 1
			acc += coupling * (n_sum - _off[i] * float(n_cnt))
			_vel[i] += acc * dt

	# 2) move os pontos e mede a energia que sobrou
	var energy: float = 0.0
	for i in _off.size():
		_off[i] = (_off[i] + _vel[i] * dt).limit_length(max_offset)
		energy = maxf(energy, _off[i].length() + _vel[i].length() * 0.1)

	if energy < 0.15:
		settle()   # parou: dorme até o próximo impacto
	else:
		queue_redraw()


# ---------- DESENHO ----------

func _point(c: int, r: int) -> Vector2:
	var i: int = _idx(c, r)
	var lift: float = minf(_off[i].length() * 0.45, 28.0)   # estufa "para cima" na tela
	return _rest[i] + _off[i] + Vector2(0.0, -lift)


func _stretch(c: int, r: int) -> float:
	return clampf(_off[_idx(c, r)].length() / 35.0, 0.0, 1.0)


func _draw() -> void:
	draw_rect(rect, fill_color)

	var pts: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	for c in _cols:
		for r in _rows:
			var a: Vector2 = _point(c, r)
			var sa: float = _stretch(c, r)
			if c < _cols - 1:
				pts.append(a)
				pts.append(_point(c + 1, r))
				cols.append(line_color.lerp(stretched_color, (sa + _stretch(c + 1, r)) * 0.5))
			if r < _rows - 1:
				pts.append(a)
				pts.append(_point(c, r + 1))
				cols.append(line_color.lerp(stretched_color, (sa + _stretch(c, r + 1)) * 0.5))
	draw_multiline_colors(pts, cols, 1.0)

	draw_rect(rect, frame_color, false, 2.0)
