class_name CharacterRoster
extends RefCounted
## Lista dos personagens que dá para escolher na tela de formação.
##
## Para adicionar um personagem novo: crie a cena herdada dele e acrescente uma linha em
## CHARACTERS (id único, nome do menu e caminho da cena). O personagem também precisa
## definir character_id com o mesmo id no _init (veja o isagi.gd).
##
## ATENÇÃO: ajuste os caminhos "scene" para onde você salvou as cenas no projeto.

const CHARACTERS: Array[Dictionary] = [
	{"id": "base", "name": "Personagem Base", "scene": "res://cena/player.tscn"},
	{"id": "isagi", "name": "Isagi", "scene": "res://cena/perso/isagi.tscn"},
	{"id": "bachira", "name": "Bachira", "scene": "res://cena/perso/bachira.tscn"},
	{"id": "rin", "name": "Rin", "scene": "res://cena/perso/rin.tscn"},
	{"id": "shidou", "name": "Shidou", "scene": "res://cena/perso/shidou.tscn"},
	{"id": "barou", "name": "Barou", "scene": "res://cena/perso/barou.tscn"},
	{"id": "kunigami", "name": "Kunigami", "scene": "res://cena/perso/kunigami.tscn"},
	{"id": "chigiri", "name": "Chigiri", "scene": "res://cena/perso/chigiri.tscn"},
	{"id": "zantetsu", "name": "Zantetsu", "scene": "res://cena/perso/zantetsu.tscn"},
	{"id": "niko", "name": "Niko", "scene": "res://cena/perso/niko.tscn"},
	{"id": "raichi", "name": "Raichi", "scene": "res://cena/perso/raichi.tscn"},
	{"id": "karasu", "name": "Karasu", "scene": "res://cena/perso/karasu.tscn"},
	{"id": "aiku", "name": "Aiku", "scene": "res://cena/perso/aiku.tscn"},
	{"id": "kurona", "name": "Kurona", "scene": "res://cena/perso/kurona.tscn"},
	{"id": "charles", "name": "Charles", "scene": "res://cena/perso/charles.tscn"},
	{"id": "ness", "name": "Ness", "scene": "res://cena/perso/ness.tscn"},
]



## Só os personagens cuja cena existe (assim o menu não quebra se faltar alguma)
static func available() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for c in CHARACTERS:
		if ResourceLoader.exists(c["scene"]):
			list.append(c)
		else:
			push_warning("CharacterRoster: cena não encontrada para '%s': %s" % [c["id"], c["scene"]])
	return list


static func find(id: String) -> Dictionary:
	for c in CHARACTERS:
		if c["id"] == id:
			return c
	return {}


## Troca o jogador "old" por um novo do personagem "id", no mesmo lugar, time e nome.
## Devolve o jogador novo (ou null se não deu). O antigo sai da cena na hora.
static func replace_player(old: Player, id: String) -> Player:
	var entry: Dictionary = find(id)
	if entry.is_empty():
		return null
	var scene := load(entry["scene"]) as PackedScene
	if scene == null:
		push_warning("CharacterRoster: não consegui carregar %s" % entry["scene"])
		return null
	var fresh := scene.instantiate() as Player
	if fresh == null:
		push_warning("CharacterRoster: a raiz de %s não é um Player" % entry["scene"])
		return null

	var parent: Node = old.get_parent()
	var index: int = old.get_index()
	var pos: Vector2 = old.global_position
	var node_name: StringName = old.name

	fresh.team = old.team          # antes de entrar na cena
	parent.remove_child(old)       # libera o nome e tira o antigo do grupo "players"
	fresh.name = node_name         # o nome aparece no placar de gols
	parent.add_child(fresh)
	parent.move_child(fresh, index)   # mantém a ordem (e a ordem dos botões do menu)
	fresh.global_position = pos
	fresh.home_position = old.home_position
	old.queue_free()
	return fresh
