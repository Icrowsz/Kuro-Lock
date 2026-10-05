class_name Field
extends Node2D
## Campo de futebol 2.5D: linhas, gols (traves + travessão + rede) e limites.
##
## - Origem (0, 0) = centro do campo.
## - Time 0 defende o gol da ESQUERDA e ataca para a DIREITA (time 1, o contrário).
## - Traves e travessão são desenhados "em pé" (subindo na tela), igual à bola,
##   e ordenados por profundidade junto com jogadores e bola.
## - Não rotacione nem escale este nó (a conversão usa to_local/to_global).
##
## Estrutura da cena:
## Field (Node2D)  <- este script (arraste a Ball em "Ball")

signal goal_scored(team: int)
signal ball_out(local_position: Vector2)
## A bola voltou ao centro depois de um gol (o MatchManager aproveita para reposicionar os times)
signal ball_reset_after_goal

@export var ball: Ball

@export_group("Campo")
@export var pitch_size: Vector2 = Vector2(1600, 900)
@export var margin: float = 120.0                      # grama além das linhas
@export var center_circle_radius: float = 110.0
@export var penalty_area_size: Vector2 = Vector2(220, 480)  # profundidade x largura
@export var goal_area_size: Vector2 = Vector2(80, 220)
@export var penalty_spot_distance: float = 150.0
@export var line_width: float = 3.0

@export_group("Gol")
@export var goal_width: float = 220.0
@export var goal_depth: float = 70.0
@export var crossbar_height: float = 80.0              # altura (Z) do travessão: Suspenso (50) passa por baixo, Voando (100) passa por cima
@export var post_radius: float = 5.0
@export var crossbar_thickness: float = 6.0
@export var ball_hit_radius: float = 8.0               # "tamanho" da bola para bater na trave
@export var post_bounce: float = 0.6
@export var reset_delay: float = 2.0                   # tempo até a bola voltar ao centro após o gol

@export_group("Goleiros")
@export var spawn_goalkeepers: bool = true             # cria um goleiro por time (se a cena não tiver)

@export_group("Rede")
@export var animate_nets: bool = true                  # rede deformável (false = rede estática antiga)
@export var net_cell_size: float = 12.0                # tamanho de cada quadradinho da malha
@export var net_stiffness: float = 90.0                # quanto a rede volta ao repouso
@export var net_damping: float = 4.5                   # quanto ela demora para parar de balançar
@export var net_bulge: float = 1.0                     # multiplicador de quanto ela estufa

@export_group("Cores")
@export var grass_dark: Color = Color("2e7d32")
@export var grass_light: Color = Color("388e3c")
@export var line_color: Color = Color(1, 1, 1, 0.9)
@export var post_color: Color = Color(0.97, 0.97, 0.97)

var _prev_pos: Vector2 = Vector2.INF
var _scored_side: int = 0  # 0 = nenhum gol em andamento, 1 = gol da direita, -1 = gol da esquerda
var _nets: Dictionary = {}  # lado (1 = direita, -1 = esquerda) -> GoalNet


## Nó auxiliar que desenha uma peça (trave) com profundidade própria
class _Drawer extends Node2D:
	var fn: Callable

	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


func _ready() -> void:
	add_to_group("field")  # o MatchManager e os goleiros encontram o campo por aqui
	_spawn_goalkeepers.call_deferred()
	z_index = -4096  # o chão fica atrás de tudo
	for side in [-1, 1]:
		var dir: int = side
		var gx: float = pitch_size.x * 0.5 * dir
		_add_drawer(Vector2(gx, -goal_width * 0.5), _draw_post.bind(true))   # trave de trás (com travessão)
		_add_drawer(Vector2(gx, goal_width * 0.5), _draw_post.bind(false))   # trave da frente
	_build_nets()


## Cria um goleiro para cada time que ainda não tem um (você pode colocar os seus na cena)
func _spawn_goalkeepers() -> void:
	if not spawn_goalkeepers or ball == null:
		return
	var has_keeper := {}
	for k: Goalkeeper in get_tree().get_nodes_in_group("goalkeepers"):
		has_keeper[k.team] = true
	for t in 2:
		if has_keeper.has(t):
			continue
		var keeper := Goalkeeper.new()
		keeper.team = t
		ball.get_parent().add_child(keeper)  # mesma camada de profundidade da bola e dos jogadores


