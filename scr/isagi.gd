class_name Isagi
extends Player
## Isagi Yoichi. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias:
##
## 1. Backheel Shot (ação de habilidade, com 3 variantes automáticas pela altura):
##      - Isagi no chão + bola no chão     -> Backheel Shot: a bola vai na direção CONTRÁRIA da mira (45%)
##      - Isagi no chão + bola suspensa, ou os dois suspensos -> Direct Shot: voleio com QTE fácil (50%)
##      - Isagi suspenso/voando + bola no ar (Voando) -> Two Gun Volley: voleio voador com QTE difícil (60%)
## 2. Pieces (ação de habilidade): as 3 peças de quebra-cabeça existem desde o começo, mas
##      escondidas e sem efeito. Quando o Isagi usa Pieces elas aparecem, ficam fixas no campo
##      por 5 rodadas e só afetam o Isagi:
##      - Ataque: +5% em qualquer chute
##      - Meio-campo: mais tempo no Correr
##      - Defesa: o Pular chega ao nível Voando
## 3. Metavision (ação de habilidade): +1 ação de habilidade para os aliados (Secundários),
##      +5% em qualquer chute e nenhum QTE nos chutes do Isagi pelas próximas 3 rodadas.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Isagi" (o nome aparece no placar de gols).

const SKILL_SHOT: StringName = &"backheel_shot"
const SKILL_PIECES: StringName = &"pieces"
const SKILL_METAVISION: StringName = &"metavision"

## Variante do Backheel Shot que cabe na situação atual (altura do Isagi x altura da bola)
enum ShotVariant { NONE, BACKHEEL, DIRECT, TWO_GUN }

@export_group("Backheel Shot")
@export_range(0.0, 1.0) var chance_backheel: float = 0.45
@export_range(0.0, 1.0) var chance_direct: float = 0.50
@export_range(0.0, 1.0) var chance_two_gun: float = 0.60

@export_group("Pieces")
@export var piece_size: Vector2 = Vector2(320.0, 380.0)
## Posição de cada peça no eixo do campo, como fração da metade do comprimento do campo.
## Positivo = em direção ao gol que o time do Isagi ataca (o jogo espelha sozinho para o outro time).
@export var attack_piece_x: float = 0.55
@export var midfield_piece_x: float = 0.0
@export var defense_piece_x: float = -0.55
@export_range(0.0, 1.0) var attack_piece_bonus: float = 0.05   # +5% em qualquer chute
@export var midfield_run_bonus: float = 0.75                   # segundos a mais no Correr
@export var pieces_rounds: int = 5                             # rodadas depois da atual (igual à Metavision)
## Só valem depois que o Isagi usa a habilidade Pieces. A peça é checada na hora em que a
## ação começa (Correr, Pular) ou na hora do chute.

@export_group("Metavision")
@export var metavision_rounds: int = 3                         # rodadas depois da atual
@export_range(0.0, 1.0) var metavision_bonus: float = 0.05     # +5% em qualquer chute
@export var metavision_extra_ally_skills: int = 1              # ações de habilidade extras para os Secundários

var _manager: MatchManager = null
var _pieces: Array[PieceZone] = []
## As peças só aparecem e funcionam depois que o Isagi usa a habilidade Pieces,
## e valem até o fim desta rodada (-1 = inativas)
var _pieces_until_round: int = -1
var _pieces_shown: bool = false
var _base_run_duration: float = 0.0
## Metavision vale até o fim desta rodada (-1 = inativa)
var _metavision_until_round: int = -1
## Mirando o Backheel: o desenho mostra também para onde a bola vai de verdade
var _aiming_backheel: bool = false


func _init() -> void:
	character_id = "isagi"   # o menu de formação usa isto para saber quem é quem
	display_name = "Yoichi Isagi"   # aparece no placar de gols e no menu (troque aqui se quiser só "Isagi")


func _ready() -> void:
	super()
	_base_run_duration = run_duration
	_build_pieces.call_deferred()   # o Field e o MatchManager entram na árvore no mesmo frame
	_hook_manager.call_deferred()


func _exit_tree() -> void:
	for z in _pieces:
		if is_instance_valid(z):
			z.queue_free()


func _get_manager() -> MatchManager:
	if _manager == null:
		_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	return _manager


func _get_ball() -> Ball:
	return get_tree().get_first_node_in_group("ball") as Ball


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)


