class_name Nagi
extends Player
## Seishiro Nagi. Herda tudo do Player (ações gerais) e adiciona as habilidades próprias.
## No menu aparecem 5 botões:
##
## 1. Trap (GRATUITA, 1x por turno): com a bola Suspensa e próxima, Nagi salta até ela, domina
##      e fica Suspenso (a bola fica pairando do lado dele).
##    - Heavy (complemento; recarga de 2 rodadas, COMPARTILHADA com o Bicycle): Nagi e bola
##      Suspensos/Voando -> chute de trajetória Suspensa que CAI para o Chão (sem quicar).
##    - Bicycle (variante automática do botão Heavy): Nagi Suspenso + bola Voando -> bicicleta.
##      Se a situação serve para os dois (Nagi Suspenso + bola Voando), o Bicycle ganha.
## 2. Zero Reset Turn (recarga de 3 rodadas): os dois no Chão e bola próxima -> Nagi segura a
##      bola ao lado dele. Ela fica TRAVADA para os adversários (mesmo mecanismo do Arresto
##      Momentum: spell_owner) até o próximo turno do time dele. Se um adversário tentar
##      chegar na bola (corre/desliza para perto dela) ou der Carrinho nele, Nagi desvia e
##      ganha +1 ação de habilidade extra no próximo turno dele.
##    - Fake Volley (variante automática; recarga de 2 rodadas): Nagi e bola Suspensos e
##      próximos -> chute falso (a bola sai e volta para ele). Com inimigo próximo,
##      +7% no PRÓXIMO chute. Uma caveira translúcida aparece.
## 3. Lift (recarga de 1 rodada): com a bola próxima, levanta a bola E ele um nível
##      (Chão -> Suspenso -> Voando).
##    - Control (complemento, GRATUITO; recarga de 1 rodada): com a bola já Voando e Nagi
##      Suspenso/Voando, ganha +1 ação de habilidade extra neste turno.
##
## Combos que o conjunto permite (com 1 ação de habilidade por turno):
##   Trap (grátis) -> Heavy                      | Lift -> Control (grátis, +1) -> Bicycle
##
## Como montar a cena: Nova Cena Herdada de player.tscn -> anexe este script ao nó raiz
## -> renomeie o nó raiz para "Nagi".
##
## Animações opcionais (nomes na SpriteFrames; as que faltarem são puladas):
##   trap, heavy, bicycle, zero_reset_turn, fake_volley, lift, control
## Frame de impacto em hit_frames, ex: {"heavy": 4, "bicycle": 5, "trap": 3}

const SKILL_TRAP: StringName = &"trap"
const SKILL_HEAVY: StringName = &"heavy"            # Heavy + Bicycle
const SKILL_ZERO: StringName = &"zero_reset_turn"   # Zero Reset Turn + Fake Volley
const SKILL_LIFT: StringName = &"lift"
const SKILL_CONTROL: StringName = &"control"

## Grupos de recarga (Heavy e Bicycle compartilham o mesmo)
const CD_HEAVY: StringName = &"cd_heavy"
const CD_ZERO: StringName = &"cd_zero"
const CD_FAKE: StringName = &"cd_fake"
const CD_LIFT: StringName = &"cd_lift"
const CD_CONTROL: StringName = &"cd_control"

## Qual variante cabe na situação atual (altura do Nagi x altura da bola)
enum HeavyVariant { NONE, HEAVY, BICYCLE }
enum ZeroVariant { NONE, ZERO_RESET, FAKE_VOLLEY }

@export_group("Trap")
@export var trap_range: float = 140.0            # alcance até a bola (ele salta até ela)
@export var trap_stop_distance: float = 32.0     # distância em que ele para da bola
@export var trap_leap_time: float = 0.3
@export var max_traps_per_turn: int = 1          # sem limite o Trap grátis dava para repetir sem fim

@export_group("Heavy / Bicycle")
@export_range(0.0, 1.0) var chance_heavy: float = 0.45
@export_range(0.0, 1.0) var chance_bicycle: float = 0.55
@export var heavy_cooldown: int = 2              # recarga compartilhada entre Heavy e Bicycle
@export var heavy_uses_qte: bool = true          # QTE do tipo do chute (voleio fácil / voando difícil)
@export var bicycle_uses_qte: bool = true

@export_group("Zero Reset Turn")
@export var zero_cooldown: int = 3
@export var zero_ball_distance: float = 34.0     # onde a bola fica, ao lado dele
@export var zero_trigger_radius: float = 80.0    # adversário agindo a esta distância da bola = "tentou interagir"
@export var zero_hold_distance: float = 110.0    # se Nagi se afastar mais que isso da bola, ele a solta
@export var zero_extra_skills: int = 1           # ações de habilidade extras no próximo turno

