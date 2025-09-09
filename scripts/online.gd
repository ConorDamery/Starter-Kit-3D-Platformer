extends Node

const MAX_PLAYERS = 8

var game_maps := {
	"Level 1": "res://scenes/level_1.tscn",
	"Level 2": "res://scenes/level_2.tscn"
	}

enum OnlineBackend { LAN, STEAM }
var online_backend = OnlineBackend.STEAM

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
	match online_backend:
		OnlineBackend.LAN:
			lan_initialize()
		OnlineBackend.STEAM:
			steam_initialize()
		_:
			game_error.emit("Unkown backend!")

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
	match online_backend:
		OnlineBackend.LAN:
			lan_poll_events()
		OnlineBackend.STEAM:
			steam_poll_events()

func create_host(new_player_name: String, new_lobby_name: String):
	match online_backend:
		OnlineBackend.LAN:
			lan_create_host(new_player_name, new_lobby_name)
		OnlineBackend.STEAM:
			steam_create_host(new_player_name, new_lobby_name)

func create_client(new_player_name: String, new_lobby_id: int):
	match online_backend:
		OnlineBackend.LAN:
			lan_create_client(new_player_name, new_lobby_id)
		OnlineBackend.STEAM:
			steam_create_client(new_player_name, new_lobby_id)

func request_lobbies():
	match online_backend:
		OnlineBackend.LAN:
			lan_request_lobbies()
		OnlineBackend.STEAM:
			steam_request_lobbies()
			pass

func close_connection():
	match online_backend:
		OnlineBackend.LAN:
			lan_close_connection()
		OnlineBackend.STEAM:
			#steam_close_connection()
			pass

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

func steam_initialize():
	var ret = Steam.steamInitEx(480, false)
	var status = ret["status"]
	if status > Steam.STEAM_API_INIT_RESULT_OK:
		push_warning("Failed to initialize steam: %d (%s)" % [status, ret["verbal"]])
		online_backend = OnlineBackend.LAN
		initialize_backend()
		return
	else:
		game_log.emit("[STEAM] Steam initialized successfully.")
	
	player_name = Steam.getPersonaName()
	
	#var app_installed_depots: Array = Steam.getInstalledDepots( app_id )
	#var app_languages: String = Steam.getAvailableGameLanguages()
	#var app_owner: int = Steam.getAppOwner()
	#var build_id: int = Steam.getAppBuildId()
	#var game_language: String = Steam.getCurrentGameLanguage()
	#var install_dir: Dictionary = Steam.getAppInstallDir( app_id )
	#var is_on_steam_deck: bool = Steam.isSteamRunningOnSteamDeck()
	#var is_on_vr: bool = Steam.isSteamRunningInVR()
	#var is_online: bool = Steam.loggedOn()
	#var is_owned: bool = Steam.isSubscribed()
	#var launch_command_line: String = Steam.getLaunchCommandLine()
	#var steam_id: int = Steam.getSteamID()
	#var steam_username: String = Steam.getPersonaName()
	#var ui_language: String = Steam.getSteamUILanguage()
	
	#Steam.join_requested.connect(_on_lobby_join_requested)
	#Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_created.connect(self.steam_on_host_joined)
	#Steam.lobby_data_update.connect(_on_lobby_data_update)
	#Steam.lobby_invite.connect(_on_lobby_invite)
	Steam.lobby_joined.connect(self.steam_on_client_joined)
	Steam.lobby_match_list.connect(self.steam_on_lobby_match_list)
	#Steam.lobby_message.connect(_on_lobby_message)
	#Steam.persona_state_change.connect(_on_persona_change)

func steam_poll_events():
	Steam.run_callbacks()

func steam_create_host(new_player_name: String, new_lobby_name: String):
	player_name = new_player_name
	lobby_name = new_lobby_name
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)

func steam_on_host_joined(status: int, new_lobby_id: int):
	if status == 1:
		lobby_id = new_lobby_id
		
		# Set this lobby as joinable, just in case, though this should be done by default
		Steam.setLobbyJoinable(lobby_id, true)
		
		# Set some lobby data
		Steam.setLobbyData(lobby_id, "name", lobby_name)
		#Steam.setLobbyData(lobby_id, "lobby_num_players", str(players.size()))
		Steam.setLobbyData(lobby_id, "lobby_max_players", str(MAX_PLAYERS))
		
		# Allow P2P connections to fallback to being relayed through Steam if needed
		var set_relay: bool = Steam.allowP2PPacketRelay(true)
		game_log.emit("[STEAM] Allowing Steam to be relay backup: %s" % set_relay)
		
		var peer = SteamMultiplayerPeer.new()
		peer.create_host(0)
		multiplayer.set_multiplayer_peer(peer)
		
		game_log.emit("[STEAM] Lobby create with ID: %d" % lobby_id)
		
		register_player.rpc_id(multiplayer.get_unique_id(), player_name)
		player_name = players[multiplayer.get_unique_id()]
		
	else:
		game_error.emit("[STEAM] Failed to create lobby!")

func steam_create_client(new_player_name: String, new_lobby_id: int):
	player_name = new_player_name
	lobby_id = new_lobby_id
	Steam.joinLobby(new_lobby_id)

