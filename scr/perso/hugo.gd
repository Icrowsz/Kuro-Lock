class_name Hugo
extends Player
## Hugo. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias.
## Visual: vermelho vinho com engrenagens douradas (o Bee-Blep! Focus é uma engrenagem dourada).
##
## 1. Coordination (recarga de 2 rodadas, compartilhada pelas 3 variantes; a variante é escolhida
##      sozinha pela situação):
##      - Bola próxima e NO CHÃO -> Coordination: Hugo segura a bola (até o fim do próximo turno do
##        adversário, ninguém do outro time toca nela). Se ele é o Protagonista: +1 ação geral e +1 de
##        habilidade para os Secundários. Se é Secundário: +1 de habilidade para o Protagonista e +1
##        ação geral só dele.
##      - Sem bola próxima -> Adequation: escolhe 2 inimigos a até 600 px. Eles ficam proibidos de ser
##        Protagonista e com o Correr mais lento pelos próximos 2 turnos do time deles.
##      - Bola próxima SUSPENSA/VOANDO (Hugo no chão ou suspenso) -> Unsuitable: ele salta até a bola
##        e dá um deflect, refletindo-a para a direção contrária.
## 2. Bee-Blep! Focus (recarga de 2 rodadas, compartilhada):
##      - Bola próxima (chão/suspensa) e Hugo no chão -> Bee-Blep! Focus: passe rasteiro longo (580 px)
##        que sobe até Suspenso no meio do caminho e desce de novo. O aliado que recebe ganha +8% nos
##        próximos 3 chutes dele.
##      - Hugo SUSPENSO com a bola próxima -> Fou: passe alto (QTE difícil) para um LOCAL escolhido.
##        Se ninguém interceptar a bola até ela chegar, cria uma marcação no chão: todo chute dado ali
##        ganha +10% de chance e força aumentada.
##      - Sem bola próxima -> Destination: vai até um inimigo e proíbe as habilidades dele por 2
##        rodadas (ou até o Hugo se afastar). Se o inimigo estiver SUSPENSO -> Collision: Hugo salta
##        até ele e disputa na sorte (70%); ganhando, derruba o inimigo e aplica o Destination.
## 3. Gears (recarga de 3 rodadas, compartilhada; a forma depende do lado do campo em que ele está):
##      - Lado aliado -> Mecanicien: vai até um inimigo e gruda nele; enquanto ficar grudado, o
##        inimigo perde 8% de chance de gol nos chutes.
##      - Meio-campo -> Brille: passe rasteiro longo para um aliado, que dá +1 ação de habilidade
##        aos Secundários.
##      - Lado inimigo -> Rêve: avança até a bola e, se alcançar, dá um chute forte que sobe até
##        Suspenso no meio da trajetória.
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Hugo".
##
## ÚNICA MUDANÇA EM OUTRO ARQUIVO: o Adequation proíbe inimigos de serem Protagonista, e quem
## escolhe o Protagonista é o match_manager.gd: sem o trecho de is_protagonist_blocked() no
## select_protagonist() o Adequation não tem efeito nenhum (veja a resposta). O resto usa só o
## que já existe nos outros arquivos.
##
## Visual: todas as engrenagens são douradas (GOLD) com borda dourada escura e furo vinho.

const SKILL_COORD: StringName = &"coordination"   # também é Adequation e Unsuitable
const SKILL_BEE: StringName = &"bee_blep_focus"   # também é Fou, Destination e Collision
const SKILL_GEARS: StringName = &"gears"          # Mecanicien / Brille / Rêve

## Grupos de recarga (as variantes de cada habilidade compartilham o mesmo)
const CD_COORD: StringName = &"cd_coord"
const CD_BEE: StringName = &"cd_bee"
const CD_GEARS: StringName = &"cd_gears"

const WINE: Color = Color(0.45, 0.07, 0.17)
const GOLD: Color = Color(1.0, 0.82, 0.3)
const GOLD_DARK: Color = Color(0.72, 0.5, 0.1)   # borda das engrenagens

enum CoordVariant { NONE, COORDINATION, ADEQUATION, UNSUITABLE }
## ENEMY = Destination (inimigo no chão) ou Collision (inimigo suspenso): quem decide é o alvo escolhido
enum BeeVariant { NONE, BEE_BLEP, FOU, ENEMY }
enum GearsForm { NONE, MECANICIEN, BRILLE, REVE }

## Dentes da engrenagem (desvios angulares, como fração do passo entre dentes)
const _TOOTH_OFFSETS := [-0.32, -0.16, 0.16, 0.32]

@export_group("Coordination / Adequation / Unsuitable")
@export var coord_cooldown: int = 2                       # igual para as 3 variantes
@export var hold_grab_time: float = 0.15                  # tempo que a bola leva até ele (Coordination)
@export var adequation_range: float = 600.0
@export var adequation_targets: int = 2                   # quantos inimigos ele escolhe
@export var adequation_turns: int = 2                     # quantos turnos do time inimigo dura
@export_range(0.1, 1.0) var adequation_run_mult: float = 0.6   # velocidade do Correr dos alvos
@export var unsuitable_leap_time: float = 0.3
@export var unsuitable_power: float = 650.0               # velocidade da bola refletida (px/s)
@export var unsuitable_lift_rise: float = 20.0            # o quanto a bola sobe a mais no deflect
@export var unsuitable_min_incoming_speed: float = 30.0   # abaixo disso a bola é considerada parada

@export_group("Bee-Blep! Focus / Fou / Destination / Collision")
@export var bee_cooldown: int = 2                         # igual para as 4 variantes
@export var bee_range: float = 580.0
@export_range(0.0, 1.0) var bee_bonus: float = 0.08       # +8% de chance de gol
@export var bee_bonus_shots: int = 3                      # nos próximos X chutes do aliado
@export var fou_range: float = 550.0
@export var fou_flight_time: float = 0.9                  # tempo até a bola subir a Voando
@export_range(0.0, 1.0) var fou_qte_fail_range_mult: float = 0.5   # alcance que sobra se errar o QTE
@export_range(0.0, 90.0) var fou_qte_fail_angle: float = 35.0      # desvio (graus) se errar o QTE
@export var fou_mark_radius: float = 90.0
@export var fou_mark_rounds: int = 2                      # quanto tempo a marcação dura (contando a rodada em que chega)
@export_range(0.0, 1.0) var fou_mark_chance_bonus: float = 0.10
@export var fou_mark_force_mult: float = 1.3
@export var destination_range: float = 400.0              # alcance do Destination / Collision
@export var destination_rounds: int = 2                   # duração da proibição de habilidades (contando a atual)
@export var destination_break_distance: float = 130.0     # o inimigo ficando mais longe que isso, solta
@export var destination_dash_time: float = 0.25
@export_range(0.0, 1.0) var collision_chance: float = 0.70

