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
##      - Charles no chão + bola no chão -> Gremlin Taunt: ARMA uma esquiva (não gasta mais
##          nada depois disso). Enquanto estiver armada, se um inimigo acertar um Carrinho
##          nele — com os dois ainda "no chão" na hora do impacto — ela dispara sozinha:
##          Charles salta visualmente por cima do carrinho (sem perder a bola, sem cair) e
##          ganha uma ação geral EXTRA, guardada para usar na próxima vez que ele agir pelo
##          time dele (extra_general_left). Isso acontece fora do turno de Charles.
##          A bola fica GRUDADA nele pelo resto da rodada em que o counter disparou: os
##          adversários não conseguem chutar, dar carrinho nem empurrar a bola (ver _stick_ball).
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
## Quantas rodadas a bola continua grudada DEPOIS da rodada em que o counter disparou
## (0 = só até essa rodada acabar)
@export var gremlin_stick_extra_rounds: int = 0

@export_group("Tricheur's Metavision")
@export var metavision_rounds: int = 3                # rodadas depois da atual
@export var metavision_range: float = 400.0            # alcance da redução de chance (e do "radar")
@export_range(0.0, 1.0) var metavision_enemy_shot_penalty: float = 0.10   # 0.10 = -10% na chance de gol dos chutes inimigos
@export var metavision_extra_ally_skills: int = 1      # ações de habilidade extras para os Secundários
@export var metavision_cooldown: int = 3               # recarga, contada a partir do fim do efeito

@export_group("Visual do chute")
## Aura + partículas dos chutes/passes de habilidade. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

## Gremlin Taunt está armado, esperando um Carrinho inimigo disparar a esquiva
var _taunt_armed: bool = false
## Tricheur's Metavision vale até o fim desta rodada (-1 = inativa)
var _metavision_until_round: int = -1
## A bola está grudada no Charles (Gremlin Taunt) até o fim desta rodada (-1 = não está)
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


## Roxo/magenta "trapaceiro"; as partículas sobem em espiral
func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.85, 0.2, 0.85)
	fx.trail_width = 14.0
	fx.shape = KickFX.Shape.SQUARE
	fx.particle_color = Color(1.0, 0.75, 0.95)
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


func _on_round_started(new_round: int) -> void:
	# A rodada do counter acabou: a bola desgruda e volta ao jogo normal
	if _stuck_until_round >= 0 and new_round > _stuck_until_round:
		_release_stuck_ball()
	queue_redraw()   # o radar da Metavision e o anel do Gremlin Taunt armado somem quando acabam


# ---------- DERRUBADO: desarma a esquiva do Gremlin Taunt ----------

func knock_down() -> void:
	super()
	_taunt_armed = false
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
	if height_level == Heights.Level.GROUND and ball_level == Heights.Level.GROUND:
		return TauntVariant.TAUNT
	if height_level == Heights.Level.SUSPENDED and ball_level == Heights.Level.SUSPENDED:
		return TauntVariant.SHOT
	return TauntVariant.NONE


func _taunt_skill_name() -> String:
	if _taunt_armed:
		return "Gremlin Taunt (armada)"
	if get_taunt_variant() == TauntVariant.SHOT:
		return "Gremlin Shot"
	return "Gremlin Taunt"


func _use_taunt_skill() -> bool:
	match get_taunt_variant():
		TauntVariant.TAUNT:
			await play_action(&"gremlin_taunt")
			_taunt_armed = true
			start_cooldown(CD_TAUNT, gremlin_cooldown)
			queue_redraw()
			return true
		TauntVariant.SHOT:
			return await _use_gremlin_shot()
	return false


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


## Esquiva do Gremlin Taunt: chamada pelo ATACANTE (dentro de _check_slide_hits do
## player.gd) quando o Carrinho dele ia acertar o Charles.
func try_counter_slide(attacker: Player) -> bool:
	if not _taunt_armed or is_down:
		return false
	var ball: Ball = _get_ball()
	# Se a situação mudou (Charles pulou, a bola subiu, rolou para longe...) a esquiva não
	# existe mais, mas continua "armada" até ele realmente disparar uma vez com a bola nos pés.
	if height_level != Heights.Level.GROUND or ball == null or ball.is_held() \
			or ball.get_level() != Heights.Level.GROUND \
			or global_position.distance_to(ball.global_position) > kick_range:
		return false

	_taunt_armed = false
	_run_gremlin_dodge(attacker)
	return true


