extends Node

const DEFAULT_PORT = 10567
const MAX_PEERS = 8

var session: Node3D

var game_scene := "res://scenes/main.tscn"
var player_name: String

var players := {}
var player_ready := {}

signal connection_failed()
signal connection_succeded()
signal player_list_changed()
signal game_started()
signal game_ended()
signal game_error(what: String)
signal game_log(what: String)

func _ready() -> void:
	session = load("res://scenes/session.tscn").instantiate()
	get_tree().get_root().add_child.call_deferred(session)
	
	initialize_backend()
	setup_callbacks()

func initialize_backend() -> void:
	return

func setup_callbacks() -> void:
	
	multiplayer.peer_connected.connect(
		func(id: int):
			print("Peer connected: ", id)
			# Tell the connected peer that we have also joined
			register_player.rpc_id(id, player_name)
	)
	
	multiplayer.peer_disconnected.connect(
		func(id: int):
			unregister_player(id)
	)
	
	multiplayer.connected_to_server.connect(
		func():
			connection_succeded.emit()
	)
	
	multiplayer.connection_failed.connect(
		func():
			close_connection()
			connection_failed.emit()
	)
	
	multiplayer.server_disconnected.connect(
		func():
			game_error.emit("The server disconnected!")
			end_game()
	)

func _process(delta: float) -> void:
	# Poll network events
	return

func start_game():
	assert(multiplayer.is_server())
	
	# Call load_world on all clients
	session.load_world.rpc(game_scene)
	
	# Iterate over our connected peer ids
	for peer_id in players:
		session.spawn_player(peer_id)

func end_game():
	close_connection()
	
	session.reset()
	
	players.clear()
	player_list_changed.emit()
	
	game_ended.emit()

@rpc("call_local", "any_peer")
func register_player(new_player_name: String):
	var id = multiplayer.get_remote_sender_id()
	var unique_name = _make_unique_name(new_player_name)
	players[id] = unique_name
	player_list_changed.emit()
	
	if session.is_game_in_progress() and multiplayer.is_server():
		# Sync authority peer ids for newely joined player
		for peer_id in session.spawned_players.keys():
			var player = session.spawned_players[peer_id]
			player.set_authority.rpc_id(id, peer_id)
		
		session.load_world.rpc_id(id, game_scene)
		session.spawn_player(id)

@rpc("call_local", "any_peer")
func unregister_player(id):
	if session.is_game_in_progress():
		#game_error.emit("Player " + players[id] + " disconnected!")
		if multiplayer.is_server():
			session.remove_player(id)
	
	players.erase(id)
	player_list_changed.emit()

# ENet functions

func create_enet_host(new_player_name: String):
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(DEFAULT_PORT)
	
	multiplayer.set_multiplayer_peer(peer)
	
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]

func create_enet_client(new_player_name: String, ip_address):
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip_address, DEFAULT_PORT)
	
	multiplayer.set_multiplayer_peer(peer)
	
	await multiplayer.connected_to_server
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]

func close_connection():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	
	multiplayer.multiplayer_peer = null

# Utility functions

func _make_unique_name(name_str: String) -> String:
	var count := 2
	var trial := name_str
	while players.values().has(trial):
		trial = name_str + ' ' + str(count)
		count += 1
	return trial