@export_group("Gears")
@export var gears_cooldown: int = 3                       # igual para as 3 formas
@export_range(0.0, 1.0) var midfield_band: float = 0.2    # largura do "meio-campo", como fração da metade do campo
@export var mecanicien_range: float = 450.0
@export_range(0.0, 1.0) var mecanicien_penalty: float = 0.08   # -8% na chance de gol dos chutes do inimigo grudado
@export var mecanicien_break_distance: float = 130.0      # a distância do inimigo passando disso, o efeito acaba
@export var brille_range: float = 520.0
@export var brille_extra_skills: int = 1                  # ações de habilidade extras para os Secundários
@export var reve_dash_distance: float = 300.0             # o quanto ele avança em direção à bola
@export var reve_dash_time: float = 0.3
@export var reve_power: float = 1300.0                    # velocidade do chute (px/s)
@export_range(0.0, 1.0) var reve_chance: float = 0.40     # chance de o chute vencer o goleiro

@export_group("Visual do chute")
## Aura + partículas dos passes/chutes de habilidade. Vazio = usa o estilo padrão do Hugo (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: coordination, bee_blep_focus, gears.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}

## Coordination: segurando a bola (até o fim do próximo turno do adversário)
var _hold_active: bool = false
var _hold_touches: int = 0

## Adequation: inimigo -> {"turns": turnos restantes, "speed": move_speed original}
var _bans: Dictionary = {}

## Bee-Blep! Focus: aliado -> quantos chutes ainda têm o bônus
var _focus_shots: Dictionary = {}

## Fou: passe alto a caminho de um ponto; a marcação nasce quando a bola chega sem ninguém tocar
var _fou_pending: bool = false
var _fou_landing: Vector2 = Vector2.ZERO
var _fou_touches: int = 0
var _mark: HugoMark = null
var _mark_seen_touches: int = 0
var _mark_boosted: bool = false

## Destination / Collision: inimigos com as habilidades travadas por mim
var _lock_targets: Array[Player] = []

## Mecanicien: inimigo em que ele está grudado (null = ninguém)
var _mec_target: Player = null


func _init() -> void:
	character_id = "hugo"   # o menu de formação usa isto para saber quem é quem
	display_name = "Hugo"


func _ready() -> void:
	super()
	# O Mecanicien reduz a chance de chute de um inimigo e o Adequation proíbe inimigos de serem
	# Protagonista: o Hugo entra no grupo dos efeitos de controle (ver shot_penalty_on e blocks_protagonist)
	add_to_group("control_sources")
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_hook_manager.call_deferred()


## Vinho, com "dentes" dourados girando
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.55, 0.08, 0.2)
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = GOLD
	fx.amount = 22
	fx.lifetime = 0.55
	fx.speed_min = 15.0
	fx.speed_max = 70.0
	fx.gravity = Vector2(0.0, -40.0)
	fx.spin = 320.0
	fx.scale_min = 0.15
	fx.scale_max = 0.32
	fx.burst_amount = 14
	fx.burst_speed = 210.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.turn_ended.connect(_on_turn_ended)
		m.round_started.connect(_on_round_started)
	var ball: Ball = _get_ball()
	if ball:
		ball.was_reset.connect(_on_ball_reset)


func _on_turn_ended(ended_team: int) -> void:
	# Coordination: sem interação, solta a bola no fim do turno do adversário
	if _hold_active and ended_team != team:
		_end_hold(true)
	# Adequation: cada turno do time proibido gasta um dos turnos da proibição
	for p: Variant in _bans.keys():
		if not is_instance_valid(p):
			_bans.erase(p)
			continue
		if (p as Player).team != ended_team:
			continue
		_bans[p]["turns"] = int(_bans[p]["turns"]) - 1
		if int(_bans[p]["turns"]) <= 0:
			_expire_ban(p as Player)


func _on_round_started(new_round: int) -> void:
	# A marcação do Fou some quando a duração acaba
	if _mark != null and new_round > _mark.until_round:
		_free_mark()
	queue_redraw()


func _on_ball_reset() -> void:
	_end_hold(false)   # gol / reposição: a bola já foi solta pelo próprio Ball
	_fou_pending = false


# ---------- UTIL ----------

func _get_field() -> Field:
	return get_tree().get_first_node_in_group("field") as Field


## Mantém uma posição (global) dentro do campo
func _clamp_to_pitch(global_p: Vector2) -> Vector2:
	var field: Field = _get_field()
	if field == null:
		return global_p
	var half: Vector2 = field.pitch_size * 0.5 - Vector2(20.0, 20.0)
	var l: Vector2 = field.to_local(global_p)
	l.x = clampf(l.x, -half.x, half.x)
	l.y = clampf(l.y, -half.y, half.y)
	return field.to_global(l)


## Vai (posição + altura) até um ponto, ficando no nível indicado
func _dash_to(dest: Vector2, target_height: float, level: Heights.Level, duration: float) -> void:
	height_level = level
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", _clamp_to_pitch(dest), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "height", target_height, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(duration).timeout


## "Bola próxima" = ao alcance de chute e livre para o time dele tocar
func _ball_is_near(ball: Ball) -> bool:
	if ball == null or ball.is_held() or ball.is_locked_for(team):
		return false
	return global_position.distance_to(ball.global_position) <= kick_range


func _enemies_in_range(range_px: float) -> Array[Player]:
	var list: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team != team and global_position.distance_to(p.global_position) <= range_px:
			list.append(p)
	return list


func _has_ally_in_range(range_px: float) -> bool:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p != self and p.team == team and global_position.distance_to(p.global_position) <= range_px:
			return true
	return false