## Uma rede deformável por gol (fica acima da grama e atrás de jogadores e bola)
func _build_nets() -> void:
	if not animate_nets:
		return
	var half_x: float = pitch_size.x * 0.5
	for side in [-1, 1]:
		var dir: int = side
		var gx: float = half_x * dir
		var net := GoalNet.new()
		net.rect = Rect2(gx if dir > 0 else gx - goal_depth, -goal_width * 0.5, goal_depth, goal_width)
		net.front_is_min_x = dir > 0
		net.cell_size = net_cell_size
		net.stiffness = net_stiffness
		net.damping = net_damping
		net.bulge = net_bulge
		add_child(net)
		net.z_index = 1   # relativo ao campo (-4096): acima da grama, abaixo de todo o resto
		_nets[dir] = net


func _net_hit(side: int, global_pos: Vector2, velocity: Vector2, strength: float) -> void:
	var net := _nets.get(side) as GoalNet
	if net:
		net.hit(global_pos, velocity, strength)


func _net_shake(side: int, global_pos: Vector2, amount: float) -> void:
	var net := _nets.get(side) as GoalNet
	if net:
		net.shake(global_pos, amount)


## Para outros scripts (ex: o goleiro mergulhando na rede): mexe na rede do gol mais perto
func poke_net(global_pos: Vector2, velocity: Vector2 = Vector2.ZERO, strength: float = 1.0) -> void:
	var side: int = 1 if to_local(global_pos).x >= 0.0 else -1
	_net_hit(side, global_pos, velocity, strength)


func _add_drawer(local_pos: Vector2, fn: Callable) -> void:
	var d := _Drawer.new()
	d.position = local_pos
	d.fn = fn
	d.z_as_relative = false
	add_child(d)
	d.z_index = int(d.global_position.y)  # mesma regra de profundidade da bola e dos jogadores


# ---------- FÍSICA: LIMITES, TRAVES E GOL ----------

func _physics_process(_delta: float) -> void:
	if ball == null:
		return

	var p: Vector2 = to_local(ball.global_position)
	if _prev_pos == Vector2.INF:
		_prev_pos = p

	if _scored_side != 0:
		p = _contain_in_net(p)
	else:
		p = _check_goals(p)
		if _scored_side == 0:
			p = _clamp_to_pitch(p)

	ball.global_position = to_global(p)
	_prev_pos = p


func _check_goals(p: Vector2) -> Vector2:
	var half: Vector2 = pitch_size * 0.5
	var post_y: float = goal_width * 0.5
	var r: float = post_radius + ball_hit_radius
	var top: float = crossbar_height + crossbar_thickness

	for side in [-1, 1]:
		var dir: int = side
		var gx: float = half.x * dir

		# A bola cruzou a linha de fundo (vindo de dentro do campo) neste frame?
		var was_inside: bool = (_prev_pos.x - gx) * dir < 0.0
		var is_outside: bool = (p.x - gx) * dir >= 0.0
		if not (was_inside and is_outside):
			continue

		# Onde (y) e a que altura (z) ela cruzou a linha
		var t: float = (gx - _prev_pos.x) / (p.x - _prev_pos.x)
		var cross_y: float = absf(lerpf(_prev_pos.y, p.y, t))
		var h: float = ball.height

		if cross_y < post_y - r:
			# Dentro da boca do gol
			if h < crossbar_height - crossbar_thickness:
				_register_goal(dir, p)
				return p
			elif h <= top:
				# Travessão: quica para baixo e volta
				ball.vel_z = -absf(ball.vel_z) * 0.5
				return _bounce_x(p, gx, dir)
			# Acima do travessão: segue para fora (tratado pelo limite do campo)
		elif cross_y <= post_y + r and h <= top:
			# Trave
			return _bounce_x(p, gx, dir)

	return p


