class_name Charles
extends Player
## Charles. Mais um personagem do time (depois de Isagi e Rin), com 3 habilidades:
##
## 1. Rabona Cross / Sky-Arc Pass (ação de habilidade, com 2 variantes automáticas pelo
##      estado da bola; recarga de 3 rodadas, compartilhada entre as variantes):
##      - Charles no chão + bola no chão -> Rabona Cross: passe alto (alcance 500) para um
##          LOCAL clicado no campo (não um aliado). A bola sobe até o nível Voando, no
##          meio do caminho, e PAIRA no local escolhido, no nível Suspenso — exatamente
##          como o Passe Alto comum, só que o "alvo" é um ponto. Se ninguém tocar nela,
##          cai para o chão sozinha. Tem QTE fácil (errar encurta e desvia o local).
##      - Charles no chão ou suspenso + bola Suspensa -> Sky-Arc Pass: passe longo e
##          curvo (alcance 550), escolhendo um aliado. Diferente do passe alto comum, a
##          bola chega a ele NO CHÃO (reaproveita o passe curvo do MatchManager, que já
##          entrega a bola no chão).
##
## 2. Gremlin Taunt / Gremlin Shot (ação de habilidade, com 2 variantes automáticas pela
##      altura; recarga de 2 rodadas, compartilhada):
##      - Charles no chão + bola no chão e PRÓXIMA -> Gremlin Taunt (igual ao Glam! do Aryu):
##          Charles SEGURA a bola nos pés. Ela acompanha o Charles e os adversários não
##          conseguem tocar nela (trava spell_owner). Dura até o fim do próximo turno do
##          adversário. Se um adversário chegar perto (ou der Carrinho nele) no turno dele,
##          Charles desvia COM a bola, ganha uma ação geral EXTRA (extra_general_left),
##          guardada para a próxima vez que ele agir, e a bola fica GRUDADA nele pelo resto
##          da rodada (ver _update_taunt). Se ele for derrubado, perde a bola.
##      - Charles e bola Suspensos -> Gremlin Shot: a outra variante aparece sozinha nessa
##          situação (assim como o Backheel Shot do Isagi muda de nome pela altura): um
##          chute "suspenso" que desce até o chão, com uma curva fraquinha. QTE fácil.
##
## 3. Tricheur's Metavision (ação de habilidade): +1 ação de habilidade para os
##      Secundários, nenhum QTE para os chutes do Charles, e reduz em 10% a chance de gol
##      de todo chute INIMIGO dado a até 400px dele, pelas próximas 3 rodadas (um "radar"
##      amarelo translúcido mostra esse alcance enquanto ela estiver ativa). Recarga de 3
##      rodadas a partir do fim do efeito.
##
## PEÇAS PEQUENAS NO RESTO DO PROJETO (já aplicadas, se você usou os arquivos que eu
## devolvi):
## - player.gd: o gancho try_counter_slide() (Gremlin Taunt) e o campo extra_general_left,
##   irmão do extra_skill_left que já existia (ação geral extra de graça).
## - match_manager.gd: begin_point_pass() (Rabona Cross: o passe que pousa num ponto) e
##   pick_point_for_skill() (escolher esse ponto clicando no campo, com o mesmo círculo de
##   alcance e aviso de "fora do alcance" que o pick_ally_for_skill já usa para aliados).
##
## Como montar a cena: igual ao Isagi/Rin — Nova Cena Herdada de player.tscn -> anexe
## este script ao nó raiz -> renomeie o nó raiz para "Charles".

const SKILL_PASS: StringName = &"rabona_cross"
const SKILL_TAUNT: StringName = &"gremlin_taunt"
const SKILL_METAVISION: StringName = &"metavision_tricheur"

## Grupos de recarga (as variantes de cada habilidade compartilham o mesmo)
const CD_PASS: StringName = &"cd_pass"
const CD_TAUNT: StringName = &"cd_taunt"
const CD_METAVISION: StringName = &"cd_metavision"