## Um passo ao lado do alvo (do lado de onde o Hugo vem), para ele não ficar por cima
func _spot_next_to(target: Node2D, target_radius: float) -> Vector2:
	var dir: Vector2 = global_position - target.global_position
	dir = dir.normalized() if dir.length() > 1.0 else Vector2(-facing, 0.0)
	return target.global_position + dir * (body_radius + target_radius + 4.0)


## Passe/chute rasteiro: um inimigo NO MESMO nível da bola (e perto dela) intercepta
func _find_interceptor(m: MatchManager, ball: Ball) -> Player:
	var level: Heights.Level = ball.get_level()
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down or other.height_level != level:
			continue
		if other.global_position.distance_to(ball.global_position) <= m.ground_pass_intercept_radius:
			return other
	return null


# ---------- DERRUBADO ----------

func knock_down() -> void:
	super()
	_end_hold(true)
	_mec_target = null
	queue_redraw()


# ---------- HABILIDADE 1: COORDINATION / ADEQUATION / UNSUITABLE ----------

func get_coord_variant() -> CoordVariant:
	if is_down:
		return CoordVariant.NONE
	var ball: Ball = _get_ball()
	if _ball_is_near(ball):
		if ball.get_level() == Heights.Level.GROUND:
			return CoordVariant.COORDINATION if can_reach_level(Heights.Level.GROUND) \
				else CoordVariant.NONE
		# Bola suspensa ou voando: ele salta até ela (precisa estar no chão ou suspenso)
		return CoordVariant.UNSUITABLE if height_level != Heights.Level.FLYING \
			else CoordVariant.NONE
	# Sem bola próxima
	if not _enemies_in_range(adequation_range).is_empty():
		return CoordVariant.ADEQUATION
	return CoordVariant.NONE


func _coord_skill_name() -> String:
	if _hold_active:
		return "Coordination (segurando)"
	match get_coord_variant():
		CoordVariant.ADEQUATION:
			return "Adequation"
		CoordVariant.UNSUITABLE:
			return "Unsuitable"
	return "Coordination"


func _use_coord_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_coord_variant():
		CoordVariant.COORDINATION:
			return await _use_coordination(m)
		CoordVariant.ADEQUATION:
			return await _use_adequation(m)
		CoordVariant.UNSUITABLE:
			return await _use_unsuitable(m)
	return false


# --- Coordination ---

func _hold_point(ball: Ball) -> Vector2:
	return global_position + Vector2(facing, 0.0) * (body_radius + ball.collision_radius + 2.0)


func _use_coordination(m: MatchManager) -> bool:
	face_towards(_get_ball().global_position - global_position)
	if not await play_action(&"coordination"):
		return false   # ação cancelada (ex: a partida reiniciou)

	var ball: Ball = _get_ball()
	if get_coord_variant() != CoordVariant.COORDINATION:   # a bola pode ter saído do alcance
		return false

	m.clear_pending_pass()   # passe alto em andamento: a bola agora é do Hugo
	ball.register_touch(self)
	ball.hover_to(_hold_point(ball), height, hold_grab_time)
	await get_tree().create_timer(hold_grab_time).timeout

	_hold_touches = ball.interaction_count   # qualquer toque depois disto solta a bola
	ball.spell_owner = self                  # adversários não conseguem tocar na bola enquanto ela está com ele
	_hold_active = true

	# Ações extras (valem já neste turno)
	if m.protagonist == self:
		m.secondary_general_left += 1
		m.secondary_skill_left += 1
	else:
		m.protagonist_skill_left += 1
		extra_general_left += 1

	start_cooldown(CD_COORD, coord_cooldown)
	queue_redraw()
	return true


## Enquanto segura a bola ela acompanha o Hugo; se alguém tocar nela (ou ela for solta por
## outro meio) o efeito acaba. Os outros efeitos do Hugo também são acompanhados aqui.
func _physics_process(delta: float) -> void:
	super(delta)
	_update_hold()
	_update_links()
	_update_fou()
	_update_mark_effect()


func _update_hold() -> void:
	if not _hold_active:
		return
	var ball: Ball = _get_ball()
	if ball == null:
		_end_hold(false)
		return
	if ball.interaction_count != _hold_touches or not ball.hovering \
			or ball.spell_owner != self or ball.is_held():
		_end_hold(false)
		return
	if is_down:   # derrubado: perde a bola
		_end_hold(true)
		return
	ball.global_position = _hold_point(ball)
	ball.height = height   # a bola acompanha a altura dele


## release = true solta a bola (cai e rola); false = a bola já foi tocada/solta por outro
func _end_hold(release: bool) -> void:
	if not _hold_active:
		return
	_hold_active = false
	var ball: Ball = _get_ball()
	if release and ball != null and ball.spell_owner == self and ball.hovering and not ball.is_held():
		ball.release_hover()
	queue_redraw()


# --- Adequation ---

func _use_adequation(m: MatchManager) -> bool:
	var candidates: Array[Player] = _enemies_in_range(adequation_range)
	var wanted: int = mini(adequation_targets, candidates.size())
	var picks: Array[Player] = []
	# Quem já foi escolhido não aparece de novo como alvo válido
	var not_picked: Callable = func(p: Player) -> bool: return not picks.has(p)
	for i in wanted:
		var target: Player = await m.pick_ally_for_skill(self, adequation_range, true, not_picked)
		if target == null:
			return false   # cancelou: não gasta a ação
		picks.append(target)
	if get_coord_variant() != CoordVariant.ADEQUATION:   # a bola pode ter chegado perto enquanto ele escolhia
		return false

	if not await play_action(&"adequation"):
		return false
	for target: Player in picks:
		_apply_ban(target)
	start_cooldown(CD_COORD, coord_cooldown)
	queue_redraw()
	return true


## Proíbe de ser Protagonista e deixa o Correr mais lento pelos próximos turnos do time dele
func _apply_ban(target: Player) -> void:
	var original_speed: float = target.move_speed
	if _bans.has(target):
		original_speed = float(_bans[target]["speed"])   # renovar não acumula a lentidão
	_bans[target] = {"turns": adequation_turns, "speed": original_speed}
	target.move_speed = original_speed * adequation_run_mult


func _expire_ban(target: Player) -> void:
	if not _bans.has(target):
		return
	if is_instance_valid(target):
		target.move_speed = float(_bans[target]["speed"])
	_bans.erase(target)