func _bounce_x(p: Vector2, gx: float, dir: int) -> Vector2:
	var v: Vector2 = ball.velocity
	# A rede está presa na trave/travessão: a pancada faz ela tremer
	_net_shake(dir, to_global(Vector2(gx, p.y)), clampf(absf(v.x) / 800.0, 0.2, 1.5))
	v.x = -v.x * post_bounce
	ball.velocity = v
	var out: Vector2 = p
	out.x = gx - dir * 2.0  # devolve a bola para dentro do campo
	return out


func _register_goal(dir: int, entry: Vector2 = Vector2.ZERO) -> void:
	_scored_side = dir
	# A rede estufa conforme a força do chute (velocidade da bola ao entrar)
	_net_hit(dir, to_global(entry), ball.velocity, clampf(ball.velocity.length() / 700.0, 0.35, 2.0))
	var scoring_team: int = 0 if dir > 0 else 1  # time 0 ataca o gol da direita
	goal_scored.emit(scoring_team)
	_reset_after_delay()


func _reset_after_delay() -> void:
	await get_tree().create_timer(reset_delay).timeout
	reset_ball()
	ball_reset_after_goal.emit()


## A bola fica presa dentro da rede depois do gol
func _contain_in_net(p: Vector2) -> Vector2:
	var half: Vector2 = pitch_size * 0.5
	var gx: float = half.x * _scored_side
	var inner_y: float = goal_width * 0.5 - post_radius - ball_hit_radius
	var x_min: float = gx if _scored_side > 0 else gx - goal_depth
	var x_max: float = gx + goal_depth if _scored_side > 0 else gx

	var out: Vector2 = p
	var v: Vector2 = ball.velocity
	var net := _nets.get(_scored_side) as GoalNet

	# A bola arrasta a rede enquanto anda lá dentro
	if net:
		net.drag(to_global(out), v, get_physics_process_delta_time())

	if out.x < x_min:
		out.x = x_min
		if net and absf(v.x) > 40.0:
			net.hit(to_global(out), Vector2(v.x, 0.0), clampf(absf(v.x) / 700.0, 0.2, 2.0))
		v.x = absf(v.x) * 0.2
	elif out.x > x_max:
		out.x = x_max
		if net and absf(v.x) > 40.0:
			net.hit(to_global(out), Vector2(v.x, 0.0), clampf(absf(v.x) / 700.0, 0.2, 2.0))
		v.x = -absf(v.x) * 0.2

	if absf(out.y) > inner_y:
		out.y = signf(out.y) * inner_y
		if net and absf(v.y) > 40.0:
			net.hit(to_global(out), Vector2(0.0, v.y), clampf(absf(v.y) / 700.0, 0.2, 2.0))
		v.y = -v.y * 0.2

	ball.velocity = v
	return out


## Por enquanto a bola quica nos limites (placeholder para lateral, escanteio e tiro de meta)
func _clamp_to_pitch(p: Vector2) -> Vector2:
	var half: Vector2 = pitch_size * 0.5
	var out: Vector2 = p
	var v: Vector2 = ball.velocity
	var went_out: bool = false

	if absf(out.x) > half.x:
		out.x = signf(out.x) * half.x
		v.x = -v.x * 0.5
		went_out = true
	if absf(out.y) > half.y:
		out.y = signf(out.y) * half.y
		v.y = -v.y * 0.5
		went_out = true

	if went_out:
		ball.velocity = v
		ball_out.emit(out)
	return out


# ---------- API ----------

## Coloca a bola parada em uma posição local do campo (padrão: centro)
func reset_ball(local_pos: Vector2 = Vector2.ZERO) -> void:
	_scored_side = 0
	_prev_pos = local_pos
	if ball:
		ball.reset(to_global(local_pos))


## Grande área que o time DEFENDE (em coordenadas locais do campo)
func get_penalty_area_rect(team: int) -> Rect2:
	var half: Vector2 = pitch_size * 0.5
	var dir: int = -1 if team == 0 else 1
	var gx: float = half.x * dir
	var x0: float = gx if dir < 0 else gx - penalty_area_size.x
	return Rect2(x0, -penalty_area_size.y * 0.5, penalty_area_size.x, penalty_area_size.y)


