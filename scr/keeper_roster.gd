class_name KeeperRoster
extends RefCounted
## Estilos de goleiro que dá para escolher na tela de formação (um por time).
##
## Para criar um goleiro novo: faça o script estendendo Goalkeeper (veja bl_man.gd), defina
## keeper_id e display_name no _init, e acrescente uma linha em KEEPERS e um caso em create().

const KEEPERS: Array[Dictionary] = [
	{"id": "base", "name": "Goleiro Padrão"},
	{"id": "bl_man", "name": "BL Man"},
	{"id": "renoir", "name": "Renoir"},
	{"id": "fukaku", "name": "Fukaku"},
	{"id": "gagamaru", "name": "Gagamaru"},
]

## Pasta das imagens dos goleiros: um PNG por goleiro, com o nome do id (base.png, bl_man.png,
## renoir.png, fukaku.png, gagamaru.png). Ajuste o caminho para o do seu projeto. Sem arquivo,
## o goleiro usa o círculo placeholder.
const ART_DIR: String = "res://img/gks/"

## Escolha de cada time (time -> id). Fica guardada entre partidas, como o TeamStyle.
static var selected: Dictionary = {}


static func create(id: String) -> Goalkeeper:
	match id:
		"bl_man":
			return BLMan.new()
		"renoir":
			return Renoir.new()
		"fukaku":
			return Fukaku.new()
		"gagamaru":
			return Gagamaru.new()
	return Goalkeeper.new()


## Imagem do goleiro (null se o arquivo não existir)
static func art_for(id: String) -> Texture2D:
	var path: String = "%s%s.png" % [ART_DIR, id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func choice_for(team: int) -> String:
	return String(selected.get(team, "base"))


## Troca o goleiro "old" por um novo do estilo "id", no mesmo lugar e time.
## O novo vai para a posição inicial sozinho (o próprio Goalkeeper faz isso no setup).
static func replace_keeper(old: Goalkeeper, id: String) -> Goalkeeper:
	var fresh: Goalkeeper = create(id)
	fresh.team = old.team          # antes de entrar na cena
	var parent: Node = old.get_parent()
	var index: int = old.get_index()
	var pos: Vector2 = old.global_position
	parent.remove_child(old)       # tira o antigo do grupo "goalkeepers"
	parent.add_child(fresh)
	parent.move_child(fresh, index)
	fresh.global_position = pos
	old.queue_free()
	selected[fresh.team] = id
	return fresh
