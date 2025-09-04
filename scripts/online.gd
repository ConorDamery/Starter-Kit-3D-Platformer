extends Node

const DEFAULT_PORT = 10567
const MAX_PEERS = 8

var peer: MultiplayerPeer = null

var player_name: String

var players := {}
var player_ready := {}

var current_world: Node3D
var player_scene: Resource
var spawned_players := {}

signal connection_failed()
signal connection_succeded()
signal player_list_changed()
signal game_started()
signal game_ended()
signal game_error(what: String)
signal game_log(what: String)

func _ready() -> void:
	player_scene = load("res://objects/player.tscn")
	
	initialize_backend()
	setup_callbacks()

func initialize_backend() -> void:
	return

func setup_callbacks() -> void:
	
	multiplayer.peer_connected.connect(
		func(id: int):
			print("Peer connected with ID: ", id, ", Our ID: ", multiplayer.get_unique_id())
			# Tell the connected peer that we have also joined
			register_player.rpc_id(id, player_name)
			
			if is_game_in_progress() and multiplayer.is_server():
				print("Spawning player in game in progress")
				load_world.rpc_id(id)
				#spawn_player(id)
				
				game_started.emit()
	)
	
	multiplayer.peer_disconnected.connect(
		func(id: int):
			if is_game_in_progress():
				game_error.emit("Player " + players[id] + " disconnected!")
				if multiplayer.is_server():
					spawned_players[id].queue_free()
			
			unregister_player(id)
	)
	
	multiplayer.connected_to_server.connect(
		func():
			connection_succeded.emit()
	)
	
	multiplayer.connection_failed.connect(
		func():
			multiplayer.multiplayer_peer = null
			connection_failed.emit()
	)
	
	multiplayer.server_disconnected.connect(
		func():
			game_error.emit("The server disconnected!")
			end_game()
	)
	
	return

func _process(delta: float) -> void:
	# Poll network events
	return

func is_game_in_progress():
	return current_world != null

@rpc("authority", "call_local")
func load_world():
	# Change scene.
	current_world = load("res://scenes/main.tscn").instantiate()
	get_tree().get_root().add_child(current_world)
	get_tree().get_root().get_node("Lobby").hide()

	get_tree().set_pause(false) # Unpause and unleash the game!

func spawn_player(id: int):
	assert(multiplayer.is_server())
	
	print("Spawning player peer ID: ", id)
	
	# Instantiate player and add it to our bookkeeping list
	var player : CharacterBody3D = player_scene.instantiate()
	spawned_players[id] = player
	
	# "true" forces a readable name, which is important, as we can't have sibling nodes
	# with the same name.
	current_world.get_node("Players").add_child(player, true)
	
	# Set the authorization for the player. This has to be called on all peers to stay in sync.
	player.set_authority.rpc(id)
	
	# The peer has authority over the player's position, so to sync it properly,
	# we need to set that position from that peer with an RPC.
	player.teleport.rpc_id(id, Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)))
	
	# Last make sure we have a camera that knows about this player
	player.setup_view.rpc_id(id)

func start_game():
	assert(multiplayer.is_server())
	
	# Call load_world on all clients
	load_world.rpc()
	
	#Iterate over our connected peer ids
	for peer_id in players:
		spawn_player(peer_id)
	
	game_started.emit()

func end_game():
	current_world.queue_free()
	current_world = null
	
	game_ended.emit()
	players.clear()

@rpc("call_local", "any_peer")
func register_player(new_player_name: String):
	var id = multiplayer.get_remote_sender_id()
	var unique_name = _make_unique_name(new_player_name)
	print("Register player: " + unique_name + ", ID: ", id)
	players[id] = unique_name
	player_list_changed.emit()

@rpc("call_local", "any_peer")
func unregister_player(id):
	players.erase(id)
	player_list_changed.emit()

# ENet functions

func create_enet_host(new_player_name: String):
	var enet_peer = ENetMultiplayerPeer.new()
	enet_peer.create_server(DEFAULT_PORT)
	
	peer = enet_peer
	multiplayer.set_multiplayer_peer(peer)
	
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]

func create_enet_client(new_player_name: String, ip_address):
	var enet_peer = ENetMultiplayerPeer.new()
	enet_peer.create_client(ip_address, DEFAULT_PORT)
	
	peer = enet_peer
	multiplayer.set_multiplayer_peer(peer)
	
	await multiplayer.connected_to_server
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]

# Utility functions

func _make_unique_name(name_str: String) -> String:
	var count := 2
	var trial := name_str
	while players.values().has(trial):
		trial = name_str + ' ' + str(count)
		count += 1
	return trial
