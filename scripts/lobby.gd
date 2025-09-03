extends Control

@export var player_name : LineEdit

@export var enet_host : Button
@export var enet_join : Button
@export var enet_ip_address : LineEdit
@export var enet_start : Button
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
	enet_host.disabled = false
	# TODO: Let the user know!
	print("Connection failed!")

func _on_connection_succeded():
	print("Connection success!")

func _on_player_list_changed():
	print("Player list changed!")
	enet_player_list.clear()
	for name in Online.players.values():
		enet_player_list.add_item(name if name != Online.player_name else name + " (you)")

func _on_game_started():
	print("Game started!")

func _on_game_ended():
	print("Game ended!")

func _on_game_error(what: String):
	error_dialog.dialog_text = what
	error_dialog.popup_centered()
	enet_host.disabled = false

func _on_game_log(what: String):
	print("GAME LOG: " + what)


func _on_enet_host_pressed() -> void:
	Online.create_enet_host(player_name.text)


func _on_enet_join_pressed() -> void:
	Online.create_enet_client(player_name.text, enet_ip_address.text)


func _on_enet_start_pressed() -> void:
	print("ENet start")
