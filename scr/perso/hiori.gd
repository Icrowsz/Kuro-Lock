class_name Hiori
extends Player
## Hiori. Mais um personagem do time (depois de Isagi, Rin e Charles), com 3 habilidades:
##
## 1. Chilling Pass / No Look Cross (ação de habilidade, com 2 variantes automáticas pela
##      altura de Hiori; recarga de 2 rodadas, compartilhada entre as duas):
##      - Hiori no chão + bola no chão ou Suspensa -> Chilling Pass: passe alto (alcance 525)
##          para um ALIADO. Igual ao Passe Alto comum: a bola sobe ao nível Voando no meio
##          do caminho e PAIRA lá; quando o turno de Hiori voltar, desce ao nível Suspenso
##          no aliado (ou onde ele estava, se saiu do alcance). Cai sozinha se ninguém tocar.
##          Sem QTE (igual ao Passe Alto comum).
##      - Hiori Suspenso + bola próxima -> No Look Cross: a mesma mecânica do Chilling Pass,
##          só que com alcance bem maior (575px). Também sem QTE.
##
## 2. Glacial Cut + Ultrasadist (ação de habilidade; recarga de 3 rodadas):
##      - Glacial Cut: Hiori faz uma corrida curta (menos tempo que o Correr normal, mas um
##          pouco mais rápida) — NÃO é a ação geral Correr, não gasta nem conta como ela
##          (runs_this_turn não muda). Se, durante essa corrida, ele chegar perto o
##          suficiente da bola, libera o complemento Ultrasadist.
##      - Ultrasadist: só aparece depois de um Glacial Cut que alcançou a bola. É GRATUITO
##          (skill_is_free) — então os dois juntos continuam contando como uma única ação
##          de habilidade, igual ao Draconic Header do Shidou (ver player.gd). Funciona como
##          o Rabona Cross do Charles: Hiori escolhe um LOCAL do campo (alcance 550) em vez
##          de um aliado; a bola sobe a Voando e pousa lá, Suspensa. QTE fácil: errar
##          encurta e desvia o local. Se o turno de Hiori terminar sem usá-lo, a chance
##          se perde.
##
## 3. Coldest Metavision (ação de habilidade; recarga de 3 rodadas, a partir do fim do
##      efeito — não especificada pelo design, ajuste à vontade):
##      Por algumas rodadas: a PRÓXIMA ação Correr de Hiori ganha mais segundos; os chutes
##      do próprio Hiori e os chutes de quem acabou de receber um passe DELE (suas
##      assistências, enquanto a habilidade durar) ganham +8% de chance de gol; e Hiori
##      ganha acesso a uma de duas habilidades extras, dependendo do lado do campo em que
##      estiver:
##      - Lado da DEFESA -> Frost Guard: com a bola Suspensa e perto, Hiori salta até ela e
##          dá um "deflect", mandando-a para a direção contrária. Recarga de 2 rodadas.
##      - Lado do ATAQUE -> Cryo Shot: chute comum, SEM QTE, com Hiori e a bola no chão ou
##          Suspensos (qualquer combinação dessas duas, menos Voando). Recarga de 2 rodadas.
##
## PEÇAS PEQUENAS NO RESTO DO PROJETO (já aplicadas, se você usou os arquivos que eu
## devolvi):
## - match_manager.gd: run_skill_high_pass() — versão pública do passe alto (_run_high_pass)
##   para habilidades, com animação/aura própria e alcance próprio. Usada pelo Chilling
##   Pass / No Look Cross.
##
## Como montar a cena: igual ao Isagi/Rin/Charles — Nova Cena Herdada de player.tscn ->
## anexe este script ao nó raiz -> renomeie o nó raiz para "Hiori".

const SKILL_PASS: StringName = &"chilling_pass"
const SKILL_GLACIAL: StringName = &"glacial_cut"
const SKILL_ULTRASADIST: StringName = &"ultrasadist"
const SKILL_METAVISION: StringName = &"coldest_metavision"
const SKILL_FROST_GUARD: StringName = &"frost_guard"
const SKILL_CRYO_SHOT: StringName = &"cryo_shot"