func _on_round_started(_round_number: int) -> void:
	queue_redraw()   # a aura da Metavision some quando as rodadas acabam
	if _pieces_shown and not is_pieces_active():   # Pieces acabou: as peças somem
		_pieces_shown = false
		for z in _pieces:
			z.disappear()


# ---------- PIECES ----------

## Cria as 3 peças (escondidas e sem efeito até o Isagi usar o Pieces)
func _build_pieces() -> void:
	var field := get_tree().get_first_node_in_group("field") as Field
	if field == null:
		push_warning("Isagi: nenhum Field encontrado; as peças do Pieces não foram criadas.")
		return

	var attack_dir: float = 1.0 if team == 0 else -1.0   # time 0 ataca para a direita
	var half_x: float = field.pitch_size.x * 0.5

	_add_piece(field, PieceZone.Kind.ATTACK, attack_dir * attack_piece_x * half_x,
		"ATAQUE", Color(1.0, 0.45, 0.35))
	_add_piece(field, PieceZone.Kind.MIDFIELD, attack_dir * midfield_piece_x * half_x,
		"MEIO-CAMPO", Color(0.45, 0.9, 0.5))
	_add_piece(field, PieceZone.Kind.DEFENSE, attack_dir * defense_piece_x * half_x,
		"DEFESA", Color(0.4, 0.65, 1.0))


func _add_piece(field: Field, kind: PieceZone.Kind, local_x: float, text: String,
		color: Color) -> void:
	var z := PieceZone.new()
	z.kind = kind
	z.size = piece_size
	z.color = color
	z.label = text
	field.add_child(z)
	z.global_position = field.to_global(Vector2(local_x, 0.0))
	_pieces.append(z)


## O Isagi está em cima da peça desse tipo?
func is_pieces_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _pieces_until_round >= 0 and m.round_number <= _pieces_until_round


func _in_piece(kind: PieceZone.Kind) -> bool:
	if not is_pieces_active():
		return false
	for z in _pieces:
		if z.kind == kind and z.contains(global_position):
			return true
	return false


## Meio-campo: mais tempo no Correr (checado na hora em que a corrida começa)
func start_run() -> void:
	run_duration = _base_run_duration
	if _in_piece(PieceZone.Kind.MIDFIELD):
		run_duration += midfield_run_bonus
	super()