@export_group("Fake Volley")
@export var fake_cooldown: int = 2
@export_range(0.0, 1.0) var fake_bonus: float = 0.07   # +7% no próximo chute
@export var fake_enemy_radius: float = 140.0     # "inimigo próximo"
@export var fake_travel: float = 70.0            # quanto a bola sai antes de voltar
@export var fake_lift: float = 18.0
@export var fake_out_time: float = 0.18
@export var fake_back_time: float = 0.22

@export_group("Lift / Control")
@export var lift_cooldown: int = 1
@export var lift_time: float = 0.3
@export var control_cooldown: int = 1
@export var control_extra_skills: int = 1
## Control grátis = +1 ação de verdade. Se custasse ação, daria +1 e gastaria 1 (resultado zero).
@export var control_is_free: bool = true

@export_group("Visual dos chutes")
## Efeitos brancos/cinzas. Vazio = usa o estilo padrão do Nagi (veja _make_*_fx)
@export var soft_fx: KickFX      # Trap, Lift, Zero Reset Turn, Fake Volley
@export var heavy_fx: KickFX     # Heavy (cinza pesado, partículas caem)
@export var bicycle_fx: KickFX   # Bicycle (branco, giratório)

@export_group("Descrição (hover)")
## Imagem de cada habilidade no balão do menu. Chaves: trap, heavy, zero_reset_turn, lift, control.
@export var skill_icons: Dictionary = {}

var _traps_this_turn: int = 0

## Zero Reset Turn
var _zero_active: bool = false
var _zero_triggered: bool = false          # a recompensa já foi dada nesta janela
var _zero_enemy_turn_pending: bool = false # o turno do time do Nagi já acabou; falta o do adversário
var _zero_anchor: Vector2 = Vector2.ZERO   # onde a bola foi deixada

## Ações extras temporárias (Control / Zero Reset Turn): sobra no fim do turno do time dele = some
var _temp_extras: int = 0

# Efeitos visuais desenhados no _draw
var _fx_kind: StringName = &""
var _fx_color: Color = Color.WHITE
var _fx_tween: Tween
var _fx_t: float = 1.0:
	set(v):
		_fx_t = v
		queue_redraw()

var _skull_tween: Tween
var _skull_t: float = 1.0:   # 1.0 = caveira escondida
	set(v):
		_skull_t = v
		queue_redraw()

var _text: String = ""
var _text_tween: Tween
var _text_alpha: float = 0.0:
	set(v):
		_text_alpha = v
		queue_redraw()


func _init() -> void:
	character_id = "nagi"            # o menu de formação usa isto para saber quem é quem
	display_name = "Seishiro Nagi"   # aparece no placar de gols e no menu


func _ready() -> void:
	super()
	if soft_fx == null:
		soft_fx = _make_soft_fx()
	if heavy_fx == null:
		heavy_fx = _make_heavy_fx()
	if bicycle_fx == null:
		bicycle_fx = _make_bicycle_fx()
	_hook_manager.call_deferred()   # o MatchManager entra na árvore no mesmo frame


# ---------- VISUAL: ESTILOS DO CHUTE (brancos e cinzas) ----------

## Fumaça clara que sobe (Trap, Lift, Zero Reset Turn, Fake Volley)
func _make_soft_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.95, 0.95, 1.0)
	fx.trail_width = 12.0
	fx.particle_color = Color(0.8, 0.8, 0.85)
	fx.amount = 18
	fx.lifetime = 0.6
	fx.speed_min = 10.0
	fx.speed_max = 55.0
	fx.gravity = Vector2(0.0, -40.0)
	fx.spin = 120.0
	fx.scale_min = 0.2
	fx.scale_max = 0.45
	fx.burst_amount = 12
	fx.burst_speed = 180.0
	return fx


## Cinza pesado: o rastro é grosso e as partículas CAEM, como a bola do Heavy
func _make_heavy_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(0.72, 0.72, 0.78)
	fx.trail_width = 22.0
	fx.particle_color = Color(0.55, 0.55, 0.6)
	fx.amount = 26
	fx.lifetime = 0.7
	fx.speed_min = 20.0
	fx.speed_max = 90.0
	fx.gravity = Vector2(0.0, 260.0)
	fx.spin = 90.0
	fx.scale_min = 0.25
	fx.scale_max = 0.55
	fx.burst_amount = 22
	fx.burst_speed = 300.0
	return fx