## Grupos de recarga (as variantes/complementos de cada habilidade compartilham o mesmo)
const CD_PASS: StringName = &"cd_pass"
const CD_GLACIAL: StringName = &"cd_glacial"
const CD_METAVISION: StringName = &"cd_metavision"
const CD_FROST_GUARD: StringName = &"cd_frost_guard"
const CD_CRYO_SHOT: StringName = &"cd_cryo_shot"

## Variante da habilidade 1, pela altura de Hiori
enum PassVariant { NONE, CHILLING, NO_LOOK }

@export_group("Chilling Pass / No Look Cross")
@export var chilling_pass_range: float = 525.0
@export var no_look_cross_range: float = 575.0
@export var pass_cooldown: int = 2

@export_group("Glacial Cut / Ultrasadist")
@export var glacial_cut_duration: float = 0.9          # run_duration padrão costuma ser maior
@export var glacial_cut_speed_mult: float = 1.3         # "um pouco mais veloz" que o Correr normal
@export var ultrasadist_range: float = 550.0
@export_range(0.0, 1.0) var ultrasadist_qte_fail_range_mult: float = 0.5   # alcance que sobra se errar o QTE
@export_range(0.0, 90.0) var ultrasadist_qte_fail_angle: float = 35.0      # desvio (graus) se errar o QTE
@export var glacial_cooldown: int = 3

@export_group("Coldest Metavision")
@export var metavision_rounds: int = 3
@export var metavision_run_bonus: float = 1.0                   # segundos extra na PRÓXIMA Correr
@export_range(0.0, 1.0) var metavision_self_shot_bonus: float = 0.08     # +8% nos chutes do próprio Hiori
@export_range(0.0, 1.0) var metavision_assist_shot_bonus: float = 0.08   # +8% em quem chuta após receber dele
@export var metavision_cooldown: int = 3    # a partir do fim do efeito

@export_group("Frost Guard (lado da defesa)")
@export var frost_guard_reach: float = 80.0
@export var frost_guard_force: float = 110.0
@export var frost_guard_cooldown: int = 2

@export_group("Cryo Shot (lado do ataque)")
@export_range(0.0, 1.0) var cryo_shot_chance: float = 0.30
@export var cryo_shot_cooldown: int = 2

@export_group("Visual do chute")
## Aura + partículas dos chutes/passes de habilidade. Vazio = usa o estilo padrão (veja _make_kick_fx)
@export var kick_fx: KickFX

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: chilling_pass, glacial_cut,
## ultrasadist, coldest_metavision, frost_guard, cryo_shot.
@export var skill_icons: Dictionary = {}

## Glacial Cut alcançou a bola: Ultrasadist está esperando ser usado (grátis) ainda
## neste turno. Vira false sozinho quando o turno de Hiori acaba.
var _glacial_ready: bool = false
## Coldest Metavision vale até o fim desta rodada (-1 = inativa)
var _metavision_until_round: int = -1
## Último aliado que recebeu um passe de Hiori com a Metavision ativa (ganha o bônus
## de chute enquanto ela durar)
var _assist_target: Player = null
## A próxima chamada de start_run() deve somar o bônus da Coldest Metavision?
var _coldest_run_bonus_pending: bool = false


func _init() -> void:
	character_id = "hiori"   # o menu de formação usa isto para saber quem é quem
	display_name = "Hiori"   # troque aqui se quiser o nome completo


func _ready() -> void:
	super()
	if kick_fx == null:
		kick_fx = _make_kick_fx()
	_hook_manager.call_deferred()


func _make_kick_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.55, 0.85, 1.0, 1.0)             # azul gelo
	fx.trail_width = 12.0
	fx.shape = KickFX.Shape.SQUARE                      # lascas de gelo
	fx.particle_color = Color(0.92, 0.98, 1.0, 1.0)     # branco gelado
	fx.amount = 18
	fx.lifetime = 0.5
	fx.speed_min = 20.0
	fx.speed_max = 70.0
	fx.gravity = Vector2(0.0, -40.0)
	fx.spin = 260.0
	fx.scale_min = 0.12
	fx.scale_max = 0.28
	fx.burst_amount = 12
	fx.burst_speed = 180.0
	return fx