## Variante da habilidade 1, pela altura da bola (e do Charles)
enum PassVariant { NONE, RABONA, SKY_ARC }
## Variante da habilidade 2, pela altura dos dois
enum TauntVariant { NONE, TAUNT, SHOT }
## NONE = sem Taunt; HOLDING = segurando a bola; STUCK = desviou, a bola fica grudada até o fim da rodada
enum TauntState { NONE, HOLDING, STUCK }

@export_group("Rabona Cross / Sky-Arc Pass")
@export var rabona_range: float = 500.0
@export var sky_arc_range: float = 550.0
@export_range(0.0, 1.0) var sky_arc_curve_ratio: float = 0.22   # o quanto o Sky-Arc Pass se curva
@export var sky_arc_bend: float = 1.0                           # lado da curva (+1 / -1)
@export_range(0.0, 1.0) var rabona_qte_fail_range_mult: float = 0.5   # alcance que sobra se errar o QTE
@export_range(0.0, 90.0) var rabona_qte_fail_angle: float = 35.0      # desvio (graus) se errar o QTE
@export var pass_cooldown: int = 3

@export_group("Gremlin Taunt / Gremlin Shot")
@export_range(0.0, 1.0) var gremlin_shot_chance: float = 0.35
@export_range(0.0, 30.0) var gremlin_shot_curve_deg: float = 14.0   # "curva fraquinha" do Gremlin Shot
@export var gremlin_cooldown: int = 2
@export var taunt_range: float = 90.0              # "bola próxima" para o Gremlin Taunt
@export var taunt_grab_time: float = 0.15          # tempo que a bola leva para grudar
@export var taunt_ball_offset: float = 2.0         # folga entre o Charles e a bola grudada
@export var taunt_trigger_radius: float = 75.0     # adversário a esta distância da bola = tentou interagir
@export var taunt_dodge_distance: float = 200.0    # quanto Charles (e a bola) desvia
@export var taunt_dodge_time: float = 0.25
## Quantas rodadas a bola continua grudada DEPOIS da rodada em que o counter disparou
## (0 = só até essa rodada acabar)
@export var gremlin_stick_extra_rounds: int = 0

@export_group("Tricheur's Metavision")
@export var metavision_rounds: int = 3                # rodadas depois da atual
@export var metavision_range: float = 230.0            # alcance da redução de chance (e do "radar")
@export_range(0.0, 1.0) var metavision_enemy_shot_penalty: float = 0.10   # 0.10 = -10% na chance de gol dos chutes inimigos
@export var metavision_extra_ally_skills: int = 1      # ações de habilidade extras para os Secundários
@export var metavision_cooldown: int = 3               # recarga, contada a partir do fim do efeito

@export_group("Visual do chute")
## Aura + partículas dos chutes/passes de habilidade. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: rabona_cross, gremlin_taunt, metavision_tricheur.
## Sem imagem, o balão aparece só com o texto.
@export var skill_icons: Dictionary = {}

## Gremlin Taunt: NONE / HOLDING (segurando a bola) / STUCK (desviou; bola grudada até o fim da rodada)
var _taunt_state: TauntState = TauntState.NONE
var _taunt_touches: int = 0        # qualquer toque depois disto solta a bola
var _taunt_dodging: bool = false
## Tricheur's Metavision vale até o fim desta rodada (-1 = inativa)
var _metavision_until_round: int = -1
## No estado STUCK, a bola fica grudada até o fim desta rodada (-1 = não está)
var _stuck_until_round: int = -1


func _init() -> void:
	character_id = "charles"   # o menu de formação usa isto para saber quem é quem
	display_name = "Charles"   # troque aqui se quiser o nome completo


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	# A Tricheur's Metavision reduz a chance de chute dos INIMIGOS por perto, então Charles
	# entra no mesmo grupo que os outros efeitos de controle (ver is_skills_suppressed/
	# is_generals_suppressed no player.gd) e implementa shot_penalty_on(); ela só faz algo
	# enquanto is_metavision_active() for true.
	add_to_group("control_sources")
	_hook_manager.call_deferred()

