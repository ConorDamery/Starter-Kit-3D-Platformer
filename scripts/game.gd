extends Node

var coins = 0

signal coin_collected

func _ready() -> void:
	Online.player_spawned.connect(self.on_player_spawned)
	Online.game_ended.connect(self.reset)

func on_player_spawned(node: Node, id: int):
	if Online.session.is_game_in_progress() and multiplayer.is_server():
		# Sync authority peer ids for newely joined player
		for peer_id in Online.session.spawned_players.keys():
			var remote_player = Online.session.spawned_players[peer_id]
			remote_player.set_authority.rpc_id(id, peer_id)
	
	var player = node as Player
	
	# Set the authorization for the player. This has to be called on all peers to stay in sync.
	player.set_authority.rpc(id)
	
	# The peer has authority over the player's position, so to sync it properly,
	# we need to set that position from that peer with an RPC.
	player.teleport.rpc_id(id, Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)))
	
	# Last make sure we have a camera that knows about this player
	player.setup_view.rpc_id(id)

func reset():
	coins = 0

@rpc("any_peer", "call_local")
func collect_coin(count: int):
	coins += count
	coin_collected.emit(coins)