## Defesa: o Pular chega ao nível Voando (se ele estiver em cima da peça de defesa)
func jump() -> void:
	if not _in_piece(PieceZone.Kind.DEFENSE):
		await super()
		return
	height_level = Heights.Level.FLYING
	var tw := create_tween()
	tw.tween_property(self, "height", Heights.FLYING_HEIGHT, jump_rise_time * 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


## Habilidade Pieces: as peças aparecem no campo e passam a valer por pieces_rounds rodadas
func _use_pieces() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or _pieces.is_empty():
		return false
	_pieces_until_round = m.round_number + pieces_rounds
	_pieces_shown = true
	for z in _pieces:
		z.appear()
	return true


# ---------- BÔNUS DE CHUTE (peça de ataque + Metavision) ----------

func _shot_bonus() -> float:
	var bonus: float = 0.0
	if _in_piece(PieceZone.Kind.ATTACK):
		bonus += attack_piece_bonus
	if is_metavision_active():
		bonus += metavision_bonus
	return bonus


## Vale também para o Chutar geral: base do tipo de chute + bônus
func get_shot_chance(kind: KickType) -> float:
	return minf(super(kind) + _shot_bonus(), 1.0)


# ---------- METAVISION ----------

func is_metavision_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _metavision_until_round >= 0 and m.round_number <= _metavision_until_round


## Com a Metavision ativa o MatchManager não roda o QTE dos chutes dele
func skips_qte() -> bool:
	return is_metavision_active()


func _use_metavision() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	_metavision_until_round = m.round_number + metavision_rounds
	m.secondary_skill_left += metavision_extra_ally_skills
	queue_redraw()
	return true


# ---------- BACKHEEL SHOT (e variantes) ----------

func get_shot_variant() -> ShotVariant:
	var ball: Ball = _get_ball()
	# get_kick_type já confere: derrubado, bola na mão do goleiro, longe demais, altura inalcançável
	if get_kick_type(ball) == KickType.NONE:
		return ShotVariant.NONE

	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND:
		if ball_level == Heights.Level.GROUND:
			return ShotVariant.BACKHEEL
		if ball_level == Heights.Level.SUSPENDED:
			return ShotVariant.DIRECT
	else:
		if ball_level == Heights.Level.FLYING:
			return ShotVariant.TWO_GUN
		# Isagi e bola os dois suspensos: também é Direct Shot
		if height_level == Heights.Level.SUSPENDED and ball_level == Heights.Level.SUSPENDED:
			return ShotVariant.DIRECT
	return ShotVariant.NONE


func _shot_skill_name() -> String:
	match get_shot_variant():
		ShotVariant.DIRECT:
			return "Direct Shot"
		ShotVariant.TWO_GUN:
			return "Two Gun Volley"
	return "Backheel Shot"


func _use_shot_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or get_shot_variant() == ShotVariant.NONE:
		return false

	# Mira. No Backheel a seta laranja é para onde ele "olha"; a bola vai para o lado oposto.
	_aiming_backheel = get_shot_variant() == ShotVariant.BACKHEEL
	queue_redraw()
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	_aiming_backheel = false
	queue_redraw()
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele mirava: confere de novo
	var ball: Ball = _get_ball()
	var variant: ShotVariant = get_shot_variant()
	if variant == ShotVariant.NONE:
		return false

	var kind: KickType = KickType.GROUND
	var base_chance: float = chance_backheel
	var dir: Vector2 = aim
	var needs_qte: bool = false
	var qte_kind: KickType = KickType.VOLLEY

	match variant:
		ShotVariant.BACKHEEL:
			dir = -aim
		ShotVariant.DIRECT:
			kind = KickType.VOLLEY
			base_chance = chance_direct
			needs_qte = true
			qte_kind = KickType.VOLLEY    # QTE fácil
		ShotVariant.TWO_GUN:
			kind = KickType.FLYING
			base_chance = chance_two_gun
			needs_qte = true
			qte_kind = KickType.FLYING    # QTE difícil

	var qte_ok: bool = true
	if needs_qte and not skips_qte():
		qte_ok = await m.run_qte(qte_kind)

	var chance: float = minf(base_chance + _shot_bonus(), 1.0)
	# Backheel Shot: a bola ignora a colisão do próprio Isagi
	await kick_ball(ball, dir, kind, qte_ok, chance, variant == ShotVariant.BACKHEEL)
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_SHOT, "name": _shot_skill_name()})
	list.append({"id": SKILL_PIECES, "name": "Pieces"})
	list.append({"id": SKILL_METAVISION, "name": "Metavision"})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_SHOT:
			return get_shot_variant() != ShotVariant.NONE
		SKILL_PIECES:
			return not is_pieces_active() and not _pieces.is_empty()   # sem reativar enquanto está valendo
		SKILL_METAVISION:
			return not is_metavision_active()   # sem reativar enquanto está valendo
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_SHOT:
			return await _use_shot_skill()
		SKILL_PIECES:
			return _use_pieces()
		SKILL_METAVISION:
			return _use_metavision()
	return false


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_metavision_until_round = -1
	_aiming_backheel = false
	_pieces_until_round = -1
	_pieces_shown = false
	for z in _pieces:
		z.hide_now()
	run_duration = _base_run_duration
	queue_redraw()


# ---------- LOOP / VISUAL ----------

func _process(delta: float) -> void:
	super(delta)
	for z in _pieces:
		z.highlighted = is_pieces_active() and z.contains(global_position)


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Aura ciano enquanto a Metavision está valendo
	if is_metavision_active():
		draw_arc(center, placeholder_radius + 6.0, 0.0, TAU, 40, Color(0.3, 0.9, 1.0, 0.9), 2.0)

	# Backheel: seta ciano = para onde a bola vai (a laranja do Player é para onde ele olha)
	if is_aiming and _aiming_backheel:
		var d: Vector2 = -aim_direction
		var start: Vector2 = d * (placeholder_radius + 4.0)
		var end: Vector2 = d * (placeholder_radius + aim_range)
		var side: Vector2 = d.orthogonal() * 8.0
		draw_line(start, end, Color.CYAN, 3.0)
		draw_colored_polygon(
			PackedVector2Array([end + d * 12.0, end + side, end - side]), Color.CYAN)