## Branco brilhante e giratório (Bicycle)
func _make_bicycle_fx() -> KickFX:
	var fx := KickFX.new()
	fx.color = Color(1.0, 1.0, 1.0)
	fx.trail_width = 16.0
	fx.particle_color = Color(0.92, 0.92, 0.97)
	fx.amount = 30
	fx.lifetime = 0.5
	fx.speed_min = 30.0
	fx.speed_max = 110.0
	fx.gravity = Vector2.ZERO
	fx.spin = 540.0
	fx.swirl = 60.0
	fx.scale_min = 0.15
	fx.scale_max = 0.4
	fx.burst_amount = 24
	fx.burst_speed = 360.0
	return fx


# ---------- LIGAÇÃO COM O MATCHMANAGER ----------

func _hook_manager() -> void:
	var m: MatchManager = _get_manager()
	if m:
		m.turn_started.connect(_on_turn_started)
		m.turn_ended.connect(_on_turn_ended)


func _on_turn_started(turn_team: int) -> void:
	if turn_team != team:
		return
	_traps_this_turn = 0
	# O turno do time dele voltou: o adversário já jogou, a janela do Zero Reset Turn acabou
	if _zero_active and _zero_enemy_turn_pending:
		_end_zero_reset()


func _on_turn_ended(turn_team: int) -> void:
	if turn_team != team:
		return
	_expire_temp_extras()
	if _zero_active:
		_zero_enemy_turn_pending = true   # a janela segue valendo durante o turno do adversário


# ---------- AÇÕES EXTRAS TEMPORÁRIAS ----------

## Dá ações de habilidade só ao Nagi. O que sobrar no fim do turno do time dele some
## (Control: "nesta rodada"; Zero Reset Turn: "na próxima rodada").
func _grant_temp_extra(amount: int) -> void:
	extra_skill_left += amount
	_temp_extras += amount


func _expire_temp_extras() -> void:
	var expiring: int = mini(_temp_extras, extra_skill_left)
	if expiring > 0:
		extra_skill_left -= expiring
	_temp_extras = 0


# ---------- AUXILIARES ----------

func _next_level(level: Heights.Level) -> Heights.Level:
	if level == Heights.Level.GROUND:
		return Heights.Level.SUSPENDED
	return Heights.Level.FLYING


## Usa a animação própria se a SpriteFrames tiver; senão cai no fallback
func _anim_or(anim: StringName, fallback: StringName) -> StringName:
	if _has_art and animated_sprite.sprite_frames.has_animation(anim):
		return anim
	return fallback


func _enemies_within(radius: float) -> Array[Player]:
	var list: Array[Player] = []
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team != team and not other.is_down \
				and global_position.distance_to(other.global_position) <= radius:
			list.append(other)
	return list


## Aura da habilidade na bola por alguns segundos (mesmo pairando). Chame DEPOIS do register_touch.
func _ball_aura(ball: Ball, fx: KickFX, seconds: float) -> void:
	if fx == null or ball == null:
		return
	var previous: bool = ball.fx_during_hover
	ball.fx_during_hover = true
	ball.play_fx(fx)
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(ball):
		ball.stop_fx()
		ball.fx_during_hover = previous


# ---------- 1. TRAP (gratuita) ----------

func _can_trap() -> bool:
	var ball: Ball = _get_ball()
	if ball == null or is_down or ball.is_held() or ball.is_locked_for(team):
		return false
	if _traps_this_turn >= max_traps_per_turn:
		return false
	if height_level == Heights.Level.FLYING:
		return false
	if ball.get_level() != Heights.Level.SUSPENDED:
		return false
	return global_position.distance_to(ball.global_position) <= trap_range