func steam_on_client_joined(new_lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		# The lobby we tried to joined should be the one we attempted to join
		assert(lobby_id == new_lobby_id)
		lobby_id = new_lobby_id
		
		var id = Steam.getLobbyOwner(new_lobby_id)
		if id == Steam.getSteamID():
			return
			
		var peer = SteamMultiplayerPeer.new()
		peer.create_client(new_lobby_id, 0)
		multiplayer.set_multiplayer_peer(peer)
		
		register_player.rpc_id(multiplayer.get_unique_id(), player_name)
		player_name = players[multiplayer.get_unique_id()]
		
	else:
		# Get the failure reason
		var reason: String
		match response:
			Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
				reason = "This lobby no longer exists."
			Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
				reason = "You don't have permission to join this lobby."
			Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
				reason = "The lobby is now full."
			Steam.CHAT_ROOM_ENTER_RESPONSE_ERROR:
				reason = "Uh... something unexpected happened!"
			Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED:
				reason = "You are banned from this lobby."
			Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED:
				reason = "You cannot join due to having a limited account."
			Steam.CHAT_ROOM_ENTER_RESPONSE_CLAN_DISABLED:
				reason = "This lobby is locked or disabled."
			Steam.CHAT_ROOM_ENTER_RESPONSE_COMMUNITY_BAN:
				reason = "This lobby is community locked."
			Steam.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU:
				reason = "A user in the lobby has blocked you from joining."
			Steam.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER:
				reason = "A user you have blocked is in the lobby."
		
		game_log.emit("[STEAM] " + reason)

func steam_request_lobbies():
	lobbies.clear()
	lobby_list_changed.emit()
	
	#addRequestLobbyListStringFilter
	#addRequestLobbyListNumericalFilter
	#addRequestLobbyListNearValueFilter
	#addRequestLobbyListFilterSlotsAvailable
	#addRequestLobbyListResultCountFilter
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_CLOSE)
	Steam.requestLobbyList()

func steam_on_lobby_match_list(lobbies : Array):
	for lby_id in lobbies:
		var lby_name = Steam.getLobbyData(lby_id, "name")
		var lby_max_players = int(Steam.getLobbyData(lby_id, "lobby_max_players"))
		var lby_num_players = Steam.getNumLobbyMembers(lby_id)
		steam_add_lobby(lby_id, lby_name, lby_num_players, lby_max_players)
	
	lobby_list_changed.emit()

func steam_add_lobby(lby_id: int, lby_name: String, lby_num_players: int, lby_max_players: int):
	lobbies[lby_id] = {
		"id":lby_id,
		"lobby_name":lby_name,
		"lobby_num_players":lby_num_players,
		"lobby_max_players":lby_max_players
	}

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
	
	game_log.emit("[LAN] Lobby discovery initialized")

func lan_poll_events():
	# Poll network events
	while lan_broadcast_socket.get_available_packet_count() > 0:
		var pkt = lan_broadcast_socket.get_packet().get_string_from_utf8()
		var sender_ip = lan_broadcast_socket.get_packet_ip()
		var sender_port = lan_broadcast_socket.get_packet_port()
		game_log.emit("[LAN] Receive packet")
		
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
	var lobby_port = peer.host.get_local_port()
	game_log.emit("[LAN] Lobby create with ID: %d, on port: " % [lobby_id, lobby_port])
	
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
	
	game_log.emit("[LAN] Broadcasted lobby query")

func lan_handle_query(client_ip: String, client_port: int):
	# Send a reply back to the querying client
	var port = multiplayer.multiplayer_peer.host.get_local_port()
	var reply = "LOBBY_INFO:%d:%s:%d:%d:%d" % [lobby_id, lobby_name, port, players.size(), MAX_PLAYERS]
	for i in lan_broadcast_retries:
		lan_broadcast_socket.set_dest_address(client_ip, client_port)
		lan_broadcast_socket.put_packet(reply.to_utf8_buffer())
		await get_tree().create_timer(lan_broadcast_delay).timeout
	
	game_log.emit("[LAN] Replied to query from: %s:%d" % [client_ip, client_port])

func lan_handle_lobby_info(sender_ip: String, reply: String):
	var parts = reply.split(":")
	if parts.size() != 6:
		return
	
	var lby_id = int(parts[1])
	if lobbies.has(lby_id):
		return
		
	game_log.emit("[LAN] Discovered lobby: ", reply, ", from: ", sender_ip)
	
	var lby_name = parts[2]
	var lby_port = int(parts[3])
	var lby_num_players = int(parts[4])
	var lby_max_players = int(parts[5])
	
	lan_add_lobby(lby_id, sender_ip, lby_port, lby_name, lby_num_players, lby_max_players)
	lobby_list_changed.emit()

func lan_add_lobby(lby_id: int, lby_addr: String, lby_port: int, lby_name: String, lby_num_players: int, lby_max_players: int):
	lobbies[lby_id] = {
		"id":lby_id,
		"addr": lby_addr,
		"port":lby_port,
		"lobby_name":lby_name,
		"lobby_num_players":lby_num_players,
		"lobby_max_players":lby_max_players
	}

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