func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.768, 0.568, 0.074, 1.0)
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(0.965, 0.82, 0.345, 1.0)
	fx.amount = 20
	fx.lifetime = 0.5
	fx.speed_min = 15.0
	fx.speed_max = 65.0
	fx.gravity = Vector2(0.0, -50.0)
	fx.spin = 300.0
	fx.scale_min = 0.15
	fx.scale_max = 0.32
	fx.burst_amount = 14
	fx.burst_speed = 200.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.round_started.connect(_on_round_started)
		m.turn_ended.connect(_on_turn_ended)
	var ball: Ball = _get_ball()
	if ball:
		ball.was_reset.connect(_on_ball_reset)


## Gremlin Taunt: sem interação, a bola solta no fim do turno do adversário
func _on_turn_ended(ended_team: int) -> void:
	if _taunt_state == TauntState.HOLDING and ended_team != team and not _taunt_dodging:
		_end_taunt(true)


func _on_ball_reset() -> void:
	_end_taunt(false)   # gol / reposição: a bola já foi solta pelo próprio Ball


func _on_round_started(new_round: int) -> void:
	# A rodada do counter acabou: a bola desgruda e volta ao jogo normal
	if _taunt_state == TauntState.STUCK and _stuck_until_round >= 0 and new_round > _stuck_until_round:
		_end_taunt(true)
	queue_redraw()   # o radar da Metavision e o anel do Gremlin Taunt somem quando acabam


# ---------- DERRUBADO: perde a bola do Gremlin Taunt ----------

func knock_down() -> void:
	super()
	_end_taunt(true)   # derrubado: a bola solta
	queue_redraw()


# ---------- HABILIDADE 1: RABONA CROSS / SKY-ARC PASS ----------

func get_pass_variant() -> PassVariant:
	var ball: Ball = _get_ball()
	if ball == null or ball.is_held() or ball.is_locked_for(team):
		return PassVariant.NONE
	if global_position.distance_to(ball.global_position) > kick_range:
		return PassVariant.NONE

	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND and ball_level == Heights.Level.GROUND:
		return PassVariant.RABONA
	if (height_level == Heights.Level.GROUND or height_level == Heights.Level.SUSPENDED) \
			and ball_level == Heights.Level.SUSPENDED:
		return PassVariant.SKY_ARC
	return PassVariant.NONE


func _pass_skill_name() -> String:
	if get_pass_variant() == PassVariant.SKY_ARC:
		return "Sky-Arc Pass"
	return "Rabona Cross"


func _use_pass_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_pass_variant():
		PassVariant.RABONA:
			return await _use_rabona_cross(m)
		PassVariant.SKY_ARC:
			return await _use_sky_arc_pass(m)
	return false