func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.pass_completed.connect(_on_pass_completed)
		m.turn_ended.connect(_on_turn_ended)


## Quem recebeu o passe, enquanto a Coldest Metavision estiver ativa, vira o alvo da
## assistência (ver shot_bonus_for_ally)
func _on_pass_completed(passer: Player, target: Player) -> void:
	if passer == self and is_metavision_active():
		_assist_target = target


## O turno de Hiori acabou: a chance "grátis" do Ultrasadist se perde se não foi usada
func _on_turn_ended(ended_team: int) -> void:
	if ended_team == team and _glacial_ready:
		_glacial_ready = false
		queue_redraw()


# ---------- HABILIDADE 1: CHILLING PASS / NO LOOK CROSS ----------

func get_pass_variant() -> PassVariant:
	var ball: Ball = _get_ball()
	if ball == null or ball.is_held() or ball.is_locked_for(team):
		return PassVariant.NONE
	if global_position.distance_to(ball.global_position) > kick_range:
		return PassVariant.NONE
	if ball.get_level() == Heights.Level.FLYING:
		return PassVariant.NONE
	if height_level == Heights.Level.SUSPENDED:
		return PassVariant.NO_LOOK
	if height_level == Heights.Level.GROUND:
		return PassVariant.CHILLING
	return PassVariant.NONE


func _pass_skill_name() -> String:
	if get_pass_variant() == PassVariant.NO_LOOK:
		return "No Look Cross"
	return "Chilling Pass"


func _use_pass_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	match get_pass_variant():
		PassVariant.CHILLING:
			return await _use_chilling_pass(m)
		PassVariant.NO_LOOK:
			return await _use_no_look_cross(m)
	return false


