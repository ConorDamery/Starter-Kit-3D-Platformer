extends Node3D
class_name Session

@export var config: SessionConfig

var session_map: Node3D
var spawned_players := {}

func _ready() -> void:
	Online.session = self

func is_game_in_progress():
	return session_map != null

func load_map(map: String):
	# Change scene.
	session_map = config.game_maps[map].instantiate()
	if not session_map:
		push_error("Failed to load session map: %s" % map)
		return
	
	self.add_child(session_map)
	
	if multiplayer.is_server():
		for child in session_map.world_dynamic.get_children():
			# Duplicate the node as instance so we keep it as original as possible and add it to session
			var dup = child.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION)
			$Dynamic.add_child(dup)
	
	# Always delete the dynamic objects from loaded scene (they will be replicated)
	session_map.world_dynamic.queue_free()

func spawn_player(id: int) -> Node:
	assert(multiplayer.is_server())
	
	# Instantiate player and add it to our bookkeeping list
	var player_scene = session_map.override_player_scene
	if player_scene == null:
		player_scene = config.default_player_scene
	
	var player: Node = player_scene.instantiate()
	spawned_players[id] = player
	
	# "true" forces a readable name, which is important, as we can't have sibling nodes
	# with the same name.
	$Players.add_child(player, true)
	return player

func remove_player(id: int):
	assert(multiplayer.is_server())
	spawned_players[id].queue_free()
	spawned_players.erase(id)

func _free_children(node: Node):
	for child in node.get_children():
		child.set_physics_process(false)
		child.queue_free()

func reset():
	_free_children($Players)
	_free_children($Dynamic)
	
	spawned_players.clear()
	
	if session_map:
		session_map.queue_free()
		session_map = null