## Rabona Cross: o jogador CLICA no local do campo (dentro de rabona_range) para onde
## a bola vai, em vez de só escolher uma direção. Ela paira lá, igual ao Passe Alto
## comum (sobe a Voando no meio do caminho, desce ao nível Suspenso no local quando o
## turno do Charles voltar, e cai ao chão sozinha se ninguém tocar nela a tempo).
func _use_rabona_cross(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()

	var landing: Vector2 = await m.pick_point_for_skill(self, rabona_range)
	if landing == Vector2.INF:
		return false   # cancelou: não gasta a ação

	# A bola pode ter rolado enquanto ele escolhia o local: confere de novo
	if get_pass_variant() != PassVariant.RABONA:
		return false

	var dir: Vector2 = landing - global_position
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(_default_facing(), 0.0)
	face_towards(dir)
	if not await play_action(&"rabona_cross", ANIM_PASS_HIGH):
		return false   # ação cancelada (ex: a partida reiniciou)

	var qte_ok: bool = true
	if not skips_qte():
		qte_ok = await m.run_qte(KickType.VOLLEY)   # QTE fácil

	if not qte_ok:
		# Errou: o local sai mais perto do que o clicado e um pouco torto
		var bad_dir: Vector2 = dir.rotated(deg_to_rad(randf_range(-rabona_qte_fail_angle, rabona_qte_fail_angle)))
		var dist: float = global_position.distance_to(landing) * rabona_qte_fail_range_mult
		landing = global_position + bad_dir * dist

	ball.register_touch(self)   # o passe alto não usa kick(), então registra o toque aqui
	if kick_fx:
		ball.play_fx(kick_fx)
	var midpoint: Vector2 = (ball.global_position + landing) * 0.5
	var tween: Tween = ball.hover_to(midpoint, Heights.FLYING_HEIGHT, 0.9)
	await tween.finished

	m.begin_point_pass(team, landing)
	start_cooldown(CD_PASS, pass_cooldown)
	return true


## Sky-Arc Pass: passe longo e curvo (reaproveita run_curved_ground_pass do MatchManager,
## que já faz a bola chegar NO CHÃO no aliado escolhido, mesmo saindo "suspensa").
func _use_sky_arc_pass(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var target: Player = await m.pick_ally_for_skill(self, sky_arc_range)
	if target == null:
		return false   # cancelou: não gasta a ação

	# A bola pode ter mudado de altura ou de alcance enquanto ele escolhia o alvo
	if get_pass_variant() != PassVariant.SKY_ARC:
		return false

	await m.run_curved_ground_pass(self, target, ball, sky_arc_curve_ratio, sky_arc_bend,
		&"sky_arc_pass", kick_fx)
	start_cooldown(CD_PASS, pass_cooldown)
	return true


# ---------- HABILIDADE 2: GREMLIN TAUNT / GREMLIN SHOT ----------

func get_taunt_variant() -> TauntVariant:
	var ball: Ball = _get_ball()
	if ball == null or is_down:
		return TauntVariant.NONE
	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND and ball_level == Heights.Level.GROUND \
			and not ball.is_held() and not ball.is_locked_for(team) \
			and global_position.distance_to(ball.global_position) <= taunt_range:
		return TauntVariant.TAUNT
	if height_level == Heights.Level.SUSPENDED and ball_level == Heights.Level.SUSPENDED:
		return TauntVariant.SHOT
	return TauntVariant.NONE


func _taunt_skill_name() -> String:
	if _taunt_state != TauntState.NONE:
		return "Gremlin Taunt (segurando)"
	if get_taunt_variant() == TauntVariant.SHOT:
		return "Gremlin Shot"
	return "Gremlin Taunt"


func _use_taunt_skill() -> bool:
	match get_taunt_variant():
		TauntVariant.TAUNT:
			return await _use_gremlin_hold()
		TauntVariant.SHOT:
			return await _use_gremlin_shot()
	return false


## Gremlin Taunt (como o Glam! do Aryu): Charles puxa a bola para os pés e a SEGURA. Ela fica
## pairando colada nele e travada para os adversários (spell_owner: a mesma trava do Zero Reset
## Turn do Nagi e do Glam do Aryu; ver Ball.is_locked_for).
func _use_gremlin_hold() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or get_taunt_variant() != TauntVariant.TAUNT:
		return false
	face_towards(ball.global_position - global_position)
	if not await play_action(&"gremlin_taunt"):
		return false   # ação cancelada (ex: a partida reiniciou)
	ball = _get_ball()
	if ball == null or get_taunt_variant() != TauntVariant.TAUNT:   # a bola pode ter saído do alcance
		return false

	_end_taunt(false)
	m.clear_pending_pass()              # passe alto em andamento: a bola agora é do Charles
	ball.register_touch(self)
	ball.hover_to(_hold_point(ball), 0.0, taunt_grab_time)
	await get_tree().create_timer(taunt_grab_time + 0.02).timeout
	ball = _get_ball()
	if ball == null or m.match_over:
		return false

	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.spell_owner = self             # adversários não conseguem tocar na bola enquanto ela está com o Charles
	_taunt_touches = ball.interaction_count   # qualquer toque depois disto solta a bola
	_taunt_state = TauntState.HOLDING
	_taunt_dodging = false
	start_cooldown(CD_TAUNT, gremlin_cooldown)
	queue_redraw()
	return true


## Gremlin Shot: chute com o Charles e a bola Suspensos. Usa KickType.VOLLEY sem
## subir mais (o pico do voleio já é o nível Suspenso, por padrão): a bola só ganha
## velocidade horizontal e a gravidade cuida sozinha da descida até o chão. A "curva
## fraquinha" é só um probleminha fixo na mira.
func _use_gremlin_shot() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação
	if get_taunt_variant() != TauntVariant.SHOT:
		return false

	var qte_ok: bool = true
	if not skips_qte():
		qte_ok = await m.run_qte(KickType.VOLLEY)   # QTE fácil

	var dir: Vector2 = aim.rotated(deg_to_rad(gremlin_shot_curve_deg))
	await kick_ball(ball, dir, KickType.VOLLEY, qte_ok, gremlin_shot_chance, false,
		kick_fx if qte_ok else null, &"gremlin_shot")
	start_cooldown(CD_TAUNT, gremlin_cooldown)
	return true


## O Carrinho de um adversário contra o Charles (com a bola segurada) conta como tentar
## interagir: ele desvia (a chamada vem do ATACANTE, dentro de _check_slide_hits do player.gd).
func try_counter_slide(attacker: Player) -> bool:
	if _taunt_state != TauntState.HOLDING or _taunt_dodging or is_down or attacker.team == team:
		return false
	attacker._slide_hit_ball = true   # o resto do carrinho dele não tenta chutar a bola de novo
	_taunt_dodge(attacker.global_position)
	return true


## Posição da bola segurada: nos pés do Charles, do lado para onde ele está virado
func _hold_point(ball: Ball) -> Vector2:
	return global_position + Vector2(facing, 0.0) * (body_radius + ball.collision_radius + taunt_ball_offset)


## Mantém a bola colada e, no turno do adversário, vigia quem chega perto. Se alguém do time
## dele chutou/passou (o kick() da bola chama release_hover(), que limpa o spell_owner), acabou.
func _update_taunt() -> void:
	if _taunt_state == TauntState.NONE:
		return
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or m.match_over:
		_end_taunt(false)
		return
	if ball.spell_owner != self or not ball.hovering or ball.is_held() \
			or ball.interaction_count != _taunt_touches:
		_end_taunt(false)   # alguém tocou/soltou a bola por outro meio
		return
	if is_down:
		_end_taunt(true)
		return

	ball.global_position = _hold_point(ball)
	ball.height = 0.0

	if _taunt_state == TauntState.HOLDING and not _taunt_dodging:
		_check_taunt_trigger(ball)


func _check_taunt_trigger(ball: Ball) -> void:
	var m: MatchManager = _get_manager()
	# Só o turno do adversário conta (no turno do próprio Charles ninguém "tenta" nada)
	if m == null or m.current_team == team:
		return
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.team == team or p.is_down or not p.can_reach_level(ball.get_level()):
			continue
		var radius: float = maxf(taunt_trigger_radius, p.kick_range + 5.0)
		if p.global_position.distance_to(ball.global_position) <= radius:
			_taunt_dodge(p.global_position)
			return


## Dispara fora da vez de Charles: ele salta por cima (hop_over), desvia COM a bola para longe de
## quem tentou interagir e ganha uma ação GERAL extra (extra_general_left), guardada para a
## próxima vez que ele agir (não dá para abrir um menu de ações no meio do turno do adversário).
## Depois a bola fica GRUDADA nele (STUCK) pelo resto da rodada.
func _taunt_dodge(from: Vector2) -> void:
	var m: MatchManager = _get_manager()
	_taunt_dodging = true
	hop_over()
	extra_general_left += 1

	var away: Vector2 = global_position - from
	if away.length() < 1.0:
		away = Vector2(-facing, 0.0)
	var dest: Vector2 = _clamp_to_pitch(global_position + away.normalized() * taunt_dodge_distance)
	face_towards(-away)
	var tw := create_tween()
	tw.tween_property(self, "global_position", dest, taunt_dodge_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(taunt_dodge_time).timeout

	_taunt_dodging = false
	if _taunt_state == TauntState.HOLDING and m != null:
		_taunt_state = TauntState.STUCK
		_stuck_until_round = m.round_number + gremlin_stick_extra_rounds
	queue_redraw()


## release = true solta a bola (cai e rola); false = ela já foi tocada/solta por outro
func _end_taunt(release: bool) -> void:
	if _taunt_state == TauntState.NONE:
		return
	_taunt_state = TauntState.NONE
	_taunt_dodging = false
	_stuck_until_round = -1
	var ball: Ball = _get_ball()
	if release and ball != null and ball.spell_owner == self:
		ball.release_hover()   # volta a gravidade e a trava some
	queue_redraw()


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


# ---------- HABILIDADE 3: TRICHEUR'S METAVISION ----------

func is_metavision_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _metavision_until_round >= 0 and m.round_number <= _metavision_until_round


## Nenhum QTE nos chutes do Charles enquanto a Tricheur's Metavision estiver ativa
func skips_qte() -> bool:
	return is_metavision_active()


## Chamado pelo kick_ball() de quem chuta (ver get_opponent_shot_penalty() no player.gd):
## devolve quanto SUBTRAIR da chance de gol deste chute (0.10 = -10%). Só vale para
## chutes de ADVERSÁRIOS dados a até metavision_range do Charles, com a Metavision ativa.
func shot_penalty_on(shooter: Player) -> float:
	if not is_metavision_active() or shooter.team == team:
		return 0.0
	if global_position.distance_to(shooter.global_position) > metavision_range:
		return 0.0
	return metavision_enemy_shot_penalty


func _use_metavision() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	await play_action(&"metavision_tricheur")
	_metavision_until_round = m.round_number + metavision_rounds
	start_cooldown(CD_METAVISION, metavision_cooldown, _metavision_until_round + 1)
	m.secondary_skill_left += metavision_extra_ally_skills
	queue_redraw()
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_PASS, "name": skill_label(_pass_skill_name(), CD_PASS)})
	list.append({"id": SKILL_TAUNT, "name": skill_label(_taunt_skill_name(), CD_TAUNT)})
	var meta_name: String = "Tricheur's Metavision (ativa)" if is_metavision_active() \
		else skill_label("Tricheur's Metavision", CD_METAVISION)
	list.append({"id": SKILL_METAVISION, "name": meta_name})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_PASS:
			return not is_on_cooldown(CD_PASS) and get_pass_variant() != PassVariant.NONE
		SKILL_TAUNT:
			if is_on_cooldown(CD_TAUNT) or _taunt_state != TauntState.NONE:
				return false   # sem reativar enquanto já está segurando a bola
			return get_taunt_variant() != TauntVariant.NONE
		SKILL_METAVISION:
			return not is_metavision_active() and not is_on_cooldown(CD_METAVISION)
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_PASS:
			return await _use_pass_skill()
		SKILL_TAUNT:
			return await _use_taunt_skill()
		SKILL_METAVISION:
			return await _use_metavision()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_PASS:
			var rabona_text: String = "Rabona Cross (Charles e bola no chão): passe alto para um LOCAL que você clica no campo (até %d px). A bola paira lá, no nível Suspenso, e cai sozinha se ninguém tocar nela. QTE fácil: errar encurta e desvia o local." % int(rabona_range)
			var sky_text: String = "Sky-Arc Pass (bola suspensa; Charles no chão ou suspenso): passe longo e curvo para um aliado a até %d px. A bola chega a ele no chão." % int(sky_arc_range)
			match get_pass_variant():
				PassVariant.RABONA:
					title = "Rabona Cross"
					text = rabona_text
				PassVariant.SKY_ARC:
					title = "Sky-Arc Pass"
					text = sky_text
				_:
					title = "Rabona Cross / Sky-Arc Pass"
					text = rabona_text + "\n" + sky_text
			text += "\nRecarga: %d rodadas, compartilhada entre os dois." % pass_cooldown
		SKILL_TAUNT:
			var taunt_text: String = "Gremlin Taunt (Charles e bola no chão, bola próxima): segura a bola nos pés até o fim do próximo turno do adversário. Ela acompanha o Charles e os adversários não conseguem tocar nela. Se um adversário chegar perto (ou der Carrinho nele), Charles desvia com a bola, ganha 1 ação geral extra para a próxima vez que agir, e a bola fica grudada nele até o fim da rodada. Derrubado, ele perde a bola."
			var shot_text: String = "Gremlin Shot (Charles e bola suspensos): chute que desce até o chão, com uma curva fraquinha. QTE fácil, %d%% de chance de gol." % _pct(gremlin_shot_chance)
			if _taunt_state != TauntState.NONE:
				title = "Gremlin Taunt (segurando)"
				text = taunt_text
			else:
				match get_taunt_variant():
					TauntVariant.SHOT:
						title = "Gremlin Shot"
						text = shot_text
					TauntVariant.TAUNT:
						title = "Gremlin Taunt"
						text = taunt_text
					_:
						title = "Gremlin Taunt / Gremlin Shot"
						text = taunt_text + "\n" + shot_text
			text += "\nRecarga: %d rodadas, compartilhada entre as duas." % gremlin_cooldown
		SKILL_METAVISION:
			title = "Tricheur's Metavision"
			text = ("Por %d rodadas depois da atual: +%d ação(ões) de habilidade extra para os Secundários, nenhum QTE nos chutes do Charles, e todo chute INIMIGO dado a até %d px dele perde %d%% de chance de gol.\n"
				+ "Recarga: %d rodadas, contadas a partir do fim do efeito.") % [
				metavision_rounds, metavision_extra_ally_skills, int(metavision_range),
				_pct(metavision_enemy_shot_penalty), metavision_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_metavision_until_round = -1
	_end_taunt(true)
	queue_redraw()


# ---------- LOOP / VISUAL ----------

## Com a Tricheur's Metavision ativa, o radar precisa redesenhar toda hora (a varredura
## gira com o tempo); nos outros casos o _draw já é acionado pelos setters/sinais normais.
func _process(delta: float) -> void:
	super(delta)
	_update_taunt()
	if is_metavision_active():
		queue_redraw()


func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Radar amarelo translúcido = alcance da Tricheur's Metavision (chutes
	# inimigos dados de dentro dele perdem chance de gol), com uma varredura girando
	if is_metavision_active():
		var radar_color := Color(1.0, 0.9, 0.2, 0.9)
		draw_circle(center, metavision_range, Color(radar_color, 0.07))
		draw_arc(center, metavision_range, 0.0, TAU, 72, Color(radar_color, 0.5), 2.0)
		var sweep: float = fmod(Time.get_ticks_msec() / 1000.0, TAU)
		draw_line(center, center + Vector2(cos(sweep), sin(sweep)) * metavision_range,
			Color(1.0, 0.95, 0.45, 0.6), 2.0)

	# Anel laranja enquanto o Gremlin Taunt está segurando a bola
	if _taunt_state != TauntState.NONE:
		draw_arc(center, placeholder_radius + 11.0, 0.0, TAU, 24, Color(1.0, 0.75, 0.1, 0.9), 2.0)
