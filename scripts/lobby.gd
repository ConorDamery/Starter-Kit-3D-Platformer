extends Control

@export var player_name_le : LineEdit

@export var enet_host_btn : Button
@export var enet_join_btn : Button
@export var enet_ip_address_le : LineEdit
@export var enet_start_btn : Button
@export var enet_player_list : ItemList

@export var error_dialog : AcceptDialog

func _ready() -> void:
	
	Online.connection_failed.connect(self._on_connection_failed)
	Online.connection_succeded.connect(self._on_connection_succeded)
	Online.player_list_changed.connect(self._on_player_list_changed)
	Online.game_started.connect(self._on_game_started)
	Online.game_ended.connect(self._on_game_ended)
	Online.game_error.connect(self._on_game_error)
	Online.game_log.connect(self._on_game_log)
	
func _on_connection_failed():
	enet_host_btn.disabled = false
	# TODO: Let the user know!
	print("Connection failed!")

func _on_connection_succeded():
	print("Connection success!")

func _on_player_list_changed():
	print("Player list changed!")
	enet_player_list.clear()
	for player_name in Online.players.values():
		enet_player_list.add_item(player_name if player_name != Online.player_name else player_name + " (you)")

func _on_game_started():
	print("Game started!")
	get_tree().get_root().get_node("Lobby").hide()

func _on_game_ended():
	print("Game ended!")
	get_tree().get_root().get_node("Lobby").show()

func _on_game_error(what: String):
	error_dialog.dialog_text = what
	error_dialog.popup_centered()
	enet_host_btn.disabled = false

func _on_game_log(what: String):
	print("GAME LOG: " + what)

func _on_enet_host_pressed() -> void:
	Online.create_enet_host(player_name_le.text)
	enet_start_btn.disabled = false

func _on_enet_join_pressed() -> void:
	Online.create_enet_client(player_name_le.text, enet_ip_address_le.text)

func _on_enet_start_pressed() -> void:
	Online.start_game()