func _use_trap() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or not _can_trap():
		return false

	face_towards(ball.global_position - global_position)
	if not await play_action(&"trap", ANIM_JUMP):
		return false
	# A bola pode ter se mexido durante a animação: confere de novo
	ball = _get_ball()
	if ball == null or not _can_trap():
		return false

	m.clear_pending_pass()   # se a bola era um passe alto em andamento, o passe deixa de valer
	_traps_this_turn += 1

	var to_ball: Vector2 = ball.global_position - global_position
	var dir: Vector2 = to_ball.normalized() if to_ball.length() > 1.0 else Vector2(facing, 0.0)
	var stop_at: Vector2 = global_position
	if to_ball.length() > trap_stop_distance:
		stop_at = ball.global_position - dir * trap_stop_distance

	# Salta até a bola e fica Suspenso
	height_level = Heights.Level.SUSPENDED
	var leap: Tween = create_tween().set_parallel(true)
	leap.tween_property(self, "global_position", stop_at, trap_leap_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	leap.tween_property(self, "height", Heights.SUSPENDED_HEIGHT, trap_leap_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await leap.finished

	# Domina: a bola para e fica pairando Suspensa do lado dele
	var hold: Tween = ball.hover_to(ball.global_position, Heights.SUSPENDED_HEIGHT, 0.15)
	await hold.finished
	ball.register_touch(self)
	_pulse(&"ring", Color(0.92, 0.92, 1.0))
	_say("TRAP!")
	_ball_aura(ball, soft_fx, 0.5)
	return true


# ---------- 1a/1b. HEAVY e BICYCLE ----------

func get_heavy_variant() -> HeavyVariant:
	var ball: Ball = _get_ball()
	# get_kick_type já confere: derrubado, bola na mão do goleiro, longe demais, altura inalcançável
	if ball == null or get_kick_type(ball) == KickType.NONE:
		return HeavyVariant.NONE
	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND or ball_level == Heights.Level.GROUND:
		return HeavyVariant.NONE
	if height_level == Heights.Level.SUSPENDED and ball_level == Heights.Level.FLYING:
		return HeavyVariant.BICYCLE
	return HeavyVariant.HEAVY


func _use_heavy_skill() -> bool:
	var m: MatchManager = _get_manager()
	if m == null or get_heavy_variant() == HeavyVariant.NONE:
		return false

	var aim: Vector2 = await m.aim_for_skill(self, kick_aim_range)
	if aim == Vector2.ZERO:
		return false   # cancelou: não gasta a ação

	# A bola pode ter mudado de altura enquanto ele mirava: confere de novo
	var ball: Ball = _get_ball()
	var variant: HeavyVariant = get_heavy_variant()
	if ball == null or variant == HeavyVariant.NONE:
		return false

	var is_bicycle: bool = variant == HeavyVariant.BICYCLE
	var kind: KickType = KickType.FLYING if ball.get_level() == Heights.Level.FLYING else KickType.VOLLEY
	var chance: float = chance_bicycle if is_bicycle else chance_heavy
	var needs_qte: bool = bicycle_uses_qte if is_bicycle else heavy_uses_qte

	var qte_ok: bool = true
	if needs_qte and not skips_qte():
		qte_ok = await m.run_qte(kind)

	var anim: StringName
	if is_bicycle:
		anim = _anim_or(&"bicycle", ANIM_FLYING_KICK)
	else:
		anim = _anim_or(&"heavy", ANIM_FLYING_KICK if kind == KickType.FLYING else ANIM_VOLLEY)
	var fx: KickFX = null
	if qte_ok:
		fx = bicycle_fx if is_bicycle else heavy_fx

	var touches_before: int = ball.interaction_count
	# Errou o QTE = chute fraquinho, sem aura. A bola já está no ar, então o kick_ball não a
	# levanta mais (só cai): é isso que dá a trajetória "suspensa que cai para o chão".
	await kick_ball(ball, aim, kind, qte_ok, chance, false, fx, anim)
	if ball.interaction_count == touches_before:
		return false   # a ação foi cancelada antes do chute (ex: a partida reiniciou)

	# Heavy: ao tocar o chão a bola NÃO quica, fica rolando
	if not is_bicycle and qte_ok:
		ball.bounces_left = 0

	start_cooldown(CD_HEAVY, heavy_cooldown)
	return true


# ---------- 2. ZERO RESET TURN / FAKE VOLLEY ----------

func get_zero_variant() -> ZeroVariant:
	var ball: Ball = _get_ball()
	if ball == null or get_kick_type(ball) == KickType.NONE:
		return ZeroVariant.NONE
	var ball_level: Heights.Level = ball.get_level()
	if height_level == Heights.Level.GROUND and ball_level == Heights.Level.GROUND:
		return ZeroVariant.ZERO_RESET
	if height_level == Heights.Level.SUSPENDED and ball_level == Heights.Level.SUSPENDED:
		return ZeroVariant.FAKE_VOLLEY
	return ZeroVariant.NONE


func _zero_cd_group() -> StringName:
	return CD_FAKE if get_zero_variant() == ZeroVariant.FAKE_VOLLEY else CD_ZERO


func _use_zero_skill() -> bool:
	match get_zero_variant():
		ZeroVariant.ZERO_RESET:
			return await _use_zero_reset()
		ZeroVariant.FAKE_VOLLEY:
			return await _use_fake_volley()
	return false


## Nagi segura a bola ao lado dele. Ela fica travada para os adversários até o próximo turno
## do time do Nagi; ver _check_zero_reset e try_counter_slide para o "desvio".
func _use_zero_reset() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or get_zero_variant() != ZeroVariant.ZERO_RESET:
		return false

	var to_ball: Vector2 = ball.global_position - global_position
	var dir: Vector2 = to_ball.normalized() if to_ball.length() > 1.0 else Vector2(facing, 0.0)
	face_towards(dir)
	if not await play_action(&"zero_reset_turn"):
		return false
	ball = _get_ball()
	if ball == null or get_zero_variant() != ZeroVariant.ZERO_RESET:
		return false

	m.clear_pending_pass()
	_zero_anchor = global_position + dir * zero_ball_distance
	var hold: Tween = ball.hover_to(_zero_anchor, Heights.GROUND_HEIGHT, 0.2)
	await hold.finished
	ball.register_touch(self)
	ball.spell_owner = self   # só o time do Nagi consegue tocar na bola (veja Ball.is_locked_for)

	_zero_active = true
	_zero_triggered = false
	_zero_enemy_turn_pending = false
	start_cooldown(CD_ZERO, zero_cooldown)
	_pulse(&"ring", Color(1.0, 1.0, 1.0), 0.6)
	_say("RESET")
	_ball_aura(ball, soft_fx, 0.6)
	queue_redraw()
	return true


## Chamado todo frame. Cuida da janela do Zero Reset Turn: termina se a bola foi mexida/solta
## ou se Nagi se afastou, e dá a recompensa quando um adversário tenta chegar na bola.
func _check_zero_reset() -> void:
	if not _zero_active:
		return
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or ball.spell_owner != self or is_down \
			or ball.global_position.distance_to(_zero_anchor) > 8.0 or ball.height > 2.0 \
			or global_position.distance_to(ball.global_position) > zero_hold_distance:
		_end_zero_reset()
		return
	# "Tentou interagir" só conta no turno do adversário: um adversário que está AGINDO
	# (correndo ou deslizando) e chega perto da bola
	if _zero_triggered or m.current_team == team:
		return
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.team == team or other.is_down or other.state == State.IDLE:
			continue
		if other.global_position.distance_to(ball.global_position) <= zero_trigger_radius:
			_trigger_zero_reset()
			return


func _trigger_zero_reset() -> void:
	if _zero_triggered:
		return
	_zero_triggered = true
	_grant_temp_extra(zero_extra_skills)
	hop_over()   # o pulinho de quem desvia
	_pulse(&"ring", Color(1.0, 1.0, 1.0), 0.55)
	_say("DESVIOU!")


func _end_zero_reset() -> void:
	if not _zero_active:
		return
	_zero_active = false
	_zero_triggered = false
	_zero_enemy_turn_pending = false
	var ball: Ball = _get_ball()
	if ball != null and is_instance_valid(ball) and ball.spell_owner == self:
		ball.spell_owner = null
		# Só solta a bola se ela ainda está onde ele a deixou (se alguém a moveu, ela já tem dono novo)
		if ball.hovering and not ball.is_held() \
				and ball.global_position.distance_to(_zero_anchor) <= 8.0 and ball.height <= 2.0:
			ball.release_hover()
	queue_redraw()


## O Carrinho de um adversário não derruba o Nagi enquanto ele segura a bola: ele desvia
func try_counter_slide(attacker: Player) -> bool:
	if not _zero_active or attacker.team == team or is_down:
		return false
	_trigger_zero_reset()   # (só paga a recompensa uma vez por janela)
	hop_over()
	return true


## Chute falso: a bola sai e volta para ele. Com inimigo próximo: +fake_bonus no próximo chute.
func _use_fake_volley() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or ball == null or get_zero_variant() != ZeroVariant.FAKE_VOLLEY:
		return false

	face_towards(ball.global_position - global_position)
	if not await play_action(&"fake_volley", ANIM_VOLLEY):
		return false
	ball = _get_ball()
	if ball == null or get_zero_variant() != ZeroVariant.FAKE_VOLLEY:
		return false

	m.clear_pending_pass()
	_show_skull()

	# A bola "sai" na direção do inimigo mais próximo (ou para onde ele olha) e volta direto
	var enemies: Array[Player] = _enemies_within(fake_enemy_radius)
	var out_dir: Vector2 = Vector2(facing, 0.0)
	if not enemies.is_empty():
		enemies.sort_custom(func(a: Player, b: Player) -> bool:
			return a.global_position.distance_to(global_position) \
				< b.global_position.distance_to(global_position))
		var to_enemy: Vector2 = enemies[0].global_position - global_position
		if to_enemy.length() > 1.0:
			out_dir = to_enemy.normalized()

	var to_ball: Vector2 = ball.global_position - global_position
	var rest_dir: Vector2 = to_ball.normalized() if to_ball.length() > 1.0 else Vector2(facing, 0.0)
	var home: Vector2 = global_position + rest_dir * zero_ball_distance
	var level_height: float = Heights.SUSPENDED_HEIGHT

	ball.register_touch(self)
	_ball_aura(ball, soft_fx, fake_out_time + fake_back_time + 0.3)
	var out_tween: Tween = ball.hover_to(home + out_dir * fake_travel, level_height + fake_lift, fake_out_time)
	await out_tween.finished
	var back_tween: Tween = ball.hover_to(home, level_height, fake_back_time)
	await back_tween.finished

	if not enemies.is_empty():
		next_shot_bonus += fake_bonus   # acumula a cada uso; é gasto no próximo chute
		_say("+%d%%" % int(round(fake_bonus * 100.0)))
	_pulse(&"ring", Color(0.85, 0.85, 0.9), 0.5)
	start_cooldown(CD_FAKE, fake_cooldown)
	return true


# ---------- 3. LIFT ----------

func _can_lift(ball: Ball) -> bool:
	if ball == null or is_down:
		return false
	# get_kick_type confere distância, goleiro, feitiço e se os níveis se alcançam
	if get_kick_type(ball) == KickType.NONE:
		return false
	# Bola já Voando não sobe mais: aí é o Control
	return ball.get_level() != Heights.Level.FLYING


func _use_lift() -> bool:
	var m: MatchManager = _get_manager()
	var ball: Ball = _get_ball()
	if m == null or not _can_lift(ball):
		return false

	face_towards(ball.global_position - global_position)
	if not await play_action(&"lift", ANIM_JUMP):
		return false
	ball = _get_ball()
	if not _can_lift(ball):
		return false

	m.clear_pending_pass()
	var ball_level: Heights.Level = _next_level(ball.get_level())
	var self_level: Heights.Level = _next_level(height_level)
	var rise_time: float = lift_time * (1.5 if self_level == Heights.Level.FLYING else 1.0)

	# Nagi e bola sobem juntos um nível; a bola fica pairando lá (como depois de um passe alto)
	height_level = self_level
	var rise: Tween = create_tween()
	rise.tween_property(self, "height", Heights.to_height(self_level), rise_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ball.hover_to(ball.global_position, Heights.to_height(ball_level), rise_time)
	_pulse(&"beam", Color(1.0, 1.0, 1.0), rise_time + 0.25)
	await rise.finished

	ball.register_touch(self)
	_ball_aura(ball, soft_fx, 0.5)
	start_cooldown(CD_LIFT, lift_cooldown)
	return true


# ---------- 3a. CONTROL (gratuito) ----------

func _can_control(ball: Ball) -> bool:
	if ball == null or is_down or height_level == Heights.Level.GROUND:
		return false
	if ball.get_level() != Heights.Level.FLYING:
		return false
	return get_kick_type(ball) != KickType.NONE   # próxima e ao alcance


func _use_control() -> bool:
	if not _can_control(_get_ball()):
		return false
	if not await play_action(&"control"):
		return false
	if not _can_control(_get_ball()):
		return false
	_grant_temp_extra(control_extra_skills)
	start_cooldown(CD_CONTROL, control_cooldown)
	_pulse(&"ring", Color(0.9, 0.9, 0.95), 0.5)
	_say("CONTROL")
	return true


# ---------- SISTEMA DE HABILIDADES (menu) ----------

func get_skills() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"id": SKILL_TRAP, "name": "Trap"})

	var heavy_name: String = "Bicycle" if get_heavy_variant() == HeavyVariant.BICYCLE else "Heavy"
	list.append({"id": SKILL_HEAVY, "name": skill_label(heavy_name, CD_HEAVY)})

	var zero_name: String
	match get_zero_variant():
		ZeroVariant.FAKE_VOLLEY:
			zero_name = skill_label("Fake Volley", CD_FAKE)
		_:
			zero_name = "Zero Reset Turn (ativo)" if _zero_active \
				else skill_label("Zero Reset Turn", CD_ZERO)
	list.append({"id": SKILL_ZERO, "name": zero_name})

	list.append({"id": SKILL_LIFT, "name": skill_label("Lift", CD_LIFT)})
	list.append({"id": SKILL_CONTROL, "name": skill_label("Control", CD_CONTROL)})
	return list


func can_use_skill(skill_id: StringName = &"default") -> bool:
	if not super(skill_id):
		return false
	match skill_id:
		SKILL_TRAP:
			return _can_trap()
		SKILL_HEAVY:
			return not is_on_cooldown(CD_HEAVY) and get_heavy_variant() != HeavyVariant.NONE
		SKILL_ZERO:
			return get_zero_variant() != ZeroVariant.NONE and not is_on_cooldown(_zero_cd_group())
		SKILL_LIFT:
			return not is_on_cooldown(CD_LIFT) and _can_lift(_get_ball())
		SKILL_CONTROL:
			return not is_on_cooldown(CD_CONTROL) and _can_control(_get_ball())
	return false


func use_skill(skill_id: StringName = &"default") -> bool:
	match skill_id:
		SKILL_TRAP:
			return await _use_trap()
		SKILL_HEAVY:
			return await _use_heavy_skill()
		SKILL_ZERO:
			return await _use_zero_skill()
		SKILL_LIFT:
			return await _use_lift()
		SKILL_CONTROL:
			return await _use_control()
	return false


## Trap e Control não gastam ação de habilidade
func skill_is_free(skill_id: StringName) -> bool:
	match skill_id:
		SKILL_TRAP:
			return true
		SKILL_CONTROL:
			return control_is_free
	return false


## Sobrou Trap/Control para usar? Então o turno não acaba sozinho quando as ações acabam
## (ex: Lift gasta a última ação, mas o Control vem de graça logo depois)
func has_free_followup() -> bool:
	return can_use_skill(SKILL_TRAP) or (control_is_free and can_use_skill(SKILL_CONTROL))


# ---------- DESCRIÇÃO (balão do menu, ver action_menu.gd) ----------

func _pct(value: float) -> int:
	return int(round(value * 100.0))


func get_skill_info(skill_id: StringName) -> Dictionary:
	var title: String = ""
	var text: String = ""
	match skill_id:
		SKILL_TRAP:
			title = "Trap"
			text = ("Com a bola Suspensa e próxima, Nagi salta até ela, domina e fica Suspenso.\n"
				+ "Não gasta ação de habilidade (%d vez por turno).") % max_traps_per_turn
		SKILL_HEAVY:
			title = "Bicycle" if get_heavy_variant() == HeavyVariant.BICYCLE else "Heavy"
			text = ("Chute de habilidade. A variante muda sozinha com a altura dele e da bola:\n"
				+ "• Heavy (Nagi e bola Suspensos ou Voando): a trajetória é Suspensa, mas a bola cai para o chão sem quicar. %d%% de chance de gol.\n"
				+ "• Bicycle (Nagi Suspenso e bola Voando): bicicleta. %d%%.\n"
				+ "Recarga: %d rodadas, compartilhada entre os dois.") % [
				_pct(chance_heavy), _pct(chance_bicycle), heavy_cooldown]
		SKILL_ZERO:
			title = "Fake Volley" if get_zero_variant() == ZeroVariant.FAKE_VOLLEY else "Zero Reset Turn"
			text = ("A variante muda sozinha com a altura dele e da bola:\n"
				+ "• Zero Reset Turn (os dois no chão, bola próxima): Nagi segura a bola até o próximo turno do time dele. Os adversários não conseguem tocar nela e, se algum tentar chegar perto ou der carrinho, Nagi desvia e ganha +%d ação de habilidade no próximo turno. Recarga: %d rodadas.\n"
				+ "• Fake Volley (os dois Suspensos e próximos): chute falso, a bola sai e volta. Com inimigo próximo, +%d%% no próximo chute. Recarga: %d rodadas.") % [
				zero_extra_skills, zero_cooldown, _pct(fake_bonus), fake_cooldown]
		SKILL_LIFT:
			title = "Lift"
			text = ("Com a bola próxima, levanta a bola e ele um nível: Chão -> Suspenso -> Voando.\n"
				+ "Recarga: %d rodada(s).") % lift_cooldown
		SKILL_CONTROL:
			title = "Control"
			text = ("Com a bola já Voando e Nagi Suspenso ou Voando: +%d ação de habilidade extra neste turno.\n"
				+ "%sRecarga: %d rodada(s).") % [
				control_extra_skills, "Não gasta ação de habilidade. " if control_is_free else "", control_cooldown]
		_:
			return {}
	var icon: Texture2D = skill_icons.get(String(skill_id), skill_icons.get(skill_id)) as Texture2D
	return {"title": title, "description": text, "icon": icon}


# ---------- PARTIDA NOVA ----------

func reset_for_new_match() -> void:
	super()   # zera também extra_skill_left e as recargas
	_traps_this_turn = 0
	_temp_extras = 0
	_zero_active = false
	_zero_triggered = false
	_zero_enemy_turn_pending = false
	_fx_t = 1.0
	_skull_t = 1.0
	_text_alpha = 0.0
	queue_redraw()


# ---------- LOOP ----------

func _process(delta: float) -> void:
	super(delta)
	_check_zero_reset()
	if _zero_active:
		queue_redraw()   # os anéis em volta da bola pulsam


# ---------- VISUAL (branco e cinza) ----------

## Onda de choque no chão ("ring") ou colunas de luz subindo ("beam")
func _pulse(kind: StringName, color: Color = Color.WHITE, duration: float = 0.45) -> void:
	_fx_kind = kind
	_fx_color = color
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_t = 0.0
	_fx_tween = create_tween()
	_fx_tween.tween_property(self, "_fx_t", 1.0, duration) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


## Texto que sobe e some em cima do Nagi
func _say(text: String) -> void:
	_text = text
	if _text_tween and _text_tween.is_valid():
		_text_tween.kill()
	_text_alpha = 1.0
	_text_tween = create_tween()
	_text_tween.tween_interval(0.5)
	_text_tween.tween_property(self, "_text_alpha", 0.0, 0.5)


## Caveira translúcida do Fake Volley: aparece, sobe um pouco e some
func _show_skull() -> void:
	if _skull_tween and _skull_tween.is_valid():
		_skull_tween.kill()
	_skull_t = 0.0
	_skull_tween = create_tween()
	_skull_tween.tween_property(self, "_skull_t", 1.0, 1.3)


func _draw() -> void:
	super()

	# Zero Reset Turn: anéis brancos e cinzas pulsando em volta da bola + fio até o Nagi
	if _zero_active:
		var ball: Ball = _get_ball()
		if ball != null and is_instance_valid(ball):
			var bp: Vector2 = to_local(ball.global_position)
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			var strength: float = 1.0 if _zero_triggered else 0.8
			draw_line(Vector2.ZERO, bp, Color(1, 1, 1, 0.22), 1.5)
			draw_set_transform(bp, 0.0, Vector2(1.0, 0.5))   # achatado, como a sombra
			draw_arc(Vector2.ZERO, 24.0 + pulse * 3.0, 0.0, TAU, 40, Color(1, 1, 1, strength), 2.5)
			draw_arc(Vector2.ZERO, 34.0 + pulse * 5.0, 0.0, TAU, 40, Color(0.7, 0.7, 0.75, 0.6), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Efeito rápido da habilidade que acabou de ser usada
	if _fx_t < 1.0:
		var a: float = 1.0 - _fx_t
		match _fx_kind:
			&"ring":
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
				draw_arc(Vector2.ZERO, lerpf(14.0, 95.0, _fx_t), 0.0, TAU, 48,
					Color(_fx_color, a), lerpf(7.0, 1.0, _fx_t))
				draw_arc(Vector2.ZERO, lerpf(8.0, 60.0, _fx_t), 0.0, TAU, 48,
					Color(0.6, 0.6, 0.66, a * 0.8), lerpf(4.0, 1.0, _fx_t))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			&"beam":
				for i in 7:
					var x: float = (i - 3) * 6.0
					var h: float = lerpf(10.0, 95.0, _fx_t) * (0.65 + 0.35 * sin(i * 1.7))
					draw_line(Vector2(x, 4.0), Vector2(x, -h),
						Color(_fx_color, a * 0.75), lerpf(5.0, 1.0, _fx_t))

	# Caveira translúcida (Fake Volley)
	if _skull_t < 1.0:
		var alpha: float = minf(_skull_t / 0.15, 1.0) * minf((1.0 - _skull_t) / 0.45, 1.0)
		var center := Vector2(0.0, -height - 62.0 - _skull_t * 30.0)
		_draw_skull(center, lerpf(0.75, 1.15, _skull_t), alpha * 0.6)

	# Texto curto em cima dele
	if _text_alpha > 0.0:
		var tp := Vector2(-40.0, -height - placeholder_radius - 46.0 - (1.0 - _text_alpha) * 14.0)
		draw_string_outline(ThemeDB.fallback_font, tp, _text, HORIZONTAL_ALIGNMENT_CENTER,
			80.0, 16, 4, Color(0, 0, 0, _text_alpha * 0.8))
		draw_string(ThemeDB.fallback_font, tp, _text, HORIZONTAL_ALIGNMENT_CENTER,
			80.0, 16, Color(1, 1, 1, _text_alpha))


func _draw_skull(center: Vector2, skull_scale: float, alpha: float) -> void:
	draw_set_transform(center, 0.0, Vector2(skull_scale, skull_scale))
	var bone := Color(0.96, 0.96, 0.98, alpha)
	var shade := Color(0.05, 0.05, 0.08, minf(alpha * 1.3, 1.0))
	draw_arc(Vector2(0.0, -4.0), 21.0, 0.0, TAU, 32, Color(1, 1, 1, alpha * 0.5), 1.5)   # halo
	draw_circle(Vector2(0.0, -6.0), 14.0, bone)                 # crânio
	draw_rect(Rect2(-8.0, 2.0, 16.0, 11.0), bone)               # mandíbula
	draw_circle(Vector2(-5.5, -6.0), 4.2, shade)                # olhos
	draw_circle(Vector2(5.5, -6.0), 4.2, shade)
	draw_colored_polygon(PackedVector2Array(
		[Vector2(0.0, -1.5), Vector2(-2.2, 3.0), Vector2(2.2, 3.0)]), shade)   # nariz
	for i in 4:
		var x: float = -4.5 + i * 3.0
		draw_line(Vector2(x, 7.5), Vector2(x, 13.0), shade, 1.2)               # dentes
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
