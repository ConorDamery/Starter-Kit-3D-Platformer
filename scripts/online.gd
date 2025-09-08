extends Node

const MAX_PLAYERS = 8

var game_maps := { "main":"res://scenes/main.tscn" }

var session: Node3D
var lobby_id := -1
var lobby_name: String
var lobby_map: String

var lobbies := {}
var is_host := false

var player_name: String

var players := {}
var player_ready := {}

signal connection_failed()
signal connection_succeded()
signal lobby_list_changed()
signal player_list_changed()
signal game_started()
signal game_ended()
signal game_error(what: String)
signal game_log(what: String)

func _ready():
	session = load("res://scenes/session.tscn").instantiate()
	get_tree().get_root().add_child.call_deferred(session)
	
	initialize_backend()
	setup_callbacks()

func _process(delta: float):
	poll_events()

#region Online API

func initialize_backend():
	lan_initialize()

func setup_callbacks():
	
	multiplayer.peer_connected.connect(
		func(id: int):
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

func poll_events():
	lan_poll_events()

func create_host(new_player_name: String, new_lobby_name: String):
	lan_create_host(new_player_name, new_lobby_name)

func create_client(new_player_name: String, new_lobby_id: int):
	lan_create_client(new_player_name, new_lobby_id)

func request_lobbies():
	lan_request_lobbies()

func close_connection():
	lan_close_connection()

func start_game():
	assert(multiplayer.is_server())
	
	# Call load_world on all clients
	session.load_world.rpc(game_maps[lobby_map])
	
	# Iterate over our connected peer ids
	for peer_id in players:
		session.spawn_player(peer_id)

func end_game():
	Game.reset()
	
	close_connection()
	
	session.reset()
	
	players.clear()
	player_list_changed.emit()
	
	game_ended.emit()

# RPC Functions

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
		
		session.load_world.rpc_id(id, game_maps[lobby_map])
		session.spawn_player(id)

@rpc("call_local", "any_peer")
func unregister_player(id):
	if session.is_game_in_progress():
		#game_error.emit("Player " + players[id] + " disconnected!")
		if multiplayer.is_server():
			session.remove_player(id)
	
	players.erase(id)
	player_list_changed.emit()

#endregion

#region Steam Backend
# TODO: Implement this
#endregion

#region LAN Backend

const LAN_BROADCAST_ADDR := "255.255.255.255"
const LAN_BROADCAST_PORT_RANGE = 65535

var lan_broadcast_socket := PacketPeerUDP.new()
var lan_broadcast_retries = 1
var lan_broadcast_delay = 0.05

func lan_initialize():
	# Bind the socket to the fixed broadcast port
	lan_broadcast_socket.set_broadcast_enabled(true)
	var err = lan_broadcast_socket.bind(0) # Bind to ephemeral port
	if err != OK:
		push_error("Failed to bind UDP port, err: ", err)
	
	print("Lobby discovery initialized")

func lan_poll_events():
	# Poll network events
	while lan_broadcast_socket.get_available_packet_count() > 0:
		var pkt = lan_broadcast_socket.get_packet().get_string_from_utf8()
		var sender_ip = lan_broadcast_socket.get_packet_ip()
		var sender_port = lan_broadcast_socket.get_packet_port()
		print("Receive packet")
		
		# If host: respond to queries
		if is_host and pkt == "LOBBY_QUERY":
			lan_handle_query(sender_ip, sender_port)
		
		# If client: handle lobby replies
		elif pkt.begins_with("LOBBY_INFO:"):
			lan_handle_lobby_info(sender_ip, pkt)

func lan_create_host(new_player_name: String, new_lobby_name: String):
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(0, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to create host!")
		return
	
	# Attach to Multiplayer API
	multiplayer.set_multiplayer_peer(peer)
	
	lobby_id = peer.generate_unique_id()
	
	# Query the actual address & port the OS assigned
	print("Lobby started on port: ", peer.host.get_local_port())
	
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]
	
	lobby_name = new_lobby_name
	
	is_host = true

func lan_create_client(new_player_name: String, new_lobby_id: int):
	if not lobbies.has(new_lobby_id):
		return
	
	var lby_info = lobbies[new_lobby_id]
	var addr = lby_info["addr"]
	var port = lby_info["port"]
	
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(addr, port)
	
	multiplayer.set_multiplayer_peer(peer)
	
	await multiplayer.connected_to_server
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]

func lan_request_lobbies():
	lobbies.clear()
	lobby_list_changed.emit()
	
	for i in lan_broadcast_retries:
		# Try all possible ports since we're using ephemeral ports (aka we don't know what port to use)
		for port in LAN_BROADCAST_PORT_RANGE:
			lan_broadcast_socket.set_dest_address(LAN_BROADCAST_ADDR, port)
			lan_broadcast_socket.put_packet("LOBBY_QUERY".to_utf8_buffer())
		await get_tree().create_timer(lan_broadcast_delay).timeout
	
	print("Broadcasted lobby query")

func lan_handle_query(client_ip: String, client_port: int):
	# Send a reply back to the querying client
	var port = multiplayer.multiplayer_peer.host.get_local_port()
	var reply = "LOBBY_INFO:%d:%s:%d:%d:%d" % [lobby_id, lobby_name, port, players.size(), MAX_PLAYERS]
	for i in lan_broadcast_retries:
		lan_broadcast_socket.set_dest_address(client_ip, client_port)
		lan_broadcast_socket.put_packet(reply.to_utf8_buffer())
		await get_tree().create_timer(lan_broadcast_delay).timeout
	
	print("Replied to query from: %s:%d" % [client_ip, client_port])

func lan_handle_lobby_info(sender_ip: String, reply: String):
	var parts = reply.split(":")
	if parts.size() != 6:
		return
	
	var lby_id = int(parts[1])
	if lobbies.has(lby_id):
		return
		
	print("Discovered lobby: ", reply, ", from: ", sender_ip)
	
	var lby_name = parts[2]
	var lby_port = int(parts[3])
	var lby_num_players = int(parts[4])
	var lby_max_players = int(parts[5])
	
	lan_add_lobby(lby_id, sender_ip, lby_port, lby_name, lby_num_players, lby_max_players)

func lan_add_lobby(lby_id: int, lby_addr: String, lby_port: int, lby_name: String, lby_num_players: int, lby_max_players: int):
	lobbies[lby_id] = {
		"id":lby_id,
		"addr": lby_addr,
		"port":lby_port,
		"lobby_name":lby_name,
		"lobby_num_players":lby_num_players,
		"lobby_max_players":lby_max_players
	}
	
	lobby_list_changed.emit()

func lan_close_connection():
	lobbies.clear()
	is_host = false
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	
	multiplayer.multiplayer_peer = null

#endregion

# Utility functions

func _make_unique_name(name_str: String) -> String:
	var count := 2
	var trial := name_str
	while players.values().has(trial):
		trial = name_str + ' ' + str(count)
		count += 1
	return trial