## Dispara fora da vez de Charles: ele salta visualmente por cima do carrinho (o mesmo
## pulinho hop_over() que o slide_immune já usa — não muda o nível de altura, não cai),
## a bola GRUDA nele (ver _stick_ball), e ele ganha uma ação GERAL extra
## (extra_general_left), guardada para a próxima vez que ele agir: é a "ação geral" que
## a habilidade dá, só que para usar na rodada do time dele em vez de na hora (não daria
## para abrir um menu de ações no meio do turno do time adversário).
func _run_gremlin_dodge(attacker: Player) -> void:
	hop_over()
	extra_general_left += 1
	_stick_ball(attacker)
	queue_redraw()


## A bola gruda no Charles durante a esquiva: vai pros pés dele (na direção em que ele
## está virado), para na hora, e registra o toque. Ela FICA grudada até o fim da rodada
## (ou até alguém do time dele tocar nela de novo):
## - hovering = true desliga a física da bola, então ninguém consegue empurrá-la
##   correndo nem por colisão;
## - spell_owner = self é a trava que o projeto já tem (a mesma do Arresto Momentum do
##   Ness): is_locked_for() faz o get_kick_type() dos adversários devolver NONE, e o
##   _check_slide_hits() do player.gd também respeita essa trava;
## - o _process() mantém a bola nos pés dele (se ele andar, ela vai junto).
## Também marca o Carrinho do atacante como já tendo "gasto" o toque na bola
## (_slide_hit_ball), para que o resto do carrinho dele não tente chutá-la de novo.
func _stick_ball(attacker: Player) -> void:
	var ball: Ball = _get_ball()
	var m: MatchManager = _get_manager()
	if ball == null or m == null:
		return
	ball.release_hover()   # limpa qualquer trava/pairo anterior
	ball.velocity = Vector2.ZERO
	ball.vel_z = 0.0
	ball.height = 0.0
	ball.pending_shot_chance = Ball.NO_SHOT
	ball.hovering = true
	ball.spell_owner = self
	_place_stuck_ball(ball)
	ball.register_touch(self)
	attacker._slide_hit_ball = true
	_stuck_until_round = m.round_number + gremlin_stick_extra_rounds


## Posição da bola grudada: nos pés do Charles, do lado para onde ele está virado
func _place_stuck_ball(ball: Ball) -> void:
	var offset: Vector2 = Vector2(facing, 0.0) * (body_radius + ball.collision_radius + 2.0)
	ball.global_position = global_position + offset


## Mantém a bola grudada enquanto o efeito durar. Se alguém do time dele chutou/passou
## (o kick() da bola chama release_hover(), que limpa o spell_owner), o efeito acaba.
func _update_stuck_ball() -> void:
	if _stuck_until_round < 0:
		return
	var ball: Ball = _get_ball()
	if ball == null or ball.spell_owner != self or not ball.hovering:
		_stuck_until_round = -1   # a bola já foi solta por outro meio
		return
	_place_stuck_ball(ball)


## Solta a bola grudada (fim da rodada, nova partida)
func _release_stuck_ball() -> void:
	_stuck_until_round = -1
	var ball: Ball = _get_ball()
	if ball != null and ball.spell_owner == self:
		ball.release_hover()   # volta a gravidade e a trava some


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
			if is_on_cooldown(CD_TAUNT) or _taunt_armed:
				return false   # sem reativar enquanto já está armado
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


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_metavision_until_round = -1
	_taunt_armed = false
	_release_stuck_ball()
	queue_redraw()


# ---------- LOOP / VISUAL ----------

## Com a Tricheur's Metavision ativa, o radar precisa redesenhar toda hora (a varredura
## gira com o tempo); nos outros casos o _draw já é acionado pelos setters/sinais normais.
func _process(delta: float) -> void:
	super(delta)
	_update_stuck_ball()
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

	# Anel laranja enquanto o Gremlin Taunt está armado, esperando a esquiva
	if _taunt_armed:
		draw_arc(center, placeholder_radius + 11.0, 0.0, TAU, 24, Color(1.0, 0.75, 0.1, 0.9), 2.0)