## Chamado pelo MatchManager (ver select_protagonist): este jogador está proibido de ser Protagonista?
## Se TODOS os jogadores do time dele estiverem proibidos, a regra não vale (o time precisa de um Protagonista).
func blocks_protagonist(p: Player) -> bool:
	if not _bans.has(p):
		return false
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	for other: Player in m.get_team_players(p.team):
		if not _bans.has(other):
			return true   # ainda existe alguém que pode ser o Protagonista
	return false


# --- Unsuitable ---

## Direção "contrária" quando a bola está parada: para longe do gol que o time dele defende
func _clear_direction(ball: Ball) -> Vector2:
	var field: Field = _get_field()
	if field != null:
		var away: Vector2 = ball.global_position - field.get_defend_goal_center(team)
		if away.length() > 1.0:
			return away.normalized()
	return Vector2(_default_facing(), 0.0)


func _use_unsuitable(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	m.clear_pending_pass()   # se a bola era um passe alto em andamento, o passe deixa de valer
	# Direção do deflect: contrária à da bola; se ela está parada (pairando), para longe do gol dele
	var incoming: Vector2 = ball.velocity
	var dir: Vector2 = -incoming.normalized() if incoming.length() > unsuitable_min_incoming_speed \
		else _clear_direction(ball)
	face_towards(dir)

	# A bola "espera" no ar enquanto ele salta até ela
	ball.hovering = true
	var level: Heights.Level = ball.get_level()
	var gap: float = body_radius + ball.collision_radius + 2.0
	await _dash_to(ball.global_position - dir * gap, Heights.to_height(level), level, unsuitable_leap_time)

	if not await play_action(&"unsuitable", ANIM_VOLLEY):
		if ball.hovering and not ball.is_held():
			ball.release_hover()
		return false

	var rise: float = Heights.lift_for_peak(unsuitable_lift_rise, ball.gravity)
	ball.kick(dir, unsuitable_power, rise, self, Ball.NO_SHOT)   # deflect não é tentativa de gol
	ball.play_fx(kick_fx)
	start_cooldown(CD_COORD, coord_cooldown)
	await get_tree().create_timer(0.15).timeout
	return true


# ---------- HABILIDADE 2: BEE-BLEP! FOCUS / FOU / DESTINATION / COLLISION ----------

func get_bee_variant() -> BeeVariant:
	if is_down:
		return BeeVariant.NONE
	var ball: Ball = _get_ball()
	if _ball_is_near(ball):
		if get_kick_type(ball) == KickType.NONE:
			return BeeVariant.NONE
		if height_level == Heights.Level.SUSPENDED:
			return BeeVariant.FOU
		if height_level == Heights.Level.GROUND and ball.get_level() != Heights.Level.FLYING:
			return BeeVariant.BEE_BLEP
		return BeeVariant.NONE
	# Sem bola próxima: Destination / Collision
	if not _enemies_in_range(destination_range).is_empty():
		return BeeVariant.ENEMY
	return BeeVariant.NONE


## Destination (inimigo no chão) e Collision (inimigo suspenso) dividem o botão
func _enemy_skill_name() -> String:
	var has_ground: bool = false
	var has_air: bool = false
	for p: Player in _enemies_in_range(destination_range):
		if p.height_level == Heights.Level.GROUND:
			has_ground = true
		else:
			has_air = true
	if has_air and has_ground:
		return "Destination / Collision"
	return "Collision" if has_air else "Destination"


func _bee_skill_name() -> String:
	match get_bee_variant():
		BeeVariant.FOU:
			return "Fou"
		BeeVariant.ENEMY:
			return _enemy_skill_name()
	return "Bee-Blep! Focus"


func _use_bee_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_bee_variant():
		BeeVariant.BEE_BLEP:
			return await _use_bee_blep(m)
		BeeVariant.FOU:
			return await _use_fou(m)
		BeeVariant.ENEMY:
			return await _use_enemy_skill(m)
	return false


# --- Bee-Blep! Focus ---

func _use_bee_blep(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var target: Player = await m.pick_ally_for_skill(self, bee_range)
	if target == null:
		return false   # cancelou: não gasta a ação
	# A bola pode ter mudado de lugar enquanto ele escolhia o alvo
	if get_bee_variant() != BeeVariant.BEE_BLEP:
		return false

	var result: int = await _run_bee_pass(m, ball, target)
	if result == 0:
		return false
	if result == 1:   # chegou no aliado: ele ganha o bônus nos próximos chutes
		_focus_shots[target] = bee_bonus_shots
	start_cooldown(CD_BEE, bee_cooldown)
	return true


## Passe rasteiro longo que sobe até Suspenso no meio do caminho e desce de novo (uma engrenagem
## dourada acompanha a bola). Devolve 0 = não saiu, 1 = chegou no aliado, 2 = foi interceptado.
## Mesmas regras do passe rasteiro do MatchManager, mas a bola muda de nível pelo caminho: um inimigo
## só intercepta quando está no mesmo nível dela (quem pulou pega a bola quando ela está suspensa).
func _run_bee_pass(m: MatchManager, ball: Ball, target: Player) -> int:
	face_towards(target.global_position - global_position)
	if not await play_action(&"bee_blep_focus", ANIM_PASS):
		return 0   # ação cancelada (ex: a partida reiniciou)

	var start: Vector2 = ball.global_position
	var to_target: Vector2 = target.global_position - start
	var dist: float = to_target.length()
	var total: float = dist - (ball.collision_radius + target.body_radius + 2.0)   # a bola para ENCOSTANDO no alvo
	if total < 1.0:
		return 0
	var dir: Vector2 = to_target / dist

	# kick_ground registra o toque; depois a bola fica pairando e eu conduzo posição e altura
	ball.kick_ground(dir, m.ground_pass_speed, self, Ball.NO_SHOT)   # passe não é chute
	ball.hovering = true
	ball.velocity = Vector2.ZERO
	ball.trail_enabled = true
	ball.fx_during_hover = true   # a aura continua mesmo com a bola pairando
	ball.play_fx(kick_fx)
	var gear: HugoGear = _spawn_gear(ball)

	var travelled: float = 0.0
	var slow_zone: float = minf(total * 0.4, 160.0)   # reta final: a bola vai "amortecendo"
	var time_left: float = total / m.ground_pass_speed * 2.5 + 1.0   # trava de segurança
	var result: int = 1
	while time_left > 0.0:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		time_left -= delta

		if not ball.hovering or ball.is_held():   # alguém pegou a bola ou ela foi reposta
			result = 0
			break
		if _find_interceptor(m, ball) != null:
			result = 2
			break
		var remaining: float = total - travelled
		if remaining <= 2.0:
			break
		var speed: float = m.ground_pass_speed * clampf(remaining / slow_zone, 0.15, 1.0)
		travelled = minf(travelled + speed * delta, total)
		ball.global_position = start + dir * travelled
		# Sobe até Suspenso no meio e desce de novo
		ball.height = Heights.SUSPENDED_HEIGHT * sin(PI * travelled / total)

	ball.fx_during_hover = false
	ball.trail_enabled = false
	if gear != null:
		gear.finish()
	if result == 0:
		return 0   # a bola já não é minha para mexer
	if result == 1:
		ball.global_position = start + dir * total
		ball.height = 0.0
	# Interceptada: solta onde está (cai e quica); entregue: já está no chão
	ball.release_hover()
	ball.velocity = Vector2.ZERO
	if result == 1:
		m.pass_completed.emit(self, target)
	return result


func _spawn_gear(ball: Ball) -> HugoGear:
	var parent: Node = ball.get_parent()
	if parent == null:
		return null
	var gear := HugoGear.new()
	gear.target = ball
	parent.add_child(gear)
	return gear


# --- Fou ---

func _use_fou(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var landing: Vector2 = await m.pick_point_for_skill(self, fou_range)
	if landing == Vector2.INF:
		return false   # cancelou: não gasta a ação
	# A bola pode ter rolado (ou ele pousou) enquanto escolhia o local: confere de novo
	if get_bee_variant() != BeeVariant.FOU:
		return false

	var dir: Vector2 = landing - global_position
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(_default_facing(), 0.0)
	face_towards(dir)
	if not await play_action(&"fou", ANIM_PASS_HIGH):
		return false   # ação cancelada (ex: a partida reiniciou)

	# QTE difícil. Errou: o local sai mais perto e um pouco torto
	var qte_ok: bool = true
	if not skips_qte():
		qte_ok = await m.run_qte(KickType.FLYING)
	if not qte_ok:
		var bad_dir: Vector2 = dir.rotated(deg_to_rad(randf_range(-fou_qte_fail_angle, fou_qte_fail_angle)))
		landing = global_position + bad_dir * (global_position.distance_to(landing) * fou_qte_fail_range_mult)

	# Mesmo fluxo do Passe Alto de ponto (Rabona Cross do Charles): sobe a Voando no meio do
	# caminho e, quando o turno do time volta, desce ao local no nível Suspenso
	ball.register_touch(self)   # o passe alto não usa kick(), então registra o toque aqui
	ball.fx_during_hover = true
	ball.play_fx(kick_fx)
	var midpoint: Vector2 = (ball.global_position + landing) * 0.5
	var tween: Tween = ball.hover_to(midpoint, Heights.FLYING_HEIGHT, fou_flight_time)
	await tween.finished
	ball.fx_during_hover = false
	m.begin_point_pass(team, landing)

	# A marcação só nasce se a bola CHEGAR sem ninguém tocar nela (ver _update_fou)
	_fou_pending = true
	_fou_landing = landing
	_fou_touches = ball.interaction_count
	start_cooldown(CD_BEE, bee_cooldown)
	return true


## Fou em andamento: quando a bola chega ao local (nível Suspenso) e ninguém interagiu, cria a marcação
func _update_fou() -> void:
	if not _fou_pending:
		return
	var ball: Ball = _get_ball()
	if ball == null or ball.interaction_count != _fou_touches or not ball.hovering or ball.is_held():
		_fou_pending = false   # interceptada (ou solta antes de chegar): sem marcação
		return
	if absf(ball.height - Heights.SUSPENDED_HEIGHT) < 2.0 \
			and ball.global_position.distance_to(_fou_landing) < 10.0:
		_fou_pending = false
		_spawn_mark(_fou_landing)


func _spawn_mark(point: Vector2) -> void:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or ball.get_parent() == null:
		return
	_free_mark()   # só existe uma marcação por vez
	_mark = HugoMark.new()
	_mark.radius = fou_mark_radius
	_mark.until_round = m.round_number + fou_mark_rounds - 1   # a rodada em que chega conta
	ball.get_parent().add_child(_mark)
	_mark.global_position = point
	_mark_seen_touches = ball.interaction_count
	_mark_boosted = false


func _free_mark() -> void:
	if _mark != null and is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null


## Qualquer chute dado com a bola em cima da marcação (de qualquer time) ganha +chance de gol e
## força. Acompanha o contador de toques da bola: se o toque foi um chute (a bola saiu com uma
## chance de gol pendente), mexe na chance e na velocidade UMA vez por chute.
func _update_mark_effect() -> void:
	if _mark == null:
		return
	var ball: Ball = _get_ball()
	if ball == null:
		return
	if not ball.has_pending_shot():
		_mark_boosted = false   # o chute anterior acabou: o próximo pode ser reforçado
	if ball.interaction_count == _mark_seen_touches:
		return
	_mark_seen_touches = ball.interaction_count
	if _mark_boosted or not ball.has_pending_shot():
		return
	if ball.global_position.distance_to(_mark.global_position) > _mark.radius:
		return
	_mark_boosted = true
	ball.pending_shot_chance = minf(1.0, ball.pending_shot_chance + fou_mark_chance_bonus)
	ball.velocity *= fou_mark_force_mult


# --- Destination / Collision ---

func _use_enemy_skill(m: MatchManager) -> bool:
	var target: Player = await m.pick_ally_for_skill(self, destination_range, true)
	if target == null:
		return false   # cancelou: não gasta a ação
	# A bola pode ter chegado perto enquanto ele escolhia o alvo
	if get_bee_variant() != BeeVariant.ENEMY:
		return false

	var is_collision: bool = target.height_level != Heights.Level.GROUND
	face_towards(target.global_position - global_position)
	if not await play_action(&"collision" if is_collision else &"destination"):
		return false

	var level: Heights.Level = target.height_level if is_collision else height_level
	await _dash_to(_spot_next_to(target, target.body_radius), Heights.to_height(level), level,
		destination_dash_time)

	if is_collision:
		# Confronto de sorte: ganhando, o inimigo cai e recebe o efeito do Destination
		if randf() < collision_chance:
			target.knock_down()
			_lock_enemy(target)
	else:
		_lock_enemy(target)
	start_cooldown(CD_BEE, bee_cooldown)
	queue_redraw()
	return true


## Proíbe as habilidades do inimigo por destination_rounds rodadas, ou até o Hugo se afastar dele
func _lock_enemy(target: Player) -> void:
	target.apply_lock(self, destination_rounds, true)
	if not _lock_targets.has(target):
		_lock_targets.append(target)


## Acompanha as travas do Destination e o Mecanicien: soltam se o Hugo se afastar
func _update_links() -> void:
	for i in range(_lock_targets.size() - 1, -1, -1):
		var t: Player = _lock_targets[i]
		if not is_instance_valid(t) or t.locked_by != self:   # a trava já acabou por tempo
			_lock_targets.remove_at(i)
		elif global_position.distance_to(t.global_position) > destination_break_distance:
			t.clear_lock()
			_lock_targets.remove_at(i)
	if _mec_target != null:
		if not is_instance_valid(_mec_target) or is_down \
				or global_position.distance_to(_mec_target.global_position) > mecanicien_break_distance:
			_mec_target = null
			queue_redraw()


# --- Bônus do Bee-Blep! Focus ---

## Chamado pelo get_team_shot_bonus() do player.gd cada vez que um COMPANHEIRO dá um chute. O aliado
## que recebeu o Bee-Blep! Focus ganha o bônus nos próximos bee_bonus_shots chutes (um é gasto a cada chamada).
func shot_bonus_for_ally(shooter: Player, _ball: Ball) -> float:
	var left: int = int(_focus_shots.get(shooter, 0))
	if left <= 0:
		return 0.0
	if left == 1:
		_focus_shots.erase(shooter)
	else:
		_focus_shots[shooter] = left - 1
	return bee_bonus


# ---------- HABILIDADE 3: GEARS (MECANICIEN / BRILLE / RÊVE) ----------

## A forma depende do lado do campo em que o Hugo está
func get_gears_form() -> GearsForm:
	var field: Field = _get_field()
	if field == null:
		return GearsForm.NONE
	var attack_dir: float = 1.0 if team == 0 else -1.0   # o time 0 ataca para a direita
	var x: float = field.to_local(global_position).x * attack_dir   # positivo = lado inimigo
	if absf(x) <= field.pitch_size.x * 0.5 * midfield_band:
		return GearsForm.BRILLE
	return GearsForm.REVE if x > 0.0 else GearsForm.MECANICIEN


func _gears_skill_name() -> String:
	match get_gears_form():
		GearsForm.MECANICIEN:
			return "Mecanicien"
		GearsForm.BRILLE:
			return "Brille"
		GearsForm.REVE:
			return "Rêve"
	return "Gears"


func _reve_possible() -> bool:
	var ball: Ball = _get_ball()
	if ball == null or is_down or ball.is_held() or ball.is_locked_for(team):
		return false
	if height_level == Heights.Level.FLYING or not can_reach_level(ball.get_level()):
		return false
	return global_position.distance_to(ball.global_position) <= reve_dash_distance


func _gears_usable() -> bool:
	match get_gears_form():
		GearsForm.MECANICIEN:
			return not _enemies_in_range(mecanicien_range).is_empty()
		GearsForm.BRILLE:
			return get_kick_type(_get_ball()) != KickType.NONE and _has_ally_in_range(brille_range)
		GearsForm.REVE:
			return _reve_possible()
	return false


func _use_gears_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_gears_form():
		GearsForm.MECANICIEN:
			return await _use_mecanicien(m)
		GearsForm.BRILLE:
			return await _use_brille(m)
		GearsForm.REVE:
			return await _use_reve(m)
	return false


## Mecanicien: vai até um inimigo e gruda nele. Enquanto o Hugo ficar perto (mecanicien_break_distance),
## os chutes desse inimigo perdem mecanicien_penalty de chance de gol (ver shot_penalty_on).
func _use_mecanicien(m: MatchManager) -> bool:
	var target: Player = await m.pick_ally_for_skill(self, mecanicien_range, true)
	if target == null:
		return false   # cancelou: não gasta a ação
	if get_gears_form() != GearsForm.MECANICIEN:
		return false
	face_towards(target.global_position - global_position)
	if not await play_action(&"mecanicien"):
		return false
	await _dash_to(_spot_next_to(target, target.body_radius), height, height_level, destination_dash_time)
	_mec_target = target
	start_cooldown(CD_GEARS, gears_cooldown)
	queue_redraw()
	return true


## Chamado pelo Player.get_opponent_shot_penalty(): quanto o Hugo tira da chance de gol do chute de um adversário
func shot_penalty_on(shooter: Player) -> float:
	if is_down or _mec_target == null or shooter != _mec_target:
		return 0.0
	if global_position.distance_to(shooter.global_position) > mecanicien_break_distance:
		return 0.0
	return mecanicien_penalty


## Brille: passe rasteiro longo (reta) para um aliado; dá mais uma ação de habilidade aos Secundários
func _use_brille(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var target: Player = await m.pick_ally_for_skill(self, brille_range)
	if target == null:
		return false   # cancelou: não gasta a ação
	if get_gears_form() != GearsForm.BRILLE or get_kick_type(ball) == KickType.NONE:
		return false
	# curve_ratio 0 = reta: é o passe rasteiro normal, só que com a aura do Hugo e animação própria
	await m.run_curved_ground_pass(self, target, ball, 0.0, 1.0, &"brille", kick_fx)
	m.secondary_skill_left += brille_extra_skills
	start_cooldown(CD_GEARS, gears_cooldown)
	queue_redraw()
	return true


## Rêve: mira, avança até a bola e, se alcançar, dá um chute forte que sobe até Suspenso
func _use_reve(m: MatchManager) -> bool:
	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação
	if get_gears_form() != GearsForm.REVE or not _reve_possible():
		return false

	var ball: Ball = _get_ball()
	face_towards(aim)
	# Avança até ficar "atrás" da bola (do lado oposto ao da mira), no máximo reve_dash_distance
	var gap: float = body_radius + ball.collision_radius + 2.0
	var spot: Vector2 = ball.global_position - aim * gap
	var step: Vector2 = spot - global_position
	if step.length() > reve_dash_distance:
		spot = global_position + step.normalized() * reve_dash_distance
	await _dash_to(spot, height, height_level, reve_dash_time)

	# Alcançou a bola?
	if not _ball_is_near(ball):
		start_cooldown(CD_GEARS, gears_cooldown)   # avançou e não chegou: a habilidade foi gasta
		return true
	if not await play_action(&"reve", ANIM_KICK):
		return false

	# Tentativa de gol: mesma conta do kick_ball (bônus e penalidades de habilidades de outros jogadores)
	var chance: float = clampf(reve_chance + take_next_shot_bonus() + get_team_shot_bonus(ball) \
		- get_shot_debuff() - get_opponent_shot_penalty(), 0.0, 1.0)
	# Sobe até o pico do nível Suspenso (se a bola já está mais alta, só cai)
	var rise: float = maxf(0.0, Heights.SUSPENDED_HEIGHT - ball.height)
	ball.kick(aim, reve_power, Heights.lift_for_peak(rise, ball.gravity), self, chance)
	ball.play_fx(kick_fx)
	start_cooldown(CD_GEARS, gears_cooldown)
	await get_tree().create_timer(0.15).timeout
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_COORD, "name": skill_label(_coord_skill_name(), CD_COORD)})
	list.append({"id": SKILL_BEE, "name": skill_label(_bee_skill_name(), CD_BEE)})
	list.append({"id": SKILL_GEARS, "name": skill_label(_gears_skill_name(), CD_GEARS)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_COORD:
			# sem reusar enquanto ainda segura a bola
			return not is_on_cooldown(CD_COORD) and not _hold_active \
				and get_coord_variant() != CoordVariant.NONE
		SKILL_BEE:
			return not is_on_cooldown(CD_BEE) and get_bee_variant() != BeeVariant.NONE
		SKILL_GEARS:
			return not is_on_cooldown(CD_GEARS) and _gears_usable()
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_COORD:
			return await _use_coord_skill()
		SKILL_BEE:
			return await _use_bee_skill()
		SKILL_GEARS:
			return await _use_gears_skill()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_COORD:
			var coord_text: String = "Coordination (bola próxima e no chão): Hugo segura a bola até o fim do próximo turno do adversário. Se ele é o Protagonista: +1 ação geral e +1 de habilidade para os Secundários. Se é Secundário: +1 de habilidade para o Protagonista e +1 ação geral só dele."
			var adeq_text: String = "Adequation (sem bola próxima): escolhe até %d inimigos a até %d px. Eles ficam proibidos de ser Protagonista e com o Correr %d%% mais lento pelos próximos %d turnos do time deles. Se todo o time estiver proibido, a regra não vale." % [
				adequation_targets, int(adequation_range), _pct(1.0 - adequation_run_mult), adequation_turns]
			var unsuit_text: String = "Unsuitable (bola próxima, suspensa ou voando; Hugo no chão ou suspenso): salta até a bola e dá um deflect, refletindo-a para a direção contrária (parada, ela vai para longe do gol dele). Não é tentativa de gol."
			match get_coord_variant():
				CoordVariant.COORDINATION:
					title = "Coordination"
					text = coord_text
				CoordVariant.ADEQUATION:
					title = "Adequation"
					text = adeq_text
				CoordVariant.UNSUITABLE:
					title = "Unsuitable"
					text = unsuit_text
				_:
					title = "Coordination / Adequation / Unsuitable"
					text = coord_text + "\n" + adeq_text + "\n" + unsuit_text
			text += "\nRecarga: %d rodadas, compartilhada entre as três." % coord_cooldown
		SKILL_BEE:
			var bee_text: String = "Bee-Blep! Focus (Hugo no chão, bola próxima no chão ou suspensa): passe rasteiro longo (até %d px) que sobe até Suspenso no meio do caminho e desce de novo. O aliado que receber ganha +%d%% nos próximos %d chutes dele." % [
				int(bee_range), _pct(bee_bonus), bee_bonus_shots]
			var fou_text: String = "Fou (Hugo suspenso, bola próxima): passe alto (QTE difícil) para um local à sua escolha (até %d px). Se ninguém interceptar e a bola chegar, cria uma marcação no chão por %d rodadas: qualquer chute dado ali ganha +%d%% de chance e força aumentada." % [
				int(fou_range), fou_mark_rounds, _pct(fou_mark_chance_bonus)]
			var dest_text: String = "Destination (sem bola próxima): vai até um inimigo (até %d px) e proíbe as habilidades dele por %d rodadas, ou até o Hugo se afastar." % [
				int(destination_range), destination_rounds]
			var coll_text: String = "Collision (sem bola próxima, inimigo suspenso): salta até ele e disputa na sorte (%d%%). Ganhando, o inimigo é derrubado e recebe o efeito do Destination." % _pct(collision_chance)
			match get_bee_variant():
				BeeVariant.BEE_BLEP:
					title = "Bee-Blep! Focus"
					text = bee_text
				BeeVariant.FOU:
					title = "Fou"
					text = fou_text
				BeeVariant.ENEMY:
					title = _enemy_skill_name()
					text = dest_text + "\n" + coll_text
				_:
					title = "Bee-Blep! Focus / Fou / Destination / Collision"
					text = bee_text + "\n" + fou_text + "\n" + dest_text + "\n" + coll_text
			text += "\nRecarga: %d rodadas, compartilhada entre as quatro." % bee_cooldown
		SKILL_GEARS:
			var mec_text: String = "Mecanicien (lado do campo aliado): vai até um inimigo (até %d px) e gruda nele. Enquanto o Hugo ficar a menos de %d px, os chutes desse inimigo perdem %d%% de chance de gol." % [
				int(mecanicien_range), int(mecanicien_break_distance), _pct(mecanicien_penalty)]
			var bri_text: String = "Brille (meio-campo): passe rasteiro longo (até %d px) para um aliado, que dá +%d ação de habilidade aos Secundários." % [
				int(brille_range), brille_extra_skills]
			var reve_text: String = "Rêve (lado do campo inimigo): avança até a bola (até %d px) e, se alcançar, dá um chute forte (%d%% de chance de gol) que sobe até Suspenso no meio da trajetória." % [
				int(reve_dash_distance), _pct(reve_chance)]
			match get_gears_form():
				GearsForm.MECANICIEN:
					title = "Mecanicien"
					text = mec_text
				GearsForm.BRILLE:
					title = "Brille"
					text = bri_text
				GearsForm.REVE:
					title = "Rêve"
					text = reve_text
				_:
					title = "Gears"
					text = mec_text + "\n" + bri_text + "\n" + reve_text
			text += "\nRecarga: %d rodadas, compartilhada entre as três." % gears_cooldown
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_end_hold(true)
	for p: Variant in _bans.keys():
		_expire_ban(p as Player)
	_bans.clear()
	_focus_shots.clear()
	for t: Player in _lock_targets:
		if is_instance_valid(t) and t.locked_by == self:
			t.clear_lock()
	_lock_targets.clear()
	_mec_target = null
	_fou_pending = false
	_free_mark()
	queue_redraw()


func _exit_tree() -> void:
	_free_mark()


# ---------- LOOP / VISUAL ----------

## Engrenagem dourada: polígono com dentes e um furo no meio. ci = quem desenha (precisa ser
## chamada de dentro de um _draw); rot em radianos.
static func draw_gear(ci: CanvasItem, c: Vector2, r: float, teeth: int, rot: float,
		col: Color, hole: Color) -> void:
	var pts := PackedVector2Array()
	var step: float = TAU / float(teeth)
	for i in teeth:
		var a: float = rot + float(i) * step
		for k in 4:
			var ang: float = a + _TOOTH_OFFSETS[k] * step
			var rad: float = r * 0.78 if (k == 0 or k == 3) else r
			pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	ci.draw_colored_polygon(pts, col)
	var rim: PackedVector2Array = pts.duplicate()
	rim.append(pts[0])   # fecha o contorno
	ci.draw_polyline(rim, Color(GOLD_DARK, col.a), maxf(1.0, r * 0.12))
	ci.draw_circle(c, r * 0.32, hole)
	ci.draw_arc(c, r * 0.32, 0.0, TAU, 16, Color(GOLD_DARK, col.a), 1.0)


func _has_visual_state() -> bool:
	return _hold_active or _mec_target != null or not _lock_targets.is_empty() \
		or not _focus_shots.is_empty() or not _bans.is_empty()


## Com algum efeito ativo o desenho gira (engrenagens), então precisa atualizar toda hora
func _process(delta: float) -> void:
	super(delta)
	if _has_visual_state():
		queue_redraw()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)
	var t: float = Time.get_ticks_msec() / 1000.0

	# Anel vinho + engrenagem dourada girando enquanto segura a bola (Coordination)
	if _hold_active:
		draw_arc(center, placeholder_radius + 6.0, 0.0, TAU, 40, Color(GOLD, 0.9), 3.0)
		draw_arc(center, placeholder_radius + 10.0, 0.0, TAU, 40, Color(WINE, 0.7), 2.0)
		draw_gear(self, center + Vector2(0.0, -placeholder_radius - 16.0), 7.0, 8, t * 2.0,
			GOLD, Color(WINE, 0.9))

	# Ligação dourada até quem está sob o efeito dele (Destination/Collision e Mecanicien)
	var linked: Array[Player] = []
	linked.append_array(_lock_targets)
	if _mec_target != null and not linked.has(_mec_target):
		linked.append(_mec_target)
	for e: Player in linked:
		if is_instance_valid(e):
			var end: Vector2 = to_local(e.global_position) + Vector2(0.0, -e.height)
			draw_line(center, end, Color(GOLD, 0.7), 2.0)
			draw_gear(self, end, 8.0, 8, -t * 2.0, Color(GOLD, 0.9), Color(WINE, 0.9))

	# Engrenagenzinha dourada em cima de quem tem o bônus do Bee-Blep! Focus
	for ally: Variant in _focus_shots.keys():
		if is_instance_valid(ally):
			var a: Player = ally as Player
			var p: Vector2 = to_local(a.global_position) + Vector2(0.0, -a.height - placeholder_radius - 30.0)
			draw_gear(self, p, 6.0, 8, t * 3.0, GOLD, Color(WINE, 0.9))

	# Inimigos proibidos de ser Protagonista / Correr lento (Adequation): engrenagem vinho parada
	for e: Variant in _bans.keys():
		if is_instance_valid(e):
			var en: Player = e as Player
			var p2: Vector2 = to_local(en.global_position) + Vector2(0.0, -en.height - placeholder_radius - 30.0)
			draw_gear(self, p2, 7.0, 8, -t * 1.5, GOLD, Color(WINE, 0.95))   # dourada, girando devagar


# ---------- ENGRENAGENS (nós visuais) ----------

## A engrenagem dourada do Bee-Blep! Focus: acompanha a bola durante o passe e some no fim
class HugoGear extends Node2D:
	var target: Ball = null
	var radius: float = 24.0
	var spin: float = 0.0
	var fading: bool = false
	var _alpha: float = 1.0

	func finish() -> void:
		fading = true

	func _process(delta: float) -> void:
		spin += delta * 5.0
		if fading:
			_alpha -= delta * 2.5
			if _alpha <= 0.0:
				queue_free()
				return
		if is_instance_valid(target):
			global_position = target.global_position + Vector2(0.0, -target.height - target.ball_radius)
			z_index = int(target.global_position.y) + 1
		queue_redraw()

	func _draw() -> void:
		Hugo.draw_gear(self, Vector2.ZERO, radius, 10, spin, Color(Hugo.GOLD, _alpha),
			Color(Hugo.WINE, _alpha))


## A marcação do Fou no chão: uma engrenagem dourada achatada (como se estivesse deitada no campo)
class HugoMark extends Node2D:
	var radius: float = 90.0
	var until_round: int = 0
	var spin: float = 0.0

	func _ready() -> void:
		z_as_relative = false
		z_index = -4000   # acima da grama (campo = -4096), abaixo de jogadores e bola

	func _process(delta: float) -> void:
		spin += delta * 0.6
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, radius, Color(Hugo.WINE, 0.28))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(Hugo.GOLD, 0.9), 3.0)
		Hugo.draw_gear(self, Vector2.ZERO, radius * 0.72, 10, spin, Color(Hugo.GOLD, 0.75),
			Color(Hugo.WINE, 0.7))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
