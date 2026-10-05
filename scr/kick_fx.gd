class_name KickFX
extends Resource
## Estilo visual de uma habilidade de chute: aura (rastro) + partículas.
## Cada personagem tem o seu. Dá para criar por código (veja isagi.gd / rin.gd) ou
## salvar como .tres e editar no Inspetor (Novo Recurso -> KickFX).
##
## O Ball só LÊ este recurso. Gradientes, curvas e texturas são criados UMA vez e
## reaproveitados (nada de alocar objetos a cada chute).

enum Shape { DOT, SQUARE }

@export_group("Aura (rastro)")
@export var color: Color = Color.WHITE                 # cor da aura
@export_range(0.0, 1.0) var trail_alpha: float = 0.85  # opacidade na ponta (perto da bola)
@export var trail_width: float = 14.0                  # espessura máxima (px)
@export var trail_points: int = 16                     # tamanho do rastro (quanto maior, mais longo)
@export var trail_min_step: float = 4.0                # só grava um ponto novo após andar tantos px
@export var additive: bool = true                      # true = brilho (soma luz); false = mistura normal

@export_group("Partículas")
@export var shape: Shape = Shape.DOT
@export var particle_color: Color = Color.WHITE
@export var amount: int = 20                           # partículas vivas ao mesmo tempo
@export var lifetime: float = 0.5
@export var speed_min: float = 10.0
@export var speed_max: float = 60.0
@export var emit_radius: float = 6.0
@export var gravity: Vector2 = Vector2.ZERO            # y negativo = sobem
@export var swirl: float = 0.0                         # aceleração tangencial (faz espiral)
@export var damping: float = 0.0                       # freia as partículas
@export var spin: float = 0.0                          # giro máximo (graus/s)
@export var scale_min: float = 0.2                     # 1.0 = 32 px
@export var scale_max: float = 0.5

@export_group("Explosão no chute")
@export var burst_amount: int = 12
@export var burst_speed: float = 180.0

# ---------- cache (criado sob demanda, uma vez só) ----------

static var _additive_mat: CanvasItemMaterial
static var _tex_dot: Texture2D
static var _tex_square: Texture2D

var _trail_gradient: Gradient
var _width_curve: Curve
var _particle_gradient: Gradient
var _shrink_curve: Curve


## Material compartilhado que soma a luz (efeito de brilho)
static func additive_material() -> CanvasItemMaterial:
	if _additive_mat == null:
		_additive_mat = CanvasItemMaterial.new()
		_additive_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_mat


func get_blend_material() -> CanvasItemMaterial:
	return additive_material() if additive else null


func get_texture() -> Texture2D:
	if shape == Shape.SQUARE:
		if _tex_square == null:
			var g := Gradient.new()
			g.colors = PackedColorArray([Color.WHITE, Color.WHITE])
			var t := GradientTexture2D.new()
			t.gradient = g
			t.width = 32
			t.height = 32
			_tex_square = t
		return _tex_square

	if _tex_dot == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 32
		t.height = 32
		_tex_dot = t
	return _tex_dot


## Rastro: cauda transparente -> ponta clara e opaca
func get_trail_gradient() -> Gradient:
	if _trail_gradient == null:
		_trail_gradient = Gradient.new()
		_trail_gradient.offsets = PackedFloat32Array([0.0, 1.0])
		_trail_gradient.colors = PackedColorArray([
			Color(color, 0.0),
			Color(color.lightened(0.3), trail_alpha),
		])
	return _trail_gradient


## Rastro: afina na cauda, grosso na ponta
func get_width_curve() -> Curve:
	if _width_curve == null:
		_width_curve = Curve.new()
		_width_curve.add_point(Vector2(0.0, 0.0))
		_width_curve.add_point(Vector2(1.0, 1.0))
	return _width_curve


## Partículas: somem (alpha) ao longo da vida
func get_particle_gradient() -> Gradient:
	if _particle_gradient == null:
		_particle_gradient = Gradient.new()
		_particle_gradient.offsets = PackedFloat32Array([0.0, 1.0])
		_particle_gradient.colors = PackedColorArray([
			Color(particle_color, 1.0),
			Color(particle_color, 0.0),
		])
	return _particle_gradient


## Partículas: encolhem ao longo da vida
func get_shrink_curve() -> Curve:
	if _shrink_curve == null:
		_shrink_curve = Curve.new()
		_shrink_curve.add_point(Vector2(0.0, 1.0))
		_shrink_curve.add_point(Vector2(1.0, 0.0))
	return _shrink_curve
