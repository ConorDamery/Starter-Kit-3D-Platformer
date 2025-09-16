extends Node
class_name Session

@export var config: SessionConfig

var map_config: MapConfig
var map_scene: Node
var spawned_players := {}

func _ready() -> void:
	Online.session = self
	
	# Setup our auto spawn list based on config
	for res in config.player_spawn_list:
		$PlayerSpawner.add_spawnable_scene(res.resource_path)
		
	for res in config.dynamic_spawn_list:
		$DynamicSpawner.add_spawnable_scene(res.resource_path)

func is_game_in_progress():
	return map_scene != null

func load_map(map_name: String):
	if !config.maps.has(map_name):
		push_error("Cannot find map: %s" % map_name)
		return
	
	map_config = config.maps[map_name]
	
	# Change scene.
	map_scene = map_config.map_scene.instantiate()
	if not map_scene:
		push_error("Failed to load session map: %s" % map_name)
		return
	
	self.add_child(map_scene, true)
	
	if multiplayer.is_server():
		# Copy dynamic objects
		for child in map_scene.world_dynamic.get_children():
			# Duplicate the node as instance so we keep it as original as possible and add it to session
			var dup = child.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION)
			$Dynamic.add_child(dup, true)
	
	# Always delete the dynamic objects from loaded scene (they will be replicated)
	map_scene.world_dynamic.queue_free()

func spawn_player(id: int) -> Node:
	assert(multiplayer.is_server())
	
	# Instantiate player and add it to our bookkeeping list
	var player: Node = map_config.player_scene.instantiate()
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
	
	map_config = null
	if map_scene:
		map_scene.queue_free()
		map_scene = null
