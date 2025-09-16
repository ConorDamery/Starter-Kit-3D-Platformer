extends Node
class_name State

@export var world_dynamic: Node

var coins = 0

signal state_updated

func _ready() -> void:
	Online.player_spawned.connect(self.on_player_spawned)
	Online.game_started.connect(self.on_game_started)
	Online.game_ended.connect(self.on_game_ended)

func on_player_spawned(node: Node, id: int):
	if Online.session.is_game_in_progress() and multiplayer.is_server():
		update_state.rpc_id(id, coins)
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

func on_game_started():
	pass

func on_game_ended():
	pass

@rpc("authority", "call_local", "reliable")
func update_state(new_coins: int):
	coins = new_coins
	
	$HUD.coins_label.text = str(coins)
	state_updated.emit(coins)

@rpc("any_peer", "call_local", "reliable")
func collect_coin(count: int):
	if multiplayer.is_server():
		update_state.rpc(coins + count)
