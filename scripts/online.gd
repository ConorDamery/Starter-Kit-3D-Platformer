extends Node

const DEFAULT_PORT = 10567
const MAX_PEERS = 8

var peer: MultiplayerPeer = null

var player_name: String

var players := {}
var player_ready := {}

var game_in_progress := false

signal connection_failed()
signal connection_succeded()
signal player_list_changed()
signal game_started()
signal game_ended()
signal game_error(what: String)
signal game_log(what: String)

func _ready() -> void:
	initialize_backend()
	setup_callbacks()
	
func initialize_backend() -> void:
	return

func setup_callbacks() -> void:
	
	multiplayer.peer_connected.connect(
		func(id: int):
			#print("Peer connected with ID: ", id, ", Our ID: ", multiplayer.get_unique_id())
			#if multiplayer.get_unique_id() == id:
			register_player.rpc_id(id, player_name)
			pass
	)
	
	multiplayer.peer_disconnected.connect(
		func(id: int):
			if is_game_in_progress():
				game_error.emit("Player " + players[id] + " disconnected!")
				if multiplayer.is_server():
					end_game()
			else:
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
	return game_in_progress
	
func start_game():
	game_in_progress = true
	game_started.emit()

func end_game():
	game_in_progress = false
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
	
	register_player.rpc(new_player_name)
	player_name = players[multiplayer.get_unique_id()]

func create_enet_client(new_player_name: String, ip_address):
	var enet_peer = ENetMultiplayerPeer.new()
	enet_peer.create_client(ip_address, DEFAULT_PORT)
	
	peer = enet_peer
	multiplayer.set_multiplayer_peer(peer)
	
	await multiplayer.connected_to_server
	register_player.rpc(new_player_name)
	player_name = players[multiplayer.get_unique_id()]

# Utility functions

func _make_unique_name(name: String) -> String:
	var count := 2
	var trial := name
	while players.values().has(trial):
		trial = name + ' ' + str(count)
		count += 1
	return trial