func _use_chilling_pass(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var target: Player = await m.pick_ally_for_skill(self, chilling_pass_range)
	if target == null:
		return false   # cancelou: não gasta a ação

	# A situação pode ter mudado (Hiori pulou, a bola subiu...) enquanto ele escolhia o alvo
	if get_pass_variant() != PassVariant.CHILLING:
		return false

	await m.run_skill_high_pass(self, target, ball, chilling_pass_range, &"chilling_pass", kick_fx)
	start_cooldown(CD_PASS, pass_cooldown)
	return true


func _use_no_look_cross(m: MatchManager) -> bool:
	var ball: Ball = _get_ball()
	var target: Player = await m.pick_ally_for_skill(self, no_look_cross_range)
	if target == null:
		return false   # cancelou: não gasta a ação

	if get_pass_variant() != PassVariant.NO_LOOK:
		return false

	await m.run_skill_high_pass(self, target, ball, no_look_cross_range, &"no_look_cross", kick_fx)
	start_cooldown(CD_PASS, pass_cooldown)
	return true


# ---------- HABILIDADE 2: GLACIAL CUT / ULTRASADIST ----------

## Corrida curta e um pouco mais rápida que o Correr normal. NÃO é a ação geral Correr:
## não mexe em runs_this_turn nem precisa dela sobrando. Se chegar perto da bola durante
## a corrida, libera o Ultrasadist (complemento gratuito, ver can_use_skill/skill_is_free).
func _use_glacial_cut() -> bool:
	state = State.RUNNING
	var time_left: float = glacial_cut_duration
	var reached: bool = false
	while time_left > 0.0:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = dir * (move_speed * glacial_cut_speed_mult)
		move_and_slide()
		time_left -= delta

		if not reached:
			var ball: Ball = _get_ball()
			if ball != null and not ball.is_held() and not ball.is_locked_for(team) \
					and ball.get_level() != Heights.Level.FLYING \
					and global_position.distance_to(ball.global_position) <= kick_range:
				reached = true
		queue_redraw()

	velocity = Vector2.ZERO
	state = State.IDLE
	start_cooldown(CD_GLACIAL, glacial_cooldown)
	_glacial_ready = reached
	queue_redraw()
	return true


## Complemento gratuito do Glacial Cut (só existe se ele alcançou a bola). Igual ao Rabona
## Cross do Charles: Hiori escolhe um LOCAL do campo em vez de um aliado.
func _use_ultrasadist() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false

	var landing: Vector2 = await m.pick_point_for_skill(self, ultrasadist_range)
	if landing == Vector2.INF:
		return false   # cancelou: a chance continua valendo até o turno acabar
	if ball.is_held() or ball.is_locked_for(team):
		return false   # a bola saiu de jogo enquanto ele escolhia o local

	_glacial_ready = false   # consumida: só dá uma chance por Glacial Cut

	var dir: Vector2 = landing - global_position
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(_default_facing(), 0.0)
	face_towards(dir)
	if not await play_action(&"ultrasadist", ANIM_PASS_HIGH):
		return false   # ação cancelada (ex: a partida reiniciou)

	var qte_ok: bool = true
	if not skips_qte():
		qte_ok = await m.run_qte(KickType.VOLLEY)   # QTE fácil

	if not qte_ok:
		# Errou: o local sai mais perto do que o clicado e um pouco torto
		var bad_dir: Vector2 = dir.rotated(deg_to_rad(randf_range(-ultrasadist_qte_fail_angle, ultrasadist_qte_fail_angle)))
		var dist: float = global_position.distance_to(landing) * ultrasadist_qte_fail_range_mult
		landing = global_position + bad_dir * dist

	ball.register_touch(self)   # o passe alto não usa kick(), então registra o toque aqui
	if kick_fx:
		ball.play_fx(kick_fx)
	var midpoint: Vector2 = (ball.global_position + landing) * 0.5
	var tween: Tween = ball.hover_to(midpoint, Heights.FLYING_HEIGHT, 0.9)
	await tween.finished

	m.begin_point_pass(team, landing)
	queue_redraw()
	return true


# ---------- HABILIDADE 3: COLDEST METAVISION (+ FROST GUARD / CRYO SHOT) ----------

func is_metavision_active() -> bool:
	var m: MatchManager = _get_manager()
	return m != null and _metavision_until_round >= 0 and m.round_number <= _metavision_until_round


## +8% nos chutes do próprio Hiori enquanto a Metavision estiver ativa
func get_shot_chance(kind: KickType) -> float:
	var base: float = super(kind)
	if is_metavision_active():
		base += metavision_self_shot_bonus
	return base


## +8% no chute de quem acabou de receber um passe de Hiori (a assistência), enquanto a
## Metavision durar (ver _on_pass_completed)
func shot_bonus_for_ally(shooter: Player, _ball: Ball) -> float:
	if is_metavision_active() and shooter == _assist_target:
		return metavision_assist_shot_bonus
	return 0.0


## Lado do campo em que Hiori está AGORA. Time 0 defende a ESQUERDA e ataca a DIREITA;
## time 1 é o contrário (ver o comentário de cabeçalho do field.gd).
func _is_on_defense_side() -> bool:
	return (global_position.x < 0.0) == (team == 0)


## Soma o bônus de tempo na PRÓXIMA corrida (gasto na hora: start_run() some com o
## bônus de novo depois de usá-lo, pra não valer pra corridas futuras)
func start_run() -> void:
	var bonus_applied: bool = _coldest_run_bonus_pending
	if bonus_applied:
		run_time_bonus += metavision_run_bonus
		_coldest_run_bonus_pending = false
	super()
	if bonus_applied:
		run_time_bonus -= metavision_run_bonus


func _use_metavision() -> bool:
	var m: MatchManager = _get_manager()
	if m == null:
		return false
	await play_action(&"coldest_metavision")
	_metavision_until_round = m.round_number + metavision_rounds
	_coldest_run_bonus_pending = true
	start_cooldown(CD_METAVISION, metavision_cooldown, _metavision_until_round + 1)
	queue_redraw()
	return true


## Frost Guard: bola Suspensa e perto, lado da defesa -> Hiori salta até ela e deflete
## para a direção contrária (um "chute" sem chance de gol: é defesa, não ataque).
func _use_frost_guard() -> bool:
	var ball: Ball = _get_ball()
	if ball == null:
		return false

	face_towards(ball.global_position - global_position)
	await jump()
	if not await play_action(&"frost_guard", ANIM_JUMP):
		return false

	var reflect_dir: Vector2 = -ball.velocity.normalized() if ball.velocity.length() > 1.0 \
		else Vector2(-facing, 0.0)
	ball.kick(reflect_dir, frost_guard_force,
		Heights.lift_for_peak(Heights.SUSPENDED_HEIGHT, ball.gravity), self, Ball.NO_SHOT)
	if kick_fx:
		ball.play_fx(kick_fx)

	start_cooldown(CD_FROST_GUARD, frost_guard_cooldown)
	return true


## Cryo Shot: chute comum sem QTE, Hiori e bola no chão ou Suspensos (qualquer combinação
## dessas duas, nunca Voando), lado do ataque.
func _use_cryo_shot() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null:
		return false

	var kind: KickType = get_kick_type(ball)
	if kind == KickType.NONE or kind == KickType.FLYING:
		return false

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	kind = get_kick_type(ball)   # a situação pode ter mudado durante a mira
	if kind == KickType.NONE or kind == KickType.FLYING:
		return false

	# qte_success = true direto: Cryo Shot nunca tem QTE (nem errada, nem o knock_down do erro)
	await kick_ball(ball, aim, kind, true, cryo_shot_chance, false, kick_fx, &"cryo_shot")
	start_cooldown(CD_CRYO_SHOT, cryo_shot_cooldown)
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_PASS, "name": skill_label(_pass_skill_name(), CD_PASS)})
	list.append({"id": SKILL_GLACIAL, "name": skill_label("Glacial Cut", CD_GLACIAL)})
	if _glacial_ready:
		list.append({"id": SKILL_ULTRASADIST, "name": "Ultrasadist (grátis)"})
	var meta_name: String = "Coldest Metavision (ativa)" if is_metavision_active() \
		else skill_label("Coldest Metavision", CD_METAVISION)
	list.append({"id": SKILL_METAVISION, "name": meta_name})
	if is_metavision_active():
		if _is_on_defense_side():
			list.append({"id": SKILL_FROST_GUARD, "name": skill_label("Frost Guard", CD_FROST_GUARD)})
		else:
			list.append({"id": SKILL_CRYO_SHOT, "name": skill_label("Cryo Shot", CD_CRYO_SHOT)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_PASS:
			return not is_on_cooldown(CD_PASS) and get_pass_variant() != PassVariant.NONE
		SKILL_GLACIAL:
			return not is_on_cooldown(CD_GLACIAL)
		SKILL_ULTRASADIST:
			return _glacial_ready
		SKILL_METAVISION:
			return not is_metavision_active() and not is_on_cooldown(CD_METAVISION)
		SKILL_FROST_GUARD:
			if not is_metavision_active() or is_on_cooldown(CD_FROST_GUARD) or not _is_on_defense_side():
				return false
			var ball: Ball = _get_ball()
			return ball != null and ball.get_level() == Heights.Level.SUSPENDED \
				and global_position.distance_to(ball.global_position) <= frost_guard_reach
		SKILL_CRYO_SHOT:
			if not is_metavision_active() or is_on_cooldown(CD_CRYO_SHOT) or _is_on_defense_side():
				return false
			var ball: Ball = _get_ball()
			var kind: KickType = get_kick_type(ball) if ball != null else KickType.NONE
			return kind == KickType.GROUND or kind == KickType.VOLLEY or kind == KickType.HIGH_BALL
	return false


## Ultrasadist é o complemento GRATUITO do Glacial Cut (ver player.gd: skill_is_free /
## has_free_followup, mesmo padrão do Draconic Header do Shidou)
func skill_is_free(skill_id: StringName) -> bool:
	return skill_id == SKILL_ULTRASADIST


func has_free_followup() -> bool:
	return _glacial_ready


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_PASS:
			return await _use_pass_skill()
		SKILL_GLACIAL:
			return await _use_glacial_cut()
		SKILL_ULTRASADIST:
			return await _use_ultrasadist()
		SKILL_METAVISION:
			return await _use_metavision()
		SKILL_FROST_GUARD:
			return await _use_frost_guard()
		SKILL_CRYO_SHOT:
			return await _use_cryo_shot()
	return false


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_PASS:
			var chilling_text: String = "Chilling Pass (Hiori no chão; bola no chão ou Suspensa): passe alto para um ALIADO, até %d px. A bola sobe a Voando no meio do caminho e pousa Suspensa nele quando o turno de Hiori voltar. Sem QTE." % int(chilling_pass_range)
			var no_look_text: String = "No Look Cross (Hiori Suspenso, bola próxima): mesma coisa, só que com bem mais alcance (%d px)." % int(no_look_cross_range)
			match get_pass_variant():
				PassVariant.CHILLING:
					title = "Chilling Pass"
					text = chilling_text
				PassVariant.NO_LOOK:
					title = "No Look Cross"
					text = no_look_text
				_:
					title = "Chilling Pass / No Look Cross"
					text = chilling_text + "\n" + no_look_text
			text += "\nRecarga: %d rodadas, compartilhada entre as duas." % pass_cooldown
		SKILL_GLACIAL:
			title = "Glacial Cut"
			text = ("Corrida curta e um pouco mais veloz que o Correr normal (não gasta nem conta como ele). "
				+ "Se alcançar a bola durante a corrida, libera o Ultrasadist de graça (não gasta outra ação de habilidade).\n"
				+ "Recarga: %d rodadas.") % glacial_cooldown
		SKILL_ULTRASADIST:
			title = "Ultrasadist"
			text = ("Complemento GRATUITO do Glacial Cut: escolha um LOCAL do campo (até %d px). "
				+ "A bola sobe a Voando e pousa lá, Suspensa. QTE fácil: errar encurta e desvia o local.\n"
				+ "Se o turno acabar sem usar, a chance se perde.") % int(ultrasadist_range)
		SKILL_METAVISION:
			title = "Coldest Metavision (ativa)" if is_metavision_active() else "Coldest Metavision"
			text = ("Por %d rodadas depois da atual: a PRÓXIMA Correr de Hiori ganha +%.1fs; os chutes do "
				+ "próprio Hiori e os de quem acabou de receber um passe dele ganham +%d%% de chance de gol; "
				+ "e Hiori ganha o Frost Guard (lado da defesa) ou o Cryo Shot (lado do ataque).\n"
				+ "Recarga: %d rodadas, a partir do fim do efeito.") % [
				metavision_rounds, metavision_run_bonus, _pct(metavision_self_shot_bonus), metavision_cooldown]
		SKILL_FROST_GUARD:
			title = "Frost Guard"
			text = ("Lado da defesa, bola Suspensa e perto (até %d px): Hiori salta até ela e deflete para a "
				+ "direção contrária.\nRecarga: %d rodadas.") % [int(frost_guard_reach), frost_guard_cooldown]
		SKILL_CRYO_SHOT:
			title = "Cryo Shot"
			text = ("Lado do ataque, Hiori e a bola no chão ou Suspensos: chute comum, SEM QTE, %d%% de "
				+ "chance de gol.\nRecarga: %d rodadas.") % [_pct(cryo_shot_chance), cryo_shot_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()
	_glacial_ready = false
	_metavision_until_round = -1
	_assist_target = null
	_coldest_run_bonus_pending = false
	queue_redraw()


# ---------- VISUAL ----------

func _draw() -> void:
	super()
	var center := Vector2(0.0, -height)

	# Auréola gelada enquanto a Coldest Metavision está ativa
	if is_metavision_active():
		var aura_color := Color(0.6, 0.9, 1.0, 0.9)
		draw_circle(center, placeholder_radius + 8.0, Color(aura_color, 0.12))
		draw_arc(center, placeholder_radius + 8.0, 0.0, TAU, 28, aura_color, 2.0)

	# Anel branco-gelo enquanto o Ultrasadist está esperando ser usado
	if _glacial_ready:
		draw_arc(center, placeholder_radius + 14.0, 0.0, TAU, 20, Color(0.9, 0.98, 1.0, 0.95), 2.0)
