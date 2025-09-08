extends Node

const BROADCAST_PORT := 9999
const BROADCAST_ADDR := "239.255.0.1" # private multicast range

const MAX_PLAYERS = 8

var session: Node3D
var lobby_id := -1
var lobby_name: String
var lobby_addr: String
var lobby_port := -1

var udp := PacketPeerUDP.new()
var lobbies := {}
var is_host := false

var game_scene := "res://scenes/main.tscn"
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

func _ready() -> void:
	session = load("res://scenes/session.tscn").instantiate()
	get_tree().get_root().add_child.call_deferred(session)
	
	initialize_backend()
	setup_callbacks()

func _exit_tree():
	# Leave multicast group when the node is leaving the scene
	shutdown_backend()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# Extra safety in case node is freed directly
		shutdown_backend()

func initialize_backend() -> void:
	# Bind the socket to the fixed discovery port
	var err = udp.bind(BROADCAST_PORT)
	if err != OK:
		push_error("Failed to bind UDP port, err: ", err)
	
	# Join multicast on all interfaces
	for iface in IP.get_local_interfaces():
		var join_err = udp.join_multicast_group(BROADCAST_ADDR, iface["name"])
		var iface_friendly = iface["friendly"]
		if join_err != OK:
			print("Failed to join multicast group on interface: " + iface_friendly + ", err: ", join_err)
		else:
			print("Joined multicast group on interface: " + iface_friendly)
	
	print("Lobby discovery initialized")

func shutdown_backend() -> void:
	if udp.is_bound():
		# Leave multicast on all interfaces
		for iface in IP.get_local_interfaces():
			udp.leave_multicast_group(BROADCAST_ADDR, iface["name"])
	
		udp.close()
	
	print("Lobby discovery shutdown")

func setup_callbacks() -> void:
	
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

func _process(delta: float) -> void:
	# Poll network events
	while udp.get_available_packet_count() > 0:
		var pkt = udp.get_packet().get_string_from_utf8()
		var sender_ip = udp.get_packet_ip()
		var sender_port = udp.get_packet_port()
		print("Receive packet")
		
		# If host: respond to queries
		if is_host and pkt == "LOBBY_QUERY":
			enet_handle_query(sender_ip, sender_port)
		
		# If client: handle lobby replies
		elif pkt.begins_with("LOBBY_INFO:"):
			enet_handle_lobby_info(sender_ip, pkt)

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

func create_enet_host(new_player_name: String, new_lobby_name: String):
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(0, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to create host!")
		return
	
	# Attach to Multiplayer API
	multiplayer.set_multiplayer_peer(peer)
	
	lobby_id = peer.generate_unique_id()
	
	# Query the actual address & port the OS assigned
	lobby_addr = "1.1.1.1"
	lobby_port = peer.host.get_local_port()
	print("Lobby started on: %s:%d" % [lobby_addr, lobby_port])
	
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]
	
	lobby_name = new_lobby_name
	
	is_host = true

func create_enet_client(new_player_name: String, ip_address, port: int):
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip_address, port)
	
	multiplayer.set_multiplayer_peer(peer)
	
	await multiplayer.connected_to_server
	register_player.rpc_id(multiplayer.get_unique_id(), new_player_name)
	player_name = players[multiplayer.get_unique_id()]


#func get_broadcast_ip() -> String:
	#var local_ip = IP.get_local_interfaces()#[0]
	#var parts = local_ip.split(".")
	#return "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]

func request_lobbies(retries := 1, delay := 0.05):
	lobbies.clear()
	lobby_list_changed.emit()
	
	for i in retries:
		udp.set_dest_address(BROADCAST_ADDR, BROADCAST_PORT)
		udp.put_packet("LOBBY_QUERY".to_utf8_buffer())
		await get_tree().create_timer(delay).timeout
	
	print("Broadcasted lobby query")

func enet_handle_query(client_ip: String, client_port: int, retries := 1, delay := 0.05):
	# Send a reply back to the querying client
	var reply = "LOBBY_INFO:%d:%d:%s:%d:%d" % [lobby_id, lobby_port, lobby_name, players.size(), MAX_PLAYERS]
	for i in retries:
		udp.set_dest_address(client_ip, client_port)
		udp.put_packet(reply.to_utf8_buffer())
		await get_tree().create_timer(delay).timeout
	
	print("Replied to query from: ", client_ip)

func enet_handle_lobby_info(sender_ip: String, reply: String):
	var parts = reply.split(":")
	if parts.size() != 6:
		return
	
	var id = int(parts[1])
	if lobbies.has(id):
		return
		
	print("Discovered lobby: ", reply, ", from: ", sender_ip)
	
	var port = int(parts[2])
	var lby_name = parts[3]
	var lby_num_players = int(parts[4])
	var lby_max_players = int(parts[5])
	lobbies[id] = { "id":id, "addr": sender_ip, "port":port, "lobby_name":lby_name, "lobby_num_players":lby_num_players, "lobby_max_players":lby_max_players }
	lobby_list_changed.emit()

func close_connection():
	lobbies.clear()
	is_host = false
	
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