## Esta posição (global) está dentro da grande área defendida por esse time?
func is_in_penalty_area(global_pos: Vector2, team: int) -> bool:
	return get_penalty_area_rect(team).has_point(to_local(global_pos))


## Centro (global) do gol que o time ataca — útil para IA e chutes
func get_attack_goal_center(team: int) -> Vector2:
	var dir: float = 1.0 if team == 0 else -1.0
	return to_global(Vector2(pitch_size.x * 0.5 * dir, 0.0))


## Centro (global) do gol que o time defende
func get_defend_goal_center(team: int) -> Vector2:
	var dir: float = -1.0 if team == 0 else 1.0
	return to_global(Vector2(pitch_size.x * 0.5 * dir, 0.0))


# ---------- DESENHO ----------

func _draw() -> void:
	var half: Vector2 = pitch_size * 0.5

	# Grama + listras
	var full := Rect2(-half - Vector2(margin, margin), pitch_size + Vector2(margin, margin) * 2.0)
	draw_rect(full, grass_dark)
	var stripes: int = 12
	var stripe_w: float = pitch_size.x / stripes
	for i in stripes:
		if i % 2 == 0:
			draw_rect(Rect2(-half.x + i * stripe_w, -half.y, stripe_w, pitch_size.y), grass_light)

	# Linhas gerais
	draw_rect(Rect2(-half, pitch_size), line_color, false, line_width)
	draw_line(Vector2(0, -half.y), Vector2(0, half.y), line_color, line_width)
	draw_arc(Vector2.ZERO, center_circle_radius, 0.0, TAU, 64, line_color, line_width)
	draw_circle(Vector2.ZERO, 4.0, line_color)

	for side in [-1, 1]:
		var dir: int = side
		var gx: float = half.x * dir

		# Grande área e pequena área
		var pa_x: float = gx if dir < 0 else gx - penalty_area_size.x
		draw_rect(Rect2(pa_x, -penalty_area_size.y * 0.5, penalty_area_size.x, penalty_area_size.y),
			line_color, false, line_width)
		var ga_x: float = gx if dir < 0 else gx - goal_area_size.x
		draw_rect(Rect2(ga_x, -goal_area_size.y * 0.5, goal_area_size.x, goal_area_size.y),
			line_color, false, line_width)

		# Marca do pênalti
		draw_circle(Vector2(gx - dir * penalty_spot_distance, 0.0), 4.0, line_color)

		# Rede estática antiga (a rede deformável é o GoalNet)
		if not animate_nets:
			_draw_static_net(gx, dir)


## Rede desenhada direto no campo (usada só quando animate_nets = false)
func _draw_static_net(gx: float, dir: int) -> void:
	var net_x: float = gx if dir > 0 else gx - goal_depth
	var net := Rect2(net_x, -goal_width * 0.5, goal_depth, goal_width)
	draw_rect(net, Color(0, 0, 0, 0.35))
	var step: float = 12.0
	var x: float = net.position.x
	while x <= net.end.x:
		draw_line(Vector2(x, net.position.y), Vector2(x, net.end.y), Color(1, 1, 1, 0.25), 1.0)
		x += step
	var y: float = net.position.y
	while y <= net.end.y:
		draw_line(Vector2(net.position.x, y), Vector2(net.end.x, y), Color(1, 1, 1, 0.25), 1.0)
		y += step
	draw_rect(net, Color(1, 1, 1, 0.6), false, 2.0)


## Desenha uma trave "em pé"; a de trás também desenha o travessão
func _draw_post(n: Node2D, with_crossbar: bool) -> void:
	n.draw_circle(Vector2.ZERO, post_radius + 2.0, Color(0, 0, 0, 0.35))  # sombra na base
	n.draw_line(Vector2.ZERO, Vector2(0, -crossbar_height), post_color, post_radius * 2.0)
	if with_crossbar:
		n.draw_line(
			Vector2(0, -crossbar_height),
			Vector2(0, goal_width - crossbar_height),
			post_color, crossbar_thickness * 2.0
		)
