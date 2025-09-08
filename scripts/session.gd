extends Node3D

var world: Node3D
var spawned_players := {}

var player_scene: Resource
var view_scene: Resource

func _ready() -> void:
	player_scene = preload("res://objects/player.tscn")
	view_scene = preload("res://objects/view.tscn")

func is_game_in_progress():
	return world != null

@rpc("any_peer", "call_local")
func load_world(world_path: String):
	# Change scene.
	world = load(world_path).instantiate()
	self.add_child(world)
	
	var world_dynamic = world.get_node("World/Dynamic")
	
	if multiplayer.is_server():
		for child in world_dynamic.get_children():
			# Duplicate the node as instance so we keep it as original as possible and add it to session
			var dup = child.duplicate(DuplicateFlags.DUPLICATE_USE_INSTANTIATION)
			$Dynamic.add_child(dup)
	
	# Always delete the dynamic objects from loaded scene (they will be replicated)
	world_dynamic.queue_free()
	
	get_tree().set_pause(false) # Unpause and unleash the game!
	Online.game_started.emit()

func create_view(target: Node3D):
	var view = view_scene.instantiate()
	$Views.add_child(view)
	view.target = target
	return view

func spawn_player(id: int):
	assert(multiplayer.is_server())
	
	# Instantiate player and add it to our bookkeeping list
	var player : CharacterBody3D = player_scene.instantiate()
	spawned_players[id] = player
	
	# "true" forces a readable name, which is important, as we can't have sibling nodes
	# with the same name.
	$Players.add_child(player, true)
	
	# Set the authorization for the player. This has to be called on all peers to stay in sync.
	player.set_authority.rpc(id)
	
	# The peer has authority over the player's position, so to sync it properly,
	# we need to set that position from that peer with an RPC.
	player.teleport.rpc_id(id, Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)))
	
	# Last make sure we have a camera that knows about this player
	player.setup_view.rpc_id(id)

func remove_player(id: int):
	assert(multiplayer.is_server())
	spawned_players[id].queue_free()
	spawned_players.erase(id)

func reset():
	for child in $Views.get_children():
		child.queue_free()
	for child in $Players.get_children():
		child.queue_free()
	for child in $Dynamic.get_children():
		child.queue_free()
	
	spawned_players.clear()
	
	if world: world.queue_free()
	world = null
